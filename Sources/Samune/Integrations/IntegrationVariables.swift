import Foundation
import Security

/// Generic passwords in the login Keychain. Values never leave this type except to the caller.
enum Keychain {
    static func read(service: String, account: String) -> String? {
        var query = base(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query = base(service: service, account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "\(AppInfo.name): \(account)"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(service: String, account: String) {
        SecItemDelete(base(service: service, account: account) as CFDictionary)
    }

    /// True when an item exists, without reading (or asking access to) its value.
    static func exists(service: String, account: String) -> Bool {
        var query = base(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static func base(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// Values of the variables an integration declares. Non-secret ones live in `UserDefaults`
/// (`integrations.vars.<id>.<key>`); secret ones in the Keychain (account `<id>.<key>`).
/// Thread-safe: the runner reads them off the main thread.
enum IntegrationVariables {
    static let keychainService = "com.egluu.samune.integrations"

    static func value(integration id: String, _ variable: IntegrationManifest.Variable) -> String? {
        let value: String?
        if variable.secret {
            value = Keychain.read(service: keychainService, account: account(id, variable.key))
        } else {
            value = UserDefaults.standard.string(forKey: defaultsKey(id, variable.key))
        }
        return value?.isEmpty == true ? nil : value
    }

    /// Empty text removes the value.
    static func set(_ value: String, integration id: String, _ variable: IntegrationManifest.Variable) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if variable.secret {
            if trimmed.isEmpty {
                Keychain.delete(service: keychainService, account: account(id, variable.key))
            } else {
                Keychain.write(trimmed, service: keychainService, account: account(id, variable.key))
            }
        } else if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey(id, variable.key))
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey(id, variable.key))
        }
    }

    static func hasSecret(integration id: String, key: String) -> Bool {
        Keychain.exists(service: keychainService, account: account(id, key))
    }

    /// Environment for a run: every declared variable that has a value.
    static func environment(integration id: String, manifest: IntegrationManifest) -> [String: String] {
        var env: [String: String] = [:]
        for variable in manifest.variables {
            if let value = value(integration: id, variable) { env[variable.key] = value }
        }
        return env
    }

    private static func defaultsKey(_ id: String, _ key: String) -> String { "integrations.vars.\(id).\(key)" }
    private static func account(_ id: String, _ key: String) -> String { "\(id).\(key)" }
}
