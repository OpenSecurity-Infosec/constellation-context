import ContextVault
import Foundation
import Testing

@Suite struct MarkdownBlocksTests {
    @Test func splitsTextAndStandaloneImages() {
        let body = "# Title\nIntro\n![[diagram.png|400]]\nMiddle ![inline](x.png) text\n![Shot](attachments/My%20Shot.jpg \"t\")\n```\n![[not-an-embed.png]]\n```\n![[Other Note]]"
        #expect(MarkdownBlocks.parse(body) == [
            .text("# Title\nIntro"),
            .image(target: "diagram.png", alt: "diagram.png"),
            .text("Middle ![inline](x.png) text"),
            .image(target: "attachments/My Shot.jpg", alt: "Shot"),
            .text("```\n![[not-an-embed.png]]\n```\n![[Other Note]]"),
        ])
        #expect(MarkdownBlocks.parse("plain") == [.text("plain")])
    }

    @Test func resolvesLikeObsidian() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ctx-embed-\(UUID().uuidString)")
        for dir in ["notes", "attachments", ".obsidian"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in ["notes/local.png", "attachments/far.png", ".obsidian/hidden.png"] {
            try Data([1]).write(to: root.appendingPathComponent(file))
        }
        let notes = root.appendingPathComponent("notes")
        #expect(MarkdownBlocks.resolve("local.png", noteFolder: notes, vaultRoot: root)?.lastPathComponent == "local.png")
        #expect(MarkdownBlocks.resolve("attachments/far.png", noteFolder: notes, vaultRoot: root)?.lastPathComponent == "far.png")
        #expect(MarkdownBlocks.resolve("far.png", noteFolder: notes, vaultRoot: root)?.lastPathComponent == "far.png")
        #expect(MarkdownBlocks.resolve("hidden.png", noteFolder: notes, vaultRoot: root) == nil)
        #expect(MarkdownBlocks.resolve("../../etc/passwd", noteFolder: notes, vaultRoot: root) == nil)
        #expect(MarkdownBlocks.resolve("https://example.com/a.png", noteFolder: notes, vaultRoot: root)?.host == "example.com")
    }
}
