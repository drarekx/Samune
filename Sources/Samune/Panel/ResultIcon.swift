import AppKit
import SwiftUI

/// Loads row icons off the main thread and keeps them in memory, keyed by path or URL.
@MainActor
final class IconLoader {
    static let shared = IconLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [ItemIcon: Task<NSImage?, Never>] = [:]
    private var symbols: [String: Bool] = [:]

    private init() { cache.countLimit = 500 }

    func cached(_ icon: ItemIcon) -> NSImage? {
        key(icon).flatMap { cache.object(forKey: $0) }
    }

    func load(_ icon: ItemIcon) async -> NSImage? {
        guard let key = key(icon) else { return nil }
        if let image = cache.object(forKey: key) { return image }
        if let task = inFlight[icon] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { await Self.fetch(icon) }
        inFlight[icon] = task
        let image = await task.value
        inFlight[icon] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// The symbol name if it exists, otherwise "square.dashed".
    func symbolName(_ name: String) -> String {
        if let known = symbols[name] { return known ? name : "square.dashed" }
        let exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        symbols[name] = exists
        return exists ? name : "square.dashed"
    }

    private func key(_ icon: ItemIcon) -> NSString? {
        switch icon {
        case .file(let url): return "file:\(url.path)" as NSString
        case .image(let url): return "image:\(url.path)" as NSString
        case .remote(let url): return "remote:\(url.absoluteString)" as NSString
        case .symbol: return nil
        }
    }

    private nonisolated static func fetch(_ icon: ItemIcon) async -> NSImage? {
        switch icon {
        case .file(let url):
            return NSWorkspace.shared.icon(forFile: url.path)
        case .image(let url):
            return NSImage(contentsOf: url)
        case .remote(let url):
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
            return NSImage(data: data)
        case .symbol:
            return nil
        }
    }
}

/// Icon of a result row: Finder icon, tinted SF Symbol, local or remote image.
struct ResultIconView: View {
    let icon: ItemIcon
    var size: CGFloat = 28
    @State private var loaded: NSImage?

    var body: some View {
        content
            .frame(width: size, height: size)
            .task(id: icon) {
                guard IconLoader.shared.cached(icon) == nil else { return }
                loaded = nil
                loaded = await IconLoader.shared.load(icon)
            }
    }

    @ViewBuilder private var content: some View {
        switch icon {
        case .symbol(let name):
            symbol(IconLoader.shared.symbolName(name), color: Theme.accentText)
        default:
            if let image = IconLoader.shared.cached(icon) ?? loaded {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else if case .remote = icon {
                symbol("globe", color: Theme.text3)
            } else {
                Color.clear
            }
        }
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.6, weight: .regular))
            .foregroundStyle(color)
    }
}
