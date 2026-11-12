import AppKit

/// The floating search panel and the global shortcut that toggles it.
/// STUB: replaced by the panel worker. Keep these entry points; `AppDelegate` calls them.
@MainActor
final class LauncherController {
    static let shared = LauncherController()

    /// Registers the global shortcut. Called once at launch.
    func start() {}

    func show() {}
    func hide() {}
    func toggle() {}

    /// Debug hook: shows the panel with this text in the search field.
    func setQuery(_ text: String) {}

    /// Re-applies the theme to the panel (called when the theme changes).
    func applyTheme() {}
}
