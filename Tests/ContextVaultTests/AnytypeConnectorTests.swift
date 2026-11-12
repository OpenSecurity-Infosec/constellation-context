import ContextVault
import Foundation
import Testing

@Suite struct AnytypeConnectorTests {
    func connector(_ fake: FakeAnytype) -> AnytypeConnector {
        AnytypeConnector(
            id: "anytype-test", displayName: "Personal", spaceID: fake.spaceID,
            client: AnytypeClient(transport: fake, apiKey: fake.apiKey)
        )
    }

    func richObject() -> FakeAnytype.Object {
        let todo = AnytypeTag(id: "t1", key: "todo", name: "Todo")
        let done = AnytypeTag(id: "t2", key: "done", name: "Done")
        let work = AnytypeTag(id: "t3", key: "work", name: "work")
        let home = AnytypeTag(id: "t4", key: "home", name: "home")
        return FakeAnytype.Object(
            id: "obj-rich", name: "Launch plan", markdown: "# Launch\n\nShip it.\n", typeKey: "task", layout: "action",
            properties: [
                .init(key: "status", format: "select", value: todo, options: [todo, done]),
                .init(key: "tag", format: "multi_select", value: [work, home], options: [work, home]),
                .init(key: "due_date", format: "date", value: "2026-11-20T00:00:00Z"),
                .init(key: "done", format: "checkbox", value: false),
                .init(key: "estimate", format: "number", value: 3.0),
                .init(key: "source", format: "url", value: "https://example.com"),
                .init(key: "description", format: "text", value: ""),
            ]
        )
    }

    @Test func passesConnectorConformance() async throws {
        try await checkConnectorConformance(connector(FakeAnytype()))
    }

