import Foundation

/// Native `::` extension commands. Domain-pure registry: AppKit feeds the
/// caret/token context, the registry returns the text edit to apply.
/// A full JS runtime can plug into this same shape later.
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

    public static let builtins: [Definition] = [
        Definition(name: "today", hint: "Insert ISO date"),
        Definition(name: "now", hint: "Insert local date + time"),
        Definition(name: "sort_lines", hint: "Sort lines A–Z"),
        Definition(name: "uuid", hint: "Insert a UUID"),
    ]

    /// Token under the caret: `::` prefix plus word chars. Returns the token
    /// text and its integer range, or nil when the caret is not on one.
    public static func token(at caret: Int, in text: String) -> (token: String, range: Range<Int>)? {
        let chars = Array(text)
        guard caret >= 0, caret <= chars.count else { return nil }
        var start = caret
        while start > 1, chars[start - 1].isCommandChar, !(chars[start - 2] == ":" && chars[start - 1] == ":") {
            start -= 1
            if start >= 2, chars[start - 2] == ":", chars[start - 1] == ":" { break }
        }
        // Rewind to the `::` opener.
        var opener: Int?
        var i = min(start, chars.count)
        while i >= 2 {
            if chars[i - 2] == ":", chars[i - 1] == ":" {
                // The char before `::` must not be a word char.
                if i - 3 < 0 || !chars[i - 3].isLetter && !chars[i - 3].isNumber {
                    opener = i - 2
                    break
                }
            }
            i -= 1
        }
        guard let open = opener else { return nil }
        var end = open + 2
        while end < chars.count, chars[end].isCommandChar { end += 1 }
        guard caret >= open, caret <= end else { return nil }
        let token = String(chars[open..<end])
        guard token.hasPrefix("::"), token.count > 2 else { return nil }
        return (token, open..<end)
    }

    /// Filtered completions for a `::` prefix fragment (without the colons).
    public static func completions(matching fragment: String) -> [Definition] {
        let lower = fragment.lowercased()
        return builtins.filter { lower.isEmpty || $0.name.lowercased().hasPrefix(lower) }
    }

    /// Runs a command. `now` is injected for deterministic tests.
    public static func run(
        name: String,
        tokenRange: Range<Int>?,
        fullText: String,
        selection: Range<Int>?,
        now: Date = Date()
    ) -> Edit? {
        switch name.lowercased() {
        case "today":
            return Edit(tokenRange: tokenRange, replacement: isoDate(now), fullText: nil)
        case "now":
            return Edit(tokenRange: tokenRange, replacement: localDateTime(now), fullText: nil)
        case "uuid":
            return Edit(tokenRange: tokenRange, replacement: UUID().uuidString.lowercased(), fullText: nil)
        case "sort_lines", "sort-lines", "sort":
            return Edit(tokenRange: nil, replacement: "", fullText: sorted(fullText: fullText, selection: selection))
        default:
            return nil
        }
    }

    public static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public static func localDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Sorts the selected lines, or the whole body when nothing is selected.
    static func sorted(fullText: String, selection: Range<Int>?) -> String {
        let chars = Array(fullText)
        var lines = fullText.components(separatedBy: "\n")
        // Map selection to line indices.
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
            if let first, let last { target = first...(last) as? Range<Int> ?? first..<last + 1 }
            _ = chars
        }
        if let target {
            let sortedSlice = lines[target].sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            lines.replaceSubrange(target, with: sortedSlice)
        } else {
            // Whole body: keep a trigger first line pinned, sort the rest.
            let first = lines.first ?? ""
            if NoteKind(trigger: first.trimmingCharacters(in: .whitespaces).lowercased()) != .plain, lines.count > 1 {
                let head = lines[0]
                let rest = lines.dropFirst().sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                lines = [head] + rest
            } else {
                lines = lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension Character {
    var isCommandChar: Bool { isLetter || isNumber || self == "_" || self == "-" }
}
