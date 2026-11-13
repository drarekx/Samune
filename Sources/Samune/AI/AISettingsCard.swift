import SwiftUI

/// Settings card "IA": the accounts, with their key, model and prefix.
struct AISettingsCard: View {
    @ObservedObject private var store = AIStore.shared
    @State private var expanded: UUID?

    init(expanded: UUID? = nil) {
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(tr("IA"))
            Text(tr("Pregunta a un modelo desde el lanzador: escribe el prefijo de una cuenta y tu pregunta («claude ¿qué es un mutex?»)."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if store.accounts.isEmpty {
                Text(tr("Todavía no hay cuentas."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            ForEach(store.accounts) { account in
                AIAccountRow(account: account, expanded: expanded == account.id) {
                    expanded = expanded == account.id ? nil : account.id
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(AIProviderKind.allCases) { kind in
                        Button(kind.title) { expanded = store.add(kind).id }
                    }
                } label: {
                    Text(tr("Añadir cuenta…"))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.lineStrong) }
            }
            .padding(.top, 4)

            Text(tr("Las claves se guardan en el Llavero de macOS. Cada pregunta se envía al proveedor de la cuenta y se cobra en ella."))
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }
}

/// One account: summary line and, expanded, its fields.
private struct AIAccountRow: View {
    let account: AIAccount
    let expanded: Bool
    let toggle: () -> Void
    @ObservedObject private var store = AIStore.shared
    @State private var key = ""
    @State private var loadingModels = false
    @State private var message: (text: String, failed: Bool)?
    @State private var testing = false

    private var hasKey: Bool { store.hasKey(account) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: account.kind.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 30, height: 30)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.name).fontWeight(.medium).foregroundStyle(Theme.text)
                            if !account.prefix.isEmpty {
                                Text(account.prefix)
                                    .monospacedText(size: 11)
                                    .foregroundStyle(Theme.text2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(summary).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let problem = store.problem(of: account) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Theme.warn)
            }

            if expanded { fields }
        }
        .padding(12)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line) }
    }

    private var summary: String {
        var parts = [account.kind.title, account.model.isEmpty ? tr("sin modelo") : account.model]
        if !hasKey { parts.append(tr("sin clave")) }
        return parts.joined(separator: " · ")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field(tr("Nombre")) {
                AppTextField(placeholder: account.kind.title, text: binding(\.name))
            }
            field(tr("Clave de la API")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AISecureField(placeholder: hasKey ? "••••" : tr("Sin guardar"), text: $key, onSubmit: saveKey)
                        if !key.isEmpty {
                            Button(tr("Guardar"), action: saveKey)
                                .buttonStyle(AppButtonStyle(kind: .primary, height: 32))
                        } else if hasKey {
                            IconButton(symbol: "trash", label: tr("Borrar")) {
                                store.setKey("", for: account)
                            }
                        }
                    }
                    let sharing = store.sharing(account)
                    if !sharing.isEmpty {
                        Text(tr("Clave compartida con: %@", sharing.joined(separator: ", ")))
                            .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                }
            }
            field(tr("Modelo")) {
                modelPicker(\.model, images: false)
            }
            if account.kind.generatesImages {
                field(tr("Modelo de imágenes")) {
                    modelPicker(\.imageModel, images: true)
                }
            }
            field(tr("Prefijo")) {
                HStack(spacing: 8) {
                    AppTextField(placeholder: account.kind.defaultPrefix, text: binding(\.prefix))
                        .frame(width: 110)
                    Toggle(tr("Seguido de un espacio"), isOn: binding(\.needsSpace))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                }
            }
            field(tr("Instrucciones")) {
                AppTextField(placeholder: tr("Opcional: cómo quieres que responda"), text: binding(\.system))
            }

            HStack(spacing: 8) {
                Button(testing ? tr("Probando…") : tr("Probar")) { test() }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 26))
                    .disabled(testing || !hasKey)
                Button(tr("Duplicar")) { _ = store.duplicate(account) }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 26))
                Button(tr("Borrar")) { store.remove(account) }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 26))
                if let message {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(message.failed ? Theme.warn : Theme.ok)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 2)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .frame(width: 124, alignment: .leading)
                .padding(.top, 8)
            content()
        }
    }

    /// Text field for any model id plus a menu with the ids the provider lists.
    private func modelPicker(_ keyPath: WritableKeyPath<AIAccount, String>, images: Bool) -> some View {
        let listed = store.models(for: account).filter { $0.generatesImages == images }
        return HStack(spacing: 6) {
            AppTextField(placeholder: tr("Identificador del modelo"), text: binding(keyPath))
            Menu {
                if listed.isEmpty {
                    Text(hasKey ? tr("Pulsa actualizar para cargar la lista") : tr("Guarda antes la clave"))
                }
                ForEach(listed) { model in
                    Button(model.name.map { "\($0) (\(model.id))" } ?? model.id) {
                        var changed = account
                        changed[keyPath: keyPath] = model.id
                        store.update(changed)
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30, height: 32)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityLabel(tr("Elegir un modelo de la lista"))
            IconButton(symbol: loadingModels ? "hourglass" : "arrow.clockwise", label: tr("Actualizar la lista de modelos")) {
                loadModels()
            }
            .disabled(loadingModels || !hasKey)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AIAccount, Value>) -> Binding<Value> {
        Binding(get: { account[keyPath: keyPath] }, set: { newValue in
            var changed = account
            changed[keyPath: keyPath] = newValue
            store.update(changed)
        })
    }

    private func saveKey() {
        guard !key.isEmpty else { return }
        store.setKey(key, for: account)
        key = ""
        loadModels()
    }

    private func loadModels() {
        guard !loadingModels else { return }
        loadingModels = true
        message = nil
        Task {
            do {
                try await store.refreshModels(for: account)
                message = (tr("%d modelos", store.models(for: account).count), false)
            } catch let error as AIError {
                message = (error.text, true)
            } catch {
                message = (error.localizedDescription, true)
            }
            loadingModels = false
        }
    }

    /// Asks for one word: checks the key and the model, and shows what it cost.
    private func test() {
        testing = true
        message = nil
        let account = account
        Task {
            defer { testing = false }
            guard let key = await Task.detached(operation: { AIStore.key(of: account) }).value else {
                message = (AIError.missingKey.text, true)
                return
            }
            do {
                let question = AIMessage(role: .user, text: "Reply with the single word: OK")
                let answer = try await AIClient.ask(account, key: key, model: store.model(account.model, of: account),
                                                    messages: [question]) { _ in }
                var text = tr("Funciona")
                if let cost = answer.usage.cost {
                    text += " · " + AICost.text(cost, estimate: answer.usage.costIsEstimate)
                }
                message = (text, false)
            } catch let error as AIError {
                message = (error.text, true)
            } catch {
                message = (error.localizedDescription, true)
            }
        }
    }
}

/// `AppTextField` look with a secure field.
private struct AISecureField: View {
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
