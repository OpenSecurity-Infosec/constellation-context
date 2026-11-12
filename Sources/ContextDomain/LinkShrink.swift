import Foundation

/// Link Shrink: pasted URLs display shortened while the full URL stays
/// intact in the note text for open/copy. The domain owns detection,
/// shortening, expand/collapse presentation, and caret lookup; the
/// editor only renders the presentation and reports clicks/keys.
///
/// Detection covers scheme URLs (`https://…`, `ftp://…`, `context://…`,
/// any `scheme://`), `mailto:`/`tel:`, bare `www.` hosts, bare domains
/// with optional port/path/query/fragment, bare e-mail addresses
/// (opened as `mailto:`), `localhost`, and IPv4 hosts. Sentence
/// punctuation glued to a URL is excluded, balanced parentheses inside
/// a URL are kept, and look-alikes (`notes.txt`, `1.2.3`, `Hello.World`)
/// are not linkified.
public enum LinkShrink: Sendable {
    /// Max visible characters before middle-ellipsis shortening kicks in.
    public static let maxVisible = 48

    /// One detected link in source (note) text.
    public struct Link: Equatable, Sendable {
        public var range: Range<String.Index>
        public var raw: String

        public init(range: Range<String.Index>, raw: String) {
            self.range = range
            self.raw = raw
        }

        /// Shortened display form (`LinkShrink.shortened(raw)`).
        public var display: String { LinkShrink.shortened(raw) }
        /// True when the display form ellipsizes the middle of `raw`.
        public var isShortened: Bool { display.contains("…") }
        /// URL to open for this link, if `raw` is openable.
        public var url: URL? { LinkShrink.openableURL(raw) }
    }

    /// A link as shown in a `Presentation`: the same link in source and
    /// display coordinates (UTF-16 ranges, matching `NSRange`).
    public struct PresentedLink: Equatable, Sendable {
        public var raw: String
        /// Text actually shown: the shortened form when collapsed,
        /// otherwise `raw` unchanged.
        public var display: String
        public var sourceUTF16Range: Range<Int>
        public var displayUTF16Range: Range<Int>
        public var isExpanded: Bool

        public init(raw: String, display: String, sourceUTF16Range: Range<Int>, displayUTF16Range: Range<Int>, isExpanded: Bool) {
            self.raw = raw
            self.display = display
            self.sourceUTF16Range = sourceUTF16Range
            self.displayUTF16Range = displayUTF16Range
            self.isExpanded = isExpanded
        }

        /// True when this link is shown shortened in the presentation.
        public var isCollapsed: Bool { display != raw }
        /// URL to open for this link, if `raw` is openable.
        public var url: URL? { LinkShrink.openableURL(raw) }
    }

    /// Display text for a note: long links collapsed to their shortened
    /// form except those in the expanded set. Source text is recovered
    /// with `sourceText(fromDisplay:links:)`; caret offsets convert
    /// with `displayOffset(forSourceOffset:)` / its inverse.
    public struct Presentation: Equatable, Sendable {
        public var text: String
        public var links: [PresentedLink]

        public init(text: String, links: [PresentedLink]) {
            self.text = text
            self.links = links
        }

        /// The presented link at a display caret offset. The offset one
        /// past the last character still counts (caret at link end).
        public func presentedLink(atDisplayUTF16Offset offset: Int) -> PresentedLink? {
            guard offset >= 0 else { return nil }
            return links.first {
                offset >= $0.displayUTF16Range.lowerBound && offset <= $0.displayUTF16Range.upperBound
            }
        }

        /// Maps a source-text UTF-16 offset to display coordinates.
        /// Offsets inside a collapsed span clamp into the shown span.
        public func displayOffset(forSourceOffset source: Int) -> Int {
            var shift = 0
            for link in links where link.isCollapsed {
                let s = link.sourceUTF16Range
                let d = link.displayUTF16Range
                if source < s.lowerBound { return source - shift }
                if source <= s.upperBound { return d.lowerBound + min(source - s.lowerBound, d.count) }
                shift += s.count - d.count
            }
            return source - shift
        }

