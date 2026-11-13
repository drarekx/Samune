import AppKit
import SwiftUI

/// Settings card "Integraciones": list with switch, prefix, variables and "Nueva integración…".
struct IntegrationsSettingsCard: View {
    @ObservedObject private var store = IntegrationStore.shared
    @State private var showingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(tr("Integraciones"))
            Text(tr("Busca en tus servicios desde el lanzador con el prefijo de cada integración («bm laravel», «!laravel»)."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if store.integrations.isEmpty {
                Text(tr("No hay integraciones en la carpeta."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            ForEach(store.integrations) { integration in
                IntegrationRow(integration: integration)
            }

            HStack(spacing: 8) {
                Button(tr("Nueva integración…")) { showingNew = true }
                    .buttonStyle(.appPrimary)
                Button(tr("Recargar")) { store.reload() }
                    .buttonStyle(.appSecondary)
                Button(tr("Abrir carpeta de integraciones")) { store.openFolder() }
                    .buttonStyle(.appGhost)
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                Text(tr("Cada integración es una carpeta con manifest.json y un script que imprime JSON."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Ver la guía")) {
                    if let url = URL(string: "https://github.com/\(AppInfo.repo)/blob/main/docs/integraciones.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accentText)
            }
        }
        .appCard()
        .sheet(isPresented: $showingNew) {
            ThemedRoot { NewIntegrationSheet(isPresented: $showingNew) }
        }
    }
}

/// One integration: header, error, variables and buttons.
private struct IntegrationRow: View {
    let integration: Integration
    @ObservedObject private var store = IntegrationStore.shared
    @State private var expanded = false
    @State private var testing = false
    @State private var testResult: (text: String, failed: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                IntegrationIconView(icon: integration.icon)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(integration.name).fontWeight(.medium)
                        if integration.manifest != nil, !store.prefix(of: integration).isEmpty {
                            Text(store.prefix(of: integration))
                                .monospacedText(size: 11)
                                .foregroundStyle(Theme.text2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Theme.control, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let description = integration.manifest?.description {
                        Text(description).font(.system(size: 12)).foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = integration.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { store.isEnabled(integration.id) },
                                         set: { store.setEnabled($0, id: integration.id) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.accentFill)
                    .controlSize(.small)
                    .accessibilityLabel(tr("Activar %@", integration.name))
            }

            if let manifest = integration.manifest {
                HStack(spacing: 8) {
                    Text(tr("Prefijo")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    AppTextField(placeholder: manifest.keyword,
                                 text: Binding(get: { store.prefixes[integration.id] ?? "" },
                                               set: { store.setPrefix($0, id: integration.id) }))
                        .frame(width: 96)
                        .accessibilityLabel(tr("Prefijo"))
                    Toggle(tr("Seguido de un espacio"),
                           isOn: Binding(get: { store.needsSpace(integration) },
                                         set: { store.setNeedsSpace($0, id: integration.id) }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                    Spacer(minLength: 0)
                }
            }

            if let variables = integration.manifest?.variables, !variables.isEmpty {
                Button {
                    expanded.toggle()
                } label: {
                    Label(tr("Variables (%d)", variables.count),
                          systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(variables) { variable in
                            VariableField(integrationID: integration.id, variable: variable)
                        }
                    }
                    .padding(.leading, 18)
                }
            }

            HStack(spacing: 8) {
                Button(tr("Abrir carpeta")) { store.openFolder(of: integration) }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 26))
                Button(testing ? tr("Probando…") : tr("Probar")) { test() }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 26))
                    .disabled(testing || !integration.isUsable)
                if let testResult {
                    Text(testResult.text)
                        .font(.system(size: 12))
                        .foregroundStyle(testResult.failed ? Theme.warn : Theme.ok)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line) }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            let outcome = await store.test(integration)
            testing = false
            switch outcome {
            case .items(let items): testResult = (tr("%d elementos", items.count), false)
            case .failure(let short, _): testResult = (short, true)
            case .cancelled: testResult = nil
            }
        }
    }
}

/// SF Symbol or image file of an integration.
private struct IntegrationIconView: View {
    let icon: ItemIcon

    var body: some View {
        Group {
            switch icon {
            case .image(let url):
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: IntegrationManifest.defaultIcon)
                }
            case .symbol(let name):
                Image(systemName: name)
            default:
                Image(systemName: IntegrationManifest.defaultIcon)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.accentText)
        .frame(width: 30, height: 30)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Field of one variable. Plain ones save as you type; secret ones save on Return to the Keychain.
private struct VariableField: View {
    let integrationID: String
    let variable: IntegrationManifest.Variable
    @State private var text = ""
    @State private var hasSecret = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(variable.label).font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text(variable.key).monospacedText(size: 10).foregroundStyle(Theme.text3)
            }
            if variable.secret {
                HStack(spacing: 6) {
                    SecureAppField(placeholder: hasSecret ? "••••" : (variable.placeholder.isEmpty ? tr("Sin guardar") : variable.placeholder),
                                   text: $text, onSubmit: saveSecret)
                    if !text.isEmpty {
                        Button(tr("Guardar"), action: saveSecret)
                            .buttonStyle(AppButtonStyle(kind: .primary, height: 32))
                    } else if hasSecret {
                        IconButton(symbol: "trash", label: tr("Borrar")) {
                            IntegrationVariables.set("", integration: integrationID, variable)
                            hasSecret = false
                            IntegrationStore.shared.clearCache(of: integrationID)
                        }
                    }
                }
                Text(tr("Se guarda en el Llavero de macOS."))
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            } else {
                AppTextField(placeholder: variable.placeholder, text: Binding(get: { text }, set: { newValue in
                    text = newValue
                    IntegrationVariables.set(newValue, integration: integrationID, variable)
                    IntegrationStore.shared.clearCache(of: integrationID)
                }))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if variable.secret {
            // Only checks that it exists: the value is never read back into the UI.
            hasSecret = IntegrationVariables.hasSecret(integration: integrationID, key: variable.key)
        } else {
            text = IntegrationVariables.value(integration: integrationID, variable) ?? ""
        }
    }

    private func saveSecret() {
        guard !text.isEmpty else { return }
        IntegrationVariables.set(text, integration: integrationID, variable)
        text = ""
        hasSecret = IntegrationVariables.hasSecret(integration: integrationID, key: variable.key)
        IntegrationStore.shared.clearCache(of: integrationID)
    }
}

/// `AppTextField` look with a secure field.
private struct SecureAppField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key").font(.system(size: 12)).foregroundStyle(Theme.text3)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.lineStrong) }
    }
}

/// Asks for the name of a new integration and creates it from the template.
private struct NewIntegrationSheet: View {
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Nueva integración")).font(.system(size: 15, weight: .semibold))
            Text(tr("Se crea una carpeta con manifest.json y run.sh a partir de la plantilla «Hola» y se abre en el Finder."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            AppTextField(placeholder: tr("Nombre"), text: $name, onSubmit: create)
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.warn)
            }
            HStack {
                Spacer()
                Button(tr("Cancelar")) { isPresented = false }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(tr("Crear"), action: create)
                    .buttonStyle(.appPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        switch IntegrationStore.shared.create(named: name) {
        case .success(let folder):
            isPresented = false
            NSWorkspace.shared.open(folder)
        case .failure(let failure):
            error = failure.message
        }
    }
}
