import Foundation

/// Antinote-style note search: title + body matching across live notes.
/// Domain-pure so it is unit-testable; the pane renders the results.
public enum NoteSearch: Sendable {
    public struct Hit: Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var snippet: String
        public var updatedAt: Date

        public init(id: UUID, title: String, snippet: String, updatedAt: Date) {
            self.id = id
            self.title = title
            self.snippet = snippet
            self.updatedAt = updatedAt
        }
    }

    /// Filters live notes by query. Empty query returns all newest-first.
    /// Multi-word queries require every word to match somewhere (exact or
    /// fuzzy). Results rank exact matches above fuzzy ones, title hits above
    /// body hits, then newest first.
    public static func search(query: String, in notes: [ContextNote]) -> [Hit] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let live = notes.filter { !$0.isTrashed }
        guard !words.isEmpty else {
            return live.sorted { $0.updatedAt > $1.updatedAt }.map { hit(for: $0, query: []) }
        }
        let scored: [(note: ContextNote, score: Int)] = live.compactMap { note in
            let title = note.text.components(separatedBy: .newlines).first?.lowercased() ?? ""
            let body = note.text.lowercased()
            var score = 0
            for word in words {
                guard let s = matchScore(word: word, title: title, body: body) else { return nil }
                score += s
            }
            return (note, score)
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.note.updatedAt > $1.note.updatedAt
            }
            .map { hit(for: $0.note, query: words) }
    }

    /// Score for one query word, or nil when it matches nothing.
    /// Exact substring in title wins, then exact in body, then fuzzy
    /// (subsequence or one edit) against individual words, title first.
    private static func matchScore(word: String, title: String, body: String) -> Int? {
        if title.contains(word) { return 4 }
        if body.contains(word) { return 3 }
        let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let bodyWords = body.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if titleWords.contains(where: { fuzzyMatch(query: word, candidate: $0) }) { return 2 }
        if bodyWords.contains(where: { fuzzyMatch(query: word, candidate: $0) }) { return 1 }
        return nil
    }

    /// True when the query is a subsequence of the candidate (partial
    /// tokens like "gro" for "groceries") or within one edit (typos like
    /// "milkk" for "milk"). Queries shorter than 3 chars must be exact,
    /// already handled above.
    static func fuzzyMatch(query: String, candidate: String) -> Bool {
        guard query.count >= 3, candidate.count >= 3 else { return false }
        if isSubsequence(query, of: candidate) { return true }
        return editDistance(query, candidate, limit: 1) <= 1
    }

    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var qi = query.startIndex
        var ci = candidate.startIndex
        while qi < query.endIndex, ci < candidate.endIndex {
            if query[qi] == candidate[ci] { qi = query.index(after: qi) }
            ci = candidate.index(after: ci)
        }
        return qi == query.endIndex
    }

    /// Levenshtein distance with early exit past the limit.
    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            var rowMin = cur[0]
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            prev = cur
        }
        return prev[b.count]
    }

    private static func hit(for note: ContextNote, query: [String]) -> Hit {
        let lines = note.text.components(separatedBy: .newlines)
        let title = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let displayTitle = title.isEmpty ? "(empty note)" : String(title.prefix(80))
        // Snippet: first line containing the first query word, else first body line.
        var snippet = ""
        if let first = query.first {
            snippet = lines.first { $0.lowercased().contains(first) }?
                .trimmingCharacters(in: .whitespaces) ?? ""
        }
        if snippet.isEmpty {
            snippet = lines.dropFirst().first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                .trimmingCharacters(in: .whitespaces) ?? ""
        }
        return Hit(id: note.id, title: displayTitle, snippet: String(snippet.prefix(120)), updatedAt: note.updatedAt)
    }
}
