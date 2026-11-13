import Foundation

/// Integration commands in the root search ("Bookmarks" → enters "bm ") and their items
/// once the query starts with the prefix of one ("bm laravel", "!laravel"), exclusively.
@MainActor
final class IntegrationsProvider: SearchProvider {
    let priority = 10
    private let maxItems = 50
    private let debounce: UInt64 = 250_000_000

    func search(_ query: String) async -> ProviderResponse {
        let store = IntegrationStore.shared
        let active = store.active
        // The longest trigger wins, so "b" without a space doesn't hide "bm ".
        let entered = active
            .map { (integration: $0, trigger: store.trigger(of: $0)) }
            .filter { query.prefix($0.trigger.count).lowercased() == $0.trigger.lowercased() }
            .max { $0.trigger.count < $1.trigger.count }
        if let entered, let manifest = entered.integration.manifest {
            let rest = String(query.dropFirst(entered.trigger.count)).trimmingCharacters(in: .whitespaces)
            return await searchInside(entered.integration, manifest: manifest, rest: rest)
        }
        return root(query, active)
    }

    // MARK: - Root

    private func root(_ query: String, _ active: [Integration]) -> ProviderResponse {
        let store = IntegrationStore.shared
        let items = active.compactMap { integration -> ResultItem? in
            let prefix = store.prefix(of: integration)
            guard let manifest = integration.manifest,
                  let score = Fuzzy.score(query, in: [manifest.name, prefix]) else { return nil }
            let id = "integration:\(integration.id)"
            return ResultItem(id: id, title: manifest.name,
                              subtitle: store.needsSpace(integration)
                                  ? tr("Escribe «%@» y un espacio para buscar", prefix)
                                  : tr("Escribe «%@» para buscar", prefix),
                              icon: integration.icon, kind: tr("Integración"),
                              action: .setQuery(store.trigger(of: integration)),
                              score: score + Frecency.shared.boost(id))
        }
        return ProviderResponse(items: items)
    }

    // MARK: - Inside an integration

    private func searchInside(_ integration: Integration, manifest: IntegrationManifest, rest: String) async -> ProviderResponse {
        let store = IntegrationStore.shared
        if manifest.passQuery, !store.hasFreshCache(integration, query: rest) {
            try? await Task.sleep(nanoseconds: debounce)
            if Task.isCancelled { return ProviderResponse(items: [], exclusive: true) }
        }
        let outcome = await store.output(of: integration, query: rest)
        if Task.isCancelled { return ProviderResponse(items: [], exclusive: true) }

        switch outcome {
        case .cancelled:
            return ProviderResponse(items: [], exclusive: true)
        case .failure(let short, let detail):
            return ProviderResponse(items: [errorRow(integration, short: short, detail: detail)], exclusive: true)
        case .items(let scriptItems):
            var rows: [ResultItem] = []
            for (index, scriptItem) in scriptItems.enumerated() {
                let orderScore = 1 - Double(index) / 10_000
                var row = resultItem(scriptItem, integration: integration, score: orderScore)
                if !manifest.passQuery, !rest.isEmpty {
                    guard let match = Fuzzy.score(rest, in: [scriptItem.title, scriptItem.subtitle ?? ""]) else { continue }
                    row.score = match + Frecency.shared.boost(row.id)
                }
                rows.append(row)
            }
            if !manifest.passQuery, !rest.isEmpty {
                rows.sort { $0.score > $1.score }
            }
            return ProviderResponse(items: Array(rows.prefix(maxItems)), exclusive: true)
        }
    }

    private func errorRow(_ integration: Integration, short: String, detail: String) -> ResultItem {
        ResultItem(id: "int:\(integration.id):error", title: integration.name + ": " + short,
                   subtitle: detail == short || detail.isEmpty ? nil : tr("Return copia el mensaje completo"),
                   icon: .symbol("exclamationmark.triangle"), kind: integration.name,
                   action: .copy(detail.isEmpty ? short : detail), score: 1)
    }

    // MARK: - Conversion

    private func resultItem(_ item: ScriptItem, integration: Integration, score: Double) -> ResultItem {
        let folder = integration.folder
        let action = Self.action(type: item.actionType, value: item.actionValue, folder: folder)
            ?? .copy(item.copy ?? item.title)
        var fileURL: URL?
        if case .open(let url) = action, url.isFileURL { fileURL = url }
        let extras = item.actions.enumerated().compactMap { index, extra -> ItemAction? in
            guard let action = Self.action(type: extra.type, value: extra.value, folder: folder) else { return nil }
            let symbol = extra.icon.map { $0.hasPrefix("sf:") ? String($0.dropFirst(3)) : $0 }
            return ItemAction(id: "script\(index)", title: extra.title,
                              symbol: symbol ?? Self.defaultSymbol(for: action), action: action)
        }
        let key = item.actionValue ?? item.title
        return ResultItem(id: "int:\(integration.id):\(key)", title: item.title, subtitle: item.subtitle,
                          icon: icon(item.icon, integration: integration), kind: integration.name,
                          action: action, score: score, fileURL: fileURL, copyText: item.copy, actions: extras)
    }

    /// `open`, `copy` or `run` with its value; nil for anything else.
    private static func action(type: String?, value: String?, folder: URL) -> ResultAction? {
        switch (type, value) {
        case ("open", let value?): return openURL(value, folder: folder).map(ResultAction.open) ?? .copy(value)
        case ("copy", let value?): return .copy(value)
        case ("run", let value?): return .run(command: value, directory: folder)
        default: return nil
        }
    }

    private static func defaultSymbol(for action: ResultAction) -> String {
        switch action {
        case .open: return "arrow.up.forward.square"
        case .copy: return "doc.on.doc"
        default: return "terminal"
        }
    }

    /// Web URL, `file://` URL, or a path (absolute, `~/…` or relative to the integration folder).
    static func openURL(_ value: String, folder: URL) -> URL? {
        if value.hasPrefix("/") || value.hasPrefix("~") {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        if let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        guard !value.isEmpty else { return nil }
        return folder.appendingPathComponent(value).standardizedFileURL
    }

    private func icon(_ value: String?, integration: Integration) -> ItemIcon {
        guard let value, !value.isEmpty else { return integration.icon }
        if value.hasPrefix("sf:") {
            let name = String(value.dropFirst(3))
            return name.isEmpty ? integration.icon : .symbol(name)
        }
        let lowered = value.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: value).map(ItemIcon.remote) ?? integration.icon
        }
        let url = value.hasPrefix("/") || value.hasPrefix("~")
            ? URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            : integration.folder.appendingPathComponent(value)
        return FileManager.default.fileExists(atPath: url.path) ? .image(url) : integration.icon
    }
}
