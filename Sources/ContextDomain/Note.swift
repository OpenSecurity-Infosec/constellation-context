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

/// Plain-text sanitizer: strips rich text, bullets, numbering, leading whitespace.
public enum PlainText {
    public static func sanitize(_ input: String) -> String {
        let lines = input.components(separatedBy: .newlines).map { line -> String in
            var out = line
            // Strip common bullet/number prefixes: "- ", "* ", "• ", "1. ", "1) ".
            if let range = out.range(of: #"^[\s>]*([-*•‣▪]|(\d+[.)]))\s+"#, options: .regularExpression) {
                out.removeSubrange(range)
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    public static func sanitizePasteboard(_ input: String) -> String {
        sanitize(input)
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
