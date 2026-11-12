import AppKit
import SwiftUI

/// The app's look, read from the theme chosen in Settings. Views use these, never loose colours.
/// Surfaces (cards, fields, lines…) are the theme's background mixed towards its text colour.
enum Theme {
    static var palette: AppPalette { Settings.shared.theme.palette }

    static var window: Color { Color(hex: palette.background) }
    static var nsWindow: NSColor { NSColor(hex: palette.background) }
    static var sidebar: Color { surface(0.03) }
    static var card: Color { surface(0.045) }
    static var field: Color { surface(0.07) }
    static var control: Color { surface(0.10) }
    static var line: Color { surface(0.11) }
    static var lineStrong: Color { surface(0.18) }

    static var text: Color { Color(hex: palette.text) }
    static var text2: Color { palette.text2.map { Color(hex: $0) } ?? Color(hex: palette.text).opacity(0.72) }
    static var text3: Color { Color(hex: palette.text3) }

    static var accent: Color { Color(hex: palette.accent) }
    static var accentText: Color { Color(hex: palette.accent) }
    static var accentFill: Color { Color(hex: palette.accent) }
    static var onAccent: Color { Color(hex: palette.onAccent) }
    static var accentSoft: Color { Color(hex: mix(palette.background, palette.accent, 0.18)) }
    static var accentBorder: Color { Color(hex: mix(palette.background, palette.accent, 0.5)) }
    static var navSelected: Color { Color(hex: palette.selection) }

    static var ok: Color { Color(hex: palette.isLight ? 0x1F8A4C : 0x3CCF7A) }
    static var warn: Color { Color(hex: palette.isLight ? 0xA86B00 : 0xF5C46B) }
    static var danger: Color { Color(hex: palette.isLight ? 0xC0392B : 0xFF7B7B) }
    static var dangerBorder: Color { Color(hex: mix(palette.background, palette.isLight ? 0xC0392B : 0xFF7B7B, 0.35)) }

    static let radius: CGFloat = 8

    private static func surface(_ amount: Double) -> Color {
        Color(hex: mix(palette.background, palette.text, amount))
    }

    /// `a` moved towards `b` by `t` (0…1), per channel.
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Buttons

struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .secondary
    var height: CGFloat = 32
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, height: height, fullWidth: fullWidth)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }

        private var foreground: Color {
            switch kind {
            case .primary: return Theme.onAccent
            case .danger: return Theme.danger
            case .ghost: return Theme.text2
            case .secondary: return Theme.text
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return Theme.accentFill
            case .secondary: return Theme.control
            case .ghost, .danger: return .clear
            }
        }

        private var border: Color {
            switch kind {
            case .primary: return .clear
            case .secondary: return Theme.lineStrong
            case .ghost: return Theme.line
            case .danger: return Theme.dangerBorder
            }
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appGhost: AppButtonStyle { AppButtonStyle(kind: .ghost) }
    static var appDanger: AppButtonStyle { AppButtonStyle(kind: .danger) }
}

/// Square icon-only button.
struct IconButton: View {
    let symbol: String
    let label: String
    var kind: AppButtonStyle.Kind = .ghost
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(AppButtonStyle(kind: kind, height: size))
        .frame(width: size)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Controls

/// Pill segmented control in the app's style.
struct SegmentedControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var expand = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let (title, value) = options[index]
                let selected = value == selection
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: expand ? .infinity : nil)
                        .frame(height: 26)
                        .background(selected ? Theme.lineStrong : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line) }
    }
}

/// Small uppercase heading used above groups.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.text3)
    }
}

/// Text field with the app's field look.
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.lineStrong) }
    }
}

/// A labelled switch row.
struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Theme.accentFill)
        .controlSize(.small)
        .padding(.vertical, 8)
    }
}

extension View {
    /// Rounded card surface.
    func appCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line) }
    }

    func monospacedText(size: CGFloat = 12) -> some View {
        self.font(.system(size: size, design: .monospaced))
    }
}
