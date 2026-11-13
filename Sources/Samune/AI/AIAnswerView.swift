import AppKit
import SwiftUI

/// The conversation with an AI account, shown in the launcher instead of the results.
struct AIAnswerView: View {
    @ObservedObject var chat: AIChat

    private static let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.turns) { turn in
                        TurnView(turn: turn)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Follows the answer while it arrives.
            .onChange(of: chat.turns.last?.text) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: chat.turns.count) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }
}

private struct TurnView: View {
    let turn: AIChat.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if let attachment = turn.attachment, let image = NSImage(data: attachment.data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(turn.question)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !turn.text.isEmpty {
                Text(Self.rendered(turn.text))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let data = turn.image, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if turn.running, turn.text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Esperando la respuesta…")).font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
            }
            if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.warn)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = Self.detail(turn.usage) {
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline Markdown (bold, italics, code, links), keeping the line breaks.
    private static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// "1.240 → 380 tokens · 0,0042 $ · claude-sonnet-5".
    private static func detail(_ usage: AIUsage?) -> String? {
        guard let usage else { return nil }
        var parts: [String] = []
        if let input = usage.inputTokens, let output = usage.outputTokens {
            parts.append(tr("%@ → %@ tokens", AICost.count(input), AICost.count(output)))
        }
        if let cost = usage.cost { parts.append(AICost.text(cost, estimate: usage.costIsEstimate)) }
        if let model = usage.model { parts.append(model) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Number formats of the usage line.
enum AICost {
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Dollars with enough decimals for fractions of a cent; "≈" when estimated from a price list.
    static func text(_ cost: Double, estimate: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = cost >= 1 ? 2 : (cost >= 0.01 ? 4 : 6)
        let amount = formatter.string(from: NSNumber(value: cost)) ?? String(cost)
        return (estimate ? "≈ " : "") + amount + " $"
    }
}
