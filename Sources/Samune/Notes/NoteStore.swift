import AppKit
import Foundation

/// A saved piece of text. Same model and JSON as Notity, so its notes can be imported as they are.
struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// When it was saved (or saved again).
    var created: Date
    /// App that was in front when it was copied.
    var app: String?
    var pinned = false
    /// Set when the note is in the trash.
    var trashed: Date?

    init(id: UUID = UUID(), text: String, created: Date, app: String? = nil, pinned: Bool = false, trashed: Date? = nil) {
        self.id = id
        self.text = text
        self.created = created
        self.app = app
        self.pinned = pinned
        self.trashed = trashed
    }

    /// Lenient: only `text` is required, so a hand-edited or older file still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        app = try container.decodeIfPresent(String.self, forKey: .app)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        trashed = try container.decodeIfPresent(Date.self, forKey: .trashed)
    }

    /// First non-empty line, for lists and menus.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// Second non-empty line, if any.
    var secondLine: String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.count > 1 ? lines[1] : nil
    }

    /// Case and accent insensitive: every word of the query must appear.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || (app?.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }
}

/// Notes on disk: `~/Library/Application Support/Samune/notes.json` (0600).
@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    /// Days a trashed note can be restored before it is deleted for good.
    static let trashDays = 7
    /// Longer texts are not saved (they are rarely a note and slow the lists down).
    static let maxLength = 200_000

    @Published private(set) var notes: [Note] = []
    private let file = AppPaths.support.appendingPathComponent("notes.json")
    private let saveQueue = DispatchQueue(label: "com.egluu.samune.notes.save")
    private var purgeTimer: Timer?

    private init() {
        load()
        purge()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { NoteStore.shared.purge() }
        }
    }

    /// Notes not in the trash, newest first.
    var active: [Note] {
        // Newest first, pinned or not: a pinned note keeps its place by date and only never expires.
        notes.filter { $0.trashed == nil }.sorted {
            $0.created > $1.created
        }
    }

    /// Trashed notes, most recently trashed first.
    var trash: [Note] {
        notes.filter { $0.trashed != nil }.sorted { ($0.trashed ?? .distantPast) > ($1.trashed ?? .distantPast) }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }

    /// Saves a text. The same text again moves the existing note to the top. Returns false if ignored.
    @discardableResult
    func add(_ text: String, app: String?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= Self.maxLength else { return false }
        if let index = notes.firstIndex(where: { $0.text == text }) {
            notes[index].created = Date()
            notes[index].trashed = nil
            if let app { notes[index].app = app }
        } else {
            notes.append(Note(text: text, created: Date(), app: app))
        }
        save()
        return true
    }

    func togglePin(_ id: Note.ID) {
        update(id) { $0.pinned.toggle() }
    }

    func moveToTrash(_ id: Note.ID) {
        update(id) { $0.trashed = Date(); $0.pinned = false }
    }

    func restore(_ id: Note.ID) {
        update(id) { $0.trashed = nil; $0.created = Date() }
    }

    func deleteForever(_ id: Note.ID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func emptyTrash() {
        notes.removeAll { $0.trashed != nil }
        save()
    }

    /// Expired notes go to the trash; old trash is deleted.
    func purge(now: Date = Date()) {
        var changed = false
        let days = NotesSettings.shared.expiryDays
        for index in notes.indices where notes[index].trashed == nil && !notes[index].pinned && days > 0 {
            if notes[index].created < now.addingTimeInterval(-Double(days) * 86_400) {
                notes[index].trashed = now
                changed = true
            }
        }
        let limit = now.addingTimeInterval(-Double(Self.trashDays) * 86_400)
        let before = notes.count
        notes.removeAll { ($0.trashed ?? .distantFuture) < limit }
        if changed || notes.count != before { save() }
    }

    #if DEBUG
    /// Sample notes for screenshots.
    func seed() {
        let now = Date()
        notes = [
            Note(text: "Revisa este código Swift y propón mejoras de rendimiento sin cambiar la API pública. Explica cada cambio en una línea.",
                 created: now.addingTimeInterval(-120), app: "Visual Studio Code"),
            Note(text: "git log --oneline --graph --decorate -20", created: now.addingTimeInterval(-3_600), app: "Terminal", pinned: true),
            Note(text: "Resume este hilo en 5 puntos y dime qué decisiones quedan pendientes.\n\nTono: directo, sin adornos.",
                 created: now.addingTimeInterval(-7_200), app: "Safari"),
            Note(text: "https://developer.apple.com/documentation/appkit/nspasteboard", created: now.addingTimeInterval(-86_400), app: "Safari"),
            Note(text: "Calle Mayor 12, 3º 2ª — 08001 Barcelona", created: now.addingTimeInterval(-2 * 86_400), app: "Mail"),
            Note(text: "Borrador antiguo que ya no hace falta", created: now.addingTimeInterval(-9 * 86_400), app: "Notas",
                 trashed: now.addingTimeInterval(-3_600)),
        ]
        save()
    }
    #endif

    // MARK: - Disk

    /// Reads `notes.json`. A file that can't be decoded is kept as `notes.json.bak` and the store
    /// starts empty. Without a file (first run), Notity's notes are imported once, read only.
    private func load() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else {
            importFromNotity()
            return
        }
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = Self.decode(data) {
            notes = decoded
            return
        }
        let backup = file.appendingPathExtension("bak")
        // An older backup goes to the Trash, never deleted outright.
        if manager.fileExists(atPath: backup.path) { try? manager.trashItem(at: backup, resultingItemURL: nil) }
        try? manager.moveItem(at: file, to: backup)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        notes = []
        // An empty file right away, so the next launch doesn't take it for a first run (Notity import).
        save()
    }

    /// `~/Library/Application Support/Notity/notes.json`, if Notity was used on this Mac.
    static var notityFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notity", isDirectory: true).appendingPathComponent("notes.json")
    }

    private func importFromNotity() {
        guard let data = try? Data(contentsOf: Self.notityFile), let imported = Self.decode(data), !imported.isEmpty else { return }
        notes = imported
        save()
    }

    private static func decode(_ data: Data) -> [Note]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Note].self, from: data)
    }

    private func update(_ id: Note.ID, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[index])
        save()
    }

    private func save() {
        let snapshot = notes
        let file = file
        saveQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: file, options: [.atomic])
            // Notes can hold private text: only the user can read the file.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}
