import ContextDomain
import ContextStore
import Foundation
import Testing

@Suite struct StageFlushTests {
    private func store(file: String) -> (NoteStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        return (NoteStore(fileURL: url), url)
    }

    @Test func stagedTextReadsImmediately() {
        let (s, _) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        s.stage(id: n.id, text: "typed")
        #expect(s.note(id: n.id)?.text == "typed")
    }

    @Test func stageSkipsDiskUntilFlush() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        let before = try Data(contentsOf: url)
        s.stage(id: n.id, text: "typed but unsaved")
        // Disk still holds the pre-stage snapshot.
        #expect(try Data(contentsOf: url) == before)
        s.flush()
        let after = try JSONDecoder().decode([ContextNote].self, from: Data(contentsOf: url))
        #expect(after.first { $0.id == n.id }?.text == "typed but unsaved")
    }

    @Test func updateStillSavesImmediately() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        s.update(id: n.id, text: "saved now")
        let after = try JSONDecoder().decode([ContextNote].self, from: Data(contentsOf: url))
        #expect(after.first { $0.id == n.id }?.text == "saved now")
    }

    @Test func flushIsSafeRedundant() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        s.create(text: "hello")
        s.flush()
        s.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct BulkRestoreTests {
    private func store(file: String) -> NoteStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        return NoteStore(fileURL: url)
    }

    @Test func restoresSeveralAtOnce() {
        let s = store(file: "ctx-bulk-\(UUID().uuidString).json")
        let a = s.create(text: "a")
        let b = s.create(text: "b")
        let c = s.create(text: "keep")
        s.trash(id: a.id)
        s.trash(id: b.id)
        let result = s.restoreMany(ids: [a.id, b.id])
        #expect(result == NoteStore.BulkRestoreResult(restored: 2, skippedExpired: 0))
        #expect(s.voidNotes.isEmpty)
        #expect(s.liveNotes.count == 3)
        _ = c
    }

    @Test func skipsExpiredNotes() {
        let s = store(file: "ctx-bulk-\(UUID().uuidString).json")
        let doomed = s.create(text: "doomed")
        let fresh = s.create(text: "fresh")
        s.trash(id: doomed.id)
        s.trash(id: fresh.id)
        // Backdate an explicit expiry via the sync-merge path.
        var all = s.allNotes
        if let i = all.firstIndex(where: { $0.id == doomed.id }) {
            all[i].expiresAt = Date().addingTimeInterval(-10)
        }
        s.replaceAll(all)
        let result = s.restoreMany(ids: [doomed.id, fresh.id])
        #expect(result == NoteStore.BulkRestoreResult(restored: 1, skippedExpired: 1))
        #expect(s.note(id: fresh.id)?.isTrashed == false)
        #expect(s.note(id: doomed.id)?.isTrashed == true)
    }

    @Test func unknownAndLiveIdsAreIgnored() {
        let s = store(file: "ctx-bulk-\(UUID().uuidString).json")
        let live = s.create(text: "live")
        let t = s.create(text: "trashed")
        s.trash(id: t.id)
        let result = s.restoreMany(ids: [live.id, UUID(), t.id])
        #expect(result.restored == 1)
        #expect(s.note(id: t.id)?.isTrashed == false)
    }
}