        /// Maps a display UTF-16 offset back to source coordinates.
        public func sourceOffset(forDisplayOffset display: Int) -> Int {
            var shift = 0
            for link in links where link.isCollapsed {
                let s = link.sourceUTF16Range
                let d = link.displayUTF16Range
                if display < d.lowerBound { return display + shift }
                if display <= d.upperBound { return s.lowerBound + min(display - d.lowerBound, s.count) }
                shift += s.count - d.count
            }
            return display + shift
        }
    }

    // MARK: - Detection

    private static let pattern = #"(?i)(?:[a-z][a-z0-9+.\-]*://[^\s<>"']+|(?:mailto|tel):[^\s<>"']+|www\.[^\s<>"']+|[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}|(?:localhost|(?:[0-9]{1,3}\.){3}[0-9]{1,3}|[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,})(?::[0-9]{1,5})?(?:[/?#][^\s<>"']*)?)"#

    /// All links in plain text, in document order.
    public static func links(in text: String) -> [Link] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [Link] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let matched = Range(match.range, in: text) else { continue }
            let range = trimTrailingPunctuation(matched, in: text)
            guard !range.isEmpty else { continue }
            // A match glued to a word character or `@` is the tail of a
            // longer token (e.g. the domain inside an e-mail address).
            if range.lowerBound > text.startIndex {
                let prev = text[text.index(before: range.lowerBound)]
                if prev.isLetter || prev.isNumber || prev == "@" { continue }
            }
            let raw = String(text[range])
            guard isPlausible(raw) else { continue }
            found.append(Link(range: range, raw: raw))
        }
        return found
    }

    /// Finds URL ranges in plain text (ranges of `links(in:)`).
    public static func urlRanges(in text: String) -> [Range<String.Index>] {
        links(in: text).map(\.range)
    }

    /// The link under a caret given as a UTF-16 offset (editor
    /// `NSRange.location`). A caret immediately after the last
    /// character still counts, matching ⌘↩ expectations.
    public static func link(atUTF16Offset offset: Int, in text: String) -> Link? {
        guard offset >= 0 else { return nil }
        for link in links(in: text) {
            let ns = NSRange(link.range, in: text)
            if offset >= ns.location && offset <= ns.location + ns.length { return link }
        }
        return nil
    }

    // MARK: - Presentation (collapsed display + expand/collapse)

    /// Builds the display form of `text`: shortened links collapse
    /// unless their raw form is in `expanded`; short links always show
    /// exactly what the user typed.
    public static func presentation(for text: String, expanded: Set<String> = []) -> Presentation {
        var out = ""
        var presented: [PresentedLink] = []
        var cursor = text.startIndex
        var sourcePos = 0
        var displayPos = 0
        for link in links(in: text) {
            let gap = String(text[cursor..<link.range.lowerBound])
            out += gap
            sourcePos += gap.utf16.count
            displayPos += gap.utf16.count
            let isExpanded = expanded.contains(link.raw)
            let shown = link.isShortened && !isExpanded ? link.display : link.raw
            presented.append(PresentedLink(
                raw: link.raw,
                display: shown,
                sourceUTF16Range: sourcePos..<(sourcePos + link.raw.utf16.count),
                displayUTF16Range: displayPos..<(displayPos + shown.utf16.count),
                isExpanded: isExpanded))
            out += shown
            sourcePos += link.raw.utf16.count
            displayPos += shown.utf16.count
            cursor = link.range.upperBound
        }
        out += String(text[cursor..<text.endIndex])
        return Presentation(text: out, links: presented)
    }

    /// Inverse of `presentation`: restores full URLs for collapsed
    /// spans whose shown text is still untouched. Spans the user has
    /// edited are left as literal display text.
    public static func sourceText(fromDisplay display: String, links: [PresentedLink]) -> String {
        var result = display
        for link in links.reversed() where link.isCollapsed {
            let range = link.displayUTF16Range
            guard range.lowerBound >= 0, range.upperBound <= result.utf16.count else { continue }
            let lower = String.Index(utf16Offset: range.lowerBound, in: result)
            let upper = String.Index(utf16Offset: range.upperBound, in: result)
            guard String(result[lower..<upper]) == link.display else { continue }
            result.replaceSubrange(lower..<upper, with: link.raw)
        }
        return result
    }

    /// Flips one raw URL in the expanded set (click expand/collapse).
    public static func toggled(_ expanded: Set<String>, raw: String) -> Set<String> {
        var copy = expanded
        if copy.contains(raw) { copy.remove(raw) } else { copy.insert(raw) }
        return copy
    }

    // MARK: - Shorten / expand / open

    /// Display base: the URL with `http(s)://` / `mailto:` and one
    /// trailing slash removed. Other schemes stay visible so the kind
    /// of link remains recognizable.
    private static func displayBase(_ url: String) -> String {
        var work = url.trimmingCharacters(in: .whitespacesAndNewlines)
        work = work.replacingOccurrences(of: #"^https?://"#, with: "", options: [.regularExpression, .caseInsensitive])
        work = work.replacingOccurrences(of: #"^mailto:"#, with: "", options: [.regularExpression, .caseInsensitive])
        if work.hasSuffix("/"), work.count > 1 { work.removeLast() }
        return work
    }

    /// Short display form: host + ellipsis-middle path, readable ending kept.
    public static func shortened(_ url: String) -> String {
        let work = displayBase(url)
        guard work.count > maxVisible else { return work }
        // Keep head (host) and tail (readable ending), ellipsis the middle.
        let headCount = 24
        let tailCount = maxVisible - headCount - 1
        return "\(String(work.prefix(headCount)))…\(String(work.suffix(tailCount)))"
    }

    /// Restores the full URL from a shortened display form by matching
    /// it against known full URLs (first exact shortened-form match,
    /// then a head/tail match so older display forms still expand).
    public static func expand(display: String, candidates: [String]) -> String? {
        if candidates.contains(display) { return display }
        if let match = candidates.first(where: { shortened($0) == display }) { return match }
        guard display.contains("…") else { return nil }
        let parts = display.split(separator: "…", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return candidates.first { full in
            let base = displayBase(full)
            return base.hasPrefix(parts[0]) && base.hasSuffix(parts[1])
        }
    }

    /// Normalizes a display/pasted string into an openable URL.
    /// Scheme URLs keep their scheme (`ftp:`, `context:`, …), a bare
    /// e-mail becomes `mailto:`, bare hosts gain `https://` (or
    /// `http://` for `localhost`/IPv4/`.local`), and shortened `…`
    /// display forms or junk return nil.
    public static func openableURL(_ raw: String) -> URL? {
        let trimmedWhitespace = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWhitespace.isEmpty,
              !trimmedWhitespace.contains("…"),
              !trimmedWhitespace.contains(where: { $0.isWhitespace })
        else { return nil }
        let whole = trimmedWhitespace.startIndex..<trimmedWhitespace.endIndex
        let trimmed = String(trimmedWhitespace[trimTrailingPunctuation(whole, in: trimmedWhitespace)])
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.range(of: #"^[a-z][a-z0-9+.\-]*://"#, options: .regularExpression) != nil {
            return URL(string: trimmed)
        }
        if lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") {
            return URL(string: trimmed)
        }
        if isEmail(trimmed) { return URL(string: "mailto:\(trimmed)") }
        // A `scheme:` form that is not `host:port` (e.g. `urn:…`).
        let isHostPort = trimmed.range(of: #"^[^:/?#]+:[0-9]{1,5}([/?#].*)?$"#, options: .regularExpression) != nil
        if !isHostPort, lower.range(of: #"^[a-z][a-z0-9+.\-]*:"#, options: .regularExpression) != nil {
            return URL(string: trimmed)
        }
        let host = hostPart(of: trimmed)
        guard isPlausibleHost(host) else { return nil }
        let scheme = host.lowercased() == "localhost" || isIPv4(host) || host.lowercased().hasSuffix(".local")
            ? "http" : "https"
        return URL(string: "\(scheme)://\(trimmed)")
    }

    // MARK: - Helpers

    /// Drops sentence punctuation glued to the end of a match, plus
    /// closing brackets that have no opener inside the match, so
    /// `(see https://x/a).` yields `https://x/a` while a balanced
    /// `Note_(software)` keeps its `)`.
    private static func trimTrailingPunctuation(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var end = range.upperBound
        while end > range.lowerBound {
            let prev = text.index(before: end)
            let ch = text[prev]
            if ".,;:!?".contains(ch) { end = prev; continue }
            if let opener: Character = switch ch {
            case ")": "("
            case "]": "["
            case "}": "{"
            default: nil
            } {
                let candidate = text[range.lowerBound..<end]
                if candidate.count(where: { $0 == ch }) > candidate.count(where: { $0 == opener }) {
                    end = prev
                    continue
                }
            }
            break
        }
        return range.lowerBound..<end
    }

    /// File extensions that make a two-label token (`notes.txt`) a
    /// file name rather than a host.
    private static let fileExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "py", "js", "ts", "json", "png",
        "jpg", "jpeg", "gif", "pdf", "zip", "csv", "html", "htm", "xml",
        "mp3", "mp4", "mov", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    ]

    /// Common TLDs accepted for a pathless bare domain (`example.com`
    /// with nothing after it); any two-letter ccTLD is also accepted.
    /// A bare domain with a port or path needs no TLD check.
    private static let commonTLDs: Set<String> = [
        "com", "org", "net", "io", "co", "dev", "app", "edu", "gov", "ai",
        "me", "tv", "info", "biz", "xyz", "site", "online", "tech", "blog",
        "news", "shop", "store", "cloud", "email", "gg", "so", "to", "fm",
    ]

    /// Rejects regex hits that are prose or file names, not links.
    private static func isPlausible(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains("://") || lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") { return true }
        if lower.hasPrefix("www.") { return raw.dropFirst(4).contains(".") }
        if isEmail(raw) { return true }
        let host = hostPart(of: raw)
        let hostLower = host.lowercased()
        if hostLower == "localhost" { return true }
        if isIPv4(host) { return true }
        if host.split(separator: ".").count == 4, host.allSatisfy({ $0.isNumber || $0 == "." }) {
            return false // dotted numbers that are not a valid IPv4 address
        }
        let labels = host.split(separator: ".").map { $0.lowercased() }
        guard labels.count >= 2, let tld = labels.last else { return false }
        if labels.count == 2, fileExtensions.contains(tld) { return false }
        let hasPortOrPath = raw.dropFirst(host.count).first.map { ":/?#".contains($0) } ?? false
        if hasPortOrPath { return true }
        return tld.count == 2 || commonTLDs.contains(tld)
    }

    private static func isPlausibleHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") { return true }
        if isIPv4(host) { return true }
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last,
              tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }
        return true
    }

    /// Host portion of a bare candidate: up to the first `/ ? #`,
    /// without userinfo or `:port`.
    private static func hostPart(of raw: String) -> String {
        let end = raw.firstIndex(where: { "/?#".contains($0) }) ?? raw.endIndex
        var hostPort = String(raw[..<end])
        if let at = hostPort.lastIndex(of: "@") {
            hostPort = String(hostPort[hostPort.index(after: at)...])
        }
        if let colon = hostPort.firstIndex(of: ":") {
            hostPort = String(hostPort[..<colon])
        }
        return hostPort
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }), let value = Int(part) else { return false }
            return value <= 255
        }
    }

    private static func isEmail(_ value: String) -> Bool {
        guard let range = value.range(
            of: #"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$"#,
            options: .regularExpression) else { return false }
        return range.lowerBound == value.startIndex && range.upperBound == value.endIndex
    }
}
