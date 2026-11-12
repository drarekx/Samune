import AppKit

/// Where the icon of a result comes from.
enum ItemIcon: Hashable {
    /// Finder icon of a file, folder or app bundle.
    case file(URL)
    /// SF Symbol name.
    case symbol(String)
    /// Local image file (png, jpg, icns…).
    case image(URL)
    /// Remote image (favicon…). Loaded lazily and cached by the panel.
    case remote(URL)
}

/// What happens when a result is activated with Return.
enum ResultAction: Hashable {
    /// Opens a file, folder, app or web URL with the default handler.
    case open(URL)
    /// Copies text to the clipboard.
    case copy(String)
    /// Runs a shell command (`/bin/zsh -lc`) in an optional working directory.
    case run(command: String, directory: URL?)
    /// Replaces the text of the search field (used to enter an integration: "bm ").
    case setQuery(String)
    /// Runs code inside the app (built-in commands).
    case perform(id: String)
}

/// One row of the launcher.
struct ResultItem: Identifiable, Hashable {
    /// Stable across searches: used for selection and frecency ("app:/Applications/Safari.app").
    let id: String
    var title: String
    var subtitle: String?
    var icon: ItemIcon
    /// Short label shown at the right of the row, already translated ("App", "Archivo"…).
    var kind: String
    var action: ResultAction
    /// Match quality, higher first. Providers get it from `Fuzzy.score` (0…1) plus `Frecency.boost`.
    var score: Double = 0
    /// File behind the result, if any: ⌘↩ reveals it in Finder.
    var fileURL: URL?
    /// Text for ⌘C. Defaults to the path or the URL of the action.
    var copyText: String?
}

/// What a provider answers to one query.
struct ProviderResponse {
    var items: [ResultItem] = []
    /// True when the query addresses this provider only ("f report", "bm laravel"):
    /// the launcher then shows nothing but these items.
    var exclusive = false

    static let empty = ProviderResponse()
}

/// A source of results. Implementations live in `Providers/` and `Integrations/`.
///
/// `search` is called on the main actor for every keystroke with the raw text of the field
/// (never empty). Heavy work goes off the main thread; honour `Task.isCancelled`, since a newer
/// keystroke cancels the task. Return quickly: each provider's results show up as they arrive.
@MainActor
protocol SearchProvider: AnyObject {
    /// Lower goes first in the list (apps 0, commands 5, integrations 10, files 20).
    var priority: Int { get }
    func search(_ query: String) async -> ProviderResponse
}
