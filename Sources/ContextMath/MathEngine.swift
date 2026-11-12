import ContextDomain
import Foundation

/// Inline math for `math` notes: arithmetic with variables, one result per line.
/// Supports + - * / % ^, parentheses, unary minus, reactive
/// `name = expr` assignment (see `evaluateLines` for the down-the-note
/// semantics and `ReactiveVariable` for naming rules; the RHS may also
/// be a conversion), unit conversions (`10 km in mi`, `5 kg in lb`),
/// and currency/crypto conversions (`42 USD in EUR`, `0.5 BTC in USD`)
/// via an injected rate table.
public struct MathEngine: Sendable {
    private let rates: CurrencyRates.Snapshot?

    public init(rates: CurrencyRates.Snapshot? = nil) {
        self.rates = rates
    }

    public struct LineResult: Equatable, Sendable {
        public var value: Double
        public var display: String
        /// Set when the line assigned a variable, so the gutter can show
        /// which name now holds the value instead of a bare number.
        public var assignedName: String?

        public init(value: Double, display: String, assignedName: String? = nil) {
            self.value = value
            self.display = display
            self.assignedName = assignedName
        }

        /// What the gutter shows: `price = 10` on an assignment line,
        /// the plain formatted value everywhere else.
        public var gutterDisplay: String {
            assignedName.map { "\($0) = \(display)" } ?? display
        }
    }

    /// Per-line outcome: blank prose, a computed value, or a recoverable
    /// error with a short gutter message. One bad line never blanks others.
    public enum LineOutcome: Equatable, Sendable {
        case blank
        case value(LineResult)
        case error(LineError)
    }

    public enum LineError: Equatable, Sendable, Error {
        case syntax
        case divideByZero
        case unknownUnit(String)
        case unknownCurrency(String)
        case noRates
        case unknownVariable(String)
        /// Name is assigned, but only on a line below this one.
        case forwardReference(String)
        /// Assignments that (transitively) need their own result.
        case cycle(String)
        case invalidVariableName(String)
        case reservedVariableName(String)

