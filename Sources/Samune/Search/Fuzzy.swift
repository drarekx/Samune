import Foundation

/// Fuzzy matching shared by every provider.
enum Fuzzy {
    /// Case and accent insensitive form used for matching.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Score in 0…1, or nil when `query` does not match `candidate`.
    /// Exact > prefix > word prefix > initials > substring > scattered letters in order.
    static func score(_ query: String, _ candidate: String) -> Double? {
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        let c = normalize(candidate)
        guard !q.isEmpty, !c.isEmpty else { return nil }
        if c == q { return 1 }
        // Shorter candidates win among equal kinds of match.
        let brevity = Double(q.count) / Double(c.count) * 0.09
        if c.hasPrefix(q) { return 0.9 + brevity }
        let words = c.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.dropFirst().contains(where: { $0.hasPrefix(q) }) { return 0.75 + brevity }
        let initials = String(words.compactMap(\.first))
        if q.count > 1, initials.hasPrefix(q) { return 0.7 + brevity }
        if c.contains(q) { return 0.55 + brevity }
        return subsequence(Array(q), Array(c)).map { 0.1 + $0 * 0.35 }
    }

    /// Best score among several fields of the same item (name, keyword, path…).
    static func score(_ query: String, in candidates: [String]) -> Double? {
        candidates.compactMap { score(query, $0) }.max()
    }

    /// 0…1 for letters found in order; contiguous runs and word starts count more.
    private static func subsequence(_ q: [Character], _ c: [Character]) -> Double? {
        var qi = 0
        var points = 0.0
        var previousMatched = false
        for (index, char) in c.enumerated() where qi < q.count {
            if char == q[qi] {
                let wordStart = index == 0 || !(c[index - 1].isLetter || c[index - 1].isNumber)
                points += previousMatched ? 1 : (wordStart ? 0.8 : 0.3)
                previousMatched = true
                qi += 1
            } else {
                previousMatched = false
            }
        }
        guard qi == q.count else { return nil }
        return points / Double(q.count)
    }
}
