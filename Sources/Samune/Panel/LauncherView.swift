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
    static let sectionHeight: CGFloat = 26
    static let cornerRadius: CGFloat = 14

    /// Height of the conversation with an AI account.
    static let answerHeight: CGFloat = 400

    static func answerPanelHeight() -> CGFloat { fieldHeight + 1 + answerHeight + 1 + footerHeight }

    static let menuWidth: CGFloat = 340
    static let menuRowHeight: CGFloat = 32
    static let menuPadding: CGFloat = 4
    static let menuFilterHeight: CGFloat = 36
    static let menuMaxRows = 8
    static let menuMargin: CGFloat = 8

    /// - Parameters:
    ///   - suggestions: the rows are suggestions for the empty field (a label goes above them).
    ///   - menuRows: number of actions when the actions menu is open (the unfiltered count, so
    ///     typing in the menu never resizes the panel).
    static func height(queryIsEmpty: Bool, rows: Int, menuRows: Int? = nil) -> CGFloat {
        if queryIsEmpty && rows == 0 { return fieldHeight }
        var body = rows == 0 ? messageHeight : listHeight(rows: rows)
        if queryIsEmpty { body += sectionHeight }
        if let menuRows { body = max(body, menuHeight(rows: menuRows) + menuMargin * 2) }
        return fieldHeight + 1 + body + 1 + footerHeight
    }

    static func listHeight(rows: Int) -> CGFloat {
        CGFloat(min(rows, maxVisibleRows)) * rowHeight + listPadding * 2
    }

    static func menuListHeight(rows: Int) -> CGFloat {
        CGFloat(max(1, min(rows, menuMaxRows))) * menuRowHeight + menuPadding * 2
    }

    static func menuHeight(rows: Int) -> CGFloat {
        menuListHeight(rows: rows) + 1 + menuFilterHeight
    }
}

/// The open actions menu: the row it belongs to, its actions and what was typed to filter them.
struct ActionsMenuState {
    let item: ResultItem
    let all: [RowAction]
    var filter = ""
    var selected = 0

    /// Actions matching the filter, best first (all of them, in order, without a filter).
    var visible: [RowAction] {
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        return all.enumerated()
            .compactMap { index, action in Fuzzy.score(text, action.title).map { (index, action, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }

    var selectedAction: RowAction? {
        let list = visible
        return list.indices.contains(selected) ? list[selected] : nil
    }
}

/// State of the panel: the text of the field, the selected row and the actions menu.
@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: String?
    /// Non-nil while the actions menu (⌘K) is open.
    @Published private(set) var menu: ActionsMenuState?
    /// The AppKit field, set by `LauncherSearchField` when it is created.
    weak var field: NSTextField?
    /// True once the user moved the selection for the current query.
    private var userMoved = false
    /// Row index to keep after an action refreshed the results.
    private var keptIndex: Int?

    var queryIsEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    var selectedItem: ResultItem? {
        SearchEngine.shared.results.first { $0.id == selectedID }
    }

    var selectedIndex: Int? {
        SearchEngine.shared.results.firstIndex { $0.id == selectedID }
    }

    /// The text changed (typing or programmatically): searches again.
    func queryChanged(_ text: String) {
        if query != text { query = text }
        // Set the field now, not in the next SwiftUI update, so the caret can be placed right away.
        if let field, field.stringValue != text { field.stringValue = text }
        userMoved = false
        keptIndex = nil
        menu = nil
        // While a conversation is shown, the field holds the next question: nothing to search.
        if AIChat.shared.isActive { return }
        SearchEngine.shared.update(query: text)
    }

    /// First row, unless the user picked one that is still there while results stream in.
    func resultsChanged(_ results: [ResultItem]) {
        if let index = keptIndex {
            selectedID = results.isEmpty ? nil : results[min(index, results.count - 1)].id
            if !SearchEngine.shared.isSearching { keptIndex = nil }
            userMoved = true
            return
        }
        if userMoved, let selectedID, results.contains(where: { $0.id == selectedID }) { return }
        userMoved = false
        selectedID = results.first?.id
    }

    /// After an action that keeps the panel open: the next results keep the selection at this index.
    func keepSelection(at index: Int) {
        keptIndex = index
        menu = nil
    }

    func move(_ delta: Int) {
        let results = SearchEngine.shared.results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : 0)
        let next = ((current + delta) % results.count + results.count) % results.count
        selectedID = results[next].id
        userMoved = true
    }

    // MARK: Actions menu

    /// Opens the menu for the selected row. False when no row is selected.
    @discardableResult
    func openMenu() -> Bool {
        guard let item = selectedItem else { return false }
        menu = ActionsMenuState(item: item, all: SearchEngine.shared.actions(for: item))
        return true
    }

    func closeMenu() { menu = nil }

    func moveInMenu(_ delta: Int) {
        guard var state = menu else { return }
        let count = state.visible.count
        guard count > 0 else { return }
        state.selected = ((state.selected + delta) % count + count) % count
        menu = state
    }

    func selectInMenu(_ index: Int) {
        guard var state = menu, state.selected != index else { return }
        state.selected = index
        menu = state
    }

    func setMenuFilter(_ text: String) {
        guard var state = menu else { return }
        state.filter = text
        state.selected = 0
        menu = state
    }
}

/// Content of the launcher panel.
struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var engine = SearchEngine.shared
    @ObservedObject private var chat = AIChat.shared
    let onActivate: (ResultItem) -> Void
    let onAction: (RowAction, ResultItem) -> Void

