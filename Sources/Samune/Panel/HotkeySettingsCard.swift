import SwiftUI

/// Settings card "Atajo": records the global shortcut that opens the launcher.
struct HotkeySettingsCard: View {
    @ObservedObject private var manager = HotkeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(tr("Atajo"))
            Text(tr("Abre la barra de búsqueda desde cualquier app, aunque %@ no esté delante.", AppInfo.name))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if manager.isRecording {
                    Text(tr("Pulsa la combinación nueva (con ⌘, ⌥ o ⌃). Esc cancela."))
                        .font(.system(size: 12)).foregroundStyle(Theme.accentText)
                        .frame(minHeight: 28)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(manager.hotkey.caps.enumerated()), id: \.offset) { _, cap in
                            KeyCap(text: cap)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer()
                if manager.isRecording {
                    Button(tr("Cancelar")) { manager.stopRecording() }
                        .buttonStyle(.appSecondary)
                } else {
                    Button(tr("Grabar atajo")) { manager.startRecording() }
                        .buttonStyle(.appSecondary)
                }
                Button(tr("Restablecer")) { manager.reset() }
                    .buttonStyle(.appGhost)
                    .disabled(manager.isRecording || manager.hotkey == .default)
                    .help(tr("Vuelve a %@", Hotkey.default.caps.joined()))
            }

            if !manager.isRegistered && !manager.isRecording {
                Label(tr("Esa combinación ya la usa el sistema u otra app. Elige otra."),
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard()
        .onDisappear { manager.stopRecording() }
    }
}

/// One key of a shortcut, drawn as a key cap.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 28)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong) }
    }
}
