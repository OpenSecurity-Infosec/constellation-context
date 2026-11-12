import ContextStore
import Foundation
import Testing

@Suite struct SavedSearchTests {
    @Test func persistenceAndOrdering() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("searches"))
        }
        let store = NoteStore(fileURL: url)
        store.create(text: "kept")
        store.saveSearch(query: " beta ")
        store.saveSearch(query: "alpha")
        store.saveSearch(query: "beta")
        store.saveSearch(query: "  ")
        #expect(store.savedSearches.map(\.name) == ["alpha", "beta"])
        let id = try #require(store.savedSearches.last?.id)
        store.editSearch(id: id, name: "renamed", togglePin: true)
        let reopened = NoteStore(fileURL: url)
        #expect(reopened.savedSearches.first?.name == "renamed")
        #expect(reopened.savedSearches.first?.query == "beta")
        #expect(reopened.liveNotes.first?.text == "kept")
        reopened.editSearch(id: id, delete: true)
        #expect(NoteStore(fileURL: url).savedSearches.count == 1)
    }
}
