import ContextVault
import Foundation
import Testing

@Suite struct ObsidianConnectorTests {
    @Test func indexedVaultScaleAndExternalChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for n in 0..<693 {
            try ("# Note \(n)\n" + String(repeating: "searchable body ", count: 100)).write(
                to: root.appendingPathComponent("Note-\(n).md"), atomically: true, encoding: .utf8)
        }
        let c = ObsidianConnector(id: "scale", displayName: "Scale", root: root)
        let clock = ContinuousClock()
        let cold = clock.now
        #expect(try await c.list().count == 693)
        let coldTime = cold.duration(to: clock.now)
        let warm = clock.now
        #expect(try await c.search("searchable").count == 693)
        print("693-note fixture: cold \(coldTime), warm search \(warm.duration(to: clock.now))")
        try "replacement needle".write(to: root.appendingPathComponent("Note-0.md"), atomically: true, encoding: .utf8)
        #expect(try await c.search("needle").count == 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Note-0.md"))
        #expect(try await c.list().count == 692)
        #expect(try await c.search("needle").isEmpty)
    }

    /// A small Obsidian-style vault: config, nested notes, attachments,
    /// frontmatter with comments and wikilinks, and Obsidian's trash.
    func fixture() throws -> (ObsidianConnector, URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ctx-obsidian-\(UUID().uuidString)", isDirectory: true)
        for dir in [".obsidian", ".trash", "Projects/Alpha", "attachments"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        let files: [String: String] = [
            ".obsidian/app.json": #"{"newFileLocation":"folder","newFileFolderPath":"Inbox"}"#,
            ".obsidian/workspace.json": "{}",
            ".trash/Old.md": "trashed",
            "Home.md": "---\ntags: [home]\n# keep this comment\naliases:\n  - Start\n---\n# Home\n\nSee [[Projects/Alpha/Plan]] and ![[diagram.png]].\r\n",
            "Projects/Alpha/Plan.md": "Plan body #alpha\n",
            "attachments/diagram.png": "PNG",
        ]
        for (path, text) in files {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        return (ObsidianConnector(id: "obs", displayName: "Notes", root: root), root)
    }

    /// Path → (contents, modification date) for every file, hidden included.
    func snapshot(_ root: URL) -> [String: (Data, Date?)] {
        var out: [String: (Data, Date?)] = [:]
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = String(url.standardizedFileURL.resolvingSymlinksInPath().path
                .dropFirst(root.standardizedFileURL.resolvingSymlinksInPath().path.count + 1))
            out[rel] = ((try? Data(contentsOf: url)) ?? Data(),
                        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
        return out
    }

    @Test func passesConnectorConformance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-obsidian-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await checkConnectorConformance(ObsidianConnector(id: "obs", displayName: "Empty", root: root))
    }

    @Test func listsNotesButNotHiddenFoldersOrAttachments() async throws {
        let (c, _) = try fixture()
        let ids = try await c.list().map(\.ref.noteID).sorted()
        #expect(ids == ["Home.md", "Projects/Alpha/Plan.md"])
        let plan = try await c.read(VaultNoteRef(vaultID: "obs", noteID: "Projects/Alpha/Plan.md"))
        #expect(plan.title == "Plan", "file name is the title, as in Obsidian")
    }

    @Test func readsFrontmatterTagsAndLinksUntouched() async throws {
        let (c, root) = try fixture()
        let home = try await c.read(VaultNoteRef(vaultID: "obs", noteID: "Home.md"))
        let raw = try String(contentsOf: root.appendingPathComponent("Home.md"), encoding: .utf8)
        #expect(home.document.text == raw)
        #expect(home.document.list(for: "aliases") == ["Start"])
        #expect(home.document.tags == ["home"])
        #expect(home.document.body.contains("[[Projects/Alpha/Plan]]"))
    }

    @Test func editsTouchOnlyTheEditedFile() async throws {
        let (c, root) = try fixture()
        let before = snapshot(root)
        var home = try await c.read(VaultNoteRef(vaultID: "obs", noteID: "Home.md"))
        home.document.setList(["home", "context"], for: "tags")
        try await c.write(home)
        let after = snapshot(root)
        #expect(Set(after.keys) == Set(before.keys), "no files created or removed")
        for (path, value) in before where path != "Home.md" {
            #expect(after[path]?.0 == value.0, "\(path) contents unchanged")
            #expect(after[path]?.1 == value.1, "\(path) not rewritten")
        }
        let text = try String(contentsOf: root.appendingPathComponent("Home.md"), encoding: .utf8)
        #expect(text.contains("# keep this comment"))
        #expect(text.hasSuffix("![[diagram.png]].\r\n"), "body bytes and CRLF kept")
    }

    @Test func unchangedWriteDoesNotTouchTheFile() async throws {
        let (c, root) = try fixture()
        let before = snapshot(root)["Home.md"]?.1
        let home = try await c.read(VaultNoteRef(vaultID: "obs", noteID: "Home.md"))
        try await c.write(home)
        #expect(snapshot(root)["Home.md"]?.1 == before)
    }

    @Test func editsAfterAnotherAppChangedTheFileConflict() async throws {
        let (c, root) = try fixture()
        var plan = try await c.read(VaultNoteRef(vaultID: "obs", noteID: "Projects/Alpha/Plan.md"))
        let url = root.appendingPathComponent("Projects/Alpha/Plan.md")
        try "Obsidian edit\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        plan.document.body = "Context edit\n"
        await #expect(throws: VaultError.conflict) { try await c.write(plan) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "Obsidian edit\n")
    }

    @Test func refusesPathsOutsideTheVaultOrInHiddenFolders() async throws {
        let (c, _) = try fixture()
        for id in ["../escape.md", ".obsidian/app.json", ".trash/Old.md", "Projects/../../x.md", "attachments/diagram.png", ""] {
            await #expect(throws: VaultError.notFound, "\(id)") {
                _ = try await c.read(VaultNoteRef(vaultID: "obs", noteID: id))
            }
        }
    }

    @Test func newNotesGoWhereObsidianSaysAndConfigIsUntouched() async throws {
        let (c, root) = try fixture()
        let config = snapshot(root).filter { $0.key.hasPrefix(".obsidian") }
        let note = try await c.create(title: "Idea: fast notes?", body: "body\n")
        #expect(note.ref.noteID == "Inbox/Idea fast notes.md")
        #expect(note.title == "Idea fast notes")
        let after = snapshot(root).filter { $0.key.hasPrefix(".obsidian") }
        #expect(after.mapValues(\.0) == config.mapValues(\.0))
    }

    @Test func searchRanksTitleMatchesFirst() async throws {
        let (c, _) = try fixture()
        let hits = try await c.search("plan")
        #expect(hits.first?.ref.noteID == "Projects/Alpha/Plan.md")
        #expect(hits.map(\.ref.noteID).contains("Home.md"), "body mention also found")
    }

    @Test func searchPreservesCanonicalUnicodeAndLiteralPunctuation() async throws {
        let (c, _) = try fixture()
        let note = try await c.create(title: "CAFÉ", body: "A cafe\u{301} and [[target]] 计划")
        #expect(try await c.search("cafe\u{301}").first?.ref == note.ref)
        #expect(try await c.search("[[target]]").first?.ref == note.ref)
        #expect(try await c.search("计划").first?.ref == note.ref)
    }

    @Test func missingFolderIsReportedNotCrashed() async throws {
        let c = ObsidianConnector(id: "gone", displayName: "Gone", root: URL(fileURLWithPath: "/tmp/ctx-missing-\(UUID().uuidString)"))
        await #expect(throws: VaultError.self) { _ = try await c.list() }
    }
}
