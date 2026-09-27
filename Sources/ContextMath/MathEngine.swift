import ContextDomain
import Foundation

/// Inline math for `math` notes: arithmetic with variables, one result per line.
/// Supports + - * / % ^, parentheses, unary minus, `name = expr` assignment,
/// and simple unit conversions (`10 km in mi`, `5 kg in lb`).
public struct MathEngine: Sendable {
    public init() {}

    public struct LineResult: Equatable, Sendable {
        public var value: Double
        public var display: String
    }

    /// Evaluates each line in order, threading variables forward.
    public func evaluate(note text: String) -> [LineResult?] {
        var variables: [String: Double] = [:]
        return text.components(separatedBy: .newlines).map { line in
            evaluateLine(line, variables: &variables)
        }
    }

    private func evaluateLine(_ line: String, variables: inout [String: Double]) -> LineResult? {
        var work = line.trimmingCharacters(in: .whitespaces)
        if work.isEmpty || work.hasPrefix("//") { return nil }
        // Strip descriptive text around `=` assignments is handled by the parser:
        // find a `name = expr` shape first.
        if let assign = parseAssignment(work, variables: variables) {
            variables[assign.name] = assign.value
            return LineResult(value: assign.value, display: format(assign.value))
        }
        // Unit conversion: "<expr> in <unit>".
        if let conv = parseConversion(work, variables: variables) {
            return LineResult(value: conv, display: format(conv))
        }
        // Otherwise evaluate trailing expression: take the longest evaluable
        // suffix so "oats 2 + 2" still yields 4. Bare names count as
        // expressions when they resolve to a variable.
        let tokens = work.split(separator: " ")
        for start in tokens.indices {
            let candidate = tokens[start...].joined(separator: " ")
            if let value = try? parseExpression(candidate, variables: variables),
               candidate.rangeOfCharacter(from: .decimalDigits) != nil || variables[candidate] != nil
            {
                return LineResult(value: value, display: format(value))
            }
        }
        // Final fallback: the whole line is a single variable name.
        if let value = variables[work] {
            return LineResult(value: value, display: format(value))
        }
        return nil
    }

    private func parseAssignment(_ line: String, variables: [String: Double]) -> (name: String, value: Double)? {
        guard let eq = line.firstIndex(of: "="), !line.contains("==") else { return nil }
        let name = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
        let expr = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard let value = try? parseExpression(String(expr), variables: variables) else { return nil }
        return (name, value)
    }

    private func parseConversion(_ line: String, variables: [String: Double]) -> Double? {
        guard let range = line.range(of: #"\bin\b"#, options: .regularExpression) else { return nil }
        let lhs = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let rhs = line[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
        // lhs is "<number expr> <from-unit>"
        guard let split = lhs.lastIndex(where: { $0.isWhitespace }) else { return nil }
        let expr = lhs[lhs.startIndex..<split].trimmingCharacters(in: .whitespaces)
        let from = lhs[lhs.index(after: split)...].trimmingCharacters(in: .whitespaces).lowercased()
        guard let amount = try? parseExpression(String(expr), variables: variables) else { return nil }
        return UnitConvert.convert(amount: amount, from: from, to: rhs)
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
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int(value))
        }
        // Trim trailing zeros to 6 significant decimals.
        return String(format: "%.6f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    /// Totals every number in the note (sum) or averages them (avg).
    public func aggregate(_ text: String, mode: AggregateMode) -> Double? {
        let pattern = #"-?\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let numbers = matches.compactMap { m -> Double? in
            guard let r = Range(m.range, in: text) else { return nil }
            // Skip numbers on `//` comment lines.
            let lineStart = text[..<r.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            if text[lineStart...].hasPrefix("//") { return nil }
            return Double(text[r])
        }
        guard !numbers.isEmpty else { return nil }
        switch mode {
        case .sum: return numbers.reduce(0, +)
        case .avg: return numbers.reduce(0, +) / Double(numbers.count)
        }
    }

    public enum AggregateMode { case sum, avg }
    enum MathError: Error { case syntax }
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
                value /= rhs
            } else if consume("%") { value = value.truncatingRemainder(dividingBy: try parsePower()) }
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
