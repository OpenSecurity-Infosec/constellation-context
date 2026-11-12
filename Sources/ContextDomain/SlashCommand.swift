import CryptoKit
import Foundation

/// Native `::` extension commands. Domain-pure registry: AppKit feeds the
/// caret/token context, the registry returns the text edit to apply.
/// JS extensions (see `JSExtension`) plug into this same shape.
///
/// Invocation grammar: `::name` or `::name(arg, arg)`. Arguments are
/// comma-separated; commas inside single/double quotes do not split and
/// one pair of surrounding quotes is stripped. Commands that take free
/// text (`upper`, `hash`, …) use the whole parenthesised string verbatim,
/// so `::upper(hello, world)` uppercases "hello, world".
public enum SlashCommand: Sendable {
    /// A text edit produced by running a command.
    public struct Edit: Equatable, Sendable {
        /// Range of the `::token` to replace (nil = whole-buffer transform).
        public var tokenRange: Range<Int>?
        public var replacement: String
        /// Full replacement text for whole-buffer commands like sort.
        public var fullText: String?
    }

    public struct Definition: Sendable {
        public var name: String
        public var hint: String
        public init(name: String, hint: String) {
            self.name = name
            self.hint = hint
        }
    }

    /// Why a command did not run. `gutterMessage` is the one-line form the
    /// editor shows in the gutter / status bar.
    public enum CommandError: Error, Equatable, Sendable {
        case unknownCommand(name: String, suggestions: [String])
        case invalidArguments(command: String, message: String)
        case failed(command: String, message: String)

        public var gutterMessage: String {
            switch self {
            case .unknownCommand(let name, let suggestions):
                if let first = suggestions.first {
                    let rest = suggestions.dropFirst().map { "::\($0)" }.joined(separator: ", ")
                    return rest.isEmpty
                        ? "unknown command ::\(name) — did you mean ::\(first)?"
                        : "unknown command ::\(name) — did you mean ::\(first)? (also \(rest))"
                }
                return "unknown command ::\(name) — ::help lists commands"
            case .invalidArguments(let command, let message),
                 .failed(let command, let message):
                return "::\(command): \(message)"
            }
        }
    }

    /// A parsed `::name(args)` token.
    public struct Invocation: Equatable, Sendable {
        public var name: String
        /// Comma-split arguments (quotes respected, surrounding quotes stripped).
        public var arguments: [String]
        /// The verbatim parenthesised text, when parentheses were typed.
        public var rawArgument: String?
        public var hasParenthesisedArgs: Bool

        public init(name: String, arguments: [String], rawArgument: String?, hasParenthesisedArgs: Bool) {
            self.name = name
            self.arguments = arguments
            self.rawArgument = rawArgument
            self.hasParenthesisedArgs = hasParenthesisedArgs
        }
    }

    public static let builtins: [Definition] = [
        Definition(name: "today", hint: "Insert ISO date — today(yyyy/MM/dd) for a custom format"),
        Definition(name: "tomorrow", hint: "Insert tomorrow's ISO date"),
        Definition(name: "yesterday", hint: "Insert yesterday's ISO date"),
        Definition(name: "now", hint: "Insert local date + time — now(HH:mm) for a custom format"),
        Definition(name: "time", hint: "Insert local time (HH:mm:ss)"),
        Definition(name: "timestamp", hint: "Insert Unix seconds — timestamp(ms) for milliseconds"),
        Definition(name: "uuid", hint: "Insert a UUID — uuid(upper) for uppercase"),
        Definition(name: "random", hint: "Random 1–100 — random(max), random(min, max), or random(a, b, c) to pick one"),
        Definition(name: "count", hint: "Insert line/word/char counts — count(words) or count(some text)"),
        Definition(name: "help", hint: "List all :: commands — help(name) for one"),
        Definition(name: "sort_lines", hint: "Sort lines A–Z — sort_lines(desc) for Z–A"),
        Definition(name: "reverse_lines", hint: "Reverse line order"),
        Definition(name: "dedupe_lines", hint: "Drop duplicate lines, keep first — dedupe_lines(ci) ignores case"),
        Definition(name: "trim_lines", hint: "Trim whitespace at both ends of every line"),
        Definition(name: "remove_blank_lines", hint: "Delete empty lines"),
        Definition(name: "shuffle_lines", hint: "Shuffle line order"),
        Definition(name: "upper", hint: "Uppercase upper(text), the selection, or the note"),
        Definition(name: "lower", hint: "Lowercase lower(text), the selection, or the note"),
        Definition(name: "title", hint: "Title-case title(text), the selection, or the note"),
        Definition(name: "trim", hint: "Trim trim(text), the selection, or the note's outer whitespace"),
        Definition(name: "base64_encode", hint: "Base64-encode base64_encode(text) or the selection"),
        Definition(name: "base64_decode", hint: "Base64-decode base64_decode(text) or the selection"),
        Definition(name: "hash", hint: "SHA-256 hex of hash(text) or the selection"),
        Definition(name: "md5", hint: "MD5 hex of md5(text) or the selection"),
        Definition(name: "json_format", hint: "Pretty-print JSON from json_format(text), the selection, or the note"),
    ]

