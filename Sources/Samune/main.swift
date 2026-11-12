import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar apps have no Dock icon (Info.plist also sets LSUIElement).
    app.setActivationPolicy(AppInfo.menuBarApp ? .accessory : .regular)
    app.run()
}
