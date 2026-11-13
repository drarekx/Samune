import Foundation

/// Reads numbers typed with either decimal separator ("1.234,5", "1,234.5", "3,5", ".5").
enum NumberReader {
    /// Reads the number that starts at `index`. Nil when there is none, or when it is incomplete ("5," or "1,2,3").
    static func read(_ chars: [Character], from index: Int) -> (value: Double, end: Int)? {
        var end = index
        while end < chars.count, chars[end].isASCII, chars[end].isNumber || chars[end] == "." || chars[end] == "," {
            end += 1
        }
        guard end > index, let value = interpret(String(chars[index..<end])) else { return nil }
        return (value, end)
    }

    /// "1.234,5" → 1234.5. Decides which separator is the decimal one from the text itself and,
    /// when it is ambiguous ("1.234"), from the grouping separator of the user's locale.
    static func interpret(_ text: String) -> Double? {
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count
        guard let last = text.last, last.isNumber else { return nil }
        if dots == 0 && commas == 0 { return Double(text) }

        if dots > 0 && commas > 0 {
            // The separator that comes last is the decimal one, and it appears once.
            guard let lastSeparator = text.last(where: { $0 == "." || $0 == "," }) else { return nil }
            let grouping: Character = lastSeparator == "." ? "," : "."
            guard (lastSeparator == "." ? dots : commas) == 1 else { return nil }
            let parts = text.split(separator: lastSeparator, omittingEmptySubsequences: false)
            guard parts.count == 2, validGroups(String(parts[0]), grouping) else { return nil }
            return Double(parts[0].replacingOccurrences(of: String(grouping), with: "") + "." + parts[1])
        }

        let separator: Character = dots > 0 ? "." : ","
        let count = max(dots, commas)
        if count > 1 {
            // "1.234.567": only grouping.
            guard validGroups(text, separator) else { return nil }
            return Double(text.replacingOccurrences(of: String(separator), with: ""))
        }
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let localGrouping = Locale.autoupdatingCurrent.groupingSeparator ?? ","
        if parts[1].count == 3, (1...3).contains(parts[0].count), String(separator) == localGrouping {
            return Double(parts[0] + parts[1])
        }
        return Double((parts[0].isEmpty ? "0" : parts[0]) + "." + parts[1])
    }

    /// "1.234.567" groups: 1–3 digits first, then exactly 3.
    private static func validGroups(_ text: String, _ separator: Character) -> Bool {
        let groups = text.split(separator: separator, omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) || groups.count == 1 else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }
}

