import ContextDomain
import ContextExport
import Foundation
import Testing

@Suite struct HandoffTests {
    @Test func titleAndBodySplit() {
        let (title, body) = Handoff.titleAndBody(for: ContextNote(text: "Groceries\nmilk\neggs"))
        #expect(title == "Groceries")
        #expect(body == "milk\neggs")
    }

    @Test func emptyNoteFallsBack() {
        let (title, _) = Handoff.titleAndBody(for: ContextNote(text: ""))
        #expect(title == "Context note")
    }

    @Test func bearURLBuilds() {
        let url = Handoff.bearURL(for: ContextNote(text: "Hi\nhello world"))
        #expect(url?.scheme == "bear")
        #expect(url?.absoluteString.contains("x-callback-url/create") == true)
        #expect(url?.absoluteString.contains("hello%20world") == true)
    }

    @Test func obsidianSlugPath() {
        let vault = URL(fileURLWithPath: "/tmp/vault")
        let url = Handoff.obsidianFileURL(for: ContextNote(text: "My Note!\nbody"), vault: vault)
        #expect(url.lastPathComponent == "my-note.md")
    }

    @Test func appleNotesScriptEscapes() {
        let script = Handoff.appleNotesScript(title: "Say \"hi\"", body: "b")
        #expect(script.contains("tell application \"Notes\""))
        #expect(script.contains("\\\"hi\\\""))
    }
}
