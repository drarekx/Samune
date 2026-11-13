import Foundation

/// Daily reference rates of the European Central Bank, cached in `rates.json`.
/// Never blocks: callers get what is in memory and a fetch starts in the background when needed.
@MainActor
final class ExchangeRates {
    static let shared = ExchangeRates()

    /// Units of each currency per euro, EUR included. Nil until loaded or fetched.
    private(set) var rates: [String: Double]?
    /// Day the ECB published the rates.
    private(set) var date: Date?

    private struct Stored: Codable {
        var date: Date
        var fetched: Date
        var rates: [String: Double]
    }

    private static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    private static let maxAge: TimeInterval = 12 * 3600
    private static let retryDelay: TimeInterval = 60

    private let file = AppPaths.support.appendingPathComponent("rates.json")
    private var fetched: Date?
    private var loading = false
    private var fetching = false
    private var lastAttempt: Date?
    /// A query wanted rates that were not there: search again once they arrive.
    private var waiting = false

    private init() {}

    /// Reads the cache from disk off the main thread. Called when the provider is created.
    func load() {
        guard rates == nil, !loading else { return }
        loading = true
        let file = file
        Task {
            let stored = await Task.detached(priority: .utility) { () -> Stored? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(Stored.self, from: data)
            }.value
            loading = false
            if let stored, rates == nil {
                rates = stored.rates
                date = stored.date
                fetched = stored.fetched
                refreshSearchIfWaiting()
            }
        }
    }

    /// Converts with the rates in memory. Starts a fetch if they are missing or old.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        fetchIfNeeded()
        guard let rates else {
            waiting = true
            return nil
        }
        guard let fromRate = rates[from], let toRate = rates[to], fromRate > 0 else { return nil }
        return amount / fromRate * toRate
    }

    private func fetchIfNeeded() {
        if let fetched, Date().timeIntervalSince(fetched) < Self.maxAge { return }
        if loading || fetching { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.retryDelay { return }
        guard let url = Self.source else { return }
        fetching = true
        lastAttempt = Date()
        let file = file
        Task {
            let stored = await Task.detached(priority: .utility) { () -> Stored? in
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.httpMethod = "GET"
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let parsed = ECBParser.parse(data) else { return nil }
                let stored = Stored(date: parsed.date, fetched: Date(), rates: parsed.rates)
                if let encoded = try? JSONEncoder().encode(stored) { try? encoded.write(to: file, options: .atomic) }
                return stored
            }.value
            fetching = false
            guard let stored else { return }
            rates = stored.rates
            date = stored.date
            fetched = stored.fetched
            refreshSearchIfWaiting()
        }
    }

    private func refreshSearchIfWaiting() {
        guard waiting else { return }
        waiting = false
        SearchEngine.shared.refresh()
    }
}

/// Reads `<Cube time="2026-11-12">` and `<Cube currency="USD" rate="1.0812"/>` from the ECB file.
private final class ECBParser: NSObject, XMLParserDelegate {
    private var rates: [String: Double] = ["EUR": 1]
    private var date: Date?

    static func parse(_ data: Data) -> (date: Date, rates: [String: Double])? {
        let delegate = ECBParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let date = delegate.date, delegate.rates.count > 1 else { return nil }
        return (date, delegate.rates)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard elementName == "Cube" else { return }
        if let time = attributes["time"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: time)
        }
        if let currency = attributes["currency"], let text = attributes["rate"], let rate = Double(text), rate > 0 {
            rates[currency.uppercased()] = rate
        }
    }
}
