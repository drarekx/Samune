import Foundation

/// Files and folders through Spotlight. Mixed in from 3 letters; alone with the "f " prefix.
@MainActor
final class FilesProvider: SearchProvider {
    let priority = 20

    private let settings = SearchSettings.shared
    private let mixedLimit = 8
    private let exclusiveLimit = 40
    private let mixedMinLength = 3
    private let debounce: UInt64 = 120_000_000
    private let timeout: TimeInterval = 1.5
    /// Hits read from Spotlight before ranking; enough to survive the exclusion filter.
    private let gatherCap = 1500

    func search(_ query: String) async -> ProviderResponse {
        let exclusive = query.hasPrefix("f ") || query.hasPrefix("F ")
        let term = (exclusive ? String(query.dropFirst(2)) : query).trimmingCharacters(in: .whitespaces)
        if exclusive {
            // "f " alone: an empty, exclusive list while the user types.
            guard !term.isEmpty else { return ProviderResponse(items: [], exclusive: true) }
        } else {
            guard settings.filesEnabled, term.count >= mixedMinLength else { return .empty }
        }

        try? await Task.sleep(nanoseconds: debounce)
        guard !Task.isCancelled else { return .empty }

        let words = FileRanking.words(of: term)
        guard !words.isEmpty, let predicate = FileRanking.predicate(words) else {
            return ProviderResponse(items: [], exclusive: exclusive)
        }
        let wholeComputer = settings.filesWholeComputer
        let scopes: [Any] = wholeComputer ? [NSMetadataQueryLocalComputerScope] : [NSMetadataQueryUserHomeScope]
        let limit = exclusive ? exclusiveLimit : mixedLimit

        let hits = await SpotlightSearch.run(predicate: predicate, scopes: scopes, timeout: timeout, cap: gatherCap)
        guard !Task.isCancelled else { return .empty }

        let ranked = await Task.detached(priority: .userInitiated) {
            FileRanking.rank(hits, term: term, words: words, limit: limit * 2)
        }.value
        guard !Task.isCancelled else { return .empty }

        let items = ranked.map { candidate -> ResultItem in
            let url = URL(fileURLWithPath: candidate.path, isDirectory: candidate.isFolder)
            let id = "file:\(candidate.path)"
            return ResultItem(id: id, title: candidate.name,
                              subtitle: SearchPaths.abbreviate((candidate.path as NSString).deletingLastPathComponent),
                              icon: .file(url), kind: candidate.isFolder ? tr("Carpeta") : tr("Archivo"),
                              action: .open(url), score: candidate.score + Frecency.shared.boost(id), fileURL: url)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        return ProviderResponse(items: Array(items), exclusive: exclusive)
    }
}

/// Query building, filtering and ranking of Spotlight hits. Pure, runs off the main thread.
enum FileRanking {
    struct Candidate: Sendable {
        let path: String
        let name: String
        let isFolder: Bool
        let score: Double
    }

    /// Folder names whose contents never show up.
    private static let skippedFolders: Set<String> = [
        "node_modules", ".git", ".build", "vendor", "Caches", "DerivedData", "Pods", "__pycache__", ".Trash",
    ]
    /// Build output and cache folders: the folder itself may show, what is inside never does.
    private static let outputFolders: Set<String> = [
        "build", "dist", "out", "target", "cache", "caches", "compiled", "coverage", "tmp", "temp",
    ]
    /// Bundles whose insides never show up.
    private static let packageExtensions: Set<String> = ["app", "framework", "bundle", "photoslibrary", "appex"]

    static func words(of term: String) -> [String] {
        term.split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "?", with: "") }
            .filter { !$0.isEmpty }
    }

    /// File name contains every word (case and diacritic insensitive), and it is not an app.
    static func predicate(_ words: [String]) -> NSPredicate? {
        guard !words.isEmpty else { return nil }
        var parts = words.map {
            NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\($0)*")
        }
        parts.append(NSPredicate(format: "%K != %@", NSMetadataItemContentTypeKey, "com.apple.application-bundle"))
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    static func isExcluded(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library/") || path == home + "/Library" { return true }
        let components = (path as NSString).pathComponents
        for (index, component) in components.enumerated() where index > 0 {
            if component.hasPrefix(".") || skippedFolders.contains(component) { return true }
            // Inside a bundle (but the bundle itself may show, e.g. a .bundle document),
            // or inside a build output or cache folder.
            if index < components.count - 1,
               packageExtensions.contains((component as NSString).pathExtension.lowercased())
                || outputFolders.contains(component.lowercased()) {
                return true
            }
        }
        // System areas when searching the whole computer.
        for prefix in ["/System/", "/private/", "/usr/", "/Library/", "/opt/", "/cores/"] where path.hasPrefix(prefix) {
            return true
        }
        return false
    }

    static func rank(_ hits: [SpotlightSearch.Hit], term: String, words: [String], limit: Int) -> [Candidate] {
        let home = NSHomeDirectory()
        let homeDepth = (home as NSString).pathComponents.count
        let now = Date()
        var seen = Set<String>()
        var candidates: [Candidate] = []
        for hit in hits where !isExcluded(hit.path) && seen.insert(hit.path).inserted {
            // Spotlight already checked that every word is in the name; Fuzzy orders them.
            let wordScores = words.compactMap { Fuzzy.score($0, hit.name) }
            let average = wordScores.isEmpty ? nil : wordScores.reduce(0, +) / Double(wordScores.count)
            var score = Fuzzy.score(term, hit.name) ?? average ?? 0.3

            if let lastUsed = hit.lastUsed {
                let days = max(0, now.timeIntervalSince(lastUsed) / 86_400)
                if days < 90 { score += 0.12 * pow(0.5, days / 14) }
            }
            if hit.isFolder { score += 0.04 }
            let depth = (hit.path as NSString).pathComponents.count - (hit.path.hasPrefix(home) ? homeDepth : 1)
            score -= min(0.15, Double(max(0, depth - 3)) * 0.015)

            candidates.append(Candidate(path: hit.path, name: hit.name, isFolder: hit.isFolder, score: score))
        }
        return Array(candidates.sorted { $0.score > $1.score }.prefix(limit))
    }
}