        /// Short gutter text, never a number that could read as a result.
        public var message: String {
            switch self {
            case .syntax: return "syntax?"
            case .divideByZero: return "÷ by 0"
            case .unknownUnit(let u): return "unknown unit \(u)"
            case .unknownCurrency(let c): return "unknown \(c)"
            case .noRates: return "no rates — offline?"
            case .unknownVariable(let n): return "unknown \(n)"
            case .forwardReference(let n): return "\(n) defined below"
            case .cycle(let n): return "cycle: \(n)"
            case .invalidVariableName(let n): return n.isEmpty ? "bad name" : "bad name \(n)"
            case .reservedVariableName(let n): return "reserved \(n)"
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
    /// Sequential semantics ("recalculates down the note"): a variable is
    /// visible only below a successful assignment; redefining it changes
    /// lines below, never lines above; a failed assignment clears the
    /// name so lines below see an error, not a stale value.
    public func evaluateLines(note text: String) -> [LineOutcome] {
        let lines = text.components(separatedBy: .newlines)
        let context = makeContext(lines: lines)
        var variables: [String: Double] = [:]
        return lines.enumerated().map { index, line in
            evaluateOutcome(line, lineIndex: index, context: context, variables: &variables)
        }
    }

    /// Note-wide facts gathered before the forward pass so a bad reference
    /// can be classified as unknown, defined-below, or part of a cycle.
    struct NoteContext {
        /// Valid assignment name per line, nil for non-assignment lines.
        var assignmentNameByLine: [Int: String]
        /// Every line index assigning each name, ascending.
        var assignmentLinesByName: [String: [Int]]
        /// Line indices whose assignment participates in a dependency cycle.
        var cyclicLines: Set<Int>

        func isAssignedLater(_ name: String, after lineIndex: Int) -> Bool {
            (assignmentLinesByName[name] ?? []).contains { $0 > lineIndex }
        }

        /// True when every assignment to `name` is part of a cycle.
        func isCyclic(_ name: String) -> Bool {
            guard let lines = assignmentLinesByName[name], !lines.isEmpty else { return false }
            return lines.allSatisfy { cyclicLines.contains($0) }
        }
    }

    /// Builds the assignment index and finds dependency cycles. Each
    /// assignment line is a node; it points at the assignment its RHS
    /// would read: the latest one above for each referenced name, or
    /// the first one at/below when none is above. Nodes in a strongly
    /// connected component of size > 1 — or with a self-edge — cycle.
    /// `x = 1` then `x = x + 1` points at the earlier node, so it is a
    /// valid increment, not a cycle.
    private func makeContext(lines: [String]) -> NoteContext {
        var nameByLine: [Int: String] = [:]
        var linesByName: [String: [Int]] = [:]
        var refsByLine: [Int: [String]] = [:]
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = Self.assignmentSplit(line),
                  ReactiveVariable.problem(with: split.name) == nil
            else { continue }
            nameByLine[index] = split.name
            linesByName[split.name, default: []].append(index)
            refsByLine[index] = Self.rhsReferences(split.rhs)
        }
        var edges: [Int: [Int]] = [:]
        for (index, refs) in refsByLine {
            var targets: [Int] = []
            for ref in refs {
                guard let candidates = linesByName[ref] else { continue }
                if let above = candidates.last(where: { $0 < index }) {
                    targets.append(above)
                } else if let atOrBelow = candidates.first(where: { $0 >= index }) {
                    targets.append(atOrBelow)
                }
            }
            edges[index] = targets
        }
        return NoteContext(
            assignmentNameByLine: nameByLine,
            assignmentLinesByName: linesByName,
            cyclicLines: Self.cyclicNodes(edges: edges)
        )
    }

    /// Names an assignment RHS reads. A conversion RHS reads only its
    /// amount expression — unit words (`km`, `in`, `mi`) are not names.
    private static func rhsReferences(_ rhs: String) -> [String] {
        if let amount = conversionAmountExpression(rhs) {
            return ReactiveVariable.references(in: amount)
        }
        return ReactiveVariable.references(in: rhs)
    }

    /// Iterative Tarjan SCC: nodes whose component loops back on itself.
    private static func cyclicNodes(edges: [Int: [Int]]) -> Set<Int> {
        var indexOf: [Int: Int] = [:]
        var lowlink: [Int: Int] = [:]
        var onStack: Set<Int> = []
        var stack: [Int] = []
        var nextIndex = 0
        var cyclic: Set<Int> = []
        for root in edges.keys.sorted() where indexOf[root] == nil {
            // Each frame: node + next edge position to visit.
            var frames: [(node: Int, edgePos: Int)] = [(root, 0)]
            indexOf[root] = nextIndex
            lowlink[root] = nextIndex
            nextIndex += 1
            stack.append(root)
            onStack.insert(root)
            while let top = frames.last {
                let node = top.node
                let targets = edges[node] ?? []
                if top.edgePos < targets.count {
                    frames[frames.count - 1].edgePos += 1
                    let target = targets[top.edgePos]
                    if indexOf[target] == nil {
                        indexOf[target] = nextIndex
                        lowlink[target] = nextIndex
                        nextIndex += 1
                        stack.append(target)
                        onStack.insert(target)
                        frames.append((target, 0))
                    } else if onStack.contains(target) {
                        lowlink[node] = min(lowlink[node]!, indexOf[target]!)
                    }
                } else {
                    frames.removeLast()
                    if let parent = frames.last?.node {
                        lowlink[parent] = min(lowlink[parent]!, lowlink[node]!)
                    }
                    if lowlink[node] == indexOf[node] {
                        var component: [Int] = []
                        while let popped = stack.popLast() {
                            onStack.remove(popped)
                            component.append(popped)
                            if popped == node { break }
                        }
                        if component.count > 1 {
                            cyclic.formUnion(component)
                        } else if let only = component.first, (edges[only] ?? []).contains(only) {
                            cyclic.insert(only)
                        }
                    }
                }
            }
        }
        return cyclic
    }

    /// Splits `name = rhs` when the line holds exactly one standalone
    /// `=` (not `==`/`<=`/`>=`/`!=`, not a chain). Name validity is the
    /// caller's check, so context building can skip bad names quietly.
    private static func assignmentSplit(_ line: String) -> (name: String, rhs: String)? {
        for op in ["==", "<=", ">=", "!="] where line.contains(op) { return nil }
        let equals = line.indices.filter { line[$0] == "=" }
        guard equals.count == 1, let eq = equals.first else { return nil }
        let name = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        let rhs = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        return (name, rhs)
    }

    private func classifyUnknown(_ name: String, lineIndex: Int, context: NoteContext) -> LineError {
        if context.cyclicLines.contains(lineIndex) || context.isCyclic(name) {
            return .cycle(name)
        }
        if context.isAssignedLater(name, after: lineIndex) {
            return .forwardReference(name)
        }
        return .unknownVariable(name)
    }

    private func mapMathError(_ error: MathError, lineIndex: Int, context: NoteContext) -> LineError {
        switch error {
        case .syntax: return .syntax
        case .divideByZero: return .divideByZero
        case .unknownVariable(let name): return classifyUnknown(name, lineIndex: lineIndex, context: context)
        }
    }

    /// Evaluates an assignment RHS: a conversion or a plain expression.
    private func evaluateRHS(_ rhs: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> Result<Double, LineError> {
        if isConversionLine(rhs), Self.conversionAmountExpression(rhs) != nil {
            return evaluateConversion(rhs, lineIndex: lineIndex, context: context, variables: variables)
        }
        do {
            let value = try parseExpression(rhs, variables: variables)
            return value.isFinite ? .success(value) : .failure(.syntax)
        } catch let e as MathError {
            return .failure(mapMathError(e, lineIndex: lineIndex, context: context))
        } catch {
            return .failure(.syntax)
        }
    }

    /// Handles any line carrying `=`; nil means "not an assignment line".
    /// A failed assignment clears the name so no stale value leaks down.
    private func evaluateAssignment(_ work: String, lineIndex: Int, context: NoteContext, variables: inout [String: Double]) -> LineOutcome? {
        for op in ["==", "<=", ">=", "!="] where work.contains(op) {
            return .error(.syntax)
        }
        let equals = work.indices.filter { work[$0] == "=" }
        guard !equals.isEmpty else { return nil }
        guard equals.count == 1, let eq = equals.first else { return .error(.syntax) }
        let name = work[work.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        let rhs = work[work.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        switch ReactiveVariable.problem(with: name) {
        case .empty:
            return .error(.invalidVariableName(name))
        case .reserved:
            return .error(.reservedVariableName(name))
        case .invalid:
            // `1x`/`my price`/`x-y` are name attempts; `2 + 3 = 5` is an
            // unsupported equation, reported as syntax.
            let nameish = name.contains(where: { $0.isLetter || $0 == "_" })
                && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == " " || $0 == "-" || $0 == "." || $0 == "$" }
            return .error(nameish ? .invalidVariableName(name) : .syntax)
        case nil:
            break
        }
        if context.cyclicLines.contains(lineIndex) {
            variables[name] = nil
            return .error(.cycle(name))
        }
        guard !rhs.isEmpty else {
            variables[name] = nil
            return .error(.syntax)
        }
        switch evaluateRHS(rhs, lineIndex: lineIndex, context: context, variables: variables) {
        case .success(let value):
            variables[name] = value
            return .value(LineResult(value: value, display: format(value), assignedName: name))
        case .failure(let error):
            variables[name] = nil
            return .error(error)
        }
    }

    /// First identifier used *as a variable* (next to an operator/paren,
    /// or the whole line) that is not currently defined. Bare label words
    /// in "oats 2 + 2" are not uses, so descriptive text still works —
    /// but "price * 3" with no `price` is an error, never a rescued `3`.
    private func firstUnknownReference(in line: String, variables: [String: Double]) -> String? {
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            guard chars[i].isLetter || chars[i] == "_" else { i += 1; continue }
            let start = i
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
            let name = String(chars[start..<i])
            if variables[name] != nil { continue }
            var before: Character?
            var j = start - 1
            while j >= 0 {
                if !chars[j].isWhitespace { before = chars[j]; break }
                j -= 1
            }
            var after: Character?
            var k = i
            while k < chars.count {
                if !chars[k].isWhitespace { after = chars[k]; break }
                k += 1
            }
            let beforeOps: Set<Character> = ["+", "-", "*", "/", "%", "^", "("]
            let afterOps: Set<Character> = ["+", "-", "*", "/", "%", "^", ")"]
            let isWholeLine = before == nil && after == nil
            if isWholeLine || (before.map { beforeOps.contains($0) } ?? false) || (after.map { afterOps.contains($0) } ?? false) {
                return name
            }
        }
        return nil
    }

    private func evaluateOutcome(_ line: String, lineIndex: Int, context: NoteContext, variables: inout [String: Double]) -> LineOutcome {
        let work = line.trimmingCharacters(in: .whitespaces)
        if work.isEmpty || work.hasPrefix("//") { return .blank }
        if let assigned = evaluateAssignment(work, lineIndex: lineIndex, context: context, variables: &variables) {
            return assigned
        }
        if isConversionLine(work) {
            return parseConversionOutcome(work, lineIndex: lineIndex, context: context, variables: variables)
        }
        if let unknown = firstUnknownReference(in: work, variables: variables) {
            return .error(classifyUnknown(unknown, lineIndex: lineIndex, context: context))
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
                let usesVariable = ReactiveVariable.references(in: candidate).contains { variables[$0] != nil }
                if candidate.rangeOfCharacter(from: .decimalDigits) != nil || usesVariable {
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
        if isBareName(work) { return .error(classifyUnknown(work, lineIndex: lineIndex, context: context)) }
        if looksLikeMath(work) {
            if sawDivideByZero { return .error(.divideByZero) }
            return .error(.syntax)
        }
        return .blank
    }

    /// A line with digits, operators, or conversion words is a math attempt;
    /// plain prose stays blank.
    private func looksLikeMath(_ line: String) -> Bool {
        if line.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if line.contains("=") { return true }
        let ops: Set<Character> = ["+", "-", "*", "/", "%", "^", "(", ")"]
        if line.contains(where: { ops.contains($0) }) { return true }
        let lower = " " + line.lowercased() + " "
        return lower.contains(" in ") || lower.contains(" to ")
    }

    private func isBareName(_ line: String) -> Bool {
        ReactiveVariable.problem(with: line) != .invalid && !line.isEmpty
            && line.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && (line.first?.isLetter == true || line.first == "_")
    }

    /// A line shaped like "<expr> in|to <word>" is a conversion attempt.
    /// Returns nil result (not a variable fallback) when units are unknown.
    private func isConversionLine(_ line: String) -> Bool {
        guard line.range(of: #"(?i)\b(in|to)\b"#, options: .regularExpression) != nil else { return false }
        // Must have at least "<something> <word>" shape before the keyword.
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.count >= 3
    }

    /// The amount expression of a conversion (`price * 2` in
    /// `price * 2 USD in EUR`), or nil when not conversion-shaped.
    private static func conversionAmountExpression(_ line: String) -> String? {
        guard let parts = conversionParts(line) else { return nil }
        return parts.expr
    }

    private static func conversionParts(_ line: String) -> (expr: String, from: String, to: String)? {
        guard let range = line.range(of: #"(?i)\b(in|to)\b"#, options: .regularExpression) else { return nil }
        let lhs = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let rhs = line[range.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
        guard let split = lhs.lastIndex(where: { $0.isWhitespace }) else { return nil }
        let expr = lhs[lhs.startIndex..<split].trimmingCharacters(in: .whitespaces)
        let from = lhs[lhs.index(after: split)...].trimmingCharacters(in: .whitespaces).lowercased()
        guard !expr.isEmpty, !from.isEmpty else { return nil }
        return (String(expr), from, rhs)
    }

    /// Conversion value shared by bare conversion lines and assignment
    /// RHSes (`dist = 10 km in mi`), so both report identical errors.
    private func evaluateConversion(_ line: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> Result<Double, LineError> {
        guard let parts = Self.conversionParts(line) else { return .failure(.syntax) }
        let amount: Double
        do {
            amount = try parseExpression(parts.expr, variables: variables)
        } catch let e as MathError {
            return .failure(mapMathError(e, lineIndex: lineIndex, context: context))
        } catch {
            return .failure(.syntax)
        }
        if let physical = UnitConvert.convert(amount: amount, from: parts.from, to: parts.to) {
            return .success(physical)
        }
        if CurrencyRates.isCurrency(parts.from) || CurrencyRates.isCurrency(parts.to) {
            guard CurrencyRates.isCurrency(parts.from), CurrencyRates.isCurrency(parts.to) else {
                return .failure(.unknownCurrency(CurrencyRates.isCurrency(parts.from) ? parts.to : parts.from))
            }
            guard let rates else { return .failure(.noRates) }
            if let converted = CurrencyRates.convert(amount: amount, from: parts.from, to: parts.to, rates: rates) {
                return .success(converted)
            }
            return .failure(.unknownCurrency(parts.from))
        }
        return .failure(.unknownUnit(parts.to.isEmpty ? parts.from : parts.to))
    }

    private func parseConversionOutcome(_ line: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> LineOutcome {
        switch evaluateConversion(line, lineIndex: lineIndex, context: context, variables: variables) {
        case .success(let value):
            return .value(LineResult(value: value, display: format(value)))
        case .failure(let error):
            return .error(error)
        }
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
    /// Variable-aware with the same down-the-note semantics as `math`:
    /// an assignment line defines a name and contributes nothing itself;
    /// a line that evaluates using a defined name (`price * 3`, a bare
    /// `price`, `price USD in EUR`) contributes its value once; every
    /// other line contributes its literal numbers as before.
    public func contributions(text: String) -> [[Double]] {
        let lines = text.components(separatedBy: .newlines)
        let context = makeContext(lines: lines)
        var variables: [String: Double] = [:]
        return lines.enumerated().map { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { return [] }
            // Assignment (or broken `=` line): apply it, count nothing.
            var probe = variables
            if evaluateAssignment(trimmed, lineIndex: index, context: context, variables: &probe) != nil {
                variables = probe
                return []
            }
            if let value = variableLineValue(trimmed, lineIndex: index, context: context, variables: variables) {
                return [value]
            }
            return lineNumbers(line)
        }
    }

    /// Value of the longest evaluable suffix that actually reads a
    /// currently defined variable, else nil (literal counting applies).
    private func variableLineValue(_ line: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> Double? {
        guard !variables.isEmpty else { return nil }
        let tokens = line.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        for start in tokens.indices {
            let candidate = tokens[start...].joined(separator: " ")
            if isConversionLine(candidate), let amount = Self.conversionAmountExpression(candidate) {
                let refs = ReactiveVariable.references(in: amount)
                guard refs.contains(where: { variables[$0] != nil }) else { continue }
                if case .success(let value) = evaluateConversion(candidate, lineIndex: lineIndex, context: context, variables: variables) {
                    return value
                }
                continue
            }
            let refs = ReactiveVariable.references(in: candidate)
            guard refs.contains(where: { variables[$0] != nil }) else { continue }
            if let value = try? parseExpression(candidate, variables: variables), value.isFinite {
                return value
            }
        }
        return nil
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
    enum MathError: Error, Equatable { case syntax, divideByZero, unknownVariable(String) }
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
            throw MathEngine.MathError.unknownVariable(name)
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
