import Foundation

/// A single scratch note. Plain text only — formatting is stripped on paste.
public struct ContextNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?
    public var expiresAt: Date?

    public init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        trashedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
        self.expiresAt = expiresAt
    }

    public var isTrashed: Bool { trashedAt != nil }

    public var firstLine: String {
        text.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    public var kind: NoteKind { NoteKind(trigger: firstLine) }

    /// Body without the trigger line, when a trigger is present.
    public var bodyWithoutTrigger: String {
        guard kind != .plain else { return text }
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return text }
        lines.removeFirst()
        // Drop one blank line after the trigger for a cleaner buffer.
        if lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }
}

/// First-line magic words, mirroring Antinote's trigger vocabulary.
public enum NoteKind: String, Equatable, Sendable {
    case plain
    case math
    case sum
    case avg
    case count
    case list
    case code
    case timer
    case paste

    public init(trigger: String) {
        switch trigger {
        case "math": self = .math
        case "sum": self = .sum
        case "avg", "average": self = .avg
        case "count": self = .count
        case "list": self = .list
        case "code": self = .code
        case "timer": self = .timer
        case "paste": self = .paste
        default: self = .plain
        }
    }

    public var triggerWord: String? {
        switch self {
        case .plain: nil
        case .math: "math"
        case .sum: "sum"
        case .avg: "avg"
        case .count: "count"
        case .list: "list"
        case .code: "code"
        case .timer: "timer"
        case .paste: "paste"
        }
    }
}

/// Plain-text sanitizer: strips rich text, bullets, numbering, table grid
/// junk, and HTML entities. Preserves relative indentation (tabs become two
/// spaces) so pasted nested lists keep their nesting for checklist parse.
public enum PlainText {
    public static func sanitize(_ input: String) -> String {
        // Normalize line endings and tabs first.
        var text = input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "  ")
        text = decodeHTMLEntities(text)
        text = normalizeSmartPunctuation(text)
        let rawLines = text.components(separatedBy: .newlines)
        // Drop markdown table delimiter rows entirely (they join as blanks).
        let lines = rawLines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            let isDelimiter = t.range(of: #"^\|?[\s:\-|]+\|?$"#, options: .regularExpression) != nil && t.contains("-")
            return !isDelimiter
        }.map { line -> String in
            var out = line
            // Strip quote markers; keep the indent that follows them.
            if let range = out.range(of: #"^(?:\s*>)+\s?"#, options: .regularExpression) {
                out.removeSubrange(range)
            }
            // Markdown tables: unwrap cell pipes into spaced text.
            let trimmed = out.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                let cells = trimmed.dropFirst().dropLast().split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let indent = String(out.prefix(while: { $0 == " " }))
                return cells.isEmpty ? "" : indent + cells.joined(separator: "  ")
            }
            // Strip bullet/number prefixes but keep leading indent.
            if let range = out.range(of: #"^(\s*)(?:[-*•‣▪‣◦▪–—]|(\d+[.)])|(\[.\]))\s+"#, options: .regularExpression) {
                let indent = String(out[range].prefix(while: { $0 == " " }))
                out.removeSubrange(range)
                out = indent + out
            }
            // Trim trailing whitespace and NBSP only; leading indent is kept.
            while out.last == " " || out.last == "\u{00A0}" { out.removeLast() }
            return out
        }
        // Collapse blank runs to a single blank line; drop leading/trailing blanks.
        var collapsed: [String] = []
        var blanks = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks <= 1 { collapsed.append("") }
            } else {
                blanks = 0
                collapsed.append(line)
            }
        }
        while collapsed.first == "" { collapsed.removeFirst() }
        while collapsed.last == "" { collapsed.removeLast() }
        return collapsed.joined(separator: "\n")
    }

    public static func sanitizePasteboard(_ input: String) -> String {
        sanitize(input)
    }

    /// Decodes common HTML entities left behind by web-app paste.
    static func decodeHTMLEntities(_ s: String) -> String {
        var out = s
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
            "&hellip;": "…", "&copy;": "©", "&reg;": "®",
        ]
        for (entity, char) in named { out = out.replacingOccurrences(of: entity, with: char) }
        // Numeric entities: &#39; and &#x27;.
        while let range = out.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let digits = out[range].filter(\.isNumber)
            if let code = UInt32(digits), let scalar = UnicodeScalar(code) {
                out.replaceSubrange(range, with: String(scalar))
            } else {
                break
            }
        }
        while let range = out.range(of: #"&#x([0-9a-fA-F]+);"#, options: .regularExpression) {
            let hex = out[range].replacingOccurrences(of: "&#x", with: "")
                .replacingOccurrences(of: ";", with: "")
            if let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) {
                out.replaceSubrange(range, with: String(scalar))
            } else {
                break
            }
        }
        return out
    }

    /// Normalizes smart quotes/dashes/ellipsis to ASCII plain text.
    static func normalizeSmartPunctuation(_ s: String) -> String {
        s.replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "…", with: "...")
    }
}

/// Stats for `count` notes.
public struct NoteStats: Equatable, Sendable {
    public var lines: Int
    public var words: Int
    public var characters: Int

    public static func compute(for text: String) -> NoteStats {
        let activeLines = text.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("//")
        }
        let words = activeLines.flatMap { $0.split(whereSeparator: \.isWhitespace) }.count
        let chars = activeLines.joined(separator: "\n").count
        return NoteStats(lines: activeLines.count, words: words, characters: chars)
    }
}
