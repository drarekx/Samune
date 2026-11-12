import AppKit
import Combine
import SwiftUI

/// App identity shared by the updater, menus and storage.
enum AppInfo {
    static let name = "Samune"
    /// GitHub repository the updater and installer read releases from.
    static let repo = "drarekx/Samune"
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/drarek")!
    /// Menu bar app (no Dock icon). `build-app.sh` sets LSUIElement to match (`MENU_BAR`).
    static let menuBarApp = true
    /// SF Symbol of the menu bar icon.
    static let statusSymbol = "magnifyingglass"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        if AppInfo.menuBarApp { setupStatusItem() }
        Localizer.shared.$choice
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.setupMainMenu() }
            .store(in: &cancellables)
        // @Published fires in willSet: apply after the change.
        Settings.shared.$theme
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &cancellables)
        LoginItem.enableOnceFromApplications()
        Updater.shared.start()
        installDebugHook()
        registerCommands()
        IntegrationStore.shared.start()
        LauncherController.shared.start()

        // The first launch shows the settings, where the shortcut is; afterwards the app stays in the menu bar.
        if !Settings.shared.hasLaunched { showSettings() }
        Settings.shared.hasLaunched = true
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// Built-in commands of the launcher (`CommandsProvider`).
    private func registerCommands() {
        SearchEngine.shared.performers = [
            "settings": { [weak self] in self?.showSettings() },
            "reloadIntegrations": { IntegrationStore.shared.reload() },
            "openIntegrationsFolder": { IntegrationStore.shared.openFolder() },
            "checkForUpdates": { Task { await Updater.shared.check(userInitiated: true) } },
            "quit": { NSApp.terminate(nil) },
        ]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: AppInfo.statusSymbol, accessibilityDescription: AppInfo.name)
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt every time it opens, so state and language are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem(title: tr("Abrir %@", AppInfo.name)) { [weak self] in self?.showMainWindow() })
        menu.addItem(ClosureMenuItem(title: tr("Recargar integraciones")) { IntegrationStore.shared.reload() })
        menu.addItem(ClosureMenuItem(title: tr("Carpeta de integraciones…")) { IntegrationStore.shared.openFolder() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: tr("Ajustes…"), keyEquivalent: ",") { [weak self] in self?.showSettings() })
        menu.addItem(.separator())
        let updating = Updater.shared.state != .idle
        let update = ClosureMenuItem(title: updating ? tr("Actualizando…") : tr("Buscar actualizaciones…")) {
            Task { await Updater.shared.check(userInitiated: true) }
        }
        update.isEnabled = !updating
        menu.addItem(update)
        let coffee = ClosureMenuItem(title: tr("Invítame a un café…")) { NSWorkspace.shared.open(AppInfo.buyMeACoffee) }
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        menu.addItem(coffee)
        let version = NSMenuItem(title: "\(AppInfo.name) \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(ClosureMenuItem(title: tr("Salir de %@", AppInfo.name), keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Windows

    /// The "main window" of Samune is the launcher panel.
    @objc func showMainWindow() {
        LauncherController.shared.show()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: tr("Ajustes de %@", AppInfo.name), size: NSSize(width: 620, height: 720),
                                        minSize: NSSize(width: 520, height: 480), autosave: "SettingsWindow",
                                        root: ThemedRoot { SettingsPane() })
        }
        settingsWindow?.title = tr("Ajustes de %@", AppInfo.name)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, minSize: NSSize, autosave: String,
                                           root: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.titlebarAppearsTransparent = true
        let hosting = NSHostingController(rootView: root)
        // NSHostingController would otherwise shrink the window to its ideal size.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
        window.center()
        // After setContentSize: restores the last frame, if any, and saves it from now on.
        window.setFrameAutosaveName(autosave)
        style(window)
        return window
    }

    private func style(_ window: NSWindow) {
        window.appearance = NSAppearance(named: Theme.palette.isLight ? .aqua : .darkAqua)
        window.backgroundColor = Theme.nsWindow
    }

    private func applyTheme() {
        if let settingsWindow { style(settingsWindow) }
        LauncherController.shared.applyTheme()
    }

    // MARK: - Main menu

    /// Dock apps show it; menu bar apps don't, but it still gives text fields ⌘C/⌘V/⌘A and windows ⌘W.
    private func setupMainMenu() {
        let main = NSMenu()
        let name = AppInfo.name

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Acerca de %@", name),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Ajustes…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: tr("Buscar actualizaciones…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        let coffee = appMenu.addItem(withTitle: tr("Invítame a un café…"), action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffee.target = self
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Ocultar %@", name), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: tr("Ocultar otras"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: tr("Mostrar todo"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Salir de %@", name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("Edición"))
        edit.addItem(withTitle: tr("Deshacer"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: tr("Rehacer"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Cortar"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Pegar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Seleccionar todo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: tr("Ventana"))
        window.addItem(withTitle: tr("Cerrar ventana"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: tr("Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(.separator())
        window.addItem(withTitle: name, action: #selector(showMainWindow), keyEquivalent: "0").target = self
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    @objc private func checkForUpdates() { Task { await Updater.shared.check(userInitiated: true) } }
    @objc private func openBuyMeACoffee() { NSWorkspace.shared.open(AppInfo.buyMeACoffee) }

    // MARK: - Debug hook

    /// Debug builds only: `DistributedNotificationCenter` `com.egluu.samune.debug` with an object
    /// string drives the app for screenshots and checks: `panel`, `hide`, `query:<text>`, `settings`, `theme:<id>`, `shot:<folder>`.
    private func installDebugHook() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                switch note.object as? String {
                case "main", "panel": self?.showMainWindow()
                case "hide": LauncherController.shared.hide()
                case let command? where command.hasPrefix("query:"):
                    LauncherController.shared.setQuery(String(command.dropFirst(6)))
                case "settings": self?.showSettings()
                case let command? where command.hasPrefix("shot:"):
                    // Renders every visible window of the app to <folder>/<title>.png (no permissions needed).
                    let folder = URL(fileURLWithPath: String(command.dropFirst(5)), isDirectory: true)
                    for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                        guard let view = window.contentView?.superview ?? window.contentView,
                              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        let name = window.title.isEmpty ? "window\(index)" : window.title
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: folder.appendingPathComponent("\(name).png"))
                    }
                case let command? where command.hasPrefix("theme:"):
                    if let theme = AppTheme(rawValue: String(command.dropFirst(6))) { Settings.shared.theme = theme }
                default: break
                }
            }
        }
        #endif
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