/// Tokenizer and recursive descent parser for the calculator. Never raises: bad input gives nil.
struct MathExpression {
    enum Token: Equatable {
        case number(Double)
        case op(Character)          // + - * / ^
        case open, close, percent
        case word(String)           // functions, constants, "de" / "of"
    }

    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "sin": sin, "cos": cos, "tan": tan,
        "log": log10, "ln": log, "abs": abs, "round": { $0.rounded() },
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
    ]
    static let constants: [String: Double] = ["pi": .pi, "e": M_E]
    /// "15% de 200", "15% of 200", "15% del total".
    static let ofWords: Set<String> = ["de", "of", "del"]

    let tokens: [Token]
    let value: Double

    /// Nil unless `text` is a complete expression with at least one operation ("42" or "pi" alone give nil).
    init?(_ text: String) {
        // "2 + 2 =" is still a calculation.
        var text = Substring(text)
        while let last = text.last, last == "=" || last.isWhitespace { text = text.dropLast() }
        guard let tokens = Self.tokenize(String(text)), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        guard let result = parser.parse(), parser.hasOperation, result.isFinite else { return nil }
        self.tokens = tokens
        self.value = result
    }

    // MARK: Tokenizer

    static func tokenize(_ text: String) -> [Token]? {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isASCII && c.isNumber || (c == "." || c == ",") && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber {
                guard let (value, end) = NumberReader.read(chars, from: i) else { return nil }
                tokens.append(.number(value))
                i = end
                continue
            }
            switch c {
            case "+": tokens.append(.op("+"))
            case "-", "−", "–": tokens.append(.op("-"))
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" { tokens.append(.op("^")); i += 1 } else { tokens.append(.op("*")) }
            case "×", "·", "∙": tokens.append(.op("*"))
            case "/", "÷", ":": tokens.append(.op("/"))
            case "^": tokens.append(.op("^"))
            case "(", "[": tokens.append(.open)
            case ")", "]": tokens.append(.close)
            case "%": tokens.append(.percent)
            case "√": tokens.append(.word("sqrt"))
            case "π": tokens.append(.word("pi"))
            default:
                guard c.isLetter else { return nil }
                var end = i
                while end < chars.count, chars[end].isLetter { end += 1 }
                let word = String(chars[i..<end]).lowercased()
                if word == "x", let previous = tokens.last, Self.endsOperand(previous), Self.startsOperand(chars, end) {
                    tokens.append(.op("*"))
                } else {
                    tokens.append(.word(word))
                }
                i = end
                continue
            }
            i += 1
        }
        return tokens
    }

    private static func endsOperand(_ token: Token) -> Bool {
        switch token {
        case .number, .close, .percent: return true
        default: return false
        }
    }

    private static func startsOperand(_ chars: [Character], _ from: Int) -> Bool {
        var i = from
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count else { return false }
        return chars[i].isNumber || "(.,-−".contains(chars[i])
    }

    // MARK: Parser

    /// A value and whether it was written as a percentage (stored already divided by 100).
    private struct Value {
        var number: Double
        var isPercent = false
    }

    private struct Fail: Error {}

    private struct Parser {
        let tokens: [Token]
        var position = 0
        /// Set by binary operators, functions and "x% of y": a lone number is not a calculation.
        var hasOperation = false

        init(tokens: [Token]) { self.tokens = tokens }

        mutating func parse() -> Double? {
            guard let value = try? expression(), position == tokens.count else { return nil }
            return value.number
        }

        private var current: Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func expression() throws -> Value {
            var left = try term()
            while case .op(let op)? = current, op == "+" || op == "-" {
                position += 1
                let right = try term()
                hasOperation = true
                let sign: Double = op == "+" ? 1 : -1
                // "200 + 15%" adds 15% of 200.
                left = Value(number: right.isPercent ? left.number * (1 + sign * right.number)
                                                     : left.number + sign * right.number)
            }
            return left
        }

        private mutating func term() throws -> Value {
            var left = try unary()
            while true {
                if case .op(let op)? = current, op == "*" || op == "/" {
                    position += 1
                    let right = try unary()
                    hasOperation = true
                    if op == "/" {
                        guard right.number != 0 else { throw Fail() }
                        left = Value(number: left.number / right.number)
                    } else {
                        left = Value(number: left.number * right.number)
                    }
                } else if startsImplicitProduct {
                    // "2(3+4)", "2pi", "3 sqrt 4".
                    let right = try unary()
                    hasOperation = true
                    left = Value(number: left.number * right.number)
                } else {
                    return left
                }
            }
        }

        private var startsImplicitProduct: Bool {
            switch current {
            case .open?: return true
            case .word(let word)?: return MathExpression.functions[word] != nil || MathExpression.constants[word] != nil
            default: return false
            }
        }

        private mutating func unary() throws -> Value {
            if case .op(let op)? = current, op == "-" || op == "+" {
                position += 1
                var value = try unary()
                if op == "-" { value.number = -value.number }
                return value
            }
            return try power()
        }

        private mutating func power() throws -> Value {
            let base = try postfix()
            guard case .op("^")? = current else { return base }
            position += 1
            let exponent = try unary()  // right associative: 2^3^2 = 2^9
            hasOperation = true
            return Value(number: pow(base.number, exponent.number))
        }

        private mutating func postfix() throws -> Value {
            var value = try primary()
            guard current == .percent else { return value }
            position += 1
            value = Value(number: value.number / 100, isPercent: true)
            if case .word(let word)? = current, MathExpression.ofWords.contains(word) {
                position += 1
                let whole = try unary()
                hasOperation = true
                value = Value(number: value.number * whole.number)
            }
            return value
        }

        private mutating func primary() throws -> Value {
            guard let token = current else { throw Fail() }
            position += 1
            switch token {
            case .number(let number):
                return Value(number: number)
            case .open:
                let inner = try expression()
                guard current == .close else { throw Fail() }
                position += 1
                return Value(number: inner.number)
            case .word(let word):
                if let constant = MathExpression.constants[word] { return Value(number: constant) }
                guard let function = MathExpression.functions[word] else { throw Fail() }
                let argument = try unary()
                hasOperation = true
                return Value(number: function(argument.number))
            default:
                throw Fail()
            }
        }
    }

    // MARK: Normalised text

    /// "23*4" → "23 × 4", with numbers in the user's format.
    func normalized(format: (Double) -> String) -> String {
        var pieces: [String] = []
        var previous: Token?
        for (index, token) in tokens.enumerated() {
            var piece: String
            switch token {
            case .number(let number): piece = format(number)
            case .op(let op):
                let isUnary: Bool
                switch previous {
                case nil, .op?, .open?: isUnary = true
                case .word(let word)?: isUnary = !(MathExpression.constants[word] != nil)
                default: isUnary = false
                }
                let symbol: String = ["+": "+", "-": "−", "*": "×", "/": "÷", "^": "^"][op] ?? String(op)
                piece = isUnary || op == "^" ? symbol : " \(symbol) "
            case .open: piece = "("
            case .close: piece = ")"
            case .percent: piece = "%"
            case .word(let word):
                piece = word == "pi" ? "π" : word
                if MathExpression.ofWords.contains(word) { piece = " \(word) " }
                // "abs −3", but "abs(−3)".
                if MathExpression.functions[word] != nil, index + 1 < tokens.count, tokens[index + 1] != .open {
                    piece += " "
                }
            }
            if let last = pieces.last?.last, let first = piece.first,
               (last.isLetter || last.isNumber) && (first.isLetter || first.isNumber) {
                piece = " " + piece
            }
            pieces.append(piece)
            previous = token
        }
        return pieces.joined()
    }
}
