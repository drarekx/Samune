import Foundation

/// What a request cost, as far as the provider tells.
struct AIUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    /// Dollars.
    var cost: Double?
    /// True when `cost` comes from a price list and not from the provider's bill.
    var costIsEstimate = false
    /// Model that answered, when it differs from the one asked (fallbacks, routing).
    var model: String?
}

/// One message of a conversation.
struct AIMessage: Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var text: String
    /// Image attached to a question.
    var image: AIImage?
    /// Anthropic only: the content blocks of an answer exactly as they arrived, to send them back
    /// unchanged in a follow-up (the API checks that thinking blocks were not edited).
    var rawContent: Data?
}

struct AIImage: Sendable, Equatable {
    var data: Data
    var mediaType: String
}

/// What ends a streamed answer.
struct AIAnswer: Sendable {
    var usage: AIUsage
    var rawContent: Data?
}

enum AIError: Error, Equatable {
    case missingKey
    case missingModel
    case refused
    case unsupported
    /// Message of the provider, or of the network.
    case message(String)

    /// Translated text for the panel and the settings.
    var text: String {
        switch self {
        case .missingKey: return tr("Falta la clave de la API. Ponla en Ajustes → IA.")
        case .missingModel: return tr("Elige un modelo en Ajustes → IA.")
        case .refused: return tr("El modelo ha rechazado la petición.")
        case .unsupported: return tr("Este proveedor no genera imágenes.")
        case .message(let message): return message
        }
    }
}

/// HTTP calls to the providers. Anthropic has its own API; OpenAI, OpenRouter and MiniMax share
/// the chat completions format.
enum AIClient {
    private static let anthropicVersion = "2026-10-21"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that may decline a request and accept the server-side fallback.
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    // MARK: - Chat

    /// Streams the answer to `messages`; `onText` receives each new piece on the main actor.
    static func ask(_ account: AIAccount, key: String, model: AIModel?, messages: [AIMessage],
                    onText: @escaping @MainActor (String) -> Void) async throws -> AIAnswer {
        guard !account.model.isEmpty else { throw AIError.missingModel }
        switch account.kind {
        case .anthropic:
            return try await askAnthropic(account, key: key, model: model, messages: messages, onText: onText)
        case .openai, .openrouter, .minimax:
            return try await askCompatible(account, key: key, model: model, messages: messages, onText: onText)
        }
    }

