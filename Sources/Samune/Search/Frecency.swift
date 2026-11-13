import Foundation

/// Remembers what the user opens, so frequent and recent results rank higher.
/// Stored in `~/Library/Application Support/Samune/frecency.json`.
@MainActor
final class Frecency {
    static let shared = Frecency()

    private struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    private var entries: [String: Entry] = [:]
    private let fileURL = AppPaths.support.appendingPathComponent("frecency.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    /// Called by the engine when a result is activated.
    func record(_ id: String) {
        var entry = entries[id] ?? Entry(count: 0, lastUsed: .now)
        entry.count += 1
        entry.lastUsed = .now
        entries[id] = entry
        save()
    }

    /// 0…0.5 to add to a fuzzy score: grows with use and fades over weeks without use.
    func boost(_ id: String) -> Double {
        guard let entry = entries[id] else { return 0 }
        let days = Date.now.timeIntervalSince(entry.lastUsed) / 86_400
        let recency = pow(0.5, days / 14)
        let frequency = min(1, log2(Double(entry.count) + 1) / 5)
        return 0.5 * frequency * (0.4 + 0.6 * recency)
    }

    /// Ids starting with `prefix` ("app:"), most boosted first, with their boost. Empty without history.
    func top(prefix: String, limit: Int) -> [(id: String, boost: Double)] {
        entries.keys
            .filter { $0.hasPrefix(prefix) }
            .map { (id: $0, boost: boost($0)) }
            .sorted { $0.boost != $1.boost ? $0.boost > $1.boost : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    private func save() {
        // Keep the file small: the 500 most recently used.
        if entries.count > 600 {
            let keep = entries.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(500)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        let snapshot = entries
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Folders of the app.
enum AppPaths {
    /// `~/Library/Application Support/Samune/` (created on first use).
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// `~/Library/Application Support/Samune/Integrations/`.
    static let integrations: URL = {
        let url = support.appendingPathComponent("Integrations", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
