import AppKit
import Combine

/// Integrations found in `AppPaths.integrations` (one folder each, with a `manifest.json`),
/// whether each one is enabled, and the cached output of their scripts.
@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    /// Every folder, sorted by name, including the ones whose manifest is invalid.
    @Published private(set) var integrations: [Integration] = []
    /// Ids switched off in Settings (`integrations.disabled`).
    @Published private(set) var disabled: Set<String>

    private let defaults = UserDefaults.standard
    private static let disabledKey = "integrations.disabled"
    private static let examplesKey = "integrations.examplesInstalled"

    private struct CacheEntry {
        let date: Date
        let items: [ScriptItem]
    }

    private var cache: [String: CacheEntry] = [:]
    /// Runs of lists that Samune filters itself, shared by keystrokes so typing doesn't restart them.
    private var inflight: [String: Task<RunOutcome, Never>] = [:]
    private var loadGeneration = 0

    private init() {
        disabled = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
    }

    /// Installs the bundled examples the first time and loads the manifests. Called once at launch.
    func start() {
        let installExamples = !defaults.bool(forKey: Self.examplesKey)
        if installExamples { defaults.set(true, forKey: Self.examplesKey) }
        load(installExamples: installExamples)
        installDebugHook()
    }

    /// Debug builds only: `com.egluu.samune.debug` with `integrations:<query>|<output file>` writes
    /// what `IntegrationsProvider` answers (one row per line), and `integrations-reload` reloads.
    private func installDebugHook() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated {
                if command == "integrations-reload" { IntegrationStore.shared.reload(); return }
                guard command.hasPrefix("integrations:"),
                      let bar = command.lastIndex(of: "|") else { return }
                let query = String(command[command.index(command.startIndex, offsetBy: 13)..<bar])
                let output = URL(fileURLWithPath: String(command[command.index(after: bar)...]))
                Task { @MainActor in
                    let response = await IntegrationsProvider().search(query)
                    let lines = response.items.map { item in
                        "\(item.id)\t\(item.title)\t\(item.subtitle ?? "")\t\(item.kind)\t\(item.icon)\t\(item.action)\t\(item.score)"
                    }
                    let text = "exclusive=\(response.exclusive)\n" + lines.joined(separator: "\n") + "\n"
                    try? Data(text.utf8).write(to: output)
                }
            }
        }
        #endif
    }

    /// Reads the manifests again and drops cached results.
    func reload() {
        load(installExamples: false)
    }

    /// Opens the integrations folder in Finder.
    func openFolder() { NSWorkspace.shared.open(AppPaths.integrations) }

    func openFolder(of integration: Integration) { NSWorkspace.shared.open(integration.folder) }

    // MARK: - Enabled

    func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }

    func setEnabled(_ enabled: Bool, id: String) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(disabled.sorted(), forKey: Self.disabledKey)
    }

    /// Valid and switched on: what the launcher uses.
    var active: [Integration] {
        integrations.filter { $0.isUsable && isEnabled($0.id) }
    }

    // MARK: - Loading

    private func load(installExamples: Bool) {
        clearCache()
        loadGeneration += 1
        let generation = loadGeneration
        Task.detached(priority: .userInitiated) {
            if installExamples { Self.installExamples() }
            let found = Self.scan()
            await MainActor.run {
                let store = IntegrationStore.shared
                guard generation == store.loadGeneration else { return }
                store.integrations = found
            }
        }
    }

    /// Writes every bundled example whose folder doesn't exist yet.
    nonisolated private static func installExamples() {
        for example in IntegrationExamples.all {
            let folder = AppPaths.integrations.appendingPathComponent(example.id, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: folder.path) else { continue }
            try? write(manifest: example.manifest, script: example.script, to: folder)
        }
    }

    nonisolated static func write(manifest: String, script: String, to folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data((manifest + "\n").utf8).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        let scriptURL = folder.appendingPathComponent(IntegrationExamples.scriptName)
        try Data((script + "\n").utf8).write(to: scriptURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    nonisolated private static func scan() -> [Integration] {
        let files = FileManager.default
        let folders = (try? files.contentsOfDirectory(at: AppPaths.integrations,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
        var found: [Integration] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let id = folder.lastPathComponent
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                found.append(Integration(id: id, folder: folder, manifest: nil,
                                         loadError: tr("Falta manifest.json")))
                continue
            }
            switch IntegrationManifest.decode(data) {
            case .success(let manifest):
                found.append(Integration(id: id, folder: folder, manifest: manifest, loadError: nil))
            case .failure(let error):
                found.append(Integration(id: id, folder: folder, manifest: nil, loadError: error.message))
            }
        }
        found.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // Keywords: empty or repeated ones disable the integration (the first one keeps it).
        var seen: [String: String] = [:]
        for index in found.indices {
            guard let manifest = found[index].manifest else { continue }
            let keyword = manifest.keyword.lowercased()
            if keyword.isEmpty {
                found[index].loadError = tr("Falta la palabra clave (keyword)")
            } else if let owner = seen[keyword] {
                found[index].loadError = tr("La palabra clave «%@» ya la usa «%@»", manifest.keyword, owner)
            } else {
                seen[keyword] = manifest.name
            }
        }
        return found
    }

    // MARK: - Running

    /// Items of `integration` for `query`, from the cache while it's fresh.
    /// Lists filtered by Samune (`passQuery` false) are run once and shared by every keystroke.
    func output(of integration: Integration, query: String) async -> RunOutcome {
        guard let manifest = integration.manifest else { return .items([]) }
        let key = cacheKey(integration.id, manifest.passQuery ? query : "")
        if let cached = cachedItems(key, seconds: manifest.cacheSeconds) { return .items(cached) }
        let spec = RunSpec(id: integration.id, folder: integration.folder, manifest: manifest)

        if manifest.passQuery {
            let outcome = await IntegrationRunner.run(spec, query: query)
            store(outcome, key: key)
            return outcome
        }
        let task: Task<RunOutcome, Never>
        if let running = inflight[key] {
            task = running
        } else {
            task = Task { await IntegrationRunner.run(spec, query: "") }
            inflight[key] = task
            Task { [weak self] in
                let outcome = await task.value
                guard let self, self.inflight[key] == task else { return }
                self.inflight[key] = nil
                self.store(outcome, key: key)
            }
        }
        return await task.value
    }

    /// True when `output(of:query:)` would answer from the cache without running anything.
    func hasFreshCache(_ integration: Integration, query: String) -> Bool {
        guard let manifest = integration.manifest else { return false }
        return cachedItems(cacheKey(integration.id, manifest.passQuery ? query : ""), seconds: manifest.cacheSeconds) != nil
    }

    /// "Probar" in Settings: runs with an empty query, ignoring the cache.
    func test(_ integration: Integration) async -> RunOutcome {
        guard let manifest = integration.manifest else {
            return .failure(short: integration.loadError ?? "", detail: integration.loadError ?? "")
        }
        clearCache(of: integration.id)
        let outcome = await IntegrationRunner.run(RunSpec(id: integration.id, folder: integration.folder,
                                                          manifest: manifest), query: "")
        store(outcome, key: cacheKey(integration.id, ""))
        return outcome
    }

    /// Drops cached output of one integration (its variables changed…).
    func clearCache(of id: String) {
        let prefix = id + "\u{1F}"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        for (key, task) in inflight where key.hasPrefix(prefix) {
            task.cancel()
            inflight[key] = nil
        }
    }

    private func clearCache() {
        cache = [:]
        inflight.values.forEach { $0.cancel() }
        inflight = [:]
    }

    private func cacheKey(_ id: String, _ query: String) -> String { id + "\u{1F}" + query }

    private func cachedItems(_ key: String, seconds: Double) -> [ScriptItem]? {
        guard let entry = cache[key], Date.now.timeIntervalSince(entry.date) < seconds else { return nil }
        return entry.items
    }

    private func store(_ outcome: RunOutcome, key: String) {
        guard case .items(let items) = outcome else { return }
        // Bound memory: per-query caches of passQuery integrations can pile up.
        if cache.count > 200 {
            let now = Date.now
            cache = cache.filter { now.timeIntervalSince($0.value.date) < 60 }
            if cache.count > 200 { cache = [:] }
        }
        cache[key] = CacheEntry(date: .now, items: items)
    }

    // MARK: - New integration

    /// Creates `<slug>/` from the `hola` template with `name` and a free keyword, then reloads.
    /// Returns the new folder, or a translated error.
    func create(named rawName: String) -> Result<URL, ManifestError> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(ManifestError(tr("Escribe un nombre"))) }
        let base = Self.slug(name).isEmpty ? "integracion" : Self.slug(name)
        let files = FileManager.default
        var id = base
        var counter = 2
        while files.fileExists(atPath: AppPaths.integrations.appendingPathComponent(id).path) {
            id = "\(base)-\(counter)"
            counter += 1
        }
        let usedKeywords = Set(integrations.compactMap { $0.manifest?.keyword.lowercased() })
        let keywordBase = String(base.replacingOccurrences(of: "-", with: "").prefix(8))
        var keyword = keywordBase.isEmpty ? "int" : keywordBase
        counter = 2
        while usedKeywords.contains(keyword) {
            keyword = (keywordBase.isEmpty ? "int" : keywordBase) + String(counter)
            counter += 1
        }
        let manifest: [(String, Any)] = [
            ("name", name), ("keyword", keyword), ("icon", "star"), ("command", "./run.sh"),
            ("passQuery", false), ("cacheSeconds", 300),
            ("description", tr("Creada a partir de la plantilla. Edita run.sh para devolver tus elementos.")),
        ]
        let folder = AppPaths.integrations.appendingPathComponent(id, isDirectory: true)
        do {
            try Self.write(manifest: Self.prettyJSON(manifest), script: IntegrationExamples.holaScript, to: folder)
        } catch {
            return .failure(ManifestError(error.localizedDescription))
        }
        reload()
        return .success(folder)
    }

    /// Lowercase ASCII letters, digits and dashes.
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var result = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result += "-"
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return String(result.prefix(40))
    }

    /// JSON object with keys in the given order, two-space indented.
    private static func prettyJSON(_ pairs: [(String, Any)]) -> String {
        let lines = pairs.map { key, value -> String in
            let encoded: String
            if let text = value as? String,
               let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes]) {
                encoded = String(decoding: data, as: UTF8.self)
            } else if let flag = value as? Bool {
                encoded = flag ? "true" : "false"
            } else {
                encoded = "\(value)"
            }
            return "  \"\(key)\": \(encoded)"
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n}"
    }
}
