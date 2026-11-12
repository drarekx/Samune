import Foundation

/// Files and folders through Spotlight. Mixed in from 3 letters; alone with the "f " prefix.
/// STUB: replaced by the apps & files worker.
@MainActor
final class FilesProvider: SearchProvider {
    let priority = 20
    func search(_ query: String) async -> ProviderResponse { .empty }
}
