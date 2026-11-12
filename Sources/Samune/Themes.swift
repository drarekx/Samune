import AppKit
import SwiftUI

/// Colours of a theme, as hex values so they can be mixed.
struct AppPalette {
    let background: UInt32
    /// Selected rows; the "current line" colour of the original theme.
    let selection: UInt32
    let text: UInt32
    /// Secondary text; `nil` = main text, dimmed.
    let text2: UInt32?
    let text3: UInt32
    let accent: UInt32
    /// Text on top of the accent colour (primary buttons, badges).
    let onAccent: UInt32
    var isLight = false
}

/// Colour themes: the family's own dark look and the classic editor and terminal themes,
/// with their official colours. The whole app follows the chosen one.
enum AppTheme: String, CaseIterable, Identifiable {
    case original, solarizedDark, solarizedLight, dracula, nord, gruvboxDark, monokai, oneDark,
         tokyoNight, catppuccinMocha, catppuccinLatte, rosePine, everforest, kanagawa, githubDark
    var id: String { rawValue }

    /// Theme names are proper names and aren't translated, except the default.
    var name: String {
        switch self {
        case .original: return tr("Original (por defecto)")
        case .solarizedDark: return "Solarized Dark"
        case .solarizedLight: return "Solarized Light"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .gruvboxDark: return "Gruvbox"
        case .monokai: return "Monokai"
        case .oneDark: return "One Dark"
        case .tokyoNight: return "Tokyo Night"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .catppuccinLatte: return "Catppuccin Latte"
        case .rosePine: return "Rosé Pine"
        case .everforest: return "Everforest"
        case .kanagawa: return "Kanagawa"
        case .githubDark: return "GitHub Dark"
        }
    }

    var palette: AppPalette {
        switch self {
        case .original: // Wallpy, DemoImages, Droppy…
            return AppPalette(background: 0x121214, selection: 0x26304A, text: 0xECECEE, text2: 0xA1A1A6,
                              text3: 0x8A8A90, accent: 0x5C8CFF, onAccent: 0xFFFFFF)
        case .solarizedDark: // base03, base02, base1, base0, base01, blue
            return AppPalette(background: 0x002B36, selection: 0x073642, text: 0x93A1A1, text2: 0x839496,
                              text3: 0x586E75, accent: 0x268BD2, onAccent: 0xFDF6E3)
        case .solarizedLight: // base3, base2, base01, base00, base1, blue
            return AppPalette(background: 0xFDF6E3, selection: 0xEEE8D5, text: 0x586E75, text2: 0x657B83,
                              text3: 0x93A1A1, accent: 0x268BD2, onAccent: 0xFDF6E3, isLight: true)
        case .dracula: // background, current line, foreground, comment, purple
            return AppPalette(background: 0x282A36, selection: 0x44475A, text: 0xF8F8F2, text2: nil,
                              text3: 0x6272A4, accent: 0xBD93F9, onAccent: 0x282A36)
        case .nord: // nord0, nord2, nord6, nord4, comment, nord8
            return AppPalette(background: 0x2E3440, selection: 0x434C5E, text: 0xECEFF4, text2: 0xD8DEE9,
                              text3: 0x616E88, accent: 0x88C0D0, onAccent: 0x2E3440)
        case .gruvboxDark: // bg, bg2, fg, fg2, gray, yellow
            return AppPalette(background: 0x282828, selection: 0x504945, text: 0xEBDBB2, text2: 0xD5C4A1,
                              text3: 0x928374, accent: 0xFABD2F, onAccent: 0x282828)
        case .monokai: // background, line highlight, foreground, comment, green
            return AppPalette(background: 0x272822, selection: 0x49483E, text: 0xF8F8F2, text2: nil,
                              text3: 0x75715E, accent: 0xA6E22E, onAccent: 0x272822)
        case .oneDark: // bg, selection, fg, comment, blue
            return AppPalette(background: 0x282C34, selection: 0x3E4451, text: 0xABB2BF, text2: nil,
                              text3: 0x5C6370, accent: 0x61AFEF, onAccent: 0x282C34)
        case .tokyoNight: // bg, bg_highlight, fg, fg_dark, comment, blue
            return AppPalette(background: 0x1A1B26, selection: 0x292E42, text: 0xC0CAF5, text2: 0xA9B1D6,
                              text3: 0x565F89, accent: 0x7AA2F7, onAccent: 0x1A1B26)
        case .catppuccinMocha: // base, surface0, text, subtext0, overlay0, mauve
            return AppPalette(background: 0x1E1E2E, selection: 0x313244, text: 0xCDD6F4, text2: 0xA6ADC8,
                              text3: 0x6C7086, accent: 0xCBA6F7, onAccent: 0x1E1E2E)
        case .catppuccinLatte: // base, surface0, text, subtext0, overlay0, mauve
            return AppPalette(background: 0xEFF1F5, selection: 0xCCD0DA, text: 0x4C4F69, text2: 0x6C6F85,
                              text3: 0x9CA0B0, accent: 0x8839EF, onAccent: 0xEFF1F5, isLight: true)
        case .rosePine: // base, overlay, text, subtle, muted, iris
            return AppPalette(background: 0x191724, selection: 0x26233A, text: 0xE0DEF4, text2: 0x908CAA,
                              text3: 0x6E6A86, accent: 0xC4A7E7, onAccent: 0x191724)
        case .everforest: // bg0, bg3, fg, grey2, grey0, green (dark medium)
            return AppPalette(background: 0x2D353B, selection: 0x475258, text: 0xD3C6AA, text2: 0x9DA9A0,
                              text3: 0x7A8478, accent: 0xA7C080, onAccent: 0x2D353B)
        case .kanagawa: // sumiInk3, waveBlue1, fujiWhite, oldWhite, fujiGray, crystalBlue
            return AppPalette(background: 0x1F1F28, selection: 0x223249, text: 0xDCD7BA, text2: 0xC8C093,
                              text3: 0x727169, accent: 0x7E9CD8, onAccent: 0x1F1F28)
        case .githubDark: // canvas, neutral muted, fg default, fg muted, accent
            return AppPalette(background: 0x0D1117, selection: 0x21262D, text: 0xE6EDF3, text2: nil,
                              text3: 0x7D8590, accent: 0x2F81F7, onAccent: 0xFFFFFF)
        }
    }
}

/// Root of every window: follows the theme and the language. Changing either rebuilds the
/// view tree, because `Theme` colours are read from computed properties.
struct ThemedRoot<Content: View>: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var localizer = Localizer.shared
    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .environment(\.colorScheme, Theme.palette.isLight ? .light : .dark)
            .tint(Theme.accent)
            .foregroundStyle(Theme.text)
            .background(Theme.window)
            .id("\(settings.theme.rawValue)-\(localizer.language.rawValue)")
    }
}

/// Small preview of a theme for Settings: a window with a selected row and a badge.
struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 5) {
                    line(Color(hex: p.text), width: 46)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: p.accent)).frame(width: 9, height: 9)
                        line(Color(hex: p.text), width: 40)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: p.selection), in: RoundedRectangle(cornerRadius: 3))
                    line(p.text2.map { Color(hex: $0) } ?? Color(hex: p.text).opacity(0.72), width: 52)
                    line(Color(hex: p.text3), width: 34)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("3")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: p.onAccent))
                    .frame(width: 14, height: 14)
                    .background(Color(hex: p.accent), in: Circle())
                    .padding(6)
            }
            .frame(height: 64)
            .background(Color(hex: p.background), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1)
            }
            Text(theme.name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.text : Theme.text2)
                .lineLimit(1)
        }
    }

    private func line(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: 4)
    }
}
