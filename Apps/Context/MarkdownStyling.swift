import AppKit

/// Display-only Markdown accents. Delimiters remain editable source text.
@MainActor
enum MarkdownStyling {
    static func apply(to storage: NSTextStorage) {
        let source = storage.string as NSString
        let full = NSRange(location: 0, length: source.length)
        var code: [NSRange] = []
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
            return regex.matches(in: storage.string, range: full)
        }
        func paint(_ pattern: String, _ attributes: [NSAttributedString.Key: Any]) {
            for match in matches(pattern) where !code.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                storage.addAttributes(attributes, range: match.range)
            }
        }
        // Match each fence character separately so a longer closing fence is valid.
        // Backtick info strings cannot contain backticks (CommonMark).
        let fences = matches("(?s)^ {0,3}(`{3,})[^`\\n]*\\n.*?(?:^ {0,3}\\1`*[ \\t]*(?:\\n|$)|\\z)")
            + matches("(?s)^ {0,3}(~{3,})[^\\n]*\\n.*?(?:^ {0,3}\\1~*[ \\t]*(?:\\n|$)|\\z)")
        for match in fences {
            code.append(match.range)
        }
        for match in matches("`[^`\\n]+`") where !code.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            code.append(match.range)
        }
        paint("^ {0,3}#{1,6}[ \\t]+[^\\n]+", [.font: NSFont.systemFont(ofSize: ContextTheme.bodyFont.pointSize * 1.25, weight: .semibold)])
        paint("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", [.font: NSFont.boldSystemFont(ofSize: ContextTheme.bodyFont.pointSize)])
        paint("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)|(?<![\\w_])_[^_\\n]+_(?![\\w_])", [.obliqueness: 0.18])
        paint("^[ \\t]*(?:[-+*]|[0-9]+[.)])[ \\t]+(?:\\[[ xX]\\])?", [.foregroundColor: NSColor.secondaryLabelColor])
        paint("^ {0,3}>[^\\n]*", [.foregroundColor: NSColor.secondaryLabelColor])
        paint("\\[\\[[^\\]\\n]+\\]\\]|\\[[^\\]\\n]+\\]\\([^\\n)]+\\)", [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue])
        for range in code {
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: ContextTheme.bodyFont.pointSize, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor], range: range)
        }
    }
}
