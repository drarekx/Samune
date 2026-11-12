import Foundation

/// Integration commands in the root search ("Bookmarks" → enters "bm ") and their items
/// once the query starts with a keyword ("bm laravel"), exclusively.
/// STUB: replaced by the integrations worker.
@MainActor
final class IntegrationsProvider: SearchProvider {
    let priority = 10
    func search(_ query: String) async -> ProviderResponse { .empty }
}
