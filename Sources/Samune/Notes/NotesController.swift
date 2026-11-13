import AppKit

/// Stub: watches the clipboard and saves what is copied twice in a row.
@MainActor
final class NotesController {
    static let shared = NotesController()
    private init() {}

    /// Called once at launch by `AppDelegate`.
    func start() {}
}
