import Foundation

/// A Markdown file split into its YAML frontmatter block and body.
///
/// Round-trips are byte-identical: `text` reassembles exactly what was
/// parsed. Edits through `setValue` touch only the named key's lines and
/// leave every other byte of the header alone (ADR-0001).
public struct MarkdownDocument: Equatable, Sendable {
    /// The full header including both `---` fences and the newline after
    /// the closing fence. Nil when the file has no frontmatter.
    public private(set) var header: String?
    public var body: String

    public init(header: String? = nil, body: String) {
        self.header = header
        self.body = body
    }

    public init(parsing text: String) {
        guard let split = Self.splitHeader(text) else {
            header = nil
            body = text
            return
        }
        header = split.header
        body = split.body
    }

    public var text: String { (header ?? "") + body }

    /// Raw YAML between the fences, without the fences.
    public var yaml: String? {
        guard let header else { return nil }
        let lines = Self.lines(header)
        guard lines.count >= 2 else { return "" }
        return lines.dropFirst().dropLast().map(\.content).joined(separator: "\n")
    }

    // MARK: - Reading

    /// Top-level scalar value for `key`, with surrounding quotes removed.
    /// Lists come back joined with ", "; use `list(for:)` for elements.
    public func value(for key: String) -> String? {
        guard let entry = entries().first(where: { $0.key == key }) else { return nil }
        switch entry.value {
        case .scalar(let s): return s
        case .list(let items): return items.joined(separator: ", ")
        }
    }

    public func list(for key: String) -> [String] {
        guard let entry = entries().first(where: { $0.key == key }) else { return [] }
        switch entry.value {
        case .scalar(let s): return s.isEmpty ? [] : [s]
        case .list(let items): return items
        }
    }

    public var keys: [String] { entries().map(\.key) }

    /// Tags from frontmatter (`tags:`) plus inline `#tags` in the body.
    public var tags: [String] {
        var out: [String] = list(for: "tags").map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        let pattern = #"(?:^|\s)#([A-Za-z][\w/-]*)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = body as NSString
            for match in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                out.append(ns.substring(with: match.range(at: 1)))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// First non-empty body line with leading `#` heading marks removed.
    public var title: String {
        for line in body.components(separatedBy: .newlines) {
            var t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            while t.hasPrefix("#") { t.removeFirst() }
            return t.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // MARK: - Editing

    /// Sets, replaces, or (with nil) removes one top-level key. Other keys,
    /// comments, ordering, and the fence lines are preserved exactly.
    public mutating func setValue(_ value: String?, for key: String) {
        let rendered = value.map { "\(key): \(Self.quoteIfNeeded($0))" }
        replaceEntry(key: key, with: rendered.map { [$0] })
    }

    public mutating func setList(_ items: [String]?, for key: String) {
        let rendered = items.map { list -> [String] in
            list.isEmpty ? ["\(key): []"] : ["\(key):"] + list.map { "  - \(Self.quoteIfNeeded($0))" }
        }
        replaceEntry(key: key, with: rendered)
    }

    private mutating func replaceEntry(key: String, with newLines: [String]?) {
        guard let header else {
            guard let newLines else { return }
            self.header = "---\n" + newLines.joined(separator: "\n") + "\n---\n"
            return
        }
        var lines = Self.lines(header)
        guard lines.count >= 2 else { return }
        let newline = lines[0].terminator.isEmpty ? "\n" : lines[0].terminator
        let inner = Array(lines[1..<(lines.count - 1)])
        let spans = Self.spans(inner.map(\.content))
        let replacement = (newLines ?? []).map { Line(content: $0, terminator: newline) }
        if let span = spans.first(where: { $0.key == key }) {
            lines.replaceSubrange((span.start + 1)...(span.end + 1), with: replacement)
        } else if !replacement.isEmpty {
            lines.insert(contentsOf: replacement, at: lines.count - 1)
        }
        self.header = lines.map { $0.content + $0.terminator }.joined()
    }

    // MARK: - Parsing

    struct Line: Equatable {
        var content: String
        var terminator: String
    }

    enum Value: Equatable {
        case scalar(String)
        case list([String])
    }

    struct Entry: Equatable {
        var key: String
        var value: Value
    }

    struct Span {
        var key: String
        var start: Int
        var end: Int
    }

    func entries() -> [Entry] {
        guard let yaml else { return [] }
        let lines = yaml.components(separatedBy: "\n")
        return Self.spans(lines).compactMap { span in
            let first = lines[span.start]
            guard let colon = first.firstIndex(of: ":") else { return nil }
            let rest = first[first.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                let items = lines[(span.start + 1)...span.end].compactMap { line -> String? in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("- ") || t == "-" else { return nil }
                    return Self.unquote(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                }
                return Entry(key: span.key, value: items.isEmpty ? .scalar("") : .list(items))
            }
            if rest.hasPrefix("["), rest.hasSuffix("]") {
                let items = rest.dropFirst().dropLast().split(separator: ",")
                    .map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
                return Entry(key: span.key, value: .list(items))
            }
            return Entry(key: span.key, value: .scalar(Self.unquote(rest)))
        }
    }

    /// Top-level keys and the line range each one covers (its key line
    /// plus any indented continuation lines).
    static func spans(_ lines: [String]) -> [Span] {
        var spans: [Span] = []
        for (i, line) in lines.enumerated() {
            let isTopLevel = !(line.first?.isWhitespace ?? true) && !line.hasPrefix("#") && !line.hasPrefix("-")
            if isTopLevel, let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                spans.append(Span(key: key, start: i, end: i))
            } else if !spans.isEmpty, line.first?.isWhitespace == true || line.hasPrefix("-") {
                spans[spans.count - 1].end = i
            }
        }
        return spans
    }

    static func splitHeader(_ text: String) -> (header: String, body: String)? {
        let lines = Self.lines(text)
        guard let first = lines.first, first.content == "---", !first.terminator.isEmpty else { return nil }
        for i in 1..<lines.count where lines[i].content == "---" || lines[i].content == "..." {
            let header = lines[0...i].map { $0.content + $0.terminator }.joined()
            let body = String(text.dropFirst(header.count))
            return (header, body)
        }
        return nil
    }

    /// Splits keeping each line's exact terminator ("\n", "\r\n", or "").
    static func lines(_ text: String) -> [Line] {
        var out: [Line] = []
        var current = ""
        var iterator = text.makeIterator()
        while let ch = iterator.next() {
            if ch == "\n" {
                out.append(Line(content: current, terminator: "\n"))
                current = ""
            } else if ch == "\r\n" {
                out.append(Line(content: current, terminator: "\r\n"))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(Line(content: current, terminator: "")) }
        return out
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    static func quoteIfNeeded(_ s: String) -> String {
        let special = CharacterSet(charactersIn: ":#[]{},&*!|>'\"%@`")
        let needs = s.isEmpty || s.unicodeScalars.contains { special.contains($0) }
            || s.hasPrefix(" ") || s.hasSuffix(" ") || s.hasPrefix("-")
        guard needs else { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
