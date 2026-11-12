import AppKit
import SwiftUI

/// Sizes shared by the SwiftUI content and the panel frame, so both agree on the height.
enum LauncherLayout {
    static let width: CGFloat = 720
    static let fieldHeight: CGFloat = 60
    static let rowHeight: CGFloat = 46
    static let listPadding: CGFloat = 6
    static let maxVisibleRows = 9
    static let messageHeight: CGFloat = 46
    static let footerHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 14

    static func height(queryIsEmpty: Bool, rows: Int) -> CGFloat {
        guard !queryIsEmpty else { return fieldHeight }
        let body = rows == 0 ? messageHeight : CGFloat(min(rows, maxVisibleRows)) * rowHeight + listPadding * 2
        return fieldHeight + 1 + body + 1 + footerHeight
    }
}

/// State of the panel: the text of the field and the selected row.
@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: String?
    /// The AppKit field, set by `LauncherSearchField` when it is created.
    weak var field: NSTextField?
    /// True once the user moved the selection for the current query.
    private var userMoved = false

    var queryIsEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    var selectedItem: ResultItem? {
        SearchEngine.shared.results.first { $0.id == selectedID }
    }

    /// The text changed (typing or programmatically): searches again.
    func queryChanged(_ text: String) {
        if query != text { query = text }
        // Set the field now, not in the next SwiftUI update, so the caret can be placed right away.
        if let field, field.stringValue != text { field.stringValue = text }
        userMoved = false
        SearchEngine.shared.update(query: text)
    }

    /// First row, unless the user picked one that is still there while results stream in.
    func resultsChanged(_ results: [ResultItem]) {
        if userMoved, let selectedID, results.contains(where: { $0.id == selectedID }) { return }
        userMoved = false
        selectedID = results.first?.id
    }

    func move(_ delta: Int) {
        let results = SearchEngine.shared.results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : 0)
        let next = ((current + delta) % results.count + results.count) % results.count
        selectedID = results[next].id
        userMoved = true
    }
}

/// Content of the launcher panel.
struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var engine = SearchEngine.shared
    let onActivate: (ResultItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.queryIsEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                if engine.results.isEmpty {
                    Text(engine.isSearching ? "" : tr("Sin resultados"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(height: LauncherLayout.messageHeight)
                } else {
                    list
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.window)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text3)
            LauncherSearchField(model: model)
            if engine.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.fieldHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(engine.results) { item in
                        ResultRow(item: item, selected: item.id == model.selectedID)
                            .id(item.id)
                            .onTapGesture { onActivate(item) }
                    }
                }
                .padding(.vertical, LauncherLayout.listPadding)
            }
            .scrollIndicators(engine.results.count > LauncherLayout.maxVisibleRows ? .automatic : .never)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↩", tr("Abrir"))
            hint("⌘↩", tr("Mostrar en Finder"))
            hint("⌘C", tr("Copiar"))
            hint("esc", tr("Cerrar"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.footerHeight)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
    }
}

private struct ResultRow: View {
    let item: ResultItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ResultIconView(icon: item.icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            Text(item.kind)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherLayout.rowHeight)
        .background(selected ? Theme.navSelected : .clear, in: RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
    }
}

/// The big search field: an AppKit text field, so the panel controls focus, caret and key handling.
struct LauncherSearchField: NSViewRepresentable {
    @ObservedObject var model: LauncherModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = .systemFont(ofSize: 22)
        field.delegate = context.coordinator
        field.stringValue = model.query
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        model.field = field
        style(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        style(field)
        if field.stringValue != model.query { field.stringValue = model.query }
    }

    private func style(_ field: NSTextField) {
        let font = NSFont.systemFont(ofSize: 22)
        field.textColor = NSColor(Theme.text)
        field.placeholderAttributedString = NSAttributedString(
            string: tr("Buscar apps, archivos e integraciones…"),
            attributes: [.foregroundColor: NSColor(Theme.text3), .font: font])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LauncherModel
        init(model: LauncherModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let text = field.stringValue
            MainActor.assumeIsolated { model.queryChanged(text) }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            MainActor.assumeIsolated {
                (field.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(Theme.accent)
            }
        }
    }
}