    /// Alternate spellings that run a canonical builtin. Aliases are not
    /// listed in completions; typing one completes to its canonical name.
    public static let aliases: [String: String] = [
        "date": "today",
        "datetime": "now",
        "unix": "timestamp",
        "sort": "sort_lines",
        "sort-lines": "sort_lines",
        "reverse": "reverse_lines",
        "dedupe": "dedupe_lines",
        "uniq": "dedupe_lines",
        "uppercase": "upper",
        "lowercase": "lower",
        "capitalize": "title",
        "sha256": "hash",
        "json": "json_format",
    ]

    /// Canonical builtin name for a typed name/alias, or nil.
    public static func canonicalName(_ name: String) -> String? {
        let lower = name.lowercased()
        if builtins.contains(where: { $0.name == lower }) { return lower }
        return aliases[lower]
    }

    public static func isBuiltin(_ name: String) -> Bool { canonicalName(name) != nil }

    /// Token under the caret: `::name` plus an optional `(args)` suffix on
    /// the same line. Returns the token text and integer range, or nil
    /// when the caret is not on one.
    public static func token(at caret: Int, in text: String) -> (token: String, range: Range<Int>)? {
        let chars = Array(text)
        guard caret >= 0, caret <= chars.count else { return nil }
        // Rewind to a `::` opener on this line with a non-word char before it.
        var opener: Int?
        var i = caret
        while i >= 2 {
            if chars[i - 1] == "\n" { break }
            if chars[i - 2] == ":", chars[i - 1] == ":" {
                if i - 3 < 0 || !chars[i - 3].isLetter && !chars[i - 3].isNumber && chars[i - 3] != ":" {
                    opener = i - 2
                    break
                }
            }
            i -= 1
        }
        guard let open = opener else { return nil }
        var end = open + 2
        while end < chars.count, chars[end].isCommandChar { end += 1 }
        guard end > open + 2 else { return nil }
        // Optional `(args)`: consume to the closing paren (quotes respected)
        // or to end-of-line while the user is still typing the arguments.
        if end < chars.count, chars[end] == "(" {
            var j = end + 1
            var quote: Character?
            var closed = false
            while j < chars.count, chars[j] != "\n" {
                let c = chars[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == ")" {
                    closed = true
                    j += 1
                    break
                }
                j += 1
            }
            _ = closed
            end = j
        }
        guard caret >= open, caret <= end else { return nil }
        return (String(chars[open..<end]), open..<end)
    }

    /// The command-name fragment of a token, for completion filtering.
    public static func fragment(fromToken token: String) -> String {
        parseInvocation(token)?.name ?? String(token.dropFirst(2).prefix(while: { $0.isCommandChar }))
    }

    /// Parses `::name` / `::name(args)` token text. An unterminated `(`
    /// (still typing) treats the rest of the token as the raw argument.
    public static func parseInvocation(_ token: String) -> Invocation? {
        guard token.hasPrefix("::") else { return nil }
        let rest = Array(token.dropFirst(2))
        var idx = 0
        while idx < rest.count, rest[idx].isCommandChar { idx += 1 }
        guard idx > 0 else { return nil }
        let name = String(rest[0..<idx]).lowercased()
        guard idx < rest.count else {
            return Invocation(name: name, arguments: [], rawArgument: nil, hasParenthesisedArgs: false)
        }
        guard rest[idx] == "(" else { return nil }
        var inner = String(rest[(idx + 1)...])
        if inner.hasSuffix(")") { inner = String(inner.dropLast()) }
        return Invocation(
            name: name,
            arguments: splitArguments(inner),
            rawArgument: inner,
            hasParenthesisedArgs: true
        )
    }

    /// Splits on commas outside quotes, trims each piece, strips one pair
    /// of surrounding quotes. Empty input yields no arguments.
    public static func splitArguments(_ raw: String) -> [String] {
        if raw.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for c in raw {
            if let q = quote {
                current.append(c)
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
                current.append(c)
            } else if c == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts.map { unquote($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              first == last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }

    /// Filtered completions for a `::` prefix fragment (without the colons).
    /// Native builtins first, then installed JS extensions. Falls back to
    /// substring matches when no name starts with the fragment.
    public static func completions(matching fragment: String, extensions: [JSExtension.Script] = []) -> [Definition] {
        let lower = fragment.lowercased()
        func matches(_ name: String) -> Bool {
            lower.isEmpty || name.lowercased().hasPrefix(lower)
        }
        var native = builtins.filter { matches($0.name) }
        // Alias fragments complete to the canonical command.
        if !lower.isEmpty {
            for (alias, canonical) in aliases where alias.hasPrefix(lower) {
                if let def = builtins.first(where: { $0.name == canonical }),
                   !native.contains(where: { $0.name == canonical }) {
                    native.append(def)
                }
            }
        }
        let js = extensions
            .filter { matches($0.commandName) }
            .filter { ext in !builtins.contains { $0.name.lowercased() == ext.commandName.lowercased() } }
            .map { Definition(name: $0.commandName, hint: $0.hint) }
        var result = native + js
        if result.isEmpty, !lower.isEmpty {
            result = builtins.filter { $0.name.contains(lower) }
                + extensions.filter { $0.commandName.lowercased().contains(lower) }
                    .map { Definition(name: $0.commandName, hint: $0.hint) }
        }
        return result
    }

    /// Looks up an installed JS extension by command name.
    public static func extensionScript(named name: String, in extensions: [JSExtension.Script]) -> JSExtension.Script? {
        extensions.first { $0.commandName.lowercased() == name.lowercased() }
    }

    /// Did-you-mean candidates for an unknown name: shared prefixes first,
    /// then small edit distances, then substring matches. Max 3, canonical.
    public static func suggestions(for name: String, extensions: [JSExtension.Script] = []) -> [String] {
        suggestions(for: name, extraNames: extensions.map(\.commandName))
    }

    public static func suggestions(for name: String, extraNames: [String]) -> [String] {
        let target = name.lowercased()
        guard !target.isEmpty else { return [] }
        var candidates: [String] = builtins.map(\.name)
        for extra in extraNames {
            let lower = extra.lowercased()
            if !candidates.contains(lower) { candidates.append(lower) }
        }
        // Alias hits suggest their canonical command.
        var aliasHits: [String] = []
        for (alias, canonical) in aliases where alias == target || alias.hasPrefix(target) || target.hasPrefix(alias) {
            if !aliasHits.contains(canonical) { aliasHits.append(canonical) }
        }
        let scored: [(name: String, score: Int)] = candidates.compactMap { candidate in
            if candidate == target { return nil }
            if candidate.hasPrefix(target) || target.hasPrefix(candidate) {
                return (candidate, 0)
            }
            let distance = levenshtein(target, candidate)
            let limit = target.count >= 7 ? 3 : 2
            if distance <= limit { return (candidate, distance) }
            if candidate.contains(target) || target.contains(candidate) { return (candidate, 4) }
            return nil
        }
        var out: [String] = aliasHits
        for entry in scored.sorted(by: { ($0.score, $0.name) < ($1.score, $1.name) }) {
            if !out.contains(entry.name) { out.append(entry.name) }
            if out.count == 3 { break }
        }
        return Array(out.prefix(3))
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var curr = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            curr[0] = i
            for j in 1...y.count {
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &curr)
        }
        return prev[y.count]
    }

    // MARK: - Running

    /// Runs a command, returning the edit or a user-facing error.
    /// `now` is injected for deterministic tests. `knownNames` carries JS
    /// extension names so unknown-command suggestions can include them.
    public static func runResult(
        name: String,
        arguments: [String] = [],
        rawArgument: String? = nil,
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        now: Date = Date(),
        knownNames: [String] = []
    ) -> Result<Edit, CommandError> {
        let typed = name.lowercased()
        guard let canonical = canonicalName(typed) else {
            return .failure(.unknownCommand(
                name: typed,
                suggestions: suggestions(for: typed, extraNames: knownNames)
            ))
        }
        func insert(_ value: String) -> Result<Edit, CommandError> {
            .success(Edit(tokenRange: tokenRange, replacement: value, fullText: nil))
        }
        func invalid(_ message: String) -> Result<Edit, CommandError> {
            .failure(.invalidArguments(command: canonical, message: message))
        }
        let format = arguments.first?.nilIfEmpty

        switch canonical {
        case "today":
            return insert(format.map { formatted(now, format: $0, timeZone: utc) } ?? isoDate(now))
        case "tomorrow", "yesterday":
            let shifted = shiftedDay(now, by: canonical == "tomorrow" ? 1 : -1)
            return insert(format.map { formatted(shifted, format: $0, timeZone: utc) } ?? isoDate(shifted))
        case "now":
            return insert(format.map { formatted(now, format: $0, timeZone: .current) } ?? localDateTime(now))
        case "time":
            return insert(formatted(now, format: format ?? "HH:mm:ss", timeZone: .current))
        case "timestamp":
            switch arguments.first?.lowercased() {
            case nil, "", "s":
                return insert(String(Int(now.timeIntervalSince1970)))
            case "ms":
                return insert(String(Int(now.timeIntervalSince1970 * 1000)))
            default:
                return invalid("use timestamp, timestamp(s), or timestamp(ms)")
            }
        case "uuid":
            switch arguments.first?.lowercased() {
            case nil, "", "lower":
                return insert(UUID().uuidString.lowercased())
            case "upper":
                return insert(UUID().uuidString.uppercased())
            default:
                return invalid("use uuid, uuid(lower), or uuid(upper)")
            }
        case "random":
            return randomValue(arguments: arguments).map { Edit(tokenRange: tokenRange, replacement: $0, fullText: nil) }
        case "count":
            return insert(countText(arguments: arguments, rawArgument: rawArgument, tokenRange: tokenRange, fullText: fullText))
        case "help":
            if let topic = arguments.first?.nilIfEmpty {
                guard let topicCanonical = canonicalName(topic),
                      let def = builtins.first(where: { $0.name == topicCanonical }) else {
                    return .failure(.unknownCommand(
                        name: topic.lowercased(),
                        suggestions: suggestions(for: topic, extraNames: knownNames)
                    ))
                }
                return insert("::\(def.name) — \(def.hint)")
            }
            return insert(builtins.map { "::\($0.name) — \($0.hint)" }.joined(separator: "\n"))
        case "sort_lines":
            let descending = arguments.contains { ["desc", "reverse", "za"].contains($0.lowercased()) }
            if let bad = arguments.first(where: { !["desc", "reverse", "za", "asc"].contains($0.lowercased()) }) {
                return invalid("unknown option \"\(bad)\" — use sort_lines or sort_lines(desc)")
            }
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { lines in
                lines.sorted {
                    let order = $0.localizedCaseInsensitiveCompare($1)
                    return descending ? order == .orderedDescending : order == .orderedAscending
                }
            }
        case "reverse_lines":
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { Array($0.reversed()) }
        case "dedupe_lines":
            let caseInsensitive = arguments.contains { $0.lowercased() == "ci" }
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { lines in
                var seen: Set<String> = []
                return lines.filter { seen.insert(caseInsensitive ? $0.lowercased() : $0).inserted }
            }
        case "trim_lines":
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { lines in
                lines.map { $0.trimmingCharacters(in: .whitespaces) }
            }
        case "remove_blank_lines":
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { lines in
                lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        case "shuffle_lines":
            return lineTransform(tokenRange: tokenRange, fullText: fullText, selection: selection) { $0.shuffled() }
        case "upper":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: true) { .success($0.uppercased()) }
        case "lower":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: true) { .success($0.lowercased()) }
        case "title":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: true) { .success(titleCased($0)) }
        case "trim":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: true) {
                .success($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case "base64_encode":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: false) {
                .success(Data($0.utf8).base64EncodedString())
            }
        case "base64_decode":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: false) { value in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let data = Data(base64Encoded: cleaned),
                      let decoded = String(data: data, encoding: .utf8) else {
                    return .failure(.failed(command: canonical, message: "input is not valid UTF-8 base64"))
                }
                return .success(decoded)
            }
        case "hash":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: false) {
                .success(SHA256.hash(data: Data($0.utf8)).hexString)
            }
        case "md5":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: false) {
                .success(Insecure.MD5.hash(data: Data($0.utf8)).hexString)
            }
        case "json_format":
            return textTransform(command: canonical, rawArgument: rawArgument, tokenRange: tokenRange,
                                 fullText: fullText, selection: selection, wholeBuffer: true) { value in
                prettyJSON(value, command: canonical)
            }
        default:
            // canonicalName only returns builtins, so this is unreachable.
            return .failure(.unknownCommand(name: typed, suggestions: suggestions(for: typed, extraNames: knownNames)))
        }
    }

    /// Runs a parsed invocation.
    public static func runResult(
        _ invocation: Invocation,
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        now: Date = Date(),
        knownNames: [String] = []
    ) -> Result<Edit, CommandError> {
        runResult(
            name: invocation.name,
            arguments: invocation.arguments,
            rawArgument: invocation.hasParenthesisedArgs ? invocation.rawArgument : nil,
            tokenRange: tokenRange,
            fullText: fullText,
            selection: selection,
            now: now,
            knownNames: knownNames
        )
    }

    /// Runs a command. `now` is injected for deterministic tests.
    /// Returns nil for unknown/invalid commands; prefer `runResult` so the
    /// user hears why.
    public static func run(
        name: String,
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        now: Date = Date()
    ) -> Edit? {
        try? runResult(name: name, tokenRange: tokenRange, fullText: fullText,
                       selection: selection, now: now).get()
    }

    // MARK: - Diagnostics (gutter)

    public struct LineDiagnostic: Equatable, Sendable {
        /// Zero-based line index in the note text.
        public var line: Int
        public var message: String
        public init(line: Int, message: String) {
            self.line = line
            self.message = message
        }
    }

    /// One diagnostic per line for `::tokens` that name no builtin, alias,
    /// or installed JS extension. A token that is a strict prefix of a
    /// known command (`::tod` while typing `::today`) is left alone — the
    /// completion popup owns that state.
    public static func diagnostics(in text: String, extensions: [JSExtension.Script] = []) -> [LineDiagnostic] {
        let extensionNames = extensions.map { $0.commandName.lowercased() }
        let known = Set(builtins.map(\.name) + aliases.keys + extensionNames)
        var out: [LineDiagnostic] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let chars = Array(line)
            var i = 0
            while i + 1 < chars.count {
                guard chars[i] == ":", chars[i + 1] == ":" else { i += 1; continue }
                if i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == ":" {
                    i += 2
                    continue
                }
                var j = i + 2
                while j < chars.count, chars[j].isCommandChar { j += 1 }
                guard j > i + 2 else { i += 2; continue }
                let name = String(chars[(i + 2)..<j]).lowercased()
                i = j
                if known.contains(name) { continue }
                if known.contains(where: { $0.hasPrefix(name) }) { continue }
                let error = CommandError.unknownCommand(
                    name: name,
                    suggestions: suggestions(for: name, extraNames: extensionNames)
                )
                out.append(LineDiagnostic(line: index, message: error.gutterMessage))
                break
            }
        }
        return out
    }

    /// Gutter text per note line ("" where the line is fine), aligned with
    /// `text.components(separatedBy: "\n")`.
    public static func gutterLines(in text: String, extensions: [JSExtension.Script] = []) -> [String] {
        var lines = [String](repeating: "", count: text.components(separatedBy: "\n").count)
        for diagnostic in diagnostics(in: text, extensions: extensions) where lines.indices.contains(diagnostic.line) {
            lines[diagnostic.line] = diagnostic.message
        }
        return lines
    }

    // MARK: - Dates

    static var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    public static func isoDate(_ date: Date) -> String {
        formatted(date, format: "yyyy-MM-dd", timeZone: utc)
    }

    public static func localDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func formatted(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    static func shiftedDay(_ date: Date, by days: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = utc
        return cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    // MARK: - Command helpers

    static func randomValue(arguments: [String]) -> Result<String, CommandError> {
        func invalid(_ message: String) -> Result<String, CommandError> {
            .failure(.invalidArguments(command: "random", message: message))
        }
        if arguments.isEmpty { return .success(String(Int.random(in: 1...100))) }
        let doubles = arguments.map { Double($0).flatMap { $0.isFinite ? $0 : nil } }
        if arguments.count <= 2, doubles.allSatisfy({ $0 != nil }) {
            let values = doubles.compactMap { $0 }
            let ints = arguments.map { Int($0) }
            if ints.allSatisfy({ $0 != nil }) {
                let nums = ints.compactMap { $0 }
                if nums.count == 1 {
                    guard nums[0] >= 1 else { return invalid("random(max): max must be at least 1, got \(nums[0])") }
                    return .success(String(Int.random(in: 1...nums[0])))
                }
                guard nums[0] <= nums[1] else { return invalid("min \(nums[0]) is greater than max \(nums[1])") }
                return .success(String(Int.random(in: nums[0]...nums[1])))
            }
            if values.count == 1 {
                guard values[0] > 0 else { return invalid("random(max): max must be above 0, got \(arguments[0])") }
                return .success(formatDouble(Double.random(in: 0...values[0])))
            }
            guard values[0] <= values[1] else { return invalid("min \(arguments[0]) is greater than max \(arguments[1])") }
            return .success(formatDouble(Double.random(in: values[0]...values[1])))
        }
        if arguments.count >= 2, doubles.allSatisfy({ $0 == nil }) {
            return .success(arguments.randomElement() ?? arguments[0])
        }
        return invalid("use random, random(max), random(min, max), or random(a, b, c) to pick one")
    }

    static func formatDouble(_ value: Double) -> String {
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text = String(text.dropLast()) }
        if text.hasSuffix(".") { text = String(text.dropLast()) }
        return text
    }

    static func countText(arguments: [String], rawArgument: String?, tokenRange: Range<Int>?, fullText: String) -> String {
        let metrics = ["lines", "words", "chars", "characters"]
        let bufferStats = { () -> NoteStats in
            let (stripped, _) = removingToken(fullText: fullText, range: tokenRange, selection: nil)
            return NoteStats.compute(for: bodyDroppingTrigger(stripped))
        }
        if arguments.count == 1, metrics.contains(arguments[0].lowercased()) {
            let stats = bufferStats()
            switch arguments[0].lowercased() {
            case "lines": return String(stats.lines)
            case "words": return String(stats.words)
            default: return String(stats.characters)
            }
        }
        if let raw = rawArgument, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let stats = NoteStats.compute(for: unquote(raw.trimmingCharacters(in: .whitespaces)))
            return "\(stats.lines) lines · \(stats.words) words · \(stats.characters) chars"
        }
        let stats = bufferStats()
        return "\(stats.lines) lines · \(stats.words) words · \(stats.characters) chars"
    }

    /// Text without a pinned trigger first line (`math`, `list`, …).
    static func bodyDroppingTrigger(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, lines.count > 1,
              NoteKind(trigger: first.trimmingCharacters(in: .whitespaces).lowercased()) != .plain else { return text }
        return lines.dropFirst().joined(separator: "\n")
    }

    static func titleCased(_ text: String) -> String {
        var out = ""
        var wordStart = true
        for c in text {
            if c.isLetter {
                out += wordStart ? String(c).uppercased() : String(c).lowercased()
                wordStart = false
            } else {
                out.append(c)
                if !c.isNumber { wordStart = true }
            }
        }
        return out
    }

    static func prettyJSON(_ text: String, command: String) -> Result<String, CommandError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.failed(command: command, message: "input is empty — nothing to format as JSON"))
        }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])
            guard object is [String: Any] || object is [Any] else { return .success(trimmed) }
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return .success(String(decoding: data, as: UTF8.self))
        } catch {
            return .failure(.failed(command: command, message: "invalid JSON: \((error as NSError).localizedDescription)"))
        }
    }

    // MARK: - Buffer transforms

    /// Removes the `::token` from the buffer (its whole line when it sits
    /// alone on one) and shifts/clamps the selection to match.
    static func removingToken(fullText: String, range: Range<Int>?, selection: Range<Int>?) -> (String, Range<Int>?) {
        let chars = Array(fullText)
        guard let range, range.lowerBound >= 0, range.upperBound <= chars.count, range.lowerBound <= range.upperBound else {
            return (fullText, selection)
        }
        var lineStart = range.lowerBound
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = range.upperBound
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }
        let before = chars[lineStart..<range.lowerBound]
        let after = chars[range.upperBound..<lineEnd]
        let removal: Range<Int>
        if before.allSatisfy({ $0.isWhitespace }), after.allSatisfy({ $0.isWhitespace }) {
            if lineEnd < chars.count {
                removal = lineStart..<(lineEnd + 1)
            } else if lineStart > 0 {
                removal = (lineStart - 1)..<lineEnd
            } else {
                removal = lineStart..<lineEnd
            }
        } else {
            removal = range
        }
        var kept = chars
        kept.removeSubrange(removal)
        var adjusted: Range<Int>?
        if let selection {
            if selection.upperBound <= removal.lowerBound {
                adjusted = selection
            } else if selection.lowerBound >= removal.upperBound {
                let shift = removal.upperBound - removal.lowerBound
                adjusted = (selection.lowerBound - shift)..<(selection.upperBound - shift)
            } else {
                adjusted = nil
            }
        }
        return (String(kept), adjusted)
    }

    /// Applies `transform` to the selected lines, or to the whole body
    /// (trigger first line pinned) when nothing is selected.
    static func transformedLines(fullText: String, selection: Range<Int>?, transform: ([String]) -> [String]) -> String {
        var lines = fullText.components(separatedBy: "\n")
        var target: Range<Int>?
        if let sel = selection, sel.lowerBound < sel.upperBound {
            var pos = 0
            var first: Int?
            var last: Int?
            for (i, line) in lines.enumerated() {
                let lineRange = pos..<(pos + line.count)
                if lineRange.overlaps(sel) || lineRange.upperBound == sel.lowerBound {
                    if first == nil { first = i }
                    last = i
                }
                pos += line.count + 1
            }
            if let first, let last { target = first..<(last + 1) }
        }
        if let target {
            lines.replaceSubrange(target, with: transform(Array(lines[target])))
        } else if let first = lines.first, lines.count > 1,
                  NoteKind(trigger: first.trimmingCharacters(in: .whitespaces).lowercased()) != .plain {
            lines = [lines[0]] + transform(Array(lines.dropFirst()))
        } else {
            lines = transform(lines)
        }
        return lines.joined(separator: "\n")
    }

    /// Sorts the selected lines, or the whole body when nothing is selected.
    static func sorted(fullText: String, selection: Range<Int>?) -> String {
        transformedLines(fullText: fullText, selection: selection) { lines in
            lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    static func lineTransform(
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        transform: ([String]) -> [String]
    ) -> Result<Edit, CommandError> {
        let (stripped, adjusted) = removingToken(fullText: fullText, range: tokenRange, selection: selection)
        let result = transformedLines(fullText: stripped, selection: adjusted, transform: transform)
        return .success(Edit(tokenRange: nil, replacement: "", fullText: result))
    }

    /// Source precedence for text commands: parenthesised text replaces the
    /// token; a selection is replaced in place; otherwise `wholeBuffer`
    /// commands transform the note body (trigger line pinned) and the rest
    /// report that they need text.
    static func textTransform(
        command: String,
        rawArgument: String?,
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        wholeBuffer: Bool,
        transform: (String) -> Result<String, CommandError>
    ) -> Result<Edit, CommandError> {
        if let raw = rawArgument, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let value = unquote(raw.trimmingCharacters(in: .whitespaces))
            return transform(value).map { Edit(tokenRange: tokenRange, replacement: $0, fullText: nil) }
        }
        let (stripped, adjusted) = removingToken(fullText: fullText, range: tokenRange, selection: selection)
        let chars = Array(stripped)
        if let sel = adjusted, sel.lowerBound < sel.upperBound, sel.upperBound <= chars.count {
            let selected = String(chars[sel])
            return transform(selected).map { replacement in
                var updated = chars
                updated.replaceSubrange(sel, with: Array(replacement))
                return Edit(tokenRange: nil, replacement: "", fullText: String(updated))
            }
        }
        guard wholeBuffer else {
            return .failure(.invalidArguments(
                command: command,
                message: "needs text — use ::\(command)(some text) or select text first"
            ))
        }
        let lines = stripped.components(separatedBy: "\n")
        if let first = lines.first, lines.count > 1,
           NoteKind(trigger: first.trimmingCharacters(in: .whitespaces).lowercased()) != .plain {
            let body = lines.dropFirst().joined(separator: "\n")
            return transform(body).map { Edit(tokenRange: nil, replacement: "", fullText: first + "\n" + $0) }
        }
        return transform(stripped).map { Edit(tokenRange: nil, replacement: "", fullText: $0) }
    }
}

private extension Character {
    var isCommandChar: Bool { isLetter || isNumber || self == "_" || self == "-" }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
