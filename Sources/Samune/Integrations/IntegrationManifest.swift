import AppKit

/// Contents of an integration's `manifest.json`, decoded tolerantly.
struct IntegrationManifest: Equatable, Sendable {
    struct Variable: Equatable, Sendable, Identifiable {
        let key: String
        let label: String
        let placeholder: String
        let secret: Bool
        var id: String { key }
    }

    var name: String
    var keyword: String
    /// False when the keyword needs no space after it ("!laravel"). Settings can override both.
    var keywordSpace: Bool
    /// SF Symbol name, or a file name inside the integration folder.
    var icon: String
    var command: String
    var passQuery: Bool
    var cacheSeconds: Double
    var description: String?
    var variables: [Variable]

    static let defaultIcon = "puzzlepiece.extension"

    /// Errors are returned already translated, to be shown in Settings.
    static func decode(_ data: Data) -> Result<IntegrationManifest, ManifestError> {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return .failure(ManifestError(tr("manifest.json no es un objeto JSON válido")))
        }
        func string(_ key: String) -> String? {
            (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let name = string("name"), !name.isEmpty else {
            return .failure(ManifestError(tr("Falta el campo «%@»", "name")))
        }
        guard let command = string("command"), !command.isEmpty else {
            return .failure(ManifestError(tr("Falta el campo «%@»", "command")))
        }
        let keyword = string("keyword") ?? ""
        if keyword.contains(where: \.isWhitespace) {
            return .failure(ManifestError(tr("La palabra clave no puede tener espacios")))
        }
        let variables = (json["variables"] as? [[String: Any]] ?? []).compactMap { entry -> Variable? in
            guard let key = (entry["key"] as? String)?.trimmingCharacters(in: .whitespaces), !key.isEmpty,
                  key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
            return Variable(key: key,
                            label: (entry["label"] as? String) ?? key,
                            placeholder: (entry["placeholder"] as? String) ?? "",
                            secret: Self.bool(entry["secret"]) ?? false)
        }
        let seconds = (json["cacheSeconds"] as? NSNumber)?.doubleValue ?? 300
        return .success(IntegrationManifest(
            name: name,
            keyword: keyword,
            keywordSpace: bool(json["keywordSpace"]) ?? true,
            icon: string("icon").flatMap { $0.isEmpty ? nil : $0 } ?? defaultIcon,
            command: command,
            passQuery: bool(json["passQuery"]) ?? false,
            cacheSeconds: max(0, seconds),
            description: string("description").flatMap { $0.isEmpty ? nil : $0 },
            variables: variables))
    }

    /// Accepts JSON booleans and also "true"/"false" strings or 0/1.
    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["true", "yes", "1"].contains(text.lowercased()) }
        return nil
    }
}

struct ManifestError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// One integration folder, valid or not.
struct Integration: Identifiable, Equatable, Sendable {
    /// Folder name.
    let id: String
    let folder: URL
    /// Nil when `manifest.json` is missing or invalid (see `loadError`).
    let manifest: IntegrationManifest?
    /// Translated reason why this integration can't be used.
    var loadError: String?

    var name: String { manifest?.name ?? id }
    var isUsable: Bool { manifest != nil && loadError == nil }

    /// Icon from the manifest: a file inside the folder if it exists, otherwise an SF Symbol.
    var icon: ItemIcon {
        let name = manifest?.icon ?? IntegrationManifest.defaultIcon
        // SF Symbol names contain dots too ("hand.wave"): a file only when it exists in the folder.
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return .image(url) }
        if name.contains("/") || NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            return .symbol(IntegrationManifest.defaultIcon)
        }
        return .symbol(name)
    }
}
