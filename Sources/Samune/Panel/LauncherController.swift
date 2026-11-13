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
        model.$menu
            .map { $0?.all.count }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
        AIChat.shared.$account
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
        installDebugCommands()
        // Suggestions ready for the first time the panel opens.
        model.queryChanged("")

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
        AIChat.shared.close()
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
            LauncherView(model: model,
                         onActivate: { [weak self] item in self?.activate(item) },
                         onAction: { [weak self] action, item in self?.run(action, on: item) })
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
        if AIChat.shared.isActive { return LauncherLayout.answerPanelHeight() }
        return LauncherLayout.height(queryIsEmpty: model.queryIsEmpty, rows: engine.results.count,
                              menuRows: model.menu?.all.count)
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
                                 chars: event.charactersIgnoringModifiers?.lowercased(),
                                 text: event.characters)
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
        /// Typed text, with Shift and Option applied (for the menu filter).
        let text: String?

        func matches(_ shortcut: KeyShortcut) -> Bool {
            var wanted: NSEvent.ModifierFlags = []
            if shortcut.command { wanted.insert(.command) }
            if shortcut.shift { wanted.insert(.shift) }
            if shortcut.option { wanted.insert(.option) }
            if shortcut.control { wanted.insert(.control) }
            guard modifiers == wanted else { return false }
            switch shortcut.key {
            case "delete": return keyCode == kVK_Delete || keyCode == kVK_ForwardDelete
            case "return": return keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
            default: return chars == shortcut.key.lowercased()
            }
        }
    }

    /// Keys of the panel. True when handled (the event is swallowed).
    ///
    /// Shortcut rule: a row's own actions (`item.actions`) win over text editing, but only when the
    /// selected row declares that shortcut; otherwise the key edits the field as usual. The built-in
    /// ⌘C copies the row only when no text is selected in the field.
    private func handle(_ press: KeyPress) -> Bool {
        if AIChat.shared.isActive { return handleInChat(press) }
        if model.menu != nil { return handleInMenu(press) }
        let modifiers = press.modifiers
        let chars = press.chars

        if modifiers == .command, chars == "k" {
            if !model.openMenu() { NSSound.beep() }
            return true
        }
        switch press.keyCode {
        case kVK_Escape:
            hide()
            return true
        case kVK_DownArrow:
            model.move(1)
            return true
        case kVK_UpArrow:
            model.move(-1)
            return true
        default:
            break
        }
        if modifiers == .control, chars == "n" { model.move(1); return true }
        if modifiers == .control, chars == "p" { model.move(-1); return true }
        if modifiers == .command, chars == "w" { hide(); return true }

        let isReturn = press.keyCode == kVK_Return || press.keyCode == kVK_ANSI_KeypadEnter
        guard let item = model.selectedItem else { return isReturn }
        let actions = engine.actions(for: item)
        if let action = actions.first(where: { $0.isExtra && $0.shortcut.map(press.matches) == true }) {
            run(action, on: item)
            return true
        }
        if modifiers == .command, chars == "c",
           let editor = model.field?.currentEditor(), editor.selectedRange.length > 0 {
            return false
        }
        if let action = actions.first(where: { !$0.isExtra && $0.shortcut.map(press.matches) == true }) {
            run(action, on: item)
            return true
        }
        if isReturn || (modifiers == .command && chars == "c") {
            // ⌘↩ without a file, ⌘C with nothing to copy.
            NSSound.beep()
            return true
        }
        return false
    }

    /// Keys while a conversation with an AI account is shown. The field holds the next question.
    private func handleInChat(_ press: KeyPress) -> Bool {
        let chat = AIChat.shared
        let modifiers = press.modifiers
        let chars = press.chars

        if press.keyCode == kVK_Escape {
            // First Esc stops an answer that is arriving; the next one goes back to the search.
            if chat.isRunning {
                chat.stop()
            } else {
                chat.close()
                model.queryChanged("")
            }
            return true
        }
        if modifiers == .command, chars == "w" { hide(); return true }
        if press.keyCode == kVK_Return || press.keyCode == kVK_ANSI_KeypadEnter, modifiers.isEmpty {
            if chat.isRunning || model.queryIsEmpty {
                NSSound.beep()
            } else {
                chat.followUp(model.query)
                model.queryChanged("")
            }
            return true
        }
        if modifiers == .command, chars == "c" {
            if let editor = model.field?.currentEditor(), editor.selectedRange.length > 0 { return false }
            if !chat.copyLast() { NSSound.beep() }
            return true
        }
        if modifiers == .command, chars == "s" {
            if !chat.saveLastImage() { NSSound.beep() }
            return true
        }
        return false
    }

    /// Keys while the actions menu is open: they never reach the search field.
    private func handleInMenu(_ press: KeyPress) -> Bool {
        guard let menu = model.menu else { return false }
        let modifiers = press.modifiers
        let chars = press.chars

        if press.keyCode == kVK_Escape || (modifiers == .command && chars == "k") {
            model.closeMenu()
            return true
        }
        if modifiers == .command, chars == "w" { hide(); return true }
        switch press.keyCode {
        case kVK_DownArrow: model.moveInMenu(1); return true
        case kVK_UpArrow: model.moveInMenu(-1); return true
        default: break
        }
        if press.keyCode == kVK_Return || press.keyCode == kVK_ANSI_KeypadEnter, modifiers.isEmpty {
            if let action = menu.selectedAction { run(action, on: menu.item) } else { NSSound.beep() }
            return true
        }
        if modifiers == .control, chars == "n" { model.moveInMenu(1); return true }
        if modifiers == .control, chars == "p" { model.moveInMenu(-1); return true }
        // Shortcuts of the listed actions work inside the menu too (before ⌫ edits the filter).
        if !modifiers.isEmpty, modifiers != .shift,
           let action = menu.all.first(where: { $0.shortcut.map(press.matches) == true }) {
            run(action, on: menu.item)
            return true
        }
        if press.keyCode == kVK_Delete {
            model.setMenuFilter(modifiers.isEmpty ? String(menu.filter.dropLast()) : "")
            return true
        }
        if modifiers.isDisjoint(with: [.command, .control]), let text = press.text,
           !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           !(text.unicodeScalars.first.map { (0xF700...0xF8FF).contains($0.value) } ?? false) {
            model.setMenuFilter(menu.filter + text)
            return true
        }
        // Other keys (⌘V, function keys…) do nothing while the menu is open.
        return modifiers.isDisjoint(with: [.command])
    }

    private func activate(_ item: ResultItem) {
        apply(engine.activate(item), from: item)
    }

    /// An entry of the actions menu, or its shortcut.
    private func run(_ action: RowAction, on item: ResultItem) {
        apply(engine.perform(action, on: item), from: item)
    }

    private func apply(_ outcome: SearchEngine.Outcome, from item: ResultItem) {
        switch outcome {
        case .close:
            hide()
        case .setQuery(let text):
            model.queryChanged(text)
            focusField(selectAll: false)
        case .refresh:
            let index = engine.results.firstIndex { $0.id == item.id } ?? model.selectedIndex ?? 0
            model.keepSelection(at: index)
            focusField(selectAll: false)
        case .stay:
            // The field is now for the next question.
            model.queryChanged("")
            focusField(selectAll: false)
        }
    }

    // MARK: - Debug

    /// Debug builds only: extra commands of the `com.egluu.samune.debug` hook for this area:
    /// `actions` opens the actions menu for the selected row, `actions:<text>` also types a filter.
    /// With the `act.` prefix (`act.query:<text>`, `act.actions`, `act.down`, `act.shot:<file.png>`)
    /// only builds that know them answer, so copies running in other worktrees stay out of the way.
    private func installDebugCommands() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { [weak self] note in
            guard var command = note.object as? String else { return }
            if command.hasPrefix("act.") { command.removeFirst(4) }
            MainActor.assumeIsolated {
                guard let self else { return }
                if command.hasPrefix("query:"), note.object as? String != command {
                    self.setQuery(String(command.dropFirst(6)))
                } else if command == "actions" || command.hasPrefix("actions:") {
                    guard self.isShown else { return }
                    if self.model.menu == nil { self.model.openMenu() }
                    if command.hasPrefix("actions:") { self.model.setMenuFilter(String(command.dropFirst(8))) }
                } else if command == "down", note.object as? String != command {
                    if self.model.menu == nil { self.model.move(1) } else { self.model.moveInMenu(1) }
                } else if command.hasPrefix("key:"), note.object as? String != command, self.isShown {
                    // Simulated key presses: "esc", "down", "up", "return", "delete", "cmd+k", "text:abc".
                    let spec = String(command.dropFirst(4))
                    let window = self.panel?.windowNumber ?? 0
                    if spec.hasPrefix("text:") {
                        for char in spec.dropFirst(5) {
                            _ = self.handle(KeyPress(window: window, keyCode: -1, modifiers: [],
                                                     chars: String(char).lowercased(), text: String(char)))
                        }
                        return
                    }
                    let codes = ["esc": kVK_Escape, "down": kVK_DownArrow, "up": kVK_UpArrow,
                                 "return": kVK_Return, "delete": kVK_Delete, "k": kVK_ANSI_K]
                    let parts = spec.split(separator: "+").map(String.init)
                    guard let key = parts.last, let code = codes[key] else { return }
                    let modifiers: NSEvent.ModifierFlags = parts.contains("cmd") ? .command : []
                    let handled = self.handle(KeyPress(window: window, keyCode: code, modifiers: modifiers,
                                                       chars: key.count == 1 ? key : nil, text: nil))
                    NSLog("act.key %@ handled=%d menu=%d shown=%d", spec, handled ? 1 : 0,
                          self.model.menu == nil ? 0 : 1, self.isShown ? 1 : 0)
                } else if command.hasPrefix("shot:"), note.object as? String != command,
                          let view = self.panel?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: String(command.dropFirst(5))))
                }
            }
        }
        #endif
    }
}
