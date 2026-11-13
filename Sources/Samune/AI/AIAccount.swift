import Foundation

/// The services Samune can ask questions to.
enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, openrouter, minimax

    var id: String { rawValue }

    /// Proper names: not translated.
    var title: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .minimax: return "MiniMax"
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: return "sparkle"
        case .openai: return "circle.hexagongrid"
        case .openrouter: return "arrow.triangle.branch"
        case .minimax: return "waveform"
        }
    }

    /// Empty where the right default changes too often: the user picks one from the list.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5-5"
        case .minimax: return "MiniMax-M3"
        case .openai, .openrouter: return ""
        }
    }

    var defaultImageModel: String {
        switch self {
        case .openai: return "gpt-image-1"
        case .minimax: return "image-01"
        case .anthropic, .openrouter: return ""
        }
    }

    var defaultPrefix: String {
        switch self {
        case .anthropic: return "claude"
        case .openai: return "gpt"
        case .openrouter: return "or"
        case .minimax: return "mm"
        }
    }

    /// Anthropic has no image generation.
    var generatesImages: Bool { self != .anthropic }

    /// Root of the API. `ai.baseURL.<kind>` in the preferences replaces it (proxies, tests).
    var baseURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "ai.baseURL.\(rawValue)"),
           let url = URL(string: custom) {
            return url
        }
        let text: String
        switch self {
        case .anthropic: text = "https://api.anthropic.com/v1"
        case .openai: text = "https://api.openai.com/v1"
        case .openrouter: text = "https://openrouter.ai/api/v1"
        case .minimax: text = "https://api.minimax.io/v1"
        }
        // Constant, valid URLs.
        return URL(string: text) ?? URL(fileURLWithPath: "/")
    }
}

/// One configured account: a provider, a key and the model to ask.
/// Duplicates share `keyID`, so the same key serves several models.
struct AIAccount: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var kind: AIProviderKind
    var model: String
    var imageModel: String
    /// What is typed in the launcher to ask this account ("claude ¿…?").
    var prefix: String
    var needsSpace = true
    /// Keychain account of the key.
    var keyID = UUID().uuidString
    /// Optional instructions sent with every question.
    var system = ""

    var trigger: String { prefix + (needsSpace ? " " : "") }
}

/// A model offered by a provider.
struct AIModel: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String?
    /// Output cap, when the provider reports it (Anthropic).
    var maxOutput: Int?
    /// Price in dollars per token, when the provider reports it (OpenRouter).
    var inputPrice: Double?
    var outputPrice: Double?
    var generatesImages = false
}

/// Accounts (in the preferences), their keys (in the Keychain) and the model lists already fetched.
@MainActor
final class AIStore: ObservableObject {
    static let shared = AIStore()
    nonisolated static let keychainService = "com.egluu.samune.ai"

    @Published private(set) var accounts: [AIAccount] = []
    /// Models fetched per key, so a key of another organisation has its own list.
    @Published private(set) var models: [String: [AIModel]] = [:]

    private let defaults = UserDefaults.standard
    private static let accountsKey = "ai.accounts"
    private static let modelsKey = "ai.models"

    private init() {
        if let data = defaults.data(forKey: Self.accountsKey),
           let saved = try? JSONDecoder().decode([AIAccount].self, from: data) {
            accounts = saved
        }
        if let data = defaults.data(forKey: Self.modelsKey),
           let saved = try? JSONDecoder().decode([String: [AIModel]].self, from: data) {
            models = saved
        }
    }

    // MARK: - Accounts

    @discardableResult
    func add(_ kind: AIProviderKind) -> AIAccount {
        let account = AIAccount(name: freeName(kind.title), kind: kind, model: kind.defaultModel,
                                imageModel: kind.defaultImageModel, prefix: freePrefix(kind.defaultPrefix))
        accounts.append(account)
        save()
        return account
    }

