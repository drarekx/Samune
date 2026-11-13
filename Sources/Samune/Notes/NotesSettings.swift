import Foundation

/// Preferences of the notes, persisted in `UserDefaults.standard` under `notes.*`.
@MainActor
final class NotesSettings: ObservableObject {
    static let shared = NotesSettings()
    private let defaults = UserDefaults.standard

    /// Copying the same text twice in a row saves it as a note.
    @Published var doubleCopy: Bool { didSet { defaults.set(doubleCopy, forKey: "notes.doubleCopy") } }
    /// Maximum time between the two copies, in seconds.
    @Published var doubleCopyWindow: Double { didSet { defaults.set(doubleCopyWindow, forKey: "notes.doubleCopyWindow") } }
    /// Detect double ⌘C from the keyboard too (Input Monitoring), for apps like iTerm2.
    @Published var keyboardDetection: Bool { didSet { defaults.set(keyboardDetection, forKey: "notes.keyboardDetection") } }
    /// Days a note is kept before it goes to the trash. 0 = never.
    @Published var expiryDays: Int {
        didSet {
            defaults.set(expiryDays, forKey: "notes.expiryDays")
            // After the change is stored (didSet), so `purge` reads the new value.
            DispatchQueue.main.async { NoteStore.shared.purge() }
        }
    }

    private init() {
        doubleCopy = defaults.object(forKey: "notes.doubleCopy") as? Bool ?? true
        doubleCopyWindow = defaults.object(forKey: "notes.doubleCopyWindow") as? Double ?? 0.5
        keyboardDetection = defaults.bool(forKey: "notes.keyboardDetection")
        expiryDays = defaults.object(forKey: "notes.expiryDays") as? Int ?? 7
    }
}
