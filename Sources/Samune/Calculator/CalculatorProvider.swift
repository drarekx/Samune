import Foundation

/// Maths and conversions typed in the launcher ("23*4", "10 km a mi", "120 eur a usd").
/// Its single row goes first; Return copies the result.
@MainActor
final class CalculatorProvider: SearchProvider {
    let priority = -10

    init() {
        ExchangeRates.shared.load()
        installDebugHook()
    }

    func search(_ query: String) async -> ProviderResponse {
        guard let item = item(for: query) else { return .empty }
        return ProviderResponse(items: [item])
    }

    /// The row for `query`, or nil when it is not a calculation. Cheap: runs on every keystroke.
    func item(for query: String) -> ResultItem? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        if let expression = MathExpression(text) {
            let subtitle = expression.normalized(format: NumberFormat.display)
            return row(title: NumberFormat.display(expression.value),
                       subtitle: subtitle,
                       copy: NumberFormat.plain(expression.value),
                       extra: ItemAction(id: "copyExpression", title: tr("Copiar la operación"), symbol: "function",
                                         action: .copy("\(subtitle) = \(NumberFormat.display(expression.value))")))
        }
        switch Conversion.parse(text) {
        case .units(let amount, let from, let to)?:
            let measurement = Measurement(value: amount, unit: from.unit)
            let value = measurement.converted(to: to.unit).value
            guard value.isFinite else { return nil }
            let title = "\(NumberFormat.measure(value)) \(to.symbol)"
            return row(title: title,
                       subtitle: "\(NumberFormat.measure(amount)) \(from.symbol) → \(to.symbol)",
                       copy: NumberFormat.plainMeasure(value),
                       extra: ItemAction(id: "copyWithUnit", title: tr("Copiar con la unidad"),
                                         symbol: "ruler", action: .copy(title)))
        case .currency(let amount, let from, let target)?:
            let to = target ?? Self.localCurrency(avoiding: from)
            guard let value = ExchangeRates.shared.convert(amount, from: from, to: to), value.isFinite else { return nil }
            let title = "\(NumberFormat.money(value)) \(to)"
            var subtitle = "\(NumberFormat.display(amount)) \(from) → \(to)"
            if let date = ExchangeRates.shared.date {
                subtitle = tr("%@ · tipos del BCE del %@", subtitle, Self.rateDate(date))
            }
            return row(title: title, subtitle: subtitle, copy: NumberFormat.plainMoney(value),
                       extra: ItemAction(id: "copyWithUnit", title: tr("Copiar con la moneda"),
                                         symbol: "dollarsign.circle", action: .copy(title)))
        case nil:
            return nil
        }
    }

    private func row(title: String, subtitle: String, copy: String, extra: ItemAction) -> ResultItem {
        ResultItem(id: "calc", title: title, subtitle: subtitle, icon: .symbol("equal.square"),
                   kind: tr("Calculadora"), action: .copy(copy), score: 1, copyText: copy, actions: [extra])
    }

    /// Currency of the user's region; another one if that is the one being converted.
    private static func localCurrency(avoiding source: String) -> String {
        let local = Locale.autoupdatingCurrent.currency?.identifier.uppercased() ?? "USD"
        let usable = CurrencyCatalog.codes.contains(local) ? local : "USD"
        if usable != source { return usable }
        return source == "EUR" ? "USD" : "EUR"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        return formatter
    }()

    private static func rateDate(_ date: Date) -> String {
        dateFormatter.locale = Localizer.shared.locale
        return dateFormatter.string(from: date)
    }

    // MARK: - Debug hook

    /// Debug builds only: `calc:<query>|<output file>` writes "title\tsubtitle\tcopy" or "none".
    private func installDebugHook() {
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.egluu.samune.debug"),
                                                            object: nil, queue: .main) { [weak self] note in
            guard let command = note.object as? String, command.hasPrefix("calc:"),
                  let bar = command.lastIndex(of: "|") else { return }
            let query = String(command[command.index(command.startIndex, offsetBy: 5)..<bar])
            let path = String(command[command.index(after: bar)...])
            MainActor.assumeIsolated {
                guard let self else { return }
                let line: String
                if let item = self.item(for: query) {
                    line = [item.title, item.subtitle ?? "", item.copyText ?? ""].joined(separator: "\t")
                } else {
                    line = "none"
                }
                try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
}

/// Number formats of the calculator, in the user's locale.
enum NumberFormat {
    private static func formatter(grouping: Bool, configure: (NumberFormatter) -> Void) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        configure(formatter)
        return formatter
    }

    private static let exact = formatter(grouping: true) { $0.maximumFractionDigits = 10 }
    private static let exactPlain = formatter(grouping: false) { $0.maximumFractionDigits = 10 }
    private static let scientific: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .scientific
        formatter.maximumFractionDigits = 8
        return formatter
    }()
    private static let measureLarge = formatter(grouping: true) { $0.maximumFractionDigits = 3 }
    private static let measureLargePlain = formatter(grouping: false) { $0.maximumFractionDigits = 3 }
    private static let measureSmall = formatter(grouping: true) {
        $0.usesSignificantDigits = true
        $0.maximumSignificantDigits = 4
    }
    private static let measureSmallPlain = formatter(grouping: false) {
        $0.usesSignificantDigits = true
        $0.maximumSignificantDigits = 4
    }
    private static let currency = formatter(grouping: true) {
        $0.minimumFractionDigits = 2
        $0.maximumFractionDigits = 2
    }
    private static let currencyPlain = formatter(grouping: false) {
        $0.minimumFractionDigits = 2
        $0.maximumFractionDigits = 2
    }

    /// 12 significant digits: removes float noise (0.1 + 0.2 = 0.3).
    private static func clean(_ value: Double) -> Double {
        let cleaned = Double(String(format: "%.12g", value)) ?? value
        return cleaned == 0 ? 0 : cleaned  // no "-0"
    }

    private static func needsScientific(_ value: Double) -> Bool {
        value != 0 && (abs(value) >= 1e15 || abs(value) < 1e-9)
    }

    private static func string(_ formatter: NumberFormatter, _ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func display(_ value: Double) -> String {
        let value = clean(value)
        return string(needsScientific(value) ? scientific : exact, value)
    }

    static func plain(_ value: Double) -> String {
        let value = clean(value)
        return string(needsScientific(value) ? scientific : exactPlain, value)
    }

    static func measure(_ value: Double) -> String {
        let value = clean(value)
        if needsScientific(value) { return string(scientific, value) }
        return string(abs(value) >= 1 || value == 0 ? measureLarge : measureSmall, value)
    }

    static func plainMeasure(_ value: Double) -> String {
        let value = clean(value)
        if needsScientific(value) { return string(scientific, value) }
        return string(abs(value) >= 1 || value == 0 ? measureLargePlain : measureSmallPlain, value)
    }

    static func money(_ value: Double) -> String { string(currency, clean(value)) }
    static func plainMoney(_ value: Double) -> String { string(currencyPlain, clean(value)) }
}
