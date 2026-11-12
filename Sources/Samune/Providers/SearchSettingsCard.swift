import AppKit
import SwiftUI

/// Settings card "Búsqueda": app folders and whether files are searched.
struct SearchSettingsCard: View {
    @ObservedObject private var settings = SearchSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(tr("Búsqueda"))
            SwitchRow(title: tr("Buscar archivos"),
                      detail: tr("A partir de 3 letras, o solo archivos escribiendo «f » delante."),
                      isOn: $settings.filesEnabled)
            SwitchRow(title: tr("Buscar en todo el ordenador"),
                      detail: tr("Si no, solo en tu carpeta de inicio."),
                      isOn: $settings.filesWholeComputer)
            SwitchRow(title: tr("Incluir paneles de Ajustes del sistema"),
                      isOn: $settings.includeSystemSettings)

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Otras carpetas con apps")).foregroundStyle(Theme.text)
                Text(tr("Además de Aplicaciones, Utilidades y las apps del sistema."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(settings.extraAppFolders, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        Text(SearchPaths.abbreviate(path))
                            .monospacedText()
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        IconButton(symbol: "minus", label: tr("Quitar carpeta"), size: 26) {
                            settings.removeAppFolder(path)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
                }
                Button(tr("Añadir carpeta…"), action: chooseFolder)
                    .buttonStyle(.appSecondary)
            }
            .padding(.top, 8)
        }
        .appCard()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Añadir")
        panel.message = tr("Elige carpetas donde buscar apps")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            settings.addAppFolder(url.path)
        }
    }
}
