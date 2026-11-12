import Foundation

/// Applications and System Settings panes.
/// STUB: replaced by the apps & files worker.
@MainActor
final class AppsProvider: SearchProvider {
    let priority = 0
    func search(_ query: String) async -> ProviderResponse { .empty }
}
