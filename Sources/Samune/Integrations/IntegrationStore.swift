import AppKit
import Combine

/// Integrations found in `AppPaths.integrations` (one folder each, with a `manifest.json`).
/// STUB: replaced by the integrations worker. Keep these entry points; `AppDelegate` calls them.
@MainActor
final class IntegrationStore: ObservableObject {
    static let shared = IntegrationStore()

    /// Installs the bundled examples the first time and loads the manifests. Called once at launch.
    func start() {}

    /// Reads the manifests again and drops cached results.
    func reload() {}

    /// Opens the integrations folder in Finder.
    func openFolder() { NSWorkspace.shared.open(AppPaths.integrations) }
}
