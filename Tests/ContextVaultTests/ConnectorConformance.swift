import ContextVault
import Foundation
import Testing

/// Behavior every `VaultConnector` must show before it ships (ADR-0002).
/// Each connector's tests call this with a fresh, empty vault.
func checkConnectorConformance(_ connector: any VaultConnector) async throws {
    // Create, list, read.
    let created = try await connector.create(title: "Conformance Alpha", body: "Hello **world**\n\n- [ ] task\n")
    let listed = try await connector.list()
    #expect(listed.contains { $0.ref == created.ref }, "created note is listed")
    let read = try await connector.read(created.ref)
    #expect(read.document.body.contains("Hello **world**"), "body survives create/read")
    #expect(read.title == "Conformance Alpha", "title survives create/read")

    // Search by title.
    let hits = try await connector.search("Alpha")
    #expect(hits.contains { $0.ref == created.ref }, "search finds by title")

    // Unchanged write is a no-op.
    try await connector.write(read)
    let again = try await connector.read(created.ref)
    #expect(again.document.text == read.document.text, "unchanged write keeps text identical")

    // Body edit persists; metadata does not drift.
    var edited = again
    edited.document.body = again.document.body + "\nAdded by Context.\n"
    try await connector.write(edited)
    let after = try await connector.read(created.ref)
    #expect(after.document.body == edited.document.body, "body edit persists")
    #expect(after.document.keys == again.document.keys, "frontmatter keys unchanged")
    for key in again.document.keys {
        #expect(after.document.value(for: key) == again.document.value(for: key), "frontmatter \(key) unchanged")
    }
    if let before = again.modified, let now = after.modified {
        #expect(now >= before, "modified date moves forward")
    }

    // Missing notes report notFound.
    do {
        _ = try await connector.read(VaultNoteRef(vaultID: connector.id, noteID: "does-not-exist"))
        Issue.record("reading a missing note should throw")
    } catch let error as VaultError {
        #expect(error == .notFound)
    }
}