    @Test func linkingTradesTheCodeForAKey() async throws {
        let fake = FakeAnytype()
        let anon = AnytypeClient(transport: fake, apiKey: nil)
        let challenge = try await anon.startChallenge()
        let key = try await anon.exchange(challengeID: challenge, code: "1234")
        #expect(key == fake.apiKey)
        await #expect(throws: VaultError.unauthorized) {
            _ = try await anon.exchange(challengeID: challenge, code: "0000")
        }
        let spaces = try await AnytypeClient(transport: fake, apiKey: key).spaces()
        #expect(spaces.map(\.name) == ["Personal"])
    }

    @Test func requestsWithoutAKeyAreUnauthorized() async throws {
        let fake = FakeAnytype()
        let c = AnytypeConnector(id: "x", displayName: "x", spaceID: fake.spaceID, client: AnytypeClient(transport: fake, apiKey: nil))
        await #expect(throws: VaultError.unauthorized) { _ = try await c.list() }
    }

    @Test func objectsBecomeMarkdownWithPropertiesAsFrontmatter() async throws {
        let fake = FakeAnytype()
        fake.add(richObject())
        let note = try await connector(fake).read(VaultNoteRef(vaultID: "anytype-test", noteID: "obj-rich"))
        let doc = note.document
        #expect(doc.body == "# Launch\n\nShip it.\n")
        #expect(doc.value(for: "title") == "Launch plan")
        #expect(doc.value(for: "type") == "task")
        #expect(doc.value(for: "status") == "Todo")
        #expect(doc.list(for: "tag") == ["work", "home"])
        #expect(doc.value(for: "due_date") == "2026-11-20T00:00:00Z")
        #expect(doc.value(for: "done") == "false")
        #expect(doc.value(for: "estimate") == "3")
        #expect(doc.value(for: "source") == "https://example.com")
        #expect(!doc.keys.contains("description"), "empty values stay out of frontmatter")
        #expect(Array(doc.keys.prefix(2)) == ["title", "type"])
        #expect(!doc.keys.contains("last_modified_date"), "self-updating properties stay out")
        #expect(note.modified != nil)
    }

    @Test func editsSendOnlyWhatChanged() async throws {
        let fake = FakeAnytype()
        fake.add(richObject())
        let c = connector(fake)
        var note = try await c.read(VaultNoteRef(vaultID: "anytype-test", noteID: "obj-rich"))
        note.document.setValue("Done", for: "status")
        note.document.setList(["work"], for: "tag")
        note.document.setValue("true", for: "done")
        try await c.write(note)
        let patch = try #require(fake.requests.last { $0.method == "PATCH" })
        let patchBody = try #require(patch.body)
        let body = try #require(try JSONSerialization.jsonObject(with: patchBody) as? [String: Any])
        #expect(body["markdown"] == nil, "unchanged body is not sent")
        #expect(body["name"] == nil, "unchanged title is not sent")
        let props = try #require(body["properties"] as? [[String: Any]])
        #expect(props.compactMap { $0["key"] as? String } == ["done", "status", "tag"])
        #expect(props.first { $0["key"] as? String == "status" }?["select"] as? String == "done")
        #expect(props.first { $0["key"] as? String == "tag" }?["multi_select"] as? [String] == ["work"])

        let back = try await c.read(note.ref)
        #expect(back.document.value(for: "status") == "Done")
        #expect(back.document.list(for: "tag") == ["work"])
        #expect(back.document.value(for: "estimate") == "3")
    }

    @Test func titleAndBodyEdits() async throws {
        let fake = FakeAnytype()
        fake.add(richObject())
        let c = connector(fake)
        var note = try await c.read(VaultNoteRef(vaultID: "anytype-test", noteID: "obj-rich"))
        note.document.setValue("Launch plan v2", for: "title")
        note.document.body += "\nMore.\n"
        try await c.write(note)
        #expect(fake.object("obj-rich")?.name == "Launch plan v2")
        #expect(fake.object("obj-rich")?.markdown == "# Launch\n\nShip it.\n\nMore.\n")
    }

    @Test func editsAnytypeCannotHoldAreRefusedNotDropped() async throws {
        let fake = FakeAnytype()
        fake.add(richObject())
        let c = connector(fake)
        let ref = VaultNoteRef(vaultID: "anytype-test", noteID: "obj-rich")

        var unknownKey = try await c.read(ref)
        unknownKey.document.setValue("x", for: "not_a_property")
        await #expect(throws: VaultError.self) { try await c.write(unknownKey) }

        var unknownTag = try await c.read(ref)
        unknownTag.document.setValue("Blocked", for: "status")
        await #expect(throws: VaultError.self) { try await c.write(unknownTag) }

        var badNumber = try await c.read(ref)
        badNumber.document.setValue("lots", for: "estimate")
        await #expect(throws: VaultError.self) { try await c.write(badNumber) }

        #expect(fake.requests.allSatisfy { $0.method != "PATCH" }, "nothing partial was written")
    }

    @Test func containersAndArchivedObjectsAreNotNotes() async throws {
        let fake = FakeAnytype()
        fake.add(.init(id: "a", name: "A note", markdown: "a"))
        fake.add(.init(id: "b", name: "A set", markdown: "", layout: "set"))
        fake.add(.init(id: "c", name: "Gone", markdown: "c", archived: true))
        fake.add(.init(id: "d", name: "", markdown: "untitled thought\nmore", layout: "note"))
        let titles = try await connector(fake).list().map(\.title)
        #expect(titles == ["A note", "untitled thought"])
    }

    @Test func listingPagesThroughLargeSpaces() async throws {
        let fake = FakeAnytype()
        for i in 0..<1203 { fake.add(.init(id: "o\(i)", name: "n\(i)", markdown: "")) }
        #expect(try await connector(fake).list().count == 1203)
        #expect(fake.requests.filter { $0.path.hasSuffix("/objects") }.count == 3)
    }

    @Test func rateLimitIsRetriedOnce() async throws {
        let fake = FakeAnytype()
        fake.add(.init(id: "a", name: "A", markdown: "a"))
        fake.rateLimitNext = 1
        #expect(try await connector(fake).list().count == 1)
        fake.rateLimitNext = 2
        await #expect(throws: VaultError.rateLimited) { _ = try await connector(fake).list() }
    }
}

@Suite struct LinkedVaultRegistryTests {
    @Test func savesAndRemovesVaults() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-vaults-\(UUID().uuidString).json")
        let registry = LinkedVaultRegistry(fileURL: file)
        #expect(registry.load().isEmpty)
        let a = LinkedVault(kind: .anytype, name: "Personal", spaceID: "s1")
        let b = LinkedVault(kind: .obsidian, name: "Notes", path: "/tmp/notes")
        try registry.add(a)
        try registry.add(b)
        #expect(registry.load() == [a, b])
        try registry.remove(id: a.id)
        #expect(registry.load() == [b])
    }

    @Test func memorySecretStore() throws {
        let store = MemorySecretStore()
        try store.setSecret("k", for: "anytype")
        #expect(store.secret(for: "anytype") == "k")
        try store.setSecret(nil, for: "anytype")
        #expect(store.secret(for: "anytype") == nil)
    }
}
