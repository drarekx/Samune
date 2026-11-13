import Foundation

/// Stub: maths and conversions typed in the launcher ("23*4", "10 km a mi").
@MainActor
final class CalculatorProvider: SearchProvider {
    let priority = -10

    func search(_ query: String) async -> ProviderResponse { .empty }
}