    private var showsSuggestions: Bool { model.queryIsEmpty && engine.showingSuggestions }

    var body: some View {
        VStack(spacing: 0) {
            header
            if chat.isActive {
                Rectangle().fill(Theme.line).frame(height: 1)
                AIAnswerView(chat: chat)
                    .frame(height: LauncherLayout.answerHeight)
                Rectangle().fill(Theme.line).frame(height: 1)
                chatFooter
            } else if !model.queryIsEmpty || !engine.results.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        if showsSuggestions {
                            Text(tr("Sugerencias"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .frame(height: LauncherLayout.sectionHeight, alignment: .bottom)
                        }
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
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    if let menu = model.menu {
                        // Clicking outside the menu closes it.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { model.closeMenu() }
                        ActionsMenuView(menu: menu, model: model) { action in onAction(action, menu.item) }
                            .padding(LauncherLayout.menuMargin)
                    }
                }
                .frame(maxHeight: .infinity)
                Rectangle().fill(Theme.line).frame(height: 1)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.window)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: chat.isActive ? "sparkles" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(chat.isActive ? Theme.accentText : Theme.text3)
            LauncherSearchField(model: model)
            if engine.isSearching && !chat.isActive {
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
        let actions = model.menu?.all ?? model.selectedItem.map { engine.actions(for: $0) } ?? []
        let returnTitle = model.menu.map { $0.selectedAction?.title ?? "" } ?? actions.first?.title
        return HStack(spacing: 16) {
            if let returnTitle, !returnTitle.isEmpty { hint("↩", returnTitle) }
            hint("esc", model.menu == nil ? tr("Cerrar") : tr("Volver"))
            Spacer(minLength: 0)
            if actions.count > 1 {
                HStack(spacing: 5) {
                    Text(tr("Acciones")).font(.system(size: 11))
                        .foregroundStyle(model.menu == nil ? Theme.text3 : Theme.accentText)
                    Text("⌘K").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
                }
                .contentShape(Rectangle())
                .onTapGesture { if model.menu == nil { model.openMenu() } else { model.closeMenu() } }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.footerHeight)
    }

    /// Footer while a conversation is shown: its keys, the account and what it has cost so far.
    private var chatFooter: some View {
        let last = chat.turns.last
        return HStack(spacing: 16) {
            if chat.isRunning {
                hint("esc", tr("Parar"))
            } else {
                if !model.queryIsEmpty { hint("↩", tr("Preguntar")) }
                if last?.image != nil { hint("⌘S", tr("Guardar imagen")) }
                if last.map({ !$0.text.isEmpty || $0.image != nil }) == true { hint("⌘C", tr("Copiar")) }
                hint("esc", tr("Volver"))
            }
            Spacer(minLength: 0)
            if let notice = chat.notice {
                Text(notice).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ok)
            }
            if let account = chat.account {
                Text(account.name).font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            if let cost = chat.totalCost {
                Text(AICost.text(cost.value, estimate: cost.estimate))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            }
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

/// The actions menu, anchored at the bottom right of the results. The filter is typed through the
/// panel's key handling (the search field keeps the focus), so it is plain text here.
private struct ActionsMenuView: View {
    let menu: ActionsMenuState
    @ObservedObject var model: LauncherModel
    let onRun: (RowAction) -> Void

    var body: some View {
        let visible = menu.visible
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if visible.isEmpty {
                            Text(tr("Sin resultados"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: LauncherLayout.menuRowHeight)
                        }
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, action in
                            ActionRow(action: action, selected: index == menu.selected)
                                .id(action.id)
                                .onTapGesture { onRun(action) }
                                .onHover { inside in if inside { model.selectInMenu(index) } }
                        }
                    }
                    .padding(.vertical, LauncherLayout.menuPadding)
                }
                .scrollIndicators(visible.count > LauncherLayout.menuMaxRows ? .automatic : .never)
                .frame(height: LauncherLayout.menuListHeight(rows: visible.count))
                .onChange(of: menu.selected) { _, index in
                    guard visible.indices.contains(index) else { return }
                    proxy.scrollTo(visible[index].id)
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text3)
                Text(menu.filter.isEmpty ? tr("Buscar acciones…") : menu.filter)
                    .font(.system(size: 13))
                    .foregroundStyle(menu.filter.isEmpty ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                if !menu.filter.isEmpty {
                    Rectangle().fill(Theme.accent).frame(width: 1.5, height: 15)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: LauncherLayout.menuFilterHeight)
        }
        .frame(width: LauncherLayout.menuWidth)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.lineStrong, lineWidth: 1) }
    }
}

private struct ActionRow: View {
    let action: RowAction
    let selected: Bool

    var body: some View {
        let color = action.destructive ? Theme.danger : Theme.text
        HStack(spacing: 10) {
            Image(systemName: IconLoader.shared.symbolName(action.symbol))
                .font(.system(size: 12.5))
                .foregroundStyle(action.destructive ? Theme.danger : Theme.text2)
                .frame(width: 18)
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut = action.shortcut {
                Text(shortcut.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: LauncherLayout.menuRowHeight)
        .background(selected ? Theme.navSelected : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .padding(.horizontal, LauncherLayout.menuPadding)
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
            string: AIChat.shared.isActive ? tr("Sigue preguntando…") : tr("Buscar apps, archivos e integraciones…"),
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
