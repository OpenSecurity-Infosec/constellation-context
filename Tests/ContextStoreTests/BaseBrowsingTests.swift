import ContextStore
import ContextVault
import Foundation
import Testing

@Suite struct BaseBrowsingTests {
    @Test func nestedFoldersAndLosslessEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = Workspace(vault: BaseVault(root: root))
        let folder = root.appendingPathComponent("Notes/Deep")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("One.md")
        let original = "---\nunknown: retained\n---\n[[Other]] ![[image.png]]\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let connector = ws.baseConnector
        let notes = try await connector.list()
        #expect(VaultFolders.paths(in: notes).contains("Notes"))
        #expect(VaultFolders.paths(in: notes).contains("Notes/Deep"))
        #expect(VaultFolders.contains("Notes/Deep/One.md", in: "Notes"))
        #expect(!VaultFolders.contains("NotesElse/One.md", in: "Notes"))
        let ref = VaultNoteRef(vaultID: Workspace.baseSourceID, noteID: "Notes/Deep/One.md")
        var note = try await connector.read(ref)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
        note.document = MarkdownDocument(parsing: original + "Edited\n")
        _ = try await ws.apply(BaseVaultCommand.write(note))
        #expect(try String(contentsOf: file, encoding: .utf8) == original + "Edited\n")
        #expect(VaultFolders.paths(in: []).isEmpty)
    }
}
