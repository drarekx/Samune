import Foundation

/// Preferences of the apps and files search. Stored in `UserDefaults.standard` under `search.*`.
@MainActor
final class SearchSettings: ObservableObject {
    static let shared = SearchSettings()

    private enum Key {
        static let filesEnabled = "search.filesEnabled"
        static let filesWholeComputer = "search.filesWholeComputer"
        static let includeSystemSettings = "search.includeSystemSettings"
        static let extraAppFolders = "search.extraAppFolders"
    }

    private let defaults = UserDefaults.standard

    /// Files show up mixed with the rest from 3 letters. The "f " prefix works regardless.
    @Published var filesEnabled: Bool {
        didSet { defaults.set(filesEnabled, forKey: Key.filesEnabled) }
    }

    /// Search the whole computer instead of the home folder only.
    @Published var filesWholeComputer: Bool {
        didSet { defaults.set(filesWholeComputer, forKey: Key.filesWholeComputer) }
    }

    /// System Settings panes show up next to the apps.
    @Published var includeSystemSettings: Bool {
        didSet { defaults.set(includeSystemSettings, forKey: Key.includeSystemSettings) }
    }

    /// Folders scanned for apps besides the standard ones (absolute paths).
    @Published var extraAppFolders: [String] {
        didSet { defaults.set(extraAppFolders, forKey: Key.extraAppFolders) }
    }

    private init() {
        defaults.register(defaults: [
            Key.filesEnabled: true,
            Key.filesWholeComputer: false,
            Key.includeSystemSettings: true,
        ])
        filesEnabled = defaults.bool(forKey: Key.filesEnabled)
        filesWholeComputer = defaults.bool(forKey: Key.filesWholeComputer)
        includeSystemSettings = defaults.bool(forKey: Key.includeSystemSettings)
        extraAppFolders = defaults.stringArray(forKey: Key.extraAppFolders) ?? []
    }

    func addAppFolder(_ path: String) {
        let standardized = (path as NSString).standardizingPath
        guard !extraAppFolders.contains(standardized) else { return }
        extraAppFolders.append(standardized)
    }

    func removeAppFolder(_ path: String) {
        extraAppFolders.removeAll { $0 == path }
    }
}

enum SearchPaths {
    /// `/Users/me/Documents` → `~/Documents`.
    static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
