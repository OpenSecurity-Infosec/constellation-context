import ContextDomain
import Foundation

/// Inline math for `math` notes: arithmetic with variables, one result per line.
/// Supports + - * / % ^, parentheses, unary minus, reactive
/// `name = expr` assignment (see `evaluateLines` for the down-the-note
/// semantics and `ReactiveVariable` for naming rules; the RHS may also
/// be a conversion), unit conversions (`10 km in mi`, `5 kg in lb`,
/// `100 km/h to mph`, `5 ft 6 in in cm` — see `UnitConversion` for the
/// dimensions and spellings), and currency/crypto conversions
/// (`42 USD in EUR`, `0.5 BTC in USD`) via an injected rate table.
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
        /// Both units are known but measure different things.
        case incompatibleUnits(String, String)
        case unknownCurrency(String)
        case belowAbsoluteZero
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
            case .incompatibleUnits(let f, let t): return "can't convert \(f) to \(t)"
            case .unknownCurrency(let c): return "unknown \(c)"
            case .belowAbsoluteZero: return "below absolute zero"
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
        let lines = text.components(separatedBy: .newlines).map(Self.withoutComment)
        let context = makeContext(lines: lines)
        var variables: [String: Double] = [:]
        return lines.enumerated().map { index, line in
            evaluateOutcome(line, lineIndex: index, context: context, variables: &variables)
        }
    }

    /// Math has no string literals: the first double slash starts a comment.
    private static func withoutComment(_ line: String) -> String {
        guard let marker = line.range(of: "//") else { return line }
        return String(line[..<marker.lowerBound])
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
    /// amount expression (every component of a compound quantity) —
    /// unit words (`km`, `in`, `mi`) are not names.
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
            // A number (with any exponent) is not a name: the `e3`
            // of `1e3` must never read as a variable reference.
            if chars[i].isNumber {
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "," { i += 1 }
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var next = i + 1
                    if next < chars.count, chars[next] == "-" || chars[next] == "+" { next += 1 }
                    var digits = 0
                    while next < chars.count, chars[next].isNumber { next += 1; digits += 1 }
                    if digits > 0 { i = next; continue }
                }
                continue
            }
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

    /// A line with digits or operators is a math attempt; plain prose
    /// stays blank, including prose that merely contains `in`/`to`
    /// ("walk to the shop" is not a broken conversion).
    private func looksLikeMath(_ line: String) -> Bool {
        if line.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if line.contains("=") { return true }
        let ops: Set<Character> = ["+", "-", "*", "/", "%", "^", "(", ")"]
        return line.contains(where: { ops.contains($0) })
    }

    private func isBareName(_ line: String) -> Bool {
        ReactiveVariable.problem(with: line) != .invalid && !line.isEmpty
            && line.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && (line.first?.isLetter == true || line.first == "_")
    }

    /// A line is a conversion attempt when some `in`/`to` splits it
    /// into an amount plus a source unit on the left and a target unit
    /// on the right (see `parseConversion`). Prose that merely contains
    /// the words ("walk to the shop") is not one.
    private func isConversionLine(_ line: String) -> Bool {
        Self.parseConversion(line) != nil
    }

    /// The amount expression of a conversion (`price * 2` in
    /// `price * 2 USD in EUR`; every component amount of a compound
    /// quantity like `5 ft 6 in`), or nil when not conversion-shaped.
    private static func conversionAmountExpression(_ line: String) -> String? {
        guard let parse = parseConversion(line) else { return nil }
        if let parts = compoundParts(lhsText: parse.lhsText) {
            return parts.map(\.amount).joined(separator: " ")
        }
        return parse.amountText
    }

    /// One parsed conversion. `fromRaw`/`toRaw` are the typed unit
    /// phrases lowercased for gutter messages; the resolved units keep
    /// the exact-cased lookup (data sizes care about case).
    struct ConversionParse {
        var lhsText: String
        var amountText: String
        var fromRaw: String
        var toRaw: String
        var fromUnit: UnitConversion.Unit?
        var toUnit: UnitConversion.Unit?
    }

    /// Splits a conversion around its `in`/`to` keyword. Every keyword
    /// occurrence is tried, last first, and the first whose two sides
    /// both resolve to known units wins — so `9 in in cm` reads the
    /// first `in` as inches and a descriptive `to` earlier in the line
    /// does not steal the split. When nothing fully resolves, the
    /// most conversion-shaped split is still returned (units partly
    /// nil) so the gutter can name the unknown or incompatible side
    /// instead of a bare syntax error; prose returns nil.
    private static func parseConversion(_ line: String) -> ConversionParse? {
        var fallback: ConversionParse?
        for range in keywordRanges(in: line).reversed() {
            let lhs = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let rhs = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !lhs.isEmpty else { continue }
            let from = matchUnitAtEnd(of: lhs)
            if rhs.isEmpty {
                // "10 km in" — a conversion missing its target.
                if let from {
                    return ConversionParse(lhsText: lhs, amountText: from.amountText, fromRaw: lowerRaw(from.raw), toRaw: "", fromUnit: from.unit, toUnit: nil)
                }
                continue
            }
            let to = matchUnitAtStart(of: rhs)
            if let from, let to {
                return ConversionParse(lhsText: lhs, amountText: from.amountText, fromRaw: lowerRaw(from.raw), toRaw: lowerRaw(to.raw), fromUnit: from.unit, toUnit: to.unit)
            }
            if fallback == nil {
                let fromSide = from.map { (raw: $0.raw, amountText: $0.amountText) } ?? fallbackUnitAtEnd(of: lhs)
                let toRaw = to?.raw ?? rhs.components(separatedBy: .whitespaces).first(where: { !$0.isEmpty }) ?? ""
                if let fromSide, !toRaw.isEmpty {
                    let amountHasDigit = fromSide.amountText.rangeOfCharacter(from: .decimalDigits) != nil
                    let currencySide = CurrencyRates.isCurrency(fromSide.raw) || CurrencyRates.isCurrency(toRaw)
                    if from != nil || to != nil || amountHasDigit || currencySide {
                        fallback = ConversionParse(
                            lhsText: lhs, amountText: fromSide.amountText,
                            fromRaw: lowerRaw(fromSide.raw), toRaw: lowerRaw(toRaw),
                            fromUnit: from?.unit, toUnit: to?.unit
                        )
                    }
                }
            }
        }
        return fallback
    }

    private static func lowerRaw(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
    }

    private static func keywordRanges(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var search = line.startIndex..<line.endIndex
        while let range = line.range(of: #"\b(in|to)\b"#, options: [.regularExpression, .caseInsensitive], range: search) {
            ranges.append(range)
            search = range.upperBound..<line.endIndex
        }
        return ranges
    }

    /// Longest unit phrase (up to three words: "miles per hour",
    /// "square feet") ending `lhs`, or a unit glued onto its amount
    /// (`10km`, `100°C`, `5'`). What precedes it is the amount text.
    private static func matchUnitAtEnd(of lhs: String) -> (raw: String, unit: UnitConversion.Unit, amountText: String)? {
        let tokens = lhs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for count in [3, 2, 1] where tokens.count > count {
            let phrase = tokens.suffix(count).joined(separator: " ")
            if let unit = UnitConversion.unit(for: phrase) {
                return (phrase, unit, tokens.dropLast(count).joined(separator: " "))
            }
        }
        if let last = tokens.last, let glued = gluedUnitSuffix(of: last) {
            let amount = (tokens.dropLast() + [glued.amount]).joined(separator: " ")
            return (glued.raw, glued.unit, amount)
        }
        return nil
    }

    /// Longest unit phrase starting `rhs`; anything after it is
    /// trailing descriptive text ("10 km in mi for the run").
    private static func matchUnitAtStart(of rhs: String) -> (raw: String, unit: UnitConversion.Unit)? {
        let tokens = rhs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for count in [3, 2, 1] where tokens.count >= count {
            let phrase = tokens.prefix(count).joined(separator: " ")
            if let unit = UnitConversion.unit(for: phrase) {
                return (phrase, unit)
            }
        }
        return nil
    }

    /// The last token (or glued letter suffix) of `lhs` treated as a
    /// would-be source unit when none resolves, so an unknown unit can
    /// be named. Nil when there is no amount-plus-unit shape at all.
    private static func fallbackUnitAtEnd(of lhs: String) -> (raw: String, amountText: String)? {
        let tokens = lhs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.count >= 2, let last = tokens.last {
            return (last, tokens.dropLast().joined(separator: " "))
        }
        if let only = tokens.first,
           let split = only.firstIndex(where: { $0.isLetter || $0 == "°" }),
           split > only.startIndex
        {
            return (String(only[split...]), String(only[only.startIndex..<split]))
        }
        return nil
    }

    /// A known unit glued onto the end of a single token: `10km`,
    /// `(d*2)km`, `100°C`, `5'`, `6"`. The amount before it must end
    /// in a digit, a dot, or a closing paren so a variable name like
    /// `dkm` is never read as amount-plus-unit.
    private static func gluedUnitSuffix(of token: String) -> (raw: String, unit: UnitConversion.Unit, amount: String)? {
        func split(at index: String.Index) -> (raw: String, unit: UnitConversion.Unit, amount: String)? {
            let amount = String(token[token.startIndex..<index])
            let raw = String(token[index...])
            guard let last = amount.last, last.isNumber || last == "." || last == ")",
                  let unit = UnitConversion.unit(for: raw)
            else { return nil }
            return (raw, unit, amount)
        }
        if let paren = token.lastIndex(of: ")"), token.index(after: paren) < token.endIndex {
            return split(at: token.index(after: paren))
        }
        if token.hasSuffix("'") || token.hasSuffix("\"") {
            return split(at: token.index(before: token.endIndex))
        }
        if let first = token.firstIndex(where: { $0.isLetter || $0 == "°" }) {
            return split(at: first)
        }
        return nil
    }

    // MARK: Compound quantities ("5 ft 6 in", "1 h 30 min")

    /// Component amounts and units when `lhsText` is two or more
    /// amount-plus-unit pairs, optionally behind a descriptive label
    /// ("height 5 ft 6 in"). Each amount is a single token: a number
    /// or a variable name, never a spaced expression.
    private static func compoundParts(lhsText: String) -> [(amount: String, raw: String, unit: UnitConversion.Unit)]? {
        let tokens = expandedCompoundTokens(lhsText)
        guard tokens.count >= 4 else { return nil }
        for start in tokens.indices {
            var parts: [(amount: String, raw: String, unit: UnitConversion.Unit)] = []
            var i = start
            var ok = true
            while i < tokens.count {
                guard isAmountToken(tokens[i]) else { ok = false; break }
                var matched: (raw: String, unit: UnitConversion.Unit, count: Int)?
                for count in [3, 2, 1] where i + count < tokens.count {
                    let phrase = tokens[(i + 1)...(i + count)].joined(separator: " ")
                    if let unit = UnitConversion.unit(for: phrase) {
                        matched = (phrase, unit, count)
                        break
                    }
                }
                guard let m = matched else { ok = false; break }
                parts.append((tokens[i], m.raw, m.unit))
                i += 1 + m.count
            }
            if ok, i == tokens.count, parts.count >= 2 { return parts }
        }
        return nil
    }

    private static func isAmountToken(_ token: String) -> Bool {
        var body = token
        if body.hasPrefix("-") || body.hasPrefix("+") { body = String(body.dropFirst()) }
        guard !body.isEmpty else { return false }
        if body.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) {
            return body.contains(where: { $0.isNumber })
        }
        // A variable may share a unit's name (`h = 5` then `h ft …`);
        // in amount position it is still the amount.
        return ReactiveVariable.isValidName(body)
    }

    /// Whitespace tokens with glued amount/unit runs split apart, so
    /// `5ft`, `6in`, `10km/h`, and `5'6"` all become alternating
    /// amount and unit tokens. A digit inside a unit (`m2`, `ft2`)
    /// stays with the unit when the result is a known unit.
    private static func expandedCompoundTokens(_ text: String) -> [String] {
        var out: [String] = []
        for token in text.components(separatedBy: .whitespaces) where !token.isEmpty {
            var current = ""
            var inAmount: Bool?
            func flush() {
                if !current.isEmpty { out.append(current) }
                current = ""
                inAmount = nil
            }
            for ch in token {
                if ch == "'" || ch == "\"" {
                    flush()
                    out.append(String(ch))
                    continue
                }
                let amountChar = ch.isNumber || ch == "." || ch == ","
                if current.isEmpty {
                    current.append(ch)
                    inAmount = amountChar || ch == "-"
                } else if inAmount == true, ch.isLetter || ch == "°" {
                    flush()
                    current.append(ch)
                    inAmount = false
                } else if inAmount == false, ch.isNumber {
                    if UnitConversion.unit(for: current + String(ch)) != nil {
                        current.append(ch)
                    } else {
                        flush()
                        current.append(ch)
                        inAmount = true
                    }
                } else {
                    current.append(ch)
                }
            }
            flush()
        }
        return out
    }

    /// Evaluates a conversion amount, allowing a descriptive label
    /// before it ("run: 10", "oats 10") the way plain math lines do.
    /// A name used *as a variable* (`nope * 2`) is an error, never a
    /// label to rescue past.
    private func evaluateAmount(_ text: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> Result<Double, LineError> {
        do {
            return .success(try parseExpression(text, variables: variables))
        } catch let e as MathError {
            if e == .divideByZero { return .failure(.divideByZero) }
            if let unknown = firstUnknownReference(in: text, variables: variables) {
                return .failure(classifyUnknown(unknown, lineIndex: lineIndex, context: context))
            }
            // Longest evaluable suffix: after a `label:` prefix, then
            // by dropping leading label words one at a time.
            var candidates: [String] = []
            if let colon = text.lastIndex(of: ":") {
                candidates.append(text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
            let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            for start in tokens.indices.dropFirst() {
                candidates.append(tokens[start...].joined(separator: " "))
            }
            for candidate in candidates where !candidate.isEmpty {
                if let value = try? parseExpression(candidate, variables: variables), value.isFinite {
                    let usesVariable = ReactiveVariable.references(in: candidate).contains { variables[$0] != nil }
                    if candidate.rangeOfCharacter(from: .decimalDigits) != nil || usesVariable {
                        return .success(value)
                    }
                }
            }
            return .failure(mapMathError(e, lineIndex: lineIndex, context: context))
        } catch {
            return .failure(.syntax)
        }
    }

    /// Conversion value shared by bare conversion lines and assignment
    /// RHSes (`dist = 10 km in mi`), so both report identical errors.
    private func evaluateConversion(_ line: String, lineIndex: Int, context: NoteContext, variables: [String: Double]) -> Result<Double, LineError> {
        guard let parse = Self.parseConversion(line) else { return .failure(.syntax) }
        guard !parse.toRaw.isEmpty else { return .failure(.syntax) }
        // Compound quantity: sum every component in the target unit.
        if let toUnit = parse.toUnit, let parts = Self.compoundParts(lhsText: parse.lhsText) {
            var total = 0.0
            for part in parts {
                let partAmount: Double
                do {
                    partAmount = try parseExpression(part.amount, variables: variables)
                } catch let e as MathError {
                    return .failure(mapMathError(e, lineIndex: lineIndex, context: context))
                } catch {
                    return .failure(.syntax)
                }
                if UnitConversion.isBelowAbsoluteZero(amount: partAmount, unit: part.unit) {
                    return .failure(.belowAbsoluteZero)
                }
                guard let converted = UnitConversion.convert(amount: partAmount, from: part.unit, to: toUnit) else {
                    return .failure(.incompatibleUnits(Self.lowerRaw(part.raw), parse.toRaw))
                }
                total += converted
            }
            return .success(total)
        }
        let amount: Double
        switch evaluateAmount(parse.amountText, lineIndex: lineIndex, context: context, variables: variables) {
        case .success(let value): amount = value
        case .failure(let error): return .failure(error)
        }
        if let fromUnit = parse.fromUnit, let toUnit = parse.toUnit {
            if UnitConversion.isBelowAbsoluteZero(amount: amount, unit: fromUnit) {
                return .failure(.belowAbsoluteZero)
            }
            if let converted = UnitConversion.convert(amount: amount, from: fromUnit, to: toUnit) {
                return .success(converted)
            }
            return .failure(.incompatibleUnits(parse.fromRaw, parse.toRaw))
        }
        if parse.fromUnit != nil {
            return .failure(CurrencyRates.isCurrency(parse.toRaw)
                ? .incompatibleUnits(parse.fromRaw, parse.toRaw)
                : .unknownUnit(parse.toRaw))
        }
        if parse.toUnit != nil {
            return .failure(CurrencyRates.isCurrency(parse.fromRaw)
                ? .incompatibleUnits(parse.fromRaw, parse.toRaw)
                : .unknownUnit(parse.fromRaw))
        }
        if CurrencyRates.isCurrency(parse.fromRaw) || CurrencyRates.isCurrency(parse.toRaw) {
            guard CurrencyRates.isCurrency(parse.fromRaw), CurrencyRates.isCurrency(parse.toRaw) else {
                return .failure(.unknownCurrency(CurrencyRates.isCurrency(parse.fromRaw) ? parse.toRaw : parse.fromRaw))
            }
            // Same code both sides needs no rate table.
            if parse.fromRaw.uppercased() == parse.toRaw.uppercased() { return .success(amount) }
            guard let rates else { return .failure(.noRates) }
            if let converted = CurrencyRates.convert(amount: amount, from: parse.fromRaw, to: parse.toRaw, rates: rates) {
                return .success(converted)
            }
            return .failure(.unknownCurrency(parse.fromRaw))
        }
        return .failure(.unknownUnit(parse.toRaw))
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

    /// Gutter formatting: plain integers, up to 6 decimal places with
    /// trailing zeros trimmed, and scientific notation outside that
    /// range so a tiny conversion result (1 mm in miles) never reads
    /// as a rounded "0" and a huge one stays short. Negative zero
    /// always displays as "0".
    public func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int(value))
        }
        if abs(value) < 1e-6 || abs(value) >= 1e15 {
            return String(format: "%.6g", value)
        }
        let trimmed = String(format: "%.6f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return trimmed == "-0" ? String(format: "%.6g", value) : trimmed
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

    /// Numbers may carry thousands separators ("1,000.5" is one
    /// number) and an exponent ("1e3", "1.5e-7"), matching what
    /// `format` can print back. A bare `e` with no exponent digits
    /// is not consumed, so names are untouched.
    mutating func parseNumber() -> Double? {
        skipSpaces()
        let start = index
        var text = ""
        var sawDigit = false
        var sawDot = false
        while index < chars.count {
            let ch = chars[index]
            if ch.isNumber {
                sawDigit = true
                text.append(ch)
                index += 1
            } else if ch == ".", !sawDot {
                sawDot = true
                text.append(ch)
                index += 1
            } else if ch == ",", sawDigit, index + 1 < chars.count, chars[index + 1].isNumber {
                index += 1
            } else {
                break
            }
        }
        guard sawDigit else { index = start; return nil }
        if index < chars.count, chars[index] == "e" || chars[index] == "E" {
            var next = index + 1
            var sign = ""
            if next < chars.count, chars[next] == "-" || chars[next] == "+" {
                sign = String(chars[next])
                next += 1
            }
            var digits = ""
            while next < chars.count, chars[next].isNumber {
                digits.append(chars[next])
                next += 1
            }
            if !digits.isEmpty {
                text += "e" + sign + digits
                index = next
            }
        }
        return Double(text)
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


