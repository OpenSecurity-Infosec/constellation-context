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

    @Test func typoFindsNote() {
        let notes = [note("Groceries\nmilk eggs"), note("Ideas\nspaceship")]
        #expect(NoteSearch.search(query: "milkk", in: notes).count == 1)
        #expect(NoteSearch.search(query: "groceris", in: notes).count == 1)
    }

    @Test func partialTokenFindsNote() {
        let notes = [note("Groceries\nmilk eggs"), note("Ideas\nspaceship")]
        #expect(NoteSearch.search(query: "gro", in: notes).count == 1)
        #expect(NoteSearch.search(query: "spceshp", in: notes).count == 1)
    }

    @Test func exactBeatsFuzzy() {
        let fuzzy = note("mile marker", updated: Date(timeIntervalSince1970: 300))
        let exact = note("milk run", updated: Date(timeIntervalSince1970: 100))
        let hits = NoteSearch.search(query: "milk", in: [fuzzy, exact])
        #expect(hits.count == 2)
        #expect(hits.first?.title == "milk run")
    }

    @Test func titleBeatsBody() {
        let body = note("notes\nbuy more milk", updated: Date(timeIntervalSince1970: 300))
        let titled = note("milk list\nbuy eggs", updated: Date(timeIntervalSince1970: 100))
        let hits = NoteSearch.search(query: "milk", in: [body, titled])
        #expect(hits.count == 2)
        #expect(hits.first?.title == "milk list")
    }

    @Test func shortQueriesStayExact() {
        let notes = [note("xyz qrs")]
        #expect(NoteSearch.search(query: "ab", in: notes).isEmpty)
        #expect(NoteSearch.search(query: "xyz", in: notes).count == 1)
    }

    @Test func fuzzyMultiWordRequiresAll() {
        let notes = [note("milk eggs"), note("milk only")]
        #expect(NoteSearch.search(query: "milkk eggs", in: notes).count == 1)
        #expect(NoteSearch.search(query: "milkk nope", in: notes).isEmpty)
    }
}

@Suite struct SearchHighlightTests {
    @Test func repeatedAndFuzzyHighlights() {
        let text = "Milk MILK groceries"
        let ranges = NoteSearch.highlightRanges(query: "milk grocries", in: text)
        #expect(ranges.map { String(text[$0]) } == ["Milk", "MILK", "groceries"])
    }
    @Test func exactTitleRanksAboveNewerFuzzyTitle() {
        let exact = ContextNote(text: "milk", createdAt: .distantPast, updatedAt: .distantPast)
        let fuzzy = ContextNote(text: "milky", createdAt: Date(), updatedAt: Date())
        #expect(NoteSearch.search(query: "milkk", in: [fuzzy, exact]).contains { $0.id == exact.id })
        #expect(NoteSearch.search(query: "milk", in: [ContextNote(text: "mlik"), exact]).first?.id == exact.id)
    }
}
