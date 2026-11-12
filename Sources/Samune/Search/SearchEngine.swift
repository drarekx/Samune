import AppKit
import Combine

/// Asks every provider for results and keeps the merged, ordered list the panel shows.
@MainActor
final class SearchEngine: ObservableObject {
    static let shared = SearchEngine()

    /// Ordered rows for the current query. Empty for an empty query.
    @Published private(set) var results: [ResultItem] = []
    /// True while some provider is still working on the current query.
    @Published private(set) var isSearching = false

    /// What the panel must do after activating a result.
    enum Outcome {
        case close
        case setQuery(String)
    }

    /// Built-in actions (`ResultAction.perform`), registered by `AppDelegate`.
    var performers: [String: () -> Void] = [:]

    private let providers: [SearchProvider]
    private var generation = 0
    private var tasks: [Task<Void, Never>] = []
    private let maxResults = 60

    private init() {
        providers = [AppsProvider(), CommandsProvider(), IntegrationsProvider(), FilesProvider()]
    }

    /// Call on every change of the search field.
    func update(query: String) {
        generation += 1
        let current = generation
        tasks.forEach { $0.cancel() }
        tasks = []

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        var responses: [Int: ProviderResponse] = [:]
        var pending = providers.count
        isSearching = true
        for (index, provider) in providers.enumerated() {
            tasks.append(Task { [weak self] in
                // Leading spaces never matter; trailing ones do ("bm " enters an integration).
                let response = await provider.search(String(query.drop(while: { $0 == " " })))
                guard let self, !Task.isCancelled, current == self.generation else { return }
                responses[index] = response
                pending -= 1
                self.results = self.merge(responses)
                self.isSearching = pending > 0
            })
        }
    }

    private func merge(_ responses: [Int: ProviderResponse]) -> [ResultItem] {
        let exclusive = responses.filter { $0.value.exclusive }
        let shown = exclusive.isEmpty ? responses : exclusive
        let ordered = shown.keys
            .sorted { providers[$0].priority < providers[$1].priority }
            .flatMap { shown[$0]!.items.sorted { $0.score > $1.score } }
        var seen = Set<String>()
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(maxResults))
    }

    // MARK: - Actions

    /// Return on a row.
    func activate(_ item: ResultItem) -> Outcome {
        if case .setQuery(let text) = item.action { return .setQuery(text) }
        Frecency.shared.record(item.id)
        switch item.action {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            copy(text)
        case .run(let command, let directory):
            run(command, in: directory)
        case .perform(let id):
            // After the panel has closed, so windows opened by the action come to the front.
            DispatchQueue.main.async { [weak self] in self?.performers[id]?() }
        case .setQuery:
            break
        }
        return .close
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
        let text: String?
        if let explicit = item.copyText {
            text = explicit
        } else if let file = item.fileURL {
            text = file.path
        } else {
            switch item.action {
            case .open(let url): text = url.isFileURL ? url.path : url.absoluteString
            case .copy(let value): text = value
            default: text = nil
            }
        }
        guard let text else { return false }
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
