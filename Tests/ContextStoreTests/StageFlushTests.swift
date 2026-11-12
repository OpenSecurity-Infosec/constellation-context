import ContextDomain
import ContextStore
import ContextVault
import Foundation
import Testing

/// A throwaway base vault under the temp directory.
func tempVault(_ name: String = #function) -> BaseVault {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ctx-\(UUID().uuidString)", isDirectory: true)
    return BaseVault(root: root)
}

func read(_ url: URL?) -> String? {
    url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
}

@Suite struct StageFlushTests {
    @Test func stagedTextReadsImmediately() {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "hello")
        s.stage(id: n.id, text: "typed")
        #expect(s.note(id: n.id)?.text == "typed")
    }

    @Test func stageSkipsDiskUntilFlush() {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "hello")
        let url = s.fileURL(id: n.id)
        #expect(read(url) == "hello")
        s.stage(id: n.id, text: "typed but unsaved")
        #expect(read(url) == "hello")
        s.flush()
        #expect(read(url) == "typed but unsaved")
    }

    @Test func updateStillSavesImmediately() {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "hello")
        s.update(id: n.id, text: "saved now")
        #expect(read(s.fileURL(id: n.id)) == "saved now")
    }

    @Test func notesArePlainMarkdownFilesInScratch() {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        let n = s.create(text: "# Title\nbody")
        let url = s.fileURL(id: n.id)
        #expect(url?.deletingLastPathComponent().standardizedFileURL == vault.scratch.standardizedFileURL)
        #expect(url?.pathExtension == "md")
        #expect(read(url) == "# Title\nbody")
    }

    @Test func emptyNotesNeverTouchDisk() {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        let n = s.create()
        s.flush()
        #expect(s.fileURL(id: n.id) == nil)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: vault.scratch.path))?.isEmpty == true)
        s.stage(id: n.id, text: "now it exists")
        s.flush()
        #expect(read(s.fileURL(id: n.id)) == "now it exists")
    }

    @Test func reopenKeepsIdsTextAndTrash() {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        let keep = s.create(text: "keep")
        let gone = s.create(text: "gone")
        s.trash(id: gone.id)
        let again = NoteStore(vault: vault)
        #expect(again.note(id: keep.id)?.text == "keep")
        #expect(again.note(id: gone.id)?.isTrashed == true)
        #expect(again.liveNotes.map(\.id) == [keep.id])
    }

    @Test func flushIsSafeRedundant() {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "hello")
        s.flush()
        s.flush()
        #expect(read(s.fileURL(id: n.id)) == "hello")
    }
}

@Suite struct ExternalEditTests {
    @Test func externalEditReloads() throws {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "mine")
        let url = try #require(s.fileURL(id: n.id))
        Thread.sleep(forTimeInterval: 0.02)
        try "edited in Obsidian".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(s.reloadFromDisk())
        #expect(s.note(id: n.id)?.text == "edited in Obsidian")
    }

    @Test func unsavedTypingWinsAndDiskVersionIsKept() throws {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        let n = s.create(text: "base")
        let url = try #require(s.fileURL(id: n.id))
        s.stage(id: n.id, text: "my unsaved typing")
        try "their edit".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        s.reloadFromDisk()
        #expect(read(url) == "my unsaved typing")
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.scratch.path)
        let conflict = try #require(names.first { $0.contains("(conflict)") })
        #expect(read(vault.scratch.appendingPathComponent(conflict)) == "their edit")
    }

    @Test func newFilesFromOtherAppsAppear() throws {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        try "dropped in".write(to: vault.scratch.appendingPathComponent("From Finder.md"), atomically: true, encoding: .utf8)
        try "not markdown".write(to: vault.scratch.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        s.reloadFromDisk()
        #expect(s.liveNotes.map(\.text) == ["dropped in"])
    }

    @Test func deletedFilesDisappear() throws {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "temp")
        try FileManager.default.removeItem(at: try #require(s.fileURL(id: n.id)))
        s.reloadFromDisk()
        #expect(s.note(id: n.id) == nil)
    }
}

