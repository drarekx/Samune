import Foundation

/// Saved notes in the launcher: "n " + text lists them (exclusive); a normal search of two or more
/// characters shows the best matching ones too.
@MainActor
final class NotesProvider: SearchProvider {
    let priority = 8

    private let exclusiveLimit = 50
    private let mixedLimit = 5
    private let titleLimit = 90

    func search(_ query: String) async -> ProviderResponse {
        let store = NoteStore.shared
        let exclusive = query.hasPrefix("n ") || query.hasPrefix("N ")
        let term = (exclusive ? String(query.dropFirst(2)) : query).trimmingCharacters(in: .whitespaces)

        if exclusive {
            var items: [ResultItem] = []
            // Typed on purpose: first. With "n " alone: last, so Return copies the newest note.
            if matchesSaveRow(term) {
                items.append(saveClipboardRow(score: 2))
            } else if term.isEmpty {
                items.append(saveClipboardRow(score: -1))
            }
            let notes = store.active.filter { term.isEmpty || matches(term, $0) != nil }.prefix(exclusiveLimit)
            // Keep the store's order (pinned, then newest): the score only preserves it.
            for (index, note) in notes.enumerated() {
                items.append(row(note, score: 1 - Double(index) * 0.001))
            }
            return ProviderResponse(items: items, exclusive: true)
        }

        guard term.count >= 2 else { return .empty }
        // The tiny index term keeps pinned and newer notes first among equal matches.
        var items = store.active.enumerated().compactMap { index, note -> ResultItem? in
            guard let score = matches(term, note) else { return nil }
            return row(note, score: score + Frecency.shared.boost(Self.id(note)) - Double(index) * 0.0001)
        }
        items.sort { $0.score > $1.score }
        items = Array(items.prefix(mixedLimit))
        if matchesSaveRow(term) { items.append(saveClipboardRow(score: saveRowScore(term) ?? 0)) }
        return ProviderResponse(items: items)
    }

    /// Pinned notes for the empty search field.
    func suggestions() async -> [ResultItem] {
        NoteStore.shared.active.filter(\.pinned).prefix(3).enumerated().map { index, note in
            row(note, score: 0.5 - Double(index) * 0.01)
        }
    }

    // MARK: - Rows

    static func id(_ note: Note) -> String { "note:\(note.id.uuidString)" }

    private func row(_ note: Note, score: Double) -> ResultItem {
        var title = note.title
        if title.count > titleLimit { title = String(title.prefix(titleLimit)) + "…" }
        var details = [Self.relativeDate(note.created)]
        if note.pinned { details.append(tr("Fijada")) }
        if let second = note.secondLine { details.append(String(second.prefix(titleLimit))) }
        let uuid = note.id.uuidString
        return ResultItem(
            id: Self.id(note),
            title: title,
            subtitle: details.joined(separator: " · "),
            icon: .symbol(note.pinned ? "pin.fill" : "note.text"),
            kind: tr("Nota"),
            action: .copy(note.text),
            score: score,
            copyText: note.text,
            actions: [
                ItemAction(id: "pin", title: note.pinned ? tr("Desfijar") : tr("Fijar"),
                           symbol: note.pinned ? "pin.slash" : "pin",
                           shortcut: KeyShortcut(key: "p"),
                           action: .invoke(handler: NotesController.pinHandler, argument: uuid),
                           keepsPanelOpen: true),
                ItemAction(id: "trash", title: tr("Mover a la papelera"), symbol: "trash",
                           shortcut: KeyShortcut(key: "delete"),
                           action: .invoke(handler: NotesController.trashHandler, argument: uuid),
                           keepsPanelOpen: true, destructive: true),
            ])
    }

    private func saveClipboardRow(score: Double) -> ResultItem {
        ResultItem(id: "notes:saveClipboard",
                   title: tr("Guardar el portapapeles como nota"),
                   subtitle: tr("Guarda ahora el texto copiado."),
                   icon: .symbol("square.and.arrow.down"),
                   kind: tr("Notas"),
                   action: .invoke(handler: NotesController.saveClipboardHandler, argument: ""),
                   score: score)
    }

    private func matchesSaveRow(_ term: String) -> Bool {
        (saveRowScore(term) ?? 0) >= 0.5
    }

    /// Against the translated title and the Spanish one, whatever the UI language.
    private func saveRowScore(_ term: String) -> Double? {
        let key = "Guardar el portapapeles como nota"
        return Fuzzy.score(term, in: [tr("Guardar el portapapeles como nota"), key])
    }

    /// Fuzzy on the title, or every word somewhere in the text. Nil when it doesn't match.
    private func matches(_ term: String, _ note: Note) -> Double? {
        if let score = Fuzzy.score(term, note.title), score >= 0.5 { return score }
        return note.matches(term) ? 0.4 : nil
    }

    static func relativeDate(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return tr("ahora") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Localizer.shared.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