    private static func askAnthropic(_ account: AIAccount, key: String, model: AIModel?, messages: [AIMessage],
                                     onText: @escaping @MainActor (String) -> Void) async throws -> AIAnswer {
        var body: [String: Any] = [
            "model": account.model,
            // Streaming, so a generous cap is safe; never above what the model allows.
            "max_tokens": min(64_000, model?.maxOutput ?? 16_000),
            "stream": true,
            "messages": messages.map(anthropicMessage),
        ]
        if !account.system.isEmpty { body["system"] = account.system }
        var request = anthropicRequest("messages", key: key)
        if fallbackModels.contains(account.model) {
            // A declined request is answered by another model inside the same call.
            body["fallbacks"] = "default"
            request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var usage = AIUsage()
        var blocks: [[String: Any]] = []
        var stopReason: String?
        var sawText = false
        try await events(of: request) { event in
            switch event["type"] as? String {
            case "message_start":
                let message = event["message"] as? [String: Any]
                if let counts = message?["usage"] as? [String: Any] { usage.inputTokens = inputTokens(counts) }
                if let served = message?["model"] as? String, served != account.model { usage.model = served }
            case "content_block_start":
                blocks.append(event["content_block"] as? [String: Any] ?? [:])
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], let index = event["index"] as? Int,
                      blocks.indices.contains(index) else { return }
                switch delta["type"] as? String {
                case "text_delta":
                    let piece = delta["text"] as? String ?? ""
                    blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + piece
                    if !piece.isEmpty {
                        sawText = true
                        await onText(piece)
                    }
                case "thinking_delta":
                    blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "")
                        + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    blocks[index]["signature"] = (blocks[index]["signature"] as? String ?? "")
                        + (delta["signature"] as? String ?? "")
                default:
                    break
                }
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
                if let counts = event["usage"] as? [String: Any] {
                    if let output = counts["output_tokens"] as? Int { usage.outputTokens = output }
                    if counts["input_tokens"] != nil { usage.inputTokens = inputTokens(counts) }
                }
            case "error":
                throw AIError.message(errorMessage(event) ?? tr("El proveedor devolvió un error."))
            default:
                break
            }
        }
        if stopReason == "refusal", !sawText { throw AIError.refused }
        if let estimate = AnthropicPrices.cost(model: usage.model ?? account.model, usage: usage) {
            usage.cost = estimate
            usage.costIsEstimate = true
        }
        return AIAnswer(usage: usage, rawContent: try? JSONSerialization.data(withJSONObject: blocks))
    }

    private static func inputTokens(_ counts: [String: Any]) -> Int {
        ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .reduce(0) { $0 + (counts[$1] as? Int ?? 0) }
    }

    private static func anthropicMessage(_ message: AIMessage) -> [String: Any] {
        if message.role == .assistant {
            if let raw = message.rawContent,
               let blocks = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]], !blocks.isEmpty {
                return ["role": "assistant", "content": blocks]
            }
            return ["role": "assistant", "content": message.text]
        }
        var content: [[String: Any]] = []
        if let image = message.image {
            content.append(["type": "image", "source": [
                "type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString(),
            ]])
        }
        content.append(["type": "text", "text": message.text])
        return ["role": "user", "content": content]
    }

    private static func askCompatible(_ account: AIAccount, key: String, model: AIModel?, messages: [AIMessage],
                                      onText: @escaping @MainActor (String) -> Void) async throws -> AIAnswer {
        var list: [[String: Any]] = []
        if !account.system.isEmpty { list.append(["role": "system", "content": account.system]) }
        for message in messages {
            if let image = message.image, message.role == .user {
                let url = "data:\(image.mediaType);base64,\(image.data.base64EncodedString())"
                list.append(["role": "user", "content": [
                    ["type": "text", "text": message.text],
                    ["type": "image_url", "image_url": ["url": url]],
                ]])
            } else {
                list.append(["role": message.role.rawValue, "content": message.text])
            }
        }
        let body: [String: Any] = [
            "model": account.model, "messages": list, "stream": true,
            "stream_options": ["include_usage": true],
        ]
        var request = bearerRequest(account.kind, "chat/completions", key: key)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var usage = AIUsage()
        try await events(of: request) { event in
            if event["error"] != nil {
                throw AIError.message(errorMessage(event) ?? tr("El proveedor devolvió un error."))
            }
            if let served = event["model"] as? String, served != account.model { usage.model = served }
            if let counts = event["usage"] as? [String: Any] {
                usage.inputTokens = counts["prompt_tokens"] as? Int
                usage.outputTokens = counts["completion_tokens"] as? Int
                if let cost = (counts["cost"] as? NSNumber)?.doubleValue { usage.cost = cost }
            }
            let choice = (event["choices"] as? [[String: Any]])?.first
            if let piece = (choice?["delta"] as? [String: Any])?["content"] as? String, !piece.isEmpty {
                await onText(piece)
            }
        }
        if usage.cost == nil, let model, let input = model.inputPrice, let output = model.outputPrice,
           let sent = usage.inputTokens, let received = usage.outputTokens {
            usage.cost = Double(sent) * input + Double(received) * output
            usage.costIsEstimate = true
        }
        return AIAnswer(usage: usage, rawContent: nil)
    }

    // MARK: - Images

    /// Generates one image from `prompt`. Returns the image bytes and what it cost, if known.
    static func image(_ account: AIAccount, key: String, prompt: String) async throws -> (Data, AIUsage) {
        guard account.kind.generatesImages else { throw AIError.unsupported }
        guard !account.imageModel.isEmpty else { throw AIError.missingModel }
        let path: String
        var body: [String: Any] = ["model": account.imageModel, "prompt": prompt]
        switch account.kind {
        case .openai:
            path = "images/generations"
            body["n"] = 1
        case .openrouter:
            path = "images"
        case .minimax:
            path = "image_generation"
            body["response_format"] = "base64"
        case .anthropic:
            throw AIError.unsupported
        }
        var request = bearerRequest(account.kind, path, key: key)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await object(of: request)

        var usage = AIUsage()
        if let counts = json["usage"] as? [String: Any] {
            usage.inputTokens = (counts["input_tokens"] ?? counts["prompt_tokens"]) as? Int
            usage.outputTokens = (counts["output_tokens"] ?? counts["completion_tokens"]) as? Int
            usage.cost = (counts["cost"] as? NSNumber)?.doubleValue
        }
        var encoded: String?
        var link: String?
        if let data = json["data"] as? [[String: Any]] {
            encoded = data.first?["b64_json"] as? String
            link = data.first?["url"] as? String
        } else if let data = json["data"] as? [String: Any] {
            encoded = (data["image_base64"] as? [String])?.first
            link = (data["image_urls"] as? [String])?.first
        }
        if let encoded, let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
            return (bytes, usage)
        }
        if let link, let url = URL(string: link) {
            let (bytes, _) = try await session.data(from: url)
            return (bytes, usage)
        }
        throw AIError.message(errorMessage(json) ?? tr("El proveedor no devolvió ninguna imagen."))
    }

    // MARK: - Models

    static func models(_ kind: AIProviderKind, key: String) async throws -> [AIModel] {
        switch kind {
        case .anthropic:
            var request = anthropicRequest("models", key: key)
            request.url = request.url.flatMap { URL(string: $0.absoluteString + "?limit=1000") }
            let json = try await object(of: request)
            return rows(json).compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                return AIModel(id: id, name: row["display_name"] as? String, maxOutput: row["max_tokens"] as? Int)
            }
        case .openai:
            let json = try await object(of: bearerRequest(kind, "models", key: key))
            return rows(json).compactMap { row -> AIModel? in
                guard let id = row["id"] as? String else { return nil }
                let image = id.contains("image") || id.hasPrefix("dall-e")
                return AIModel(id: id, generatesImages: image)
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        case .openrouter:
            let text = try await object(of: bearerRequest(kind, "models", key: key))
            var image = bearerRequest(kind, "models", key: key)
            image.url = image.url.flatMap { URL(string: $0.absoluteString + "?output_modalities=image") }
            // The image list is optional: without it the chat models still work.
            let images = (try? await object(of: image)).map(rows) ?? []
            let imageIDs = Set(images.compactMap { $0["id"] as? String })
            let all = rows(text) + images.filter { row in
                !rows(text).contains { $0["id"] as? String == row["id"] as? String }
            }
            return all.compactMap { row -> AIModel? in
                guard let id = row["id"] as? String else { return nil }
                let pricing = row["pricing"] as? [String: Any]
                return AIModel(id: id, name: row["name"] as? String,
                               inputPrice: (pricing?["prompt"] as? String).flatMap(Double.init),
                               outputPrice: (pricing?["completion"] as? String).flatMap(Double.init),
                               generatesImages: imageIDs.contains(id))
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        case .minimax:
            // No list endpoint: the documented ids. Any other id can be typed by hand.
            return [AIModel(id: "MiniMax-M3"), AIModel(id: "MiniMax-M3.1-Flash"),
                    AIModel(id: "image-01", generatesImages: true)]
        }
    }

    private static func rows(_ json: [String: Any]) -> [[String: Any]] {
        json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - HTTP

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static func anthropicRequest(_ path: String, key: String) -> URLRequest {
        var request = URLRequest(url: AIProviderKind.anthropic.baseURL.appendingPathComponent(path))
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func bearerRequest(_ kind: AIProviderKind, _ path: String, key: String) -> URLRequest {
        var request = URLRequest(url: kind.baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// A JSON object answer, or the provider's error.
    private static func object(of request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AIError.message(error.localizedDescription)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.message(errorMessage(json) ?? tr("El proveedor respondió HTTP %d.", status))
        }
        // MiniMax answers 200 with the error inside.
        if let base = json["base_resp"] as? [String: Any], let code = base["status_code"] as? Int, code != 0 {
            throw AIError.message(base["status_msg"] as? String ?? tr("El proveedor devolvió un error."))
        }
        return json
    }

    /// Server-sent events of a streaming answer, one JSON object per `data:` line.
    private static func events(of request: URLRequest,
                               handle: ([String: Any]) async throws -> Void) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AIError.message(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes.prefix(64_000) { body.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            throw AIError.message(errorMessage(json) ?? tr("El proveedor respondió HTTP %d.", status))
        }
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
                else { continue }
                try await handle(json)
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AIError.message(error.localizedDescription)
        }
    }

    /// `{"error": {"message": …}}`, `{"error": "…"}` or MiniMax's `base_resp`.
    private static func errorMessage(_ json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        if let base = json["base_resp"] as? [String: Any], let message = base["status_msg"] as? String,
           !message.isEmpty, message != "success" {
            return message
        }
        return json["message"] as? String
    }
}

/// List prices of Anthropic models, in dollars per million tokens (input, output). The API reports
/// tokens, not money, so the cost shown for Anthropic is an estimate from this table.
enum AnthropicPrices {
    private static let table: [(prefix: String, input: Double, output: Double)] = [
        ("claude-fable-5-2", 8, 40), ("claude-mythos-5-2", 8, 40),
        ("claude-fable-5", 10, 50), ("claude-mythos-5", 10, 50),
        ("claude-opus-5-5", 4, 20), ("claude-opus-5", 5, 25),
        ("claude-opus-4-8", 5, 25), ("claude-opus-4-7", 5, 25), ("claude-opus-4-6", 5, 25),
        ("claude-sonnet-5", 2, 10), ("claude-sonnet-4-6", 3, 15),
        ("claude-haiku-5-5", 0.1, 0.5), ("claude-haiku-4-5", 1, 5),
    ]

    static func cost(model: String, usage: AIUsage) -> Double? {
        guard let price = table.first(where: { model.hasPrefix($0.prefix) }),
              let input = usage.inputTokens, let output = usage.outputTokens else { return nil }
        return (Double(input) * price.input + Double(output) * price.output) / 1_000_000
    }
}