@Suite struct BulkRestoreTests {
    @Test func trashMovesFilesToVaultTrash() throws {
        let vault = tempVault()
        let s = NoteStore(vault: vault)
        let n = s.create(text: "bye")
        s.trash(id: n.id)
        let url = try #require(s.fileURL(id: n.id))
        #expect(url.deletingLastPathComponent().standardizedFileURL == vault.trash.standardizedFileURL)
        s.restore(id: n.id)
        #expect(s.fileURL(id: n.id)?.deletingLastPathComponent().standardizedFileURL == vault.scratch.standardizedFileURL)
        #expect(read(s.fileURL(id: n.id)) == "bye")
    }

    @Test func restoresSeveralAtOnce() {
        let s = NoteStore(vault: tempVault())
        let a = s.create(text: "a")
        let b = s.create(text: "b")
        s.create(text: "keep")
        s.trash(id: a.id)
        s.trash(id: b.id)
        let result = s.restoreMany(ids: [a.id, b.id])
        #expect(result == NoteStore.BulkRestoreResult(restored: 2, skippedExpired: 0))
        #expect(s.voidNotes.isEmpty)
        #expect(s.liveNotes.count == 3)
    }

    @Test func skipsExpiredNotes() {
        let s = NoteStore(vault: tempVault())
        let doomed = s.create(text: "doomed")
        let fresh = s.create(text: "fresh")
        s.trash(id: doomed.id)
        s.trash(id: fresh.id)
        s.setExpiry(id: doomed.id, at: Date().addingTimeInterval(-10))
        let result = s.restoreMany(ids: [doomed.id, fresh.id])
        #expect(result == NoteStore.BulkRestoreResult(restored: 1, skippedExpired: 1))
        #expect(s.note(id: fresh.id)?.isTrashed == false)
        #expect(s.note(id: doomed.id)?.isTrashed == true)
    }

    @Test func unknownAndLiveIdsAreIgnored() {
        let s = NoteStore(vault: tempVault())
        let live = s.create(text: "live")
        let t = s.create(text: "trashed")
        s.trash(id: t.id)
        let result = s.restoreMany(ids: [live.id, UUID(), t.id])
        #expect(result.restored == 1)
        #expect(s.note(id: t.id)?.isTrashed == false)
    }

    @Test func garbageCollectionDeletesOldTrashFiles() throws {
        let s = NoteStore(vault: tempVault())
        let n = s.create(text: "old")
        s.trash(id: n.id)
        let url = try #require(s.fileURL(id: n.id))
        s.collectGarbage(now: Date().addingTimeInterval(31 * 24 * 3600))
        #expect(s.note(id: n.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct MigrationTests {
    @Test func movesLegacyNotesIntoTheVaultLosslessly() throws {
        let vault = tempVault()
        let legacyDir = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = legacyDir.appendingPathComponent("notes.json")
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let live = ContextNote(text: "math\n2+2", createdAt: created, updatedAt: created.addingTimeInterval(60))
        let trashed = ContextNote(text: "old idea", createdAt: created, updatedAt: created, trashedAt: created.addingTimeInterval(120))
        let empty = ContextNote(text: "")
        try JSONEncoder().encode([live, trashed, empty]).write(to: legacy)

        let result = try #require(try NotesJSONMigration.run(from: legacy, into: vault))
        #expect(result.live == 1 && result.trashed == 1 && result.skippedEmpty == 1)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: try #require(result.backup).path))

        let s = NoteStore(vault: vault)
        let l = try #require(s.note(id: live.id))
        #expect(l.text == "math\n2+2")
        #expect(abs(l.createdAt.timeIntervalSince(created)) < 1)
        #expect(abs(l.updatedAt.timeIntervalSince(created.addingTimeInterval(60))) < 1)
        let t = try #require(s.note(id: trashed.id))
        #expect(t.isTrashed)
        #expect(abs((t.trashedAt ?? .distantPast).timeIntervalSince(created.addingTimeInterval(120))) < 1)

        // Running again is a no-op.
        #expect(try NotesJSONMigration.run(from: legacy, into: vault) == nil)
    }

    @Test func undecodableFileIsLeftAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent("notes.json")
        try Data("not json".utf8).write(to: legacy)
        #expect(try NotesJSONMigration.run(from: legacy, into: tempVault()) == nil)
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }
}
