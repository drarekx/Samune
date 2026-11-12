import AppKit

/// Applications and System Settings panes.
@MainActor
final class AppsProvider: SearchProvider {
    let priority = 0

    private let index = AppIndex()
    private let settings = SearchSettings.shared
    private let maxResults = 12
    private var launchObserver: NSObjectProtocol?

    init() {
        // A newly installed app shows up as soon as it is launched for the first time.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [index] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let path = app.bundleURL?.path, path.hasSuffix(".app") else { return }
            Task { @MainActor in
                let folders = SearchSettings.shared.extraAppFolders
                if await !index.contains(path) {
                    await index.rescan(extraFolders: folders)
                }
            }
        }
    }

    deinit {
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
    }

    func search(_ query: String) async -> ProviderResponse {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .empty }
        let entries = await index.entries(extraFolders: settings.extraAppFolders,
                                          includePanes: settings.includeSystemSettings)
        guard !Task.isCancelled else { return .empty }

        // Fuzzy matching off the main thread; frecency (main actor) only for the best candidates.
        let matches = await Task.detached(priority: .userInitiated) {
            entries.compactMap { entry -> (AppEntry, Double)? in
                Fuzzy.score(text, in: entry.names).map { (entry, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(40)
        }.value
        guard !Task.isCancelled else { return .empty }

        let items = matches.map { entry, score in item(for: entry, score: score) }
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
        return ProviderResponse(items: Array(items))
    }

    private func item(for entry: AppEntry, score: Double) -> ResultItem {
        switch entry.kind {
        case .app:
            let id = "app:\(entry.bundleURL.path)"
            return ResultItem(id: id, title: entry.title,
                              subtitle: SearchPaths.abbreviate(entry.bundleURL.deletingLastPathComponent().path),
                              icon: .file(entry.bundleURL), kind: tr("App"), action: .open(entry.openURL),
                              score: score + Frecency.shared.boost(id), fileURL: entry.bundleURL)
        case .settingsPane:
            let id = "settings:\(entry.openURL.absoluteString)"
            // Slightly below an app with the same match, so "Teclado" the pane never hides an app.
            return ResultItem(id: id, title: entry.title, subtitle: nil,
                              icon: .file(AppScanner.systemSettingsApp), kind: tr("Ajustes del sistema"),
                              action: .open(entry.openURL), score: score - 0.02 + Frecency.shared.boost(id),
                              copyText: entry.openURL.absoluteString)
        }
    }
}
