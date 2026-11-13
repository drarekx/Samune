import AppKit
import SwiftUI

/// Settings card "Notas": double ⌘C, keyboard detection, expiry, count and trash.
struct NotesSettingsCard: View {
    @ObservedObject private var settings = NotesSettings.shared
    @ObservedObject private var store = NoteStore.shared
    @ObservedObject private var keyWatcher = KeyWatcher.shared
    @State private var showTrash: Bool
    @State private var notityRunning = false

    init(showTrash: Bool = false) {
        _showTrash = State(initialValue: showTrash)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(tr("Notas"))
            Text(tr("Selecciona un texto y pulsa ⌘C dos veces seguidas: se guarda como nota. Búscalas escribiendo «n » delante."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if notityRunning {
                Label(tr("Notity también está abierta: las dos apps guardarán las mismas copias."),
                      systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SwitchRow(title: tr("Guardar al copiar dos veces (⌘C ⌘C)"),
                      detail: tr("Un ⌘C normal no guarda nada. Las contraseñas que copian los gestores (1Password, Bitwarden, Llavero…) no se guardan nunca."),
                      isOn: $settings.doubleCopy)
            HStack {
                Text(tr("Tiempo entre las dos copias")).foregroundStyle(settings.doubleCopy ? Theme.text : Theme.text3)
                Spacer()
                SegmentedControl(options: [(tr("Rápido"), 0.35), (tr("Normal"), 0.5), (tr("Lento"), 0.8)],
                                 selection: $settings.doubleCopyWindow)
                    .disabled(!settings.doubleCopy)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            SwitchRow(title: tr("Detectar ⌘C con el teclado"),
                      detail: tr("Para apps como iTerm2, que no vuelven a copiar si el texto no ha cambiado. Pide el permiso de Monitorización de entrada; Samune solo mira si pulsas ⌘C, nunca lo que escribes."),
                      isOn: Binding(get: { settings.keyboardDetection }, set: { on in
                          settings.keyboardDetection = on
                          keyWatcher.refresh(ask: on)
                      }))
                .disabled(!settings.doubleCopy)
            if settings.keyboardDetection && settings.doubleCopy {
                if keyWatcher.isRunning {
                    Label(tr("Activo: el doble ⌘C funciona en todas las apps."), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.ok)
                } else {
                    HStack {
                        Label(tr("Falta el permiso. Activa Samune en Monitorización de entrada."),
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(tr("Abrir Ajustes del Sistema…")) { KeyWatcher.openPrivacySettings() }
                            .buttonStyle(.appSecondary)
                    }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Caducidad")).foregroundStyle(Theme.text)
                Text(tr("Las notas fijadas no caducan. Las caducadas pasan a la papelera, de donde se pueden recuperar durante %d días.", NoteStore.trashDays))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                SegmentedControl(options: [(tr("1 día"), 1), (tr("7 días"), 7), (tr("30 días"), 30), (tr("Nunca"), 0)],
                                 selection: $settings.expiryDays)
            }
            .padding(.vertical, 4)
            Rectangle().fill(Theme.line).frame(height: 1)

            Text(tr("Notas guardadas: %d", store.active.count)).foregroundStyle(Theme.text)
            trashSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .onAppear { notityRunning = NotesController.notityIsRunning }
    }

    @ViewBuilder
    private var trashSection: some View {
        let trash = store.trash
        Button {
            showTrash.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showTrash ? 90 : 0))
                Text(tr("Papelera (%d)", trash.count))
                Spacer()
            }
            .foregroundStyle(Theme.text2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showTrash {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Las notas caducadas o borradas se quedan aquí %d días.", NoteStore.trashDays))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                if trash.isEmpty {
                    Text(tr("La papelera está vacía"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                        .padding(.vertical, 4)
                }
                ForEach(trash) { note in
                    HStack(spacing: 8) {
                        Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.title).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                            Text(NotesProvider.relativeDate(note.trashed ?? note.created))
                                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                        IconButton(symbol: "arrow.uturn.backward", label: tr("Restaurar"), size: 26) {
                            store.restore(note.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
                }
                if !trash.isEmpty {
                    Button(tr("Vaciar la papelera")) { store.emptyTrash() }
                        .buttonStyle(.appDanger)
                }
            }
            .padding(.leading, 16)
        }
    }
}
