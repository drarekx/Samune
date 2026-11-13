import Foundation

/// Stub: saved notes in the launcher (prefix "n ").
@MainActor
final class NotesProvider: SearchProvider {
    let priority = 8

    func search(_ query: String) async -> ProviderResponse { .empty }
}
