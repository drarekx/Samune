import AppKit
import Combine

/// Asks every provider for results and keeps the merged, ordered list the panel shows.
@MainActor
final class SearchEngine: ObservableObject {
    static let shared = SearchEngine()

    /// Ordered rows for the current query; for an empty query, the providers' suggestions.
    @Published private(set) var results: [ResultItem] = []
    /// True when `results` are suggestions for the empty field, not search results.
    @Published private(set) var showingSuggestions = false
    /// True while some provider is still working on the current query.
    @Published private(set) var isSearching = false

    /// What the panel must do after activating a result.
    enum Outcome {
        case close
        case setQuery(String)
        /// The panel stays open and shows the results of the same query again.
        case refresh
        /// The panel stays open as it is (the action shows something in it).
        case stay
    }

    /// Built-in actions (`ResultAction.perform`), registered by `AppDelegate`.
    var performers: [String: () -> Void] = [:]
    /// Actions with an argument (`ResultAction.invoke`), registered by each area at launch.
    var handlers: [String: (String) -> Void] = [:]
    /// Handlers of `handlers` whose action shows something in the panel instead of closing it.
    var stayOpenHandlers: Set<String> = []
    private var lastQuery = ""
    private var cachedSuggestions: [ResultItem] = []

    private let providers: [SearchProvider]
    private var generation = 0
    private var tasks: [Task<Void, Never>] = []
    private let maxResults = 60

    private init() {
        providers = [AppsProvider(), CalculatorProvider(), CommandsProvider(), NotesProvider(), AIProvider(),
                     IntegrationsProvider(), FilesProvider()]
    }

    /// Call on every change of the search field.
    func update(query: String) {
        start(query: query, holdUntilComplete: false)
    }

