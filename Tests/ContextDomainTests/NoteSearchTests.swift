import ContextDomain
import Foundation
import Testing

@Suite struct NoteSearchTests {
    private func note(_ text: String, updated: Date = Date()) -> ContextNote {
        ContextNote(text: text, createdAt: updated, updatedAt: updated)
    }

    @Test func emptyQueryReturnsAllNewestFirst() {
        let old = note("old", updated: Date(timeIntervalSince1970: 100))
        let new = note("new", updated: Date(timeIntervalSince1970: 200))
        let hits = NoteSearch.search(query: "", in: [old, new])
        #expect(hits.map(\.title) == ["new", "old"])
    }

    @Test func filtersByTitleAndBody() {
        let notes = [note("Groceries\nmilk eggs"), note("Ideas\nspaceship")]
        #expect(NoteSearch.search(query: "milk", in: notes).count == 1)
        #expect(NoteSearch.search(query: "groceries", in: notes).count == 1)
        #expect(NoteSearch.search(query: "nope", in: notes).isEmpty)
    }

    @Test func multiWordRequiresAll() {
        let notes = [note("milk eggs"), note("milk only")]
        #expect(NoteSearch.search(query: "milk eggs", in: notes).count == 1)
    }

    @Test func skipsTrashed() {
        var trashed = note("milk eggs")
        trashed.trashedAt = Date()
        #expect(NoteSearch.search(query: "milk", in: [trashed]).isEmpty)
    }

    @Test func snippetShowsMatch() {
        let hits = NoteSearch.search(query: "eggs", in: [note("Groceries\nmilk eggs please")])
        #expect(hits.first?.snippet.contains("eggs") == true)
    }

    @Test func emptyNoteTitle() {
        let hits = NoteSearch.search(query: "", in: [note("")])
        #expect(hits.first?.title == "(empty note)")
    }
}
