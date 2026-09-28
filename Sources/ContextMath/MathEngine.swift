import ContextDomain
import Foundation

/// Inline math for `math` notes: arithmetic with variables, one result per line.
/// Supports + - * / % ^, parentheses, unary minus, `name = expr` assignment,
/// unit conversions (`10 km in mi`, `5 kg in lb`), and currency/crypto
/// conversions (`42 USD in EUR`, `0.5 BTC in USD`) via an injected rate table.
public struct MathEngine: Sendable {
    private let rates: CurrencyRates.Snapshot?

    public init(rates: CurrencyRates.Snapshot? = nil) {
        self.rates = rates
    }

    public struct LineResult: Equatable, Sendable {
        public var value: Double
        public var display: String

        public init(value: Double, display: String) {
            self.value = value
            self.display = display
        }
    }

    /// Per-line outcome: blank prose, a computed value, or a recoverable
    /// error with a short gutter message. One bad line never blanks others.
    public enum LineOutcome: Equatable, Sendable {
        case blank
        case value(LineResult)
        case error(LineError)
    }

    public enum LineError: Equatable, Sendable {
        case syntax
        case divideByZero
        case unknownUnit(String)
        case unknownCurrency(String)
        case noRates
        case unknownVariable(String)

        /// Short gutter text, never a number that could read as a result.
        public var message: String {
            switch self {
            case .syntax: return "syntax?"
            case .divideByZero: return "÷ by 0"
            case .unknownUnit(let u): return "unknown unit \(u)"
            case .unknownCurrency(let c): return "unknown \(c)"
            case .noRates: return "no rates — offline?"
            case .unknownVariable(let n): return "unknown \(n)"
            }
        }
    }

    /// Evaluates each line in order, threading variables forward.
    public func evaluate(note text: String) -> [LineResult?] {
        evaluateLines(note: text).map {
            if case .value(let r) = $0 { return r }
            return nil
        }
    }

    /// Evaluates each line with per-line error classification.
    public func evaluateLines(note text: String) -> [LineOutcome] {
        var variables: [String: Double] = [:]
        return text.components(separatedBy: .newlines).map { line in
            evaluateOutcome(line, variables: &variables)
        }
    }

    private func evaluateOutcome(_ line: String, variables: inout [String: Double]) -> LineOutcome {
        let work = line.trimmingCharacters(in: .whitespaces)
        if work.isEmpty || work.hasPrefix("//") { return .blank }
        if let assign = parseAssignment(work, variables: variables) {
            variables[assign.name] = assign.value
            return .value(LineResult(value: assign.value, display: format(assign.value)))
        }
        if let bad = parseAssignmentError(work, variables: variables) { return .error(bad) }
        if isConversionLine(work) {
            return parseConversionOutcome(work, variables: &variables)
        }
        // Longest evaluable suffix so "oats 2 + 2" still yields 4.
        // A divide-by-zero on the whole line is never rescued by a suffix.
        let tokens = work.split(separator: " ")
        if !tokens.isEmpty {
            do {
                _ = try parseExpression(work, variables: variables)
            } catch let e as MathError {
                if e == .divideByZero { return .error(.divideByZero) }
            } catch {}
        }
        var sawDivideByZero = false
        for start in tokens.indices {
            let candidate = tokens[start...].joined(separator: " ")
            do {
                let value = try parseExpression(candidate, variables: variables)
                if candidate.rangeOfCharacter(from: .decimalDigits) != nil || variables[candidate] != nil {
                    return .value(LineResult(value: value, display: format(value)))
                }
            } catch let e as MathError {
                if e == .divideByZero { sawDivideByZero = true }
            } catch {}
        }
        if let value = variables[work] {
            return .value(LineResult(value: value, display: format(value)))
        }
        // Looks like math but nothing evaluated: classify, else blank prose.
        // A lone undefined name is a bad reactive ref, not prose.
        if isBareName(work) { return .error(.unknownVariable(work)) }
        if looksLikeMath(work) {
            if sawDivideByZero { return .error(.divideByZero) }
            return .error(.syntax)
        }
        return .blank
    }

    private func parseAssignmentError(_ line: String, variables: [String: Double]) -> LineError? {
        guard let eq = line.firstIndex(of: "="), !line.contains("==") else { return nil }
        let name = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
        let expr = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if expr.isEmpty { return .syntax }
        do {
            _ = try parseExpression(String(expr), variables: variables)
            return nil
        } catch let e as MathError {
            return e == .divideByZero ? .divideByZero : .syntax
        } catch {
            return .syntax
        }
    }