    /// Asks the providers. `holdUntilComplete` keeps the current rows until every provider has
    /// answered (or a short timeout), so a refresh does not make the list shrink and grow again.
    private func start(query: String, holdUntilComplete: Bool) {
        lastQuery = query
        generation += 1
        let current = generation
        tasks.forEach { $0.cancel() }
        tasks = []

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let suggesting = trimmed.isEmpty
        if suggesting {
            // Last suggestions right away (no jump when the panel opens); fresh ones replace them.
            results = cachedSuggestions
            showingSuggestions = true
        }
        let hold = holdUntilComplete || suggesting

        var responses: [Int: ProviderResponse] = [:]
        var pending = providers.count
        isSearching = !suggesting
        for (index, provider) in providers.enumerated() {
            tasks.append(Task { [weak self] in
                let response: ProviderResponse
                if suggesting {
                    response = ProviderResponse(items: await provider.suggestions())
                } else {
                    // Leading spaces never matter; trailing ones do ("bm " enters an integration).
                    response = await provider.search(String(query.drop(while: { $0 == " " })))
                }
                guard let self, !Task.isCancelled, current == self.generation else { return }
                responses[index] = response
                pending -= 1
                guard !hold || pending == 0 else { return }
                self.publish(self.merge(responses), suggesting: suggesting)
                self.isSearching = pending > 0
            })
        }
        if hold {
            // A slow provider must not freeze the list: show what is there after a moment.
            tasks.append(Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !Task.isCancelled, current == self.generation, pending > 0 else { return }
                self.publish(self.merge(responses), suggesting: suggesting)
            })
        }
    }

    private func publish(_ rows: [ResultItem], suggesting: Bool) {
        if suggesting { cachedSuggestions = rows }
        showingSuggestions = suggesting
        results = rows
    }

    private func merge(_ responses: [Int: ProviderResponse]) -> [ResultItem] {
        let exclusive = responses.filter { $0.value.exclusive }
        let shown = exclusive.isEmpty ? responses : exclusive
        let ordered = shown.keys
            .sorted { providers[$0].priority < providers[$1].priority }
            .flatMap { (shown[$0]?.items ?? []).sorted { $0.score > $1.score } }
        var seen = Set<String>()
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(maxResults))
    }

    // MARK: - Actions

    /// Searches the current query again (after an action that changes the results).
    func refresh() { start(query: lastQuery, holdUntilComplete: true) }

    /// Return on a row.
    func activate(_ item: ResultItem) -> Outcome {
        Frecency.shared.record(item.id)
        return run(item.action)
    }

    /// An entry of the actions menu.
    func perform(_ action: ItemAction, on item: ResultItem) -> Outcome {
        let outcome = run(action.action)
        guard action.keepsPanelOpen, case .close = outcome else { return outcome }
        refresh()
        return .refresh
    }

    private func run(_ action: ResultAction) -> Outcome {
        if case .setQuery(let text) = action { return .setQuery(text) }
        switch action {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            copy(text)
        case .run(let command, let directory):
            run(command, in: directory)
        case .perform(let id):
            // After the panel has closed, so windows opened by the action come to the front.
            DispatchQueue.main.async { [weak self] in self?.performers[id]?() }
        case .invoke(let handler, let argument):
            handlers[handler]?(argument)
            if stayOpenHandlers.contains(handler) { return .stay }
        case .setQuery:
            break
        }
        return .close
    }

    /// Every action of a row, in menu order: the primary one (Return), reveal in Finder (⌘↩),
    /// copy (⌘C) and the row's own `actions`. The menu, the footer and the keys all read this list.
    func actions(for item: ResultItem) -> [RowAction] {
        var list = [RowAction(id: "primary", title: Self.primaryTitle(item.action), symbol: Self.primarySymbol(item.action),
                              shortcut: KeyShortcut(key: "return", command: false), destructive: false,
                              kind: .primary)]
        if item.fileURL != nil {
            list.append(RowAction(id: "reveal", title: tr("Mostrar en el Finder"), symbol: "folder",
                                  shortcut: KeyShortcut(key: "return"), destructive: false, kind: .reveal))
        }
        // Skipped when Return already copies that same text.
        if let copy = copyCandidate(of: item), item.action != .copy(copy.text) {
            list.append(RowAction(id: "copy", title: copy.title, symbol: "doc.on.doc",
                                  shortcut: KeyShortcut(key: "c"), destructive: false, kind: .copy))
        }
        for extra in item.actions where !list.contains(where: { $0.id == extra.id }) {
            list.append(RowAction(id: extra.id, title: extra.title, symbol: extra.symbol, shortcut: extra.shortcut,
                                  destructive: extra.destructive, kind: .extra(extra)))
        }
        return list
    }

    /// Runs an entry of `actions(for:)`.
    func perform(_ action: RowAction, on item: ResultItem) -> Outcome {
        switch action.kind {
        case .primary: return activate(item)
        case .reveal: reveal(item); return .close
        case .copy: copyText(of: item); return .close
        case .extra(let extra): return perform(extra, on: item)
        }
    }

    private static func primaryTitle(_ action: ResultAction) -> String {
        switch action {
        case .open: return tr("Abrir")
        case .copy: return tr("Copiar")
        case .run, .perform, .invoke: return tr("Ejecutar")
        case .setQuery: return tr("Entrar")
        }
    }

    private static func primarySymbol(_ action: ResultAction) -> String {
        switch action {
        case .open: return "arrow.up.forward.app"
        case .copy: return "doc.on.doc"
        case .run, .perform, .invoke: return "play"
        case .setQuery: return "arrow.right.circle"
        }
    }

    /// What ⌘C copies and how the menu names it.
    private func copyCandidate(of item: ResultItem) -> (text: String, title: String)? {
        if let explicit = item.copyText {
            let isURL = URL(string: explicit).map { $0.scheme != nil && !explicit.contains(" ") } ?? false
            return (explicit, explicit.hasPrefix("/") ? tr("Copiar ruta") : isURL ? tr("Copiar enlace") : tr("Copiar texto"))
        }
        if let file = item.fileURL { return (file.path, tr("Copiar ruta")) }
        switch item.action {
        case .open(let url):
            return url.isFileURL ? (url.path, tr("Copiar ruta")) : (url.absoluteString, tr("Copiar enlace"))
        case .copy(let value):
            return (value, tr("Copiar texto"))
        default:
            return nil
        }
    }

    /// ⌘Return: shows the file in Finder. False when the row has no file.
    @discardableResult
    func reveal(_ item: ResultItem) -> Bool {
        guard let url = item.fileURL else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// ⌘C: copies the path, the URL or the text of the row. False when there is nothing to copy.
    @discardableResult
    func copyText(of item: ResultItem) -> Bool {
        guard let text = copyCandidate(of: item)?.text else { return false }
        copy(text)
        return true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func run(_ command: String, in directory: URL?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}

/// One entry of the actions menu (⌘K): what every row gets plus the row's own `ItemAction`s.
struct RowAction: Identifiable {
    enum Kind {
        case primary
        case reveal
        case copy
        case extra(ItemAction)
    }

    let id: String
    /// Already translated.
    let title: String
    /// SF Symbol name.
    let symbol: String
    let shortcut: KeyShortcut?
    let destructive: Bool
    let kind: Kind

    /// True for the row's own actions, whose shortcuts work straight from the result list.
    var isExtra: Bool {
        if case .extra = kind { return true }
        return false
    }
}

extension KeyShortcut {
    /// "⌘P", "⇧⌘⌫", "↩".
    var label: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        switch key {
        case "delete": text += "⌫"
        case "return": text += "↩"
        default: text += key.uppercased()
        }
        return text
    }
}
