import ContextDomain
import Foundation
import Testing

@Suite struct SyncPayloadTests {
    private func note(_ text: String, updated: Date) -> ContextNote {
        ContextNote(text: text, createdAt: updated, updatedAt: updated)
    }

    @Test func roundTrips() throws {
        let notes = [note("hello", updated: Date(timeIntervalSince1970: 100))]
        let decoded = try SyncPayload.decode(SyncPayload.encode(notes))
        #expect(decoded == notes)
    }

    @Test func trashedAndExpirySurvive() throws {
        var n = note("x", updated: Date(timeIntervalSince1970: 100))
        n.trashedAt = Date(timeIntervalSince1970: 200)
        n.expiresAt = Date(timeIntervalSince1970: 300)
        let decoded = try SyncPayload.decode(SyncPayload.encode([n]))
        #expect(decoded == [n])
    }

    @Test func chunksJoin() throws {
        let notes = (0..<50).map { note(String(repeating: "a\($0) ", count: 200), updated: Date(timeIntervalSince1970: Double($0))) }
        let data = try SyncPayload.encode(notes)
        let joined = SyncPayload.join(SyncPayload.chunk(data))
        #expect(joined == data)
        #expect(try SyncPayload.decode(joined).count == 50)
    }

    @Test func mergeLastWriterWins() {
        let old = note("old", updated: Date(timeIntervalSince1970: 100))
        var newer = old
        newer.text = "new"
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        let (merged, changed) = SyncPayload.merge(local: [old], remote: [newer])
        #expect(changed)
        #expect(merged.first?.text == "new")
    }

    @Test func mergeKeepsLocalWhenNewer() {
        let local = note("local", updated: Date(timeIntervalSince1970: 300))
        var remote = local
        remote.text = "stale"
        remote.updatedAt = Date(timeIntervalSince1970: 100)
        let (merged, changed) = SyncPayload.merge(local: [local], remote: [remote])
        #expect(!changed)
        #expect(merged.first?.text == "local")
    }

    @Test func mergeAddsUnknown() {
        let (merged, changed) = SyncPayload.merge(local: [], remote: [note("r", updated: Date())])
        #expect(changed && merged.count == 1)
    }
}
