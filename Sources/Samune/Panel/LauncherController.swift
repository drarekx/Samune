import AppKit
import Carbon
import Combine
import SwiftUI

/// Borderless panel that can take the keyboard without activating the app.
private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The floating search panel and the global shortcut that toggles it.
///
/// The panel is `.nonactivatingPanel`: it takes the keyboard while the app in front stays active,
/// so hiding it gives the focus back to that app without having to reactivate it.
@MainActor
final class LauncherController {
    static let shared = LauncherController()

    private let model = LauncherModel()
    private let engine = SearchEngine.shared
    private var panel: LauncherPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var isShown = false
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Registers the global shortcut. Called once at launch.
    func start() {
        HotkeyManager.shared.onPress = { [weak self] in self?.toggle() }
        HotkeyManager.shared.start()
        makePanel()
        installKeyMonitor()

        // @Published fires in willSet: react on the next run loop pass, with the new values in place.
        engine.$results
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.model.resultsChanged(results)
                self?.resize()
            }
            .store(in: &cancellables)
        model.$query
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                               queue: .main) { [weak self] _ in
            // Clicking outside (another app, the desktop, a Samune window) closes the panel.
            MainActor.assumeIsolated { self?.hide() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func show() {
        guard let panel else { return }
        if !isShown {
            isShown = true
            position(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        focusField(selectAll: true)
    }

    func hide() {
        guard isShown, let panel else { return }
        isShown = false
        panel.orderOut(nil)
        model.queryChanged("")
        // If a Samune window was in front before, give it the keyboard back.
        if NSApp.isActive, NSApp.keyWindow == nil,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) }) {
            window.makeKey()
        }
    }

    func toggle() {
        isShown ? hide() : show()
    }

    /// Debug hook: shows the panel with this text in the search field.
    func setQuery(_ text: String) {
        show()
        model.queryChanged(text)
        focusField(selectAll: false)
    }

    /// Re-applies the theme to the panel (called when the theme changes).
    func applyTheme() {
        guard let panel else { return }
        panel.appearance = NSAppearance(named: Theme.palette.isLight ? .aqua : .darkAqua)
        panel.contentView?.layer?.borderColor = NSColor(Theme.lineStrong).cgColor
        // `ThemedRoot` rebuilds its content with a new id, so the field is a new one: focus it again.
        if isShown {
            DispatchQueue.main.async { [weak self] in self?.focusField(selectAll: false) }
        }
    }

    // MARK: - Panel

    private func makePanel() {
        let size = NSSize(width: LauncherLayout.width, height: LauncherLayout.fieldHeight)
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.title = AppInfo.name

        // Rounded container drawn by its layer; the SwiftUI content fills it.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = LauncherLayout.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.autoresizingMask = [.width, .height]

        let root = ThemedRoot { [model, weak self] in
            LauncherView(model: model) { [weak self] item in self?.activate(item) }
        }
        // Autoresizing and no Auto Layout: constraints would make the window obey SwiftUI's minimum size.
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        panel.setContentSize(size)
        self.panel = panel
        self.hostingView = hosting
        applyTheme()
    }

    /// Centred horizontally on the screen with the mouse, a bit above the middle.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = currentHeight
        let top = visible.maxY - visible.height * 0.2
        let x = visible.midX - LauncherLayout.width / 2
        panel.setFrame(NSRect(x: x, y: top - height, width: LauncherLayout.width, height: height), display: true)
    }

    private var currentHeight: CGFloat {
        LauncherLayout.height(queryIsEmpty: model.queryIsEmpty, rows: engine.results.count)
    }

    /// Grows or shrinks the panel downwards, keeping its top edge in place. No animation:
    /// animating the frame with SwiftUI inside makes it jump.
    private func resize() {
        guard let panel else { return }
        let height = currentHeight
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func focusField(selectAll: Bool) {
        guard let panel, let field = model.field else { return }
        panel.makeKey()
        panel.makeFirstResponder(field)
        guard let editor = field.currentEditor() else { return }
        let length = (field.stringValue as NSString).length
        editor.selectedRange = selectAll ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0)
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent is not Sendable: hand plain values to the main actor.
            let press = KeyPress(window: event.windowNumber, keyCode: Int(event.keyCode),
                                 modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift]),
                                 chars: event.charactersIgnoringModifiers?.lowercased())
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isShown, press.window == self.panel?.windowNumber else { return false }
                return self.handle(press)
            }
            return handled ? nil : event
        }
    }

    private struct KeyPress: Sendable {
        let window: Int
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        let chars: String?
    }

    /// Keys of the panel. True when handled (the event is swallowed).
    private func handle(_ press: KeyPress) -> Bool {
        let modifiers = press.modifiers
        let key = press.keyCode
        let chars = press.chars

        switch key {
        case kVK_Escape:
            hide()
            return true
        case kVK_DownArrow:
            model.move(1)
            return true
        case kVK_UpArrow:
            model.move(-1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let item = model.selectedItem else { return true }
            if modifiers == .command {
                if engine.reveal(item) { hide() } else { NSSound.beep() }
            } else {
                activate(item)
            }
            return true
        default:
            break
        }

        if modifiers == .control, chars == "n" { model.move(1); return true }
        if modifiers == .control, chars == "p" { model.move(-1); return true }
        if modifiers == .command, chars == "w" { hide(); return true }
        if modifiers == .command, chars == "c" {
            // Selected text in the field copies as usual; otherwise ⌘C copies the row.
            if let editor = model.field?.currentEditor(), editor.selectedRange.length > 0 { return false }
            guard let item = model.selectedItem else { return false }
            if engine.copyText(of: item) { hide() } else { NSSound.beep() }
            return true
        }
        return false
    }

    private func activate(_ item: ResultItem) {
        switch engine.activate(item) {
        case .close:
            hide()
        case .setQuery(let text):
            model.queryChanged(text)
            focusField(selectAll: false)
        case .refresh:
            break
        }
    }
}
