import AppKit

/// The conversation shown in the launcher: a first question and the follow-ups, until it is closed.
@MainActor
final class AIChat: ObservableObject {
    static let shared = AIChat()

    enum Mode: String {
        case ask
        /// Ask with the image that is on the clipboard.
        case askWithImage
        /// Generate an image from the text.
        case image
    }

    struct Turn: Identifiable {
        let id = UUID()
        var question: String
        /// Image sent with the question.
        var attachment: AIImage?
        var text = ""
        /// Generated image.
        var image: Data?
        var usage: AIUsage?
        var error: String?
        var running = true
        var rawContent: Data?
    }

    @Published private(set) var account: AIAccount?
    @Published private(set) var turns: [Turn] = []
    /// Short confirmation shown in the footer ("Copiado").
    @Published private(set) var notice: String?

    private var task: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    private init() {}

    var isActive: Bool { account != nil }
    var isRunning: Bool { turns.last?.running == true }

    /// Sum of what the provider reported for every turn. Nil when none reported a cost.
    var totalCost: (value: Double, estimate: Bool)? {
        let costs = turns.compactMap { $0.usage }.filter { $0.cost != nil }
        guard !costs.isEmpty else { return nil }
        return (costs.reduce(0) { $0 + ($1.cost ?? 0) }, costs.contains { $0.costIsEstimate })
    }

    // MARK: - Asking

    /// Starts a new conversation with `account`.
    func start(_ account: AIAccount, prompt: String, mode: Mode) {
        close()
        self.account = account
        send(prompt, mode: mode)
    }

    /// Another question in the same conversation, with what was said before as context.
    func followUp(_ prompt: String) {
        guard isActive, !isRunning else { return }
        send(prompt, mode: .ask)
    }

    private func send(_ prompt: String, mode: Mode) {
        guard let account else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var turn = Turn(question: text)
        if mode == .askWithImage {
            guard let image = Self.clipboardImage() else {
                turn.error = tr("No hay ninguna imagen en el portapapeles.")
                turn.running = false
                turns.append(turn)
                return
            }
            turn.attachment = image
        }
        let history = turns
        turns.append(turn)
        let id = turn.id
        let attachment = turn.attachment

        task = Task { [weak self] in
            let key = await Task.detached { AIStore.key(of: account) }.value
            guard let self, !Task.isCancelled else { return }
            guard let key else {
                self.finish(id) { $0.error = AIError.missingKey.text }
                return
            }
            do {
                if mode == .image {
                    let (data, usage) = try await AIClient.image(account, key: key, prompt: text)
                    self.finish(id) { $0.image = data; $0.usage = usage }
                } else {
                    var messages: [AIMessage] = []
                    for old in history where old.error == nil && old.image == nil && !old.text.isEmpty {
                        messages.append(AIMessage(role: .user, text: old.question, image: old.attachment))
                        messages.append(AIMessage(role: .assistant, text: old.text, rawContent: old.rawContent))
                    }
                    messages.append(AIMessage(role: .user, text: text, image: attachment))
                    let model = AIStore.shared.model(account.model, of: account)
                    let answer = try await AIClient.ask(account, key: key, model: model, messages: messages) { piece in
                        AIChat.shared.append(piece, to: id)
                    }
                    self.finish(id) { $0.usage = answer.usage; $0.rawContent = answer.rawContent }
                }
            } catch is CancellationError {
                self.finish(id) { _ in }
            } catch let error as AIError {
                self.finish(id) { $0.error = error.text }
            } catch {
                self.finish(id) { $0.error = error.localizedDescription }
            }
        }
    }

    private func append(_ piece: String, to id: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[index].text += piece
    }

    private func finish(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
        turns[index].running = false
    }

    /// Stops the answer that is arriving; what already arrived stays.
    func stop() {
        task?.cancel()
        task = nil
        if let index = turns.indices.last, turns[index].running { turns[index].running = false }
    }

    /// Ends the conversation.
    func close() {
        stop()
        account = nil
        turns = []
        notice = nil
    }

    // MARK: - Results

    /// ⌘C: the last answer (text or image). False when there is nothing yet.
    @discardableResult
    func copyLast() -> Bool {
        guard let turn = turns.last(where: { !$0.text.isEmpty || $0.image != nil }) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = turn.image, let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(turn.text, forType: .string)
        }
        show(notice: tr("Copiado"))
        return true
    }

    /// ⌘S: saves the last generated image to Downloads and shows it in Finder.
    @discardableResult
    func saveLastImage() -> Bool {
        guard let data = turns.last(where: { $0.image != nil })?.image else { return false }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let type = Self.fileExtension(of: data)
        let url = folder.appendingPathComponent("\(AppInfo.name) \(formatter.string(from: Date())).\(type)")
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            show(notice: error.localizedDescription)
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        show(notice: tr("Guardada en Descargas"))
        return true
    }

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private static func fileExtension(of data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "webp" }
        return "png"
    }

    // MARK: - Clipboard

    static var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// The image on the clipboard (copied pixels or an image file), as a JPEG no larger than
    /// 1568 px on its long side, which is what the providers work with.
    static func clipboardImage() -> AIImage? {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let longSide = CGFloat(max(source.width, source.height))
        let scale = min(1, 1568 / longSide)
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // White behind transparent pixels: JPEG has no alpha.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        return AIImage(data: data, mediaType: "image/jpeg")
    }
}
