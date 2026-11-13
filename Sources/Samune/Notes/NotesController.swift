import AppKit
import SwiftUI

/// Starts the notes: loads the store, watches the clipboard (and the keyboard if enabled) and
/// registers the launcher handlers.
@MainActor
final class NotesController {
    static let shared = NotesController()
    private init() {}

    static let pinHandler = "notes.pin"
    static let trashHandler = "notes.trash"
    static let saveClipboardHandler = "notes.saveClipboard"

    private var started = false

    /// Called once at launch by `AppDelegate`.
    func start() {
        guard !started else { return }
        started = true
        _ = NoteStore.shared

        ClipboardWatcher.shared.onSaved = { SavedBubble.shared.show() }
        ClipboardWatcher.shared.start()
        KeyWatcher.shared.refresh()
        // Permission granted while away: check again when the app comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyWatcher.shared.refresh() }
        }

        let engine = SearchEngine.shared
        engine.handlers[Self.pinHandler] = { argument in
            guard let id = UUID(uuidString: argument) else { return }
            NoteStore.shared.togglePin(id)
        }
        engine.handlers[Self.trashHandler] = { argument in
            guard let id = UUID(uuidString: argument) else { return }
            NoteStore.shared.moveToTrash(id)
        }
        engine.handlers[Self.saveClipboardHandler] = { _ in
            if !ClipboardWatcher.shared.saveCurrent() { NSSound.beep() }
        }
        installDebugHook()
    }

    /// Whether Notity runs too: both apps would then save the same copies.
    static var notityIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.egluu.notity").isEmpty
    }

    // MARK: - Debug hook

    /// Debug builds only: `com.egluu.samune.debug` with `notes:seed`, `notes:bubble`, `notes:list`,
    /// `notes:keys`, `notes:shot:<folder>`, `notes:card:<file.png>`, `notes:pin:<index>`, `notes:trash:<index>`, `notes:restore:<index>`
    /// (index into the active list, or the trash for restore) and `notes:save` (clipboard now).
    private func installDebugHook() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { note in
            let command = note.object as? String
            MainActor.assumeIsolated { NotesController.shared.debug(command) }
        }
        #endif
    }

    #if DEBUG
    private func debug(_ command: String?) {
        guard let command, command.hasPrefix("notes:") else { return }
        let parts = command.split(separator: ":").map(String.init)
        let store = NoteStore.shared
        let index = parts.count > 2 ? Int(parts[2]) : nil
        func activeID() -> String? {
            guard let index, store.active.indices.contains(index) else { return nil }
            return store.active[index].id.uuidString
        }
        switch parts.count > 1 ? parts[1] : "" {
        case "seed": store.seed()
        case "bubble": SavedBubble.shared.show()
        case "save": SearchEngine.shared.handlers[Self.saveClipboardHandler]?("")
        case "keys":
            print("notes keyWatcher running=\(KeyWatcher.shared.isRunning) permission=\(KeyWatcher.shared.hasPermission)")
        case "pin": if let id = activeID() { SearchEngine.shared.handlers[Self.pinHandler]?(id); SearchEngine.shared.refresh() }
        case "trash": if let id = activeID() { SearchEngine.shared.handlers[Self.trashHandler]?(id); SearchEngine.shared.refresh() }
        case "restore":
            if let index, store.trash.indices.contains(index) { store.restore(store.trash[index].id) }
        case "shot":
            // Same as the app's `shot:` but answered only by this area, so other debug copies don't overwrite it.
            let folder = URL(fileURLWithPath: String(command.dropFirst("notes:shot:".count)), isDirectory: true)
            for (number, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("notes-window\(number).png"))
            }
        case "card":
            // Renders the settings card (trash open) to a PNG: the Settings window may have it scrolled away.
            let file = URL(fileURLWithPath: String(command.dropFirst("notes:card:".count)))
            let view = NotesSettingsCard(showTrash: true)
                .frame(width: 560)
                .padding(20)
                .background(Theme.window)
                .environment(\.colorScheme, Theme.palette.isLight ? .light : .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: file)
            }
        case "list":
            for note in store.active { print("notes active pinned=\(note.pinned) \(note.title)") }
            for note in store.trash { print("notes trash \(note.title)") }
        default: break
        }
        fflush(stdout)
    }
    #endif
}
