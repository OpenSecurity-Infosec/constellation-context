import CloudKit
import ContextDomain
import Foundation
import Testing

@Suite struct CloudKitSyncTests {
    private func zone() -> CKRecordZone.ID {
        CloudKitSync.zoneID(covering: "iCloud.app.constellation.Context")
    }

    @Test func recordRoundTrips() {
        var note = ContextNote(text: "hello")
        note.trashedAt = nil
        let record = CloudKitSync.record(for: note, zoneID: zone())
        #expect(record.recordType == "ContextNote")
        #expect(record.recordID.recordName == note.id.uuidString)
        let back = CloudKitSync.note(from: record)
        #expect(back?.text == "hello")
        #expect(back?.id == note.id)
    }

    @Test func trashedAndExpirySurvive() {
        var note = ContextNote(text: "x")
        note.trashedAt = Date(timeIntervalSince1970: 200)
        note.expiresAt = Date(timeIntervalSince1970: 300)
        let back = CloudKitSync.note(from: CloudKitSync.record(for: note, zoneID: zone()))
        #expect(back?.trashedAt?.timeIntervalSince1970 == 200)
        #expect(back?.expiresAt?.timeIntervalSince1970 == 300)
    }

    @Test func rejectsBadRecords() {
        let record = CKRecord(
            recordType: "ContextNote",
            recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: zone())
        )
        #expect(CloudKitSync.note(from: record) == nil)
    }

    @Test func lastWriterWins() {
        let old = ContextNote(text: "old", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 100))
        var newer = old
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        #expect(CloudKitSync.shouldTakeRemote(local: old, remote: newer))
        #expect(!CloudKitSync.shouldTakeRemote(local: newer, remote: old))
    }
}
