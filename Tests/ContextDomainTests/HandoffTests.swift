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

@Suite struct HandoffAvailabilityTests {    private func env(
        notes: Bool = true, bear: Bool = true,
        files: Set<String> = [], dirs: Set<String> = [], writable: Set<String> = []
    ) -> Handoff.Environment {
        Handoff.Environment(
            notesAppPresent: notes, bearSchemeOpenable: bear,
            fileExists: { files.contains($0) || dirs.contains($0) },
            isDirectory: { dirs.contains($0) },
            isWritable: { writable.contains($0) }
        )
    }

    @Test func notesCheck() {
        #expect(Handoff.checkNotes(env: env()) == nil)
        #expect(Handoff.checkNotes(env: env(notes: false)) == .notesMissing)
        #expect(Handoff.UnavailableReason.notesMissing.message.contains("not installed"))
    }

    @Test func bearCheck() {
        #expect(Handoff.checkBear(env: env()) == nil)
        #expect(Handoff.checkBear(env: env(bear: false)) == .bearMissing)
        #expect(Handoff.UnavailableReason.bearMissing.message.contains("Bear is not installed"))
    }

    @Test func vaultUnsetAndBlank() {
        #expect(Handoff.checkVault(path: nil, env: env()) == .vaultUnset)
        #expect(Handoff.checkVault(path: "   ", env: env()) == .vaultUnset)
        #expect(Handoff.UnavailableReason.vaultUnset.message.contains("Pick your vault"))
    }

    @Test func vaultMissing() {
        let r = Handoff.checkVault(path: "/nope/vault", env: env())
        #expect(r == .vaultMissing(path: "/nope/vault"))
        #expect(r?.message.contains("missing") == true)
    }

    @Test func vaultFileInsteadOfDir() {
        let e = env(files: ["/x/file.md"])
        #expect(Handoff.checkVault(path: "/x/file.md", env: e) == .vaultNotDirectory(path: "/x/file.md"))
    }

    @Test func vaultUnwritable() {
        let e = env(dirs: ["/x/vault"])
        let r = Handoff.checkVault(path: "/x/vault", env: e)
        #expect(r == .vaultUnwritable(path: "/x/vault"))
        #expect(r?.message.contains("permissions") == true)
    }

    @Test func goodVaultPasses() {
        let e = env(dirs: ["/x/vault"], writable: ["/x/vault"])
        #expect(Handoff.checkVault(path: "/x/vault", env: e) == nil)
    }

    @Test func obsidianRefusesMissingVault() {
        // Pure check layer: a missing vault never reaches directory creation.
        let e = env()
        #expect(Handoff.checkVault(path: "/nope", env: e) != nil)
    }
}

@Suite struct QuickExportTests {
    @Test func slugFilenamePerKind() {
        let note = ContextNote(text: "Grocery List\nmilk")
        let dir = URL(fileURLWithPath: "/tmp/qx", isDirectory: true)
        #expect(NoteExport.quickDestination(for: note, kind: .txt, in: dir) { _ in false }.lastPathComponent == "grocery-list.txt")
        #expect(NoteExport.quickDestination(for: note, kind: .markdown, in: dir) { _ in false }.lastPathComponent == "grocery-list.md")
        #expect(NoteExport.quickDestination(for: note, kind: .pdf, in: dir) { _ in false }.lastPathComponent == "grocery-list.pdf")
    }

    @Test func dedupsExistingNames() {
        let note = ContextNote(text: "Hi")
        let dir = URL(fileURLWithPath: "/tmp/qx", isDirectory: true)
        let taken: Set<String> = ["/tmp/qx/hi.txt", "/tmp/qx/hi-2.txt"]
        let dest = NoteExport.quickDestination(for: note, kind: .txt, in: dir) { taken.contains($0) }
        #expect(dest.lastPathComponent == "hi-3.txt")
    }

    @Test func emptyNoteFallsBackToSlug() {
        let note = ContextNote(text: "")
        let dir = URL(fileURLWithPath: "/tmp/qx", isDirectory: true)
        #expect(NoteExport.quickDestination(for: note, kind: .txt, in: dir) { _ in false }.lastPathComponent == "context-note.txt")
    }

    @Test func defaultFolderPrefersLastUsed() {
        let dir = FileManager.default.temporaryDirectory
        #expect(NoteExport.defaultFolder(lastUsed: dir.path) == dir)
        #expect(NoteExport.defaultFolder(lastUsed: "/nope/missing-\(UUID().uuidString)") != URL(fileURLWithPath: "/nope"))
        #expect(NoteExport.defaultFolder(lastUsed: nil).lastPathComponent == "Downloads")
    }
}