import Foundation

/// Lightweight per-block syntax highlighting for `code` snippet buffers.
///
/// Domain-pure tokenizer: the editor asks for the code blocks in a note and
/// colors the returned spans. Blocks are fenced (```lang … ```) regions in
/// any note, or — in a `code`-mode note with no fences — the whole body as a
/// single block with an inferred language. Identifier roles are heuristic;
/// this lexer does not parse types or interpolation.
public enum CodeHighlight: Sendable {
    public enum Language: String, Equatable, Sendable, CaseIterable {
        case swift
        case python
        case javascript
        case shell
        case generic

        /// Maps a fence tag (`swift`, `py`, `js`, `sh`, …) to a language.
        /// Unknown or empty tags fall back to `.generic`.
        public init(fenceTag: String) {
            switch fenceTag.trimmingCharacters(in: .whitespaces).lowercased() {
            case "swift": self = .swift
            case "python", "py": self = .python
            case "javascript", "js", "typescript", "ts": self = .javascript
            case "shell", "sh", "bash", "zsh": self = .shell
            default: self = .generic
            }
        }

        var lineCommentPrefixes: [String] {
            switch self {
            case .swift, .javascript: ["//"]
            case .python, .shell: ["#"]
            case .generic: ["//", "#"]
            }
        }

        var allowsBlockComments: Bool { self != .python && self != .shell }

        var keywords: Set<String> {
            switch self {
            case .swift:
                ["associatedtype", "break", "case", "catch", "class", "continue",
                 "default", "defer", "do", "else", "enum", "extension", "fallthrough",
                 "false", "for", "func", "guard", "if", "import", "in", "init",
                 "inout", "let", "nil", "private", "protocol", "public", "repeat",
                 "return", "self", "static", "struct", "switch", "throw", "throws",
                 "true", "try", "typealias", "var", "where", "while"]
            case .python:
                ["and", "as", "assert", "async", "await", "break", "class", "continue",
                 "def", "elif", "else", "except", "False", "finally", "for", "from",
                 "global", "if", "import", "in", "is", "lambda", "None", "nonlocal",
                 "not", "or", "pass", "raise", "return", "True", "try", "while",
                 "with", "yield"]
            case .javascript:
                ["async", "await", "break", "case", "catch", "class", "const",
                 "continue", "default", "do", "else", "export", "extends", "false",
                 "finally", "for", "from", "function", "if", "import", "in", "let",
                 "new", "null", "of", "return", "static", "switch", "this", "throw",
                 "true", "try", "typeof", "undefined", "var", "void", "while", "yield"]
            case .shell:
                ["case", "do", "done", "echo", "elif", "else", "esac", "exit",
                 "export", "false", "fi", "for", "function", "if", "in", "local",
                 "return", "set", "source", "then", "true", "while"]
            case .generic:
                Language.swift.keywords
                    .union(Language.python.keywords)
                    .union(Language.javascript.keywords)
                    .union(Language.shell.keywords)
            }
        }
    }

    public enum TokenKind: Equatable, Sendable {
        case keyword
        case string
        case comment
        case number
        case type
        case function
        case identifier
    }

    public struct Token: Equatable, Sendable {
        public var kind: TokenKind
        public var range: Range<String.Index>

        public init(kind: TokenKind, range: Range<String.Index>) {
            self.kind = kind
            self.range = range
        }
    }

    /// One highlightable region: its content range (fence lines excluded)
    /// and the language to tokenize it as.
    public struct Block: Equatable, Sendable {
        public var range: Range<String.Index>
        public var language: Language

        public init(range: Range<String.Index>, language: Language) {
            self.range = range
            self.language = language
        }
    }

    // MARK: - Block detection

