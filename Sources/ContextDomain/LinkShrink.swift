import Foundation

/// Link Shrink: pasted URLs display shortened while the full URL stays
/// intact in the text for open/copy. Short form keeps a readable ending.
public enum LinkShrink: Sendable {
    /// Max visible characters before middle-ellipsis shortening kicks in.
    public static let maxVisible = 48

    /// Finds URL ranges in plain text (http/https, bare www., bare domains).
    public static func urlRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let pattern = #"(?i)\b((?:https?://|www\.)[^\s<>\]\)\}]+|[a-z0-9-]+(?:\.[a-z0-9-]+)+\.[a-z]{2,}(?:/[^\s<>\]\)\}]*)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            ranges.append(trimTrailingPunctuation(range, in: text))
        }
        return ranges
    }

    /// Short display form: host + ellipsis-middle path, readable ending kept.
    public static func shortened(_ url: String) -> String {
        var work = url.trimmingCharacters(in: .whitespacesAndNewlines)
        work = work.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        work = work.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression)
        guard work.count > maxVisible else { return work }
        // Keep head (host) and tail (readable ending), ellipsis the middle.
        let headCount = 24
        let tailCount = maxVisible - headCount - 1
        let head = String(work.prefix(headCount))
        let tail = String(work.suffix(tailCount))
        return "\(head)…\(tail)"
    }

    /// Restores the full URL from a shortened display form when it matches
    /// the tail of a known full URL.
    public static func expand(display: String, candidates: [String]) -> String? {
        if candidates.contains(display) { return display }
        guard display.contains("…") else { return nil }
        let parts = display.split(separator: "…", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return candidates.first { full in
            let short = full.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            return short.hasPrefix(parts[0]) && short.hasSuffix(parts[1])
        }
    }

    /// Normalizes a display/pasted string into an openable URL.
    public static func openableURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    private static func trimTrailingPunctuation(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var end = range.upperBound
        while end > range.lowerBound {
            let prev = text.index(before: end)
            if ".,;:!?".contains(text[prev]) { end = prev } else { break }
        }
        return range.lowerBound..<end
    }
}
