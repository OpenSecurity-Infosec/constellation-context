import ContextVault
import Foundation
import Testing

@Suite struct MarkdownDocumentTests {
    let obsidian = """
    ---
    title: "Plan: Q4"
    tags:
      - work
      - planning
    aliases: [q4, fourth]
    # a comment Obsidian keeps
    cssclasses: wide
    ---
    # Plan

    See [[Roadmap]] and ![[diagram.png]]. #inline-tag
    """

    @Test func roundTripIsByteIdentical() {
        for text in [obsidian, "no frontmatter\n", "", "---\nonly: header\n---\n", "---\r\nk: v\r\n---\r\nbody\r\n", "---\nunterminated\n"] {
            #expect(MarkdownDocument(parsing: text).text == text)
        }
    }

    @Test func readsScalarsListsAndQuotes() {
        let doc = MarkdownDocument(parsing: obsidian)
        #expect(doc.value(for: "title") == "Plan: Q4")
        #expect(doc.list(for: "tags") == ["work", "planning"])
        #expect(doc.list(for: "aliases") == ["q4", "fourth"])
        #expect(doc.value(for: "cssclasses") == "wide")
        #expect(doc.keys == ["title", "tags", "aliases", "cssclasses"])
        #expect(doc.body.hasPrefix("# Plan"))
        #expect(doc.title == "Plan")
    }

    @Test func tagsMergeFrontmatterAndInline() {
        #expect(MarkdownDocument(parsing: obsidian).tags == ["work", "planning", "inline-tag"])
    }

    @Test func editingOneKeyLeavesEverythingElse() {
        var doc = MarkdownDocument(parsing: obsidian)
        doc.setValue("wider", for: "cssclasses")
        let expected = obsidian.replacingOccurrences(of: "cssclasses: wide", with: "cssclasses: wider")
        #expect(doc.text == expected)
    }

    @Test func replacingABlockListReplacesItsContinuationLines() {
        var doc = MarkdownDocument(parsing: obsidian)
        doc.setList(["solo"], for: "tags")
        #expect(doc.list(for: "tags") == ["solo"])
        #expect(doc.list(for: "aliases") == ["q4", "fourth"])
        #expect(doc.text.contains("# a comment Obsidian keeps"))
    }

    @Test func removingAndAddingKeys() {
        var doc = MarkdownDocument(parsing: obsidian)
        doc.setValue(nil, for: "aliases")
        doc.setValue("2026-11-12", for: "updated")
        #expect(doc.value(for: "aliases") == nil)
        #expect(doc.value(for: "updated") == "2026-11-12")
        #expect(doc.keys.last == "updated")
        #expect(doc.body == MarkdownDocument(parsing: obsidian).body)
    }

    @Test func addingFrontmatterToAPlainNote() {
        var doc = MarkdownDocument(parsing: "hello\n")
        doc.setValue("ctx", for: "project")
        #expect(doc.text == "---\nproject: ctx\n---\nhello\n")
    }

    @Test func crlfHeadersStayCRLF() {
        var doc = MarkdownDocument(parsing: "---\r\nk: v\r\n---\r\nbody")
        doc.setValue("w", for: "k")
        #expect(doc.text == "---\r\nk: w\r\n---\r\nbody")
    }

    @Test func valuesNeedingQuotesAreQuoted() {
        var doc = MarkdownDocument(parsing: "")
        doc.setValue("a: b", for: "t")
        #expect(doc.text.contains("t: \"a: b\""))
        #expect(doc.value(for: "t") == "a: b")
    }
}

@Suite struct BaseVaultTests {
    @Test func ensureCreatesObsidianCompatibleLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = BaseVault(root: root)
        try vault.ensure()
        try vault.ensure()
        for dir in [vault.scratch, vault.clipboard, vault.projects, vault.trash, vault.state] {
            #expect(FileManager.default.fileExists(atPath: dir.path))
        }
        // Context never creates Obsidian's config folder.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".obsidian").path))
        #expect(vault.relativePath(of: vault.scratch.appendingPathComponent("a.md")) == "Scratch/a.md")
    }

    @Test func fileNamesAreStableAndDeduplicated() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_794_470_400) // 2026-11-12 08:00:00 UTC
        let stem = NoteFileName.timestamp(date, calendar: cal)
        #expect(stem == "2026-11-12 080000")
        let first = NoteFileName.available(stem: stem, in: folder)
        try "x".write(to: first, atomically: true, encoding: .utf8)
        #expect(NoteFileName.available(stem: stem, in: folder).lastPathComponent == "2026-11-12 080000 2.md")
        #expect(NoteFileName.slug("Plan: Q4/2026?") == "Plan Q4 2026")
        #expect(NoteFileName.slug("///") == "Untitled")
    }
}