    /// Fenced code blocks in any text. An unclosed fence runs to the end.
    public static func blocks(in text: String) -> [Block] {
        var blocks: [Block] = []
        var cursor = text.startIndex
        var open: (contentStart: String.Index, language: Language)?
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            if trimmed.hasPrefix("```") {
                if let current = open {
                    // Close: content ends where this fence line starts,
                    // minus the newline that precedes it.
                    var end = cursor
                    if end > current.contentStart, text[text.index(before: end)] == "\n" {
                        end = text.index(before: end)
                    }
                    blocks.append(Block(range: current.contentStart..<end, language: current.language))
                    open = nil
                } else {
                    open = (next, Language(fenceTag: String(trimmed.dropFirst(3))))
                }
            }
            cursor = next
        }
        if let current = open {
            var end = text.endIndex
            if end > current.contentStart, text[text.index(before: end)] == "\n" {
                end = text.index(before: end)
            }
            blocks.append(Block(range: current.contentStart..<end, language: current.language))
        }
        return blocks
    }

    /// Blocks for a note: fenced blocks if present, otherwise a `code`-mode
    /// note's whole body as one inferred-language block. Plain notes with no
    /// fences get nothing.
    public static func blocks(for note: ContextNote) -> [Block] {
        let fenced = blocks(in: note.text)
        if !fenced.isEmpty { return fenced }
        guard note.kind == .code else { return [] }
        let body = note.bodyWithoutTrigger
        guard !body.isEmpty, let start = note.text.range(of: body)?.lowerBound else { return [] }
        return [Block(range: start..<note.text.index(start, offsetBy: body.count), language: detect(body))]
    }

    /// Persist a language in the opening fence of the block under the source caret.
    /// Unfenced code notes are wrapped, keeping the trigger and body intact.
    public static func choosing(_ language: Language, in note: ContextNote, caret: Int) -> String {
        let text = note.text
        let blocks = blocks(in: text)
        if let block = blocks.first(where: {
            let range = NSRange($0.range, in: text)
            return caret >= range.location && caret <= range.location + range.length
        }) {
            let prefix = text[..<block.range.lowerBound]
            let end = prefix.index(before: prefix.endIndex)
            let start = prefix[..<end].lastIndex(of: "\n").map { prefix.index(after: $0) } ?? prefix.startIndex
            return text.replacingCharacters(in: start..<end, with: "```" + language.rawValue)
        }
        guard blocks.isEmpty, note.kind == .code else { return text }
        return "code\n```" + language.rawValue + "\n" + note.bodyWithoutTrigger + "\n```"
    }

    /// All highlighted tokens for a note, in document order.
    public static func tokens(for note: ContextNote) -> [Token] {
        blocks(for: note).flatMap { tokens(in: note.text, range: $0.range, language: $0.language) }
    }

    /// Best-effort language guess for an unfenced `code` body.
    public static func detect(_ text: String) -> Language {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("#!") {
            let firstLine = head.components(separatedBy: .newlines).first ?? ""
            if firstLine.contains("python") { return .python }
            if firstLine.contains("node") { return .javascript }
            return .shell
        }
        // Score each language by its distinctive markers; highest wins.
        let markers: [(Language, [String])] = [
            (.swift, ["func ", "guard ", "import Foundation", "import SwiftUI", "-> ", "@State", "struct ", "let ", "var "]),
            (.python, ["def ", "import ", "from ", "print(", "elif ", "self.", "__init__", "None"]),
            (.javascript, ["const ", "=>", "function ", "console.log", "require(", "export ", "let ", "var "]),
            (.shell, ["echo ", "export ", "#!/bin", "fi\n", "done\n", "set -e"]),
        ]
        var best: (Language, Int) = (.generic, 0)
        for (language, needles) in markers {
            let score = needles.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            if score > best.1 { best = (language, score) }
        }
        return best.0
    }

    // MARK: - Tokenizer

    /// Keyword/string/comment/number spans within `range` of `text`.
    /// Ranges are in terms of `text` so callers can map them directly.
    public static func tokens(in text: String, range: Range<String.Index>? = nil, language: Language) -> [Token] {
        let range = range ?? text.startIndex..<text.endIndex
        let keywords = language.keywords
        var tokens: [Token] = []
        var i = range.lowerBound

        func peek(_ offset: Int = 0) -> Character? {
            guard let idx = text.index(i, offsetBy: offset, limitedBy: range.upperBound),
                  idx < range.upperBound else { return nil }
            return text[idx]
        }
        func starts(with prefix: String) -> Bool {
            text[i...].hasPrefix(prefix) && text.index(i, offsetBy: prefix.count, limitedBy: range.upperBound) != nil
        }

        while i < range.upperBound {
            let ch = text[i]

            // Comments win over everything at the same position.
            if language.allowsBlockComments, starts(with: "/*") {
                let start = i
                i = text.index(i, offsetBy: 2)
                while i < range.upperBound, !starts(with: "*/") { i = text.index(after: i) }
                if i < range.upperBound { i = text.index(i, offsetBy: 2) }
                tokens.append(Token(kind: .comment, range: start..<i))
                continue
            }
            if let prefix = language.lineCommentPrefixes.first(where: { starts(with: $0) }) {
                // In shell/generic, `#` mid-word (e.g. `a#b`) is not a comment.
                let blockedByWord = prefix == "#"
                    && i > range.lowerBound
                    && !text[text.index(before: i)].isWhitespace
                if !blockedByWord {
                    let start = i
                    while i < range.upperBound, text[i] != "\n" { i = text.index(after: i) }
                    tokens.append(Token(kind: .comment, range: start..<i))
                    continue
                }
            }

            // Strings: triple quotes (python), then single-line quotes.
            if language == .python || language == .generic,
               starts(with: "\"\"\"") || starts(with: "'''") {
                let quote = starts(with: "\"\"\"") ? "\"\"\"" : "'''"
                let start = i
                i = text.index(i, offsetBy: 3)
                while i < range.upperBound, !starts(with: quote) { i = text.index(after: i) }
                if i < range.upperBound { i = text.index(i, offsetBy: 3) }
                tokens.append(Token(kind: .string, range: start..<i))
                continue
            }
            if ch == "\"" || ch == "'" || (ch == "`" && (language == .javascript || language == .generic)) {
                let start = i
                let multiline = ch == "`" // JS template literals may span lines.
                i = text.index(after: i)
                while i < range.upperBound {
                    let c = text[i]
                    if c == "\\", ch != "'" || language != .shell {
                        i = text.index(i, offsetBy: 2, limitedBy: range.upperBound) ?? range.upperBound
                        continue
                    }
                    if c == ch { i = text.index(after: i); break }
                    if c == "\n", !multiline { break } // unterminated: stop at EOL
                    i = text.index(after: i)
                }
                tokens.append(Token(kind: .string, range: start..<i))
                continue
            }

            // Numbers: hex/binary or decimal with fraction/exponent. Must not
            // be glued to a preceding identifier character (`sha256`).
            if ch.isNumber, i == range.lowerBound || !isIdentChar(text[text.index(before: i)]) {
                let start = i
                if starts(with: "0x") || starts(with: "0X") || starts(with: "0b") || starts(with: "0B") {
                    i = text.index(i, offsetBy: 2)
                    while i < range.upperBound, text[i].isHexDigit || text[i] == "_" { i = text.index(after: i) }
                } else {
                    var sawDot = false
                    while i < range.upperBound {
                        let c = text[i]
                        if c.isNumber || c == "_" { i = text.index(after: i); continue }
                        // A dot joins only when a digit follows (`1.5`, not `1.toString`).
                        if c == ".", !sawDot, let next = peek(1), next.isNumber {
                            sawDot = true
                            i = text.index(after: i)
                            continue
                        }
                        if c == "e" || c == "E", let next = peek(1), next.isNumber || next == "+" || next == "-" {
                            i = text.index(i, offsetBy: next.isNumber ? 1 : 2, limitedBy: range.upperBound) ?? range.upperBound
                            continue
                        }
                        break
                    }
                }
                tokens.append(Token(kind: .number, range: start..<i))
                continue
            }

            // Words: keyword when the whole identifier matches.
            if ch.isLetter || ch == "_" {
                let start = i
                while i < range.upperBound, isIdentChar(text[i]) { i = text.index(after: i) }
                let word = String(text[start..<i])
                let next = text[i..<range.upperBound].drop(while: { $0 == " " || $0 == "\t" }).first
                let kind: TokenKind = keywords.contains(word) ? .keyword
                    : next == "(" ? .function
                    : language != .shell && ch.isUppercase ? .type : .identifier
                tokens.append(Token(kind: kind, range: start..<i))
                continue
            }

            i = text.index(after: i)
        }
        return tokens
    }

    private static func isIdentChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }
}