    /// Same provider and key, to try another model without typing the key again.
    @discardableResult
    func duplicate(_ account: AIAccount) -> AIAccount {
        var copy = account
        copy.id = UUID()
        copy.name = freeName(account.name)
        copy.prefix = freePrefix(account.prefix)
        let index = accounts.firstIndex { $0.id == account.id } ?? accounts.count - 1
        accounts.insert(copy, at: index + 1)
        save()
        return copy
    }

    func update(_ account: AIAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var cleaned = account
        cleaned.prefix = String(account.prefix.filter { !$0.isWhitespace })
        accounts[index] = cleaned
        save()
    }

    /// Removes the account, and its key when no other account uses it.
    func remove(_ account: AIAccount) {
        accounts.removeAll { $0.id == account.id }
        if !accounts.contains(where: { $0.keyID == account.keyID }) {
            Keychain.delete(service: Self.keychainService, account: account.keyID)
            models[account.keyID] = nil
            saveModels()
        }
        save()
    }

    /// Names of the other accounts using the same key.
    func sharing(_ account: AIAccount) -> [String] {
        accounts.filter { $0.keyID == account.keyID && $0.id != account.id }.map(\.name)
    }

    /// Translated reason why the account can't be used from the launcher, if any.
    func problem(of account: AIAccount) -> String? {
        if account.prefix.isEmpty { return tr("Falta el prefijo") }
        if let other = accounts.first(where: {
            $0.id != account.id && $0.prefix.lowercased() == account.prefix.lowercased()
        }), accounts.firstIndex(of: other) ?? 0 < accounts.firstIndex(of: account) ?? 0 {
            return tr("El prefijo «%@» ya lo usa «%@»", account.prefix, other.name)
        }
        return nil
    }

    /// Accounts the launcher offers.
    var usable: [AIAccount] { accounts.filter { problem(of: $0) == nil } }

    private func freeName(_ base: String) -> String {
        let names = Set(accounts.map(\.name))
        guard names.contains(base) else { return base }
        let stem = base.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
        var number = 2
        while names.contains("\(stem) \(number)") { number += 1 }
        return "\(stem) \(number)"
    }

    private func freePrefix(_ base: String) -> String {
        let used = Set(accounts.map { $0.prefix.lowercased() })
        guard used.contains(base.lowercased()) else { return base }
        let stem = base.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
        var number = 2
        while used.contains("\(stem)\(number)".lowercased()) { number += 1 }
        return "\(stem)\(number)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: Self.accountsKey) }
    }

    // MARK: - Keys

    /// The value never goes to the preferences or to a file.
    nonisolated static func key(of account: AIAccount) -> String? {
        #if DEBUG
        // Tests against a local server, without touching the Keychain.
        if let test = ProcessInfo.processInfo.environment["SAMUNE_AI_TEST_KEY"] { return test }
        #endif
        let value = Keychain.read(service: keychainService, account: account.keyID)
        return value?.isEmpty == false ? value : nil
    }

    func hasKey(_ account: AIAccount) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SAMUNE_AI_TEST_KEY"] != nil { return true }
        #endif
        return Keychain.exists(service: Self.keychainService, account: account.keyID)
    }

    /// Empty text removes the key (for every account sharing it).
    func setKey(_ text: String, for account: AIAccount) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: Self.keychainService, account: account.keyID)
        } else {
            Keychain.write(trimmed, service: Self.keychainService, account: account.keyID)
        }
        objectWillChange.send()
    }

    // MARK: - Models

    func models(for account: AIAccount) -> [AIModel] { models[account.keyID] ?? [] }

    func model(_ id: String, of account: AIAccount) -> AIModel? {
        models(for: account).first { $0.id == id }
    }

    /// Asks the provider for its models and remembers them. Throws `AIError`.
    func refreshModels(for account: AIAccount) async throws {
        guard let key = Self.key(of: account) else { throw AIError.missingKey }
        let list = try await AIClient.models(account.kind, key: key)
        models[account.keyID] = list
        saveModels()
    }

    private func saveModels() {
        if let data = try? JSONEncoder().encode(models) { defaults.set(data, forKey: Self.modelsKey) }
    }
}
