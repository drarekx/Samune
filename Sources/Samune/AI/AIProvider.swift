import AppKit
import SwiftUI

/// AI accounts in the launcher: their name in the normal search ("Claude" → enters "claude ") and,
/// once the text starts with the prefix of one, the ways to send it (ask, ask with an image,
/// generate an image), exclusively.
@MainActor
final class AIProvider: SearchProvider {
    let priority = 9

    /// Handler of the rows: the argument is `<account id>|<mode>|<text>`.
    static let askHandler = "ai.ask"

    /// Called once at launch by `AppDelegate` (not from `init`: the engine creates the providers
    /// while it is being created itself).
    static func register() {
        SearchEngine.shared.handlers[askHandler] = { argument in
            let parts = argument.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let mode = AIChat.Mode(rawValue: parts[1]),
                  let account = AIStore.shared.accounts.first(where: { $0.id.uuidString == parts[0] }) else { return }
            AIChat.shared.start(account, prompt: parts[2], mode: mode)
        }
        // The answer is shown in the panel: it stays open.
        SearchEngine.shared.stayOpenHandlers.insert(askHandler)
        installDebugHook()
    }

    /// Debug builds only: `com.egluu.samune.debug` with `ai:card:<file.png>` renders the settings
    /// card with the first account expanded (the Settings window may have it scrolled away).
    private static func installDebugHook() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { note in
            guard let command = note.object as? String, command.hasPrefix("ai:card:") else { return }
            MainActor.assumeIsolated {
                let view = AISettingsCard(expanded: AIStore.shared.accounts.first?.id)
                    .frame(width: 560)
                    .padding(20)
                    .background(Theme.window)
                    .environment(\.colorScheme, Theme.palette.isLight ? .light : .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: String(command.dropFirst("ai:card:".count))))
                }
            }
        }
        #endif
    }

    func search(_ query: String) async -> ProviderResponse {
        let accounts = AIStore.shared.usable
        // The longest trigger wins, as with integrations.
        let entered = accounts
            .filter { query.prefix($0.trigger.count).lowercased() == $0.trigger.lowercased() }
            .max { $0.trigger.count < $1.trigger.count }
        if let entered {
            let text = String(query.dropFirst(entered.trigger.count)).trimmingCharacters(in: .whitespaces)
            return ProviderResponse(items: rows(for: entered, text: text), exclusive: true)
        }
        let items = accounts.compactMap { account -> ResultItem? in
            guard let score = Fuzzy.score(query, in: [account.name, account.prefix]) else { return nil }
            let id = "ai:\(account.id.uuidString)"
            return ResultItem(id: id, title: account.name,
                              subtitle: account.needsSpace
                                  ? tr("Escribe «%@» y un espacio para preguntar", account.prefix)
                                  : tr("Escribe «%@» para preguntar", account.prefix),
                              icon: .symbol(account.kind.symbol), kind: tr("IA"),
                              action: .setQuery(account.trigger), score: score + Frecency.shared.boost(id))
        }
        return ProviderResponse(items: items)
    }

    private func rows(for account: AIAccount, text: String) -> [ResultItem] {
        let model = account.model.isEmpty ? tr("sin modelo") : account.model
        guard !text.isEmpty else {
            return [ResultItem(id: "ai:\(account.id.uuidString):hint", title: tr("Escribe tu pregunta"),
                               subtitle: "\(account.name) · \(model)", icon: .symbol(account.kind.symbol),
                               kind: tr("IA"), action: .setQuery(account.trigger), score: 1)]
        }
        func row(_ mode: AIChat.Mode, title: String, detail: String, symbol: String, score: Double) -> ResultItem {
            ResultItem(id: "ai:\(account.id.uuidString):\(mode.rawValue)", title: title,
                       subtitle: "\(account.name) · \(detail)", icon: .symbol(symbol), kind: tr("IA"),
                       action: .invoke(handler: Self.askHandler,
                                       argument: "\(account.id.uuidString)|\(mode.rawValue)|\(text)"),
                       score: score)
        }
        var items = [row(.ask, title: tr("Preguntar"), detail: model, symbol: account.kind.symbol, score: 3)]
        if AIChat.clipboardHasImage {
            items.append(row(.askWithImage, title: tr("Preguntar con la imagen del portapapeles"),
                             detail: model, symbol: "photo.badge.plus", score: 2))
        }
        if account.kind.generatesImages {
            let imageModel = account.imageModel.isEmpty ? tr("sin modelo") : account.imageModel
            items.append(row(.image, title: tr("Generar una imagen"), detail: imageModel, symbol: "photo", score: 1))
        }
        return items
    }
}
