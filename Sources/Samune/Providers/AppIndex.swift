import Foundation
import IOKit.ps

/// One searchable application or System Settings pane.
struct AppEntry: Sendable {
    enum Kind: Sendable { case app, settingsPane }

    let kind: Kind
    /// Shown as the title: the localized name.
    let title: String
    /// Every name the entry answers to (localized, file name, bundle name, English…).
    let names: [String]
    /// The bundle (`.app` or `.appex`).
    let bundleURL: URL
    /// What Return opens: the app itself or an `x-apple.systempreferences:` URL.
    let openURL: URL
}

/// Scans the disk for applications and System Settings panes. Pure functions, run off the main thread.
enum AppScanner {
    static let systemSettingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    /// Standard folders; one level of subfolders is scanned too ("Utilities", "Adobe…").
    static var standardFolders: [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            NSHomeDirectory() + "/Applications",
        ]
    }

    /// Apps found outside the standard folders.
    static let singleApps = ["/System/Library/CoreServices/Finder.app"]

    static func scanApps(extraFolders: [String]) -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var entries: [AppEntry] = []

        func add(_ url: URL) {
            let real = url.resolvingSymlinksInPath().path
            guard seen.insert(real).inserted, let entry = appEntry(url) else { return }
            entries.append(entry)
        }

        func children(of folder: URL) -> [URL] {
            // Not `.skipsHiddenFiles`: /Applications/Safari.app is a symlink with the hidden flag.
            ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey]))
                ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
        }

        for folder in standardFolders + extraFolders {
            for item in children(of: URL(fileURLWithPath: folder, isDirectory: true)) {
                if item.pathExtension == "app" {
                    add(item)
                } else if isPlainFolder(item) {
                    // One level down, without entering bundles.
                    for inner in children(of: item) where inner.pathExtension == "app" {
                        add(inner)
                    }
                }
            }
        }
        for path in singleApps where fm.fileExists(atPath: path) {
            add(URL(fileURLWithPath: path))
        }
        return entries
    }

    private static func isPlainFolder(_ url: URL) -> Bool {
        guard let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        else { return false }
        return values.isDirectory == true && values.isPackage != true
    }

    private static func appEntry(_ url: URL) -> AppEntry? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let fileName = url.deletingPathExtension().lastPathComponent
        let contents = url.resolvingSymlinksInPath().appendingPathComponent("Contents")
        var plainNames: [String] = []
        if let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = info[key] as? String, !name.isEmpty { plainNames.append(name) }
            }
        }
        let localized = localizedNames(resources: contents.appendingPathComponent("Resources"))
        // Like Finder: the localized name unless the user renamed the bundle ("Xcode-16.app").
        let renamed = !(plainNames + localized).contains(fileName)
        let title = renamed ? fileName : (localized.first ?? fileName)
        var display = fm.displayName(atPath: url.path)
        if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
        let names = [title, fileName, display] + localized + plainNames
        return AppEntry(kind: .app, title: title, names: unique(names), bundleURL: url, openURL: url)
    }

    // MARK: - System Settings panes

    private static let panesFolder = "/System/Library/ExtensionKit/Extensions"
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"
    /// Internal panes with no place in the sidebar.
    private static let hiddenPanes: Set<String> = ["com.apple.FollowUpSettings.FollowUpSettingsExtension"]

    /// Panes are app extensions whose extension point is `com.apple.Settings.extension.ui`.
    /// Their names live in `Contents/Resources/InfoPlist.loctable` (language → keys).
    static func scanSettingsPanes() -> [AppEntry] {
        let folder = URL(fileURLWithPath: panesFolder, isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var entries: [AppEntry] = []
        var seen = Set<String>()
        for appex in items where appex.pathExtension == "appex" {
            let contents = appex.appendingPathComponent("Contents")
            guard let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")),
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  let url = URL(string: "x-apple.systempreferences:\(bundleID)"),
                  seen.insert(bundleID).inserted
            else { continue }
            let settings = attributes["SettingsExtensionAttributes"] as? [String: Any]
            // Panes that do not accept the URL scheme cannot be opened directly.
            if let allows = settings?["allowsXAppleSystemPreferencesURLScheme"] as? Bool, !allows { continue }

            let resources = contents.appendingPathComponent("Resources")
            var localized = localizedNames(resources: resources)
            if localized.isEmpty, let key = sidebarNameKey(settings?["representations"] as? [[String: Any]]) {
                // Panes like Battery name themselves in the sidebar through a key of Localizable.loctable.
                localized = localizedStrings(key, loctable: resources.appendingPathComponent("Localizable.loctable"))
            }
            guard let title = localized.first, !title.hasSuffix("Extension"), !hiddenPanes.contains(bundleID)
            else { continue }
            var names = localized
            if let plain = info["CFBundleDisplayName"] as? String { names.append(plain) }
            entries.append(AppEntry(kind: .settingsPane, title: title, names: unique(names),
                                    bundleURL: appex, openURL: url))
        }
        return entries
    }

    /// `CFBundleDisplayName` (or `CFBundleName`) in each of the user's system languages, then English.
    /// Read from `InfoPlist.loctable` (language → keys) or from `<language>.lproj/InfoPlist.strings`.
    static func localizedNames(resources: URL) -> [String] {
        let loctable = NSDictionary(contentsOf: resources.appendingPathComponent("InfoPlist.loctable"))
            as? [String: Any]
        let languages: [String]
        if let loctable {
            languages = loctable.keys.filter { $0 != "LocProvenance" }
        } else {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
            languages = items.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }
        }
        return userLanguages(among: languages).compactMap { language in
            let strings: [String: Any]?
            if let loctable {
                strings = loctable[language] as? [String: Any]
            } else {
                let file = resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")
                strings = NSDictionary(contentsOf: file) as? [String: Any]
            }
            let value = (strings?["CFBundleDisplayName"] as? String) ?? (strings?["CFBundleName"] as? String)
            return value?.isEmpty == false ? value : nil
        }
        .uniqued()
    }

    /// `key` of a `.loctable` in each of the user's system languages, then English.
    private static func localizedStrings(_ key: String, loctable url: URL) -> [String] {
        guard let table = NSDictionary(contentsOf: url) as? [String: Any] else { return [] }
        let languages = table.keys.filter { $0 != "LocProvenance" }
        return userLanguages(among: languages).compactMap { language in
            ((table[language] as? [String: Any])?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        .uniqued()
    }

    /// The localizations of `available` that match the user's system languages, in order, then English.
    private static func userLanguages(among available: [String]) -> [String] {
        guard !available.isEmpty else { return [] }
        var chosen: [String] = []
        for preferred in Locale.preferredLanguages + ["en"] {
            // `preferredLocalizations` falls back to anything; keep it only if the language matches.
            let code = Locale(identifier: preferred).language.languageCode
            guard let best = Bundle.preferredLocalizations(from: available, forPreferences: [preferred]).first,
                  Locale(identifier: best).language.languageCode == code
            else { continue }
            chosen.append(best)
        }
        if available.contains("Base") { chosen.append("Base") }
        return chosen.uniqued()
    }

    /// Sidebar name key of the representation that applies to this Mac (battery or not).
    private static func sidebarNameKey(_ representations: [[String: Any]]?) -> String? {
        guard let representations, !representations.isEmpty else { return nil }
        let battery = hasBattery()
        let applying = representations.first { representation in
            guard let predicate = representation["predicate"] as? String else { return true }
            if predicate.contains("powersource.battery == YES") { return battery }
            if predicate.contains("powersource.battery != YES") { return !battery }
            return representation["hidden"] as? Bool != true
        }
        return (applying ?? representations[0])["sidebar-name"] as? String
    }

    private static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    private static func unique(_ names: [String]) -> [String] {
        names.uniqued()
    }
}

private extension Array where Element == String {
    /// Same order, without repeats.
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

/// In-memory index, built off the main thread on first use and refreshed when stale.
actor AppIndex {
    private var apps: [AppEntry] = []
    private var panes: [AppEntry]?
    private var scannedAt: Date?
    private var scannedFolders: [String] = []
    private var scanTask: Task<[AppEntry], Never>?

    /// Minimum time between two scans triggered by searches.
    private let maxAge: TimeInterval = 60

    /// Duration of the last scan, for diagnostics.
    private(set) var lastScanDuration: TimeInterval = 0

    /// The current entries. The first call waits for the scan; later ones return at once
    /// and refresh in the background when the index is older than a minute.
    func entries(extraFolders: [String], includePanes: Bool) async -> [AppEntry] {
        if scannedAt == nil || extraFolders != scannedFolders {
            await rescan(extraFolders: extraFolders)
        } else if let scannedAt, Date().timeIntervalSince(scannedAt) > maxAge {
            Task { await self.rescan(extraFolders: extraFolders) }
        }
        if includePanes {
            if panes == nil {
                panes = await Task.detached(priority: .userInitiated) { AppScanner.scanSettingsPanes() }.value
            }
            return apps + (panes ?? [])
        }
        return apps
    }

    /// True when `path` is already indexed (used to rescan when an unknown app launches).
    func contains(_ path: String) -> Bool {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return apps.contains { $0.bundleURL.resolvingSymlinksInPath().path == real }
    }

    /// Scans now unless a scan is already running, in which case it waits for that one.
    func rescan(extraFolders: [String]) async {
        if let scanTask {
            _ = await scanTask.value
            if extraFolders == scannedFolders { return }
        }
        let task = Task.detached(priority: .userInitiated) { AppScanner.scanApps(extraFolders: extraFolders) }
        scanTask = task
        let start = Date()
        let result = await task.value
        lastScanDuration = Date().timeIntervalSince(start)
        apps = result
        scannedAt = Date()
        scannedFolders = extraFolders
        scanTask = nil
    }
}
