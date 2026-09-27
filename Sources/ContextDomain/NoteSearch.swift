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
    /// Multi-word queries require every word to match somewhere.
    public static func search(query: String, in notes: [ContextNote]) -> [Hit] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let live = notes.filter { !$0.isTrashed }.sorted { $0.updatedAt > $1.updatedAt }
        guard !words.isEmpty else {
            return live.map { hit(for: $0, query: []) }
        }
        return live.compactMap { note in
            let hay = note.text.lowercased()
            guard words.allSatisfy({ hay.contains($0) }) else { return nil }
            return hit(for: note, query: words)
        }
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