    /// A line with digits, operators, or conversion words is a math attempt;
    /// plain prose stays blank.
    private func looksLikeMath(_ line: String) -> Bool {
        if line.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if line.contains("=") && !line.contains("==") { return true }
        let ops: Set<Character> = ["+", "-", "*", "/", "%", "^", "(", ")"]
        if line.contains(where: { ops.contains($0) }) { return true }
        let lower = " " + line.lowercased() + " "
        return lower.contains(" in ") || lower.contains(" to ")
    }

    private func isBareName(_ line: String) -> Bool {
        line.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    private func parseAssignment(_ line: String, variables: [String: Double]) -> (name: String, value: Double)? {
        guard let eq = line.firstIndex(of: "="), !line.contains("==") else { return nil }
        let name = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
        let expr = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard let value = try? parseExpression(String(expr), variables: variables),
              value.isFinite else { return nil }
        return (name, value)
    }

    /// A line shaped like "<expr> in|to <word>" is a conversion attempt.
    /// Returns nil result (not a variable fallback) when units are unknown.
    private func isConversionLine(_ line: String) -> Bool {
        guard line.range(of: #"\b(in|to)\b"#, options: .regularExpression) != nil else { return false }
        // Must have at least "<something> <word>" shape before the keyword.
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.count >= 3
    }

    private func parseConversionOutcome(_ line: String, variables: inout [String: Double]) -> LineOutcome {
        guard let range = line.range(of: #"\b(in|to)\b"#, options: .regularExpression) else { return .error(.syntax) }
        let lhs = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let rhs = line[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
        guard let split = lhs.lastIndex(where: { $0.isWhitespace }) else { return .error(.syntax) }
        let expr = lhs[lhs.startIndex..<split].trimmingCharacters(in: .whitespaces)
        let from = lhs[lhs.index(after: split)...].trimmingCharacters(in: .whitespaces).lowercased()
        let amount: Double
        do {
            guard let value = try? parseExpression(String(expr), variables: variables) else {
                if isBareName(String(expr)) { return .error(.unknownVariable(String(expr))) }
                return .error(.syntax)
            }
            amount = value
        }
        if let physical = UnitConvert.convert(amount: amount, from: from, to: rhs) {
            return .value(LineResult(value: physical, display: format(physical)))
        }
        if CurrencyRates.isCurrency(from) || CurrencyRates.isCurrency(rhs) {
            guard CurrencyRates.isCurrency(from), CurrencyRates.isCurrency(rhs) else {
                return .error(.unknownCurrency(CurrencyRates.isCurrency(from) ? rhs : from))
            }
            guard let rates else { return .error(.noRates) }
            if let converted = CurrencyRates.convert(amount: amount, from: from, to: rhs, rates: rates) {
                return .value(LineResult(value: converted, display: format(converted)))
            }
            return .error(.unknownCurrency(from))
        }
        return .error(.unknownUnit(rhs.isEmpty ? from : rhs))
    }

    // MARK: - Expression parser (recursive descent)

    private func parseExpression(_ input: String, variables: [String: Double]) throws -> Double {
        var parser = ExprParser(text: input, variables: variables)
        let value = try parser.parseSum()
        parser.skipSpaces()
        guard parser.isAtEnd else { throw MathError.syntax }
        return value
    }

    public func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int(value))
        }
        // Trim trailing zeros to 6 significant decimals.
        return String(format: "%.6f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    /// Totals every number in the note (sum) or averages them (avg).
    /// Single source of truth with contributions(): thousands separators
    /// fold ("1,000" counts once), ISO dates are ignored, `//` comments
    /// are skipped.
    public func aggregate(_ text: String, mode: AggregateMode) -> Double? {
        let all = contributions(text: text).flatMap { $0 }
        guard !all.isEmpty else { return nil }
        switch mode {
        case .sum: return all.reduce(0, +)
        case .avg: return all.reduce(0, +) / Double(all.count)
        }
    }

    /// Per-line numbers for sum/avg notes: one entry per body line, each
    /// the numbers that line contributes (empty when the line counts for
    /// nothing). Drives both the total and the per-line gutter.
    public func contributions(text: String) -> [[Double]] {
        text.components(separatedBy: .newlines).map { lineNumbers($0) }
    }

    /// Numbers on one line after normalization. Empty for comments,
    /// dateless prose, and lines with no digits.
    public func lineNumbers(_ line: String) -> [Double] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("//") { return [] }
        var work = line
        // ISO dates never count: "2024-01-15" is a day, not 2040.
        work = work.replacingOccurrences(of: #"\d{4}-\d{1,2}-\d{1,2}"#, with: " ", options: .regularExpression)
        // Thousands separators fold: "1,000" is one thousand, not 1 and 0.
        var prev = ""
        while prev != work {
            prev = work
            work = work.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1$2", options: .regularExpression)
        }
        let pattern = #"-?\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: work, range: NSRange(work.startIndex..., in: work))
        return matches.compactMap { m -> Double? in
            guard let r = Range(m.range, in: work) else { return nil }
            return Double(work[r])
        }
    }

    public enum AggregateMode { case sum, avg }
    enum MathError: Error { case syntax, divideByZero }
}

private struct ExprParser {
    let chars: [Character]
    var index: Int = 0
    let variables: [String: Double]

    init(text: String, variables: [String: Double]) {
        self.chars = Array(text)
        self.variables = variables
    }

    var isAtEnd: Bool { index >= chars.count }

    mutating func parseSum() throws -> Double {
        var value = try parseProduct()
        while true {
            skipSpaces()
            if consume("+") { value += try parseProduct() }
            else if consume("-") { value -= try parseProduct() }
            else { return value }
        }
    }

    mutating func parseProduct() throws -> Double {
        var value = try parsePower()
        while true {
            skipSpaces()
            if consume("*") { value *= try parsePower() }
            else if consume("/") {
                let rhs = try parsePower()
                guard rhs != 0 else { throw MathEngine.MathError.divideByZero }
                value /= rhs
            } else if consume("%") {
                let rhs = try parsePower()
                guard rhs != 0 else { throw MathEngine.MathError.divideByZero }
                value = value.truncatingRemainder(dividingBy: rhs)
            }
            else { return value }
        }
    }

    mutating func parsePower() throws -> Double {
        let base = try parseUnary()
        skipSpaces()
        if consume("^") { return pow(base, try parsePower()) }
        return base
    }

    mutating func parseUnary() throws -> Double {
        skipSpaces()
        if consume("-") { return -(try parseUnary()) }
        if consume("+") { return try parseUnary() }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> Double {
        skipSpaces()
        if consume("(") {
            let value = try parseSum()
            skipSpaces()
            guard consume(")") else { throw MathEngine.MathError.syntax }
            return value
        }
        if let number = parseNumber() { return number }
        if let name = parseName() {
            if let value = variables[name] { return value }
            throw MathEngine.MathError.syntax
        }
        throw MathEngine.MathError.syntax
    }

    mutating func parseNumber() -> Double? {
        skipSpaces()
        let start = index
        while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
        guard start != index else { return nil }
        return Double(String(chars[start..<index]))
    }

    mutating func parseName() -> String? {
        skipSpaces()
        let start = index
        guard index < chars.count, chars[index].isLetter || chars[index] == "_" else { return nil }
        while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "_" { index += 1 }
        return String(chars[start..<index])
    }

    mutating func skipSpaces() {
        while index < chars.count, chars[index].isWhitespace { index += 1 }
    }

    mutating func consume(_ s: String) -> Bool {
        skipSpaces()
        guard let c = s.first, index < chars.count, chars[index] == c else { return false }
        index += 1
        return true
    }
}

/// Length / weight conversions to a base unit, then out to the target.
enum UnitConvert {
    static let lengthToMeter: [String: Double] = [
        "mm": 0.001, "cm": 0.01, "m": 1, "km": 1000,
        "in": 0.0254, "ft": 0.3048, "yd": 0.9144, "mi": 1609.344,
    ]
    static let weightToKg: [String: Double] = [
        "g": 0.001, "kg": 1, "oz": 0.0283495, "lb": 0.453592, "lbs": 0.453592,
    ]

    static func convert(amount: Double, from: String, to: String) -> Double? {
        if let f = lengthToMeter[from], let t = lengthToMeter[to] {
            return amount * f / t
        }
        if let f = weightToKg[from], let t = weightToKg[to] {
            return amount * f / t
        }
        // Temperature one-offs.
        switch (from, to) {
        case ("c", "f"): return amount * 9 / 5 + 32
        case ("f", "c"): return (amount - 32) * 5 / 9
        case ("c", "k"): return amount + 273.15
        case ("k", "c"): return amount - 273.15
        default: return nil
        }
    }
}
