import Foundation

/// A unit the calculator understands, with the symbol shown in results.
struct UnitDefinition {
    enum Category { case length, mass, temperature, volume, area, speed, duration, data }

    let symbol: String
    let unit: Dimension
    let category: Category
}

/// Unit names and symbols in Spanish, English and Catalan, singular and plural.
enum UnitCatalog {
    /// Looks up "km", "Kilómetros", "°F", "km/h", "fl oz"…
    static func lookup(_ text: String) -> UnitDefinition? {
        let key = normalize(text)
        guard !key.isEmpty else { return nil }
        if let found = table[key] { return found }
        // Plurals not listed: "kilometros" → "kilometro", "mpbs" stays unknown.
        if key.hasSuffix("es"), let found = table[String(key.dropLast(2))] { return found }
        if key.hasSuffix("s"), let found = table[String(key.dropLast())] { return found }
        return nil
    }

    /// Lowercase, without accents, "º" as "°", "²"/"³" as digits, single spaces.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    private static let year = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_536_000))

    private static let table: [String: UnitDefinition] = {
        var table: [String: UnitDefinition] = [:]
        func add(_ symbol: String, _ unit: Dimension, _ category: UnitDefinition.Category, _ names: [String]) {
            let definition = UnitDefinition(symbol: symbol, unit: unit, category: category)
            for name in names + [symbol] { table[normalize(name)] = definition }
        }

        add("m", UnitLength.meters, .length, ["metro", "metros", "meter", "meters", "metre", "metres"])
        add("km", UnitLength.kilometers, .length, ["kilometro", "kilometer", "kilometers", "kilometre", "kilometres",
                                                   "quilometre", "quilometres", "kms"])
        add("cm", UnitLength.centimeters, .length, ["centimetro", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("mm", UnitLength.millimeters, .length, ["milimetro", "millimeter", "millimeters", "millimetre",
                                                    "millimetres", "mil·limetre", "mil·limetres"])
        add("mi", UnitLength.miles, .length, ["milla", "millas", "mile", "miles", "milles"])
        add("ft", UnitLength.feet, .length, ["pie", "pies", "foot", "feet", "peu", "peus", "'"])
        add("in", UnitLength.inches, .length, ["pulgada", "pulgadas", "inch", "inches", "polzada", "polzades", "\""])
        add("yd", UnitLength.yards, .length, ["yarda", "yardas", "yard", "yards", "iarda", "iardes"])
        add("nmi", UnitLength.nauticalMiles, .length, ["milla nautica", "millas nauticas", "nautical mile",
                                                       "nautical miles", "milla nautica", "milles nautiques"])

        add("kg", UnitMass.kilograms, .mass, ["kilo", "kilos", "kilogramo", "kilogram", "kilograms", "quilo",
                                              "quilos", "quilogram", "quilograms", "kgs"])
        add("g", UnitMass.grams, .mass, ["gramo", "gramos", "gram", "grams", "gr", "gramme", "grammes"])
        add("mg", UnitMass.milligrams, .mass, ["miligramo", "milligram", "milligrams", "mil·ligram", "mil·ligrams"])
        add("lb", UnitMass.pounds, .mass, ["lbs", "libra", "libras", "pound", "pounds", "lliura", "lliures"])
        add("oz", UnitMass.ounces, .mass, ["onza", "onzas", "ounce", "ounces", "unca", "unces"])
        add("t", UnitMass.metricTons, .mass, ["tonelada", "toneladas", "tonne", "tonnes", "ton", "tons", "tona", "tones"])
        add("st", UnitMass.stones, .mass, ["stone", "stones"])

        add("°C", UnitTemperature.celsius, .temperature, ["c", "celsius", "centigrado", "centigrados",
                                                            "grados celsius", "graus celsius", "centigrade"])
        add("°F", UnitTemperature.fahrenheit, .temperature, ["f", "fahrenheit", "grados fahrenheit", "graus fahrenheit"])
        add("K", UnitTemperature.kelvin, .temperature, ["kelvin", "kelvins"])

        add("l", UnitVolume.liters, .volume, ["litro", "litros", "liter", "liters", "litre", "litres", "lt"])
        add("ml", UnitVolume.milliliters, .volume, ["mililitro", "milliliter", "milliliters", "millilitre",
                                                    "millilitres", "mil·lilitre", "mil·lilitres"])
        add("cl", UnitVolume.centiliters, .volume, ["centilitro", "centiliter", "centilitre"])
        add("dl", UnitVolume.deciliters, .volume, ["decilitro", "deciliter", "decilitre"])
        add("m³", UnitVolume.cubicMeters, .volume, ["m3", "metro cubico", "metros cubicos", "cubic meter",
                                                     "cubic meters", "metre cubic", "metres cubics"])
        add("gal", UnitVolume.gallons, .volume, ["galon", "galones", "gallon", "gallons", "galo", "galons"])
        add("qt", UnitVolume.quarts, .volume, ["quart", "quarts"])
        add("pt", UnitVolume.pints, .volume, ["pinta", "pintas", "pint", "pints", "pintes"])
        add("cup", UnitVolume.cups, .volume, ["cups", "taza", "tazas", "tassa", "tasses"])
        add("fl oz", UnitVolume.fluidOunces, .volume, ["floz", "fluid ounce", "fluid ounces", "onza liquida", "onzas liquidas"])
        add("tbsp", UnitVolume.tablespoons, .volume, ["tablespoon", "tablespoons", "cucharada", "cucharadas",
                                                      "cullerada", "cullerades"])
        add("tsp", UnitVolume.teaspoons, .volume, ["teaspoon", "teaspoons", "cucharadita", "cucharaditas",
                                                   "culleradeta", "culleradetes"])

        add("m²", UnitArea.squareMeters, .area, ["m2", "metro cuadrado", "metros cuadrados", "square meter",
                                                  "square meters", "sq m", "metre quadrat", "metres quadrats"])
        add("km²", UnitArea.squareKilometers, .area, ["km2", "kilometro cuadrado", "kilometros cuadrados",
                                                       "square kilometer", "square kilometers", "sq km"])
        add("cm²", UnitArea.squareCentimeters, .area, ["cm2", "sq cm"])
        add("ha", UnitArea.hectares, .area, ["hectarea", "hectareas", "hectare", "hectares", "hectarees"])
        add("ac", UnitArea.acres, .area, ["acre", "acres", "acres"])
        add("ft²", UnitArea.squareFeet, .area, ["ft2", "sq ft", "sqft", "square foot", "square feet", "pie cuadrado",
                                                 "pies cuadrados"])
        add("in²", UnitArea.squareInches, .area, ["in2", "sq in", "square inch", "square inches"])
        add("mi²", UnitArea.squareMiles, .area, ["mi2", "sq mi", "square mile", "square miles"])
        add("yd²", UnitArea.squareYards, .area, ["yd2", "sq yd", "square yard", "square yards"])

        add("km/h", UnitSpeed.kilometersPerHour, .speed, ["kmh", "kph", "km / h", "kilometros por hora",
                                                           "kilometers per hour", "quilometres per hora"])
        add("mph", UnitSpeed.milesPerHour, .speed, ["mi/h", "miles per hour", "millas por hora"])
        add("m/s", UnitSpeed.metersPerSecond, .speed, ["mps", "metros por segundo", "meters per second"])
        add("kn", UnitSpeed.knots, .speed, ["kt", "knot", "knots", "nudo", "nudos", "nus", "nusos"])

        add("ms", UnitDuration.milliseconds, .duration, ["milisegundo", "millisecond", "milliseconds", "mil·lisegon",
                                                         "mil·lisegons"])
        add("s", UnitDuration.seconds, .duration, ["sec", "secs", "seg", "segs", "segundo", "segundos", "second",
                                                   "seconds", "segon", "segons"])
        add("min", UnitDuration.minutes, .duration, ["mins", "minuto", "minutos", "minute", "minutes", "minut", "minuts"])
        add("h", UnitDuration.hours, .duration, ["hr", "hrs", "hora", "horas", "hour", "hours", "hores"])
        add("d", day, .duration, ["dia", "dias", "day", "days", "dies"])
        add("wk", week, .duration, ["semana", "semanas", "week", "weeks", "setmana", "setmanes"])
        add("yr", year, .duration, ["año", "años", "ano", "anos", "year", "years", "any", "anys"])

        add("B", UnitInformationStorage.bytes, .data, ["b", "byte", "bytes", "octeto", "octetos"])
        add("bit", UnitInformationStorage.bits, .data, ["bits"])
        add("KB", UnitInformationStorage.kilobytes, .data, ["kb", "kilobyte", "kilobytes", "kbyte"])
        add("MB", UnitInformationStorage.megabytes, .data, ["mb", "megabyte", "megabytes", "mega", "megas"])
        add("GB", UnitInformationStorage.gigabytes, .data, ["gb", "gigabyte", "gigabytes", "giga", "gigas"])
        add("TB", UnitInformationStorage.terabytes, .data, ["tb", "terabyte", "terabytes", "tera", "teras"])
        add("KiB", UnitInformationStorage.kibibytes, .data, ["kib", "kibibyte", "kibibytes"])
        add("MiB", UnitInformationStorage.mebibytes, .data, ["mib", "mebibyte", "mebibytes"])
        add("GiB", UnitInformationStorage.gibibytes, .data, ["gib", "gibibyte", "gibibytes"])
        add("TiB", UnitInformationStorage.tebibytes, .data, ["tib", "tebibyte", "tebibytes"])
        add("kbit", UnitInformationStorage.kilobits, .data, ["kbits", "kilobit", "kilobits"])
        add("Mbit", UnitInformationStorage.megabits, .data, ["mbits", "megabit", "megabits"])
        add("Gbit", UnitInformationStorage.gigabits, .data, ["gbits", "gigabit", "gigabits"])
        return table
    }()
}

/// Currencies published by the European Central Bank, by code, symbol and name.
enum CurrencyCatalog {
    static let codes: Set<String> = [
        "EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK", "NOK",
        "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NZD", "PHP",
        "SGD", "THB", "ZAR",
    ]

    private static let names: [String: String] = [
        "€": "EUR", "euro": "EUR", "euros": "EUR",
        "$": "USD", "us$": "USD", "dolar": "USD", "dolares": "USD", "dollar": "USD", "dollars": "USD",
        "dolars": "USD",
        "£": "GBP", "esterlina": "GBP", "esterlinas": "GBP", "sterling": "GBP", "lliura esterlina": "GBP",
        "lliures esterlines": "GBP", "libra esterlina": "GBP", "libras esterlinas": "GBP",
        "¥": "JPY", "yen": "JPY", "yenes": "JPY", "yens": "JPY", "ien": "JPY", "iens": "JPY",
        "yuan": "CNY", "yuanes": "CNY", "yuans": "CNY", "iuan": "CNY",
        "franco suizo": "CHF", "francos suizos": "CHF", "swiss franc": "CHF", "swiss francs": "CHF",
        "franc suis": "CHF", "francs suissos": "CHF",
        "rupia": "INR", "rupias": "INR", "rupee": "INR", "rupees": "INR", "rupies": "INR",
        "real": "BRL", "reales": "BRL", "reais": "BRL", "reals": "BRL",
        "₹": "INR", "₩": "KRW", "₺": "TRY", "₪": "ILS", "c$": "CAD", "a$": "AUD", "r$": "BRL",
    ]

    /// Symbols that may go before the amount ("$50", "€ 20").
    static let prefixSymbols: Set<Character> = ["$", "€", "£", "¥", "₹", "₩", "₺", "₪"]

    static func lookup(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 3, codes.contains(trimmed.uppercased()) { return trimmed.uppercased() }
        return names[UnitCatalog.normalize(trimmed)]
    }
}

/// "10 km a mi", "120 eur en usd", "100 gbp".
enum Conversion {
    case units(amount: Double, from: UnitDefinition, to: UnitDefinition)
    /// `to` is nil for a bare amount ("100 gbp"): the user's own currency.
    case currency(amount: Double, from: String, to: String?)

    /// Words between the amount and the target unit. "in" also names inches: it is only taken as a
    /// connector when what follows is a unit too.
    private static let connectors: Set<String> = ["a", "en", "to", "in", "into", "as", "=", "->", "→", "=>"]

    static func parse(_ text: String) -> Conversion? {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 1 else { return nil }
        for index in words.indices.reversed() where connectors.contains(words[index]) && index > 0 {
            let target = words[(index + 1)...].joined(separator: " ")
            guard !target.isEmpty, let (amount, source) = amount(words[..<index].joined(separator: " ")) else { continue }
            if let from = UnitCatalog.lookup(source), let to = UnitCatalog.lookup(target), from.category == to.category {
                return .units(amount: amount, from: from, to: to)
            }
            if let from = CurrencyCatalog.lookup(source), let to = CurrencyCatalog.lookup(target) {
                return .currency(amount: amount, from: from, to: to)
            }
        }
        if let (amount, source) = amount(words.joined(separator: " ")), let from = CurrencyCatalog.lookup(source) {
            return .currency(amount: amount, from: from, to: nil)
        }
        return nil
    }

    /// "10 km" → (10, "km"); "-40°f" → (-40, "°f"); "$50" → (50, "$").
    private static func amount(_ text: String) -> (Double, String)? {
        var chars = Array(text)
        var prefix = ""
        if let first = chars.first, CurrencyCatalog.prefixSymbols.contains(first) {
            prefix = String(first)
            chars.removeFirst()
            while chars.first?.isWhitespace == true { chars.removeFirst() }
        }
        var sign = 1.0
        if let first = chars.first, first == "-" || first == "−" {
            sign = -1
            chars.removeFirst()
        }
        guard let (value, end) = NumberReader.read(chars, from: 0) else { return nil }
        let rest = String(chars[end...]).trimmingCharacters(in: .whitespaces)
        if !prefix.isEmpty { return rest.isEmpty ? (sign * value, prefix) : nil }
        return rest.isEmpty ? nil : (sign * value, rest)
    }
}
