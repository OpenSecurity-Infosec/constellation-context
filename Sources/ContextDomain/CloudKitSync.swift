import CloudKit
import Foundation

/// CloudKit private-database transport for note sync. Same record shape as
/// the KVS payload, one CKRecord per note in a custom zone.
/// Record type `ContextNote`, zone `ContextNotes`.
///
/// Privacy: note bodies ride in fields Apple encrypts in the private DB
/// (the user's own iCloud, no Context account or server). Last-writer-wins
/// per note id on `updatedAt`, same rule as the KVS path.
public enum CloudKitSync: Sendable {
    public static let recordType = "ContextNote"
    public static let zoneName = "ContextNotes"

    /// Encrypted-field mapping: text + timestamps on the record,
    /// id as recordName.
    public static func record(for note: ContextNote, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: note.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: id)
        record["text"] = note.text as CKRecordValue
        record["createdAt"] = note.createdAt.timeIntervalSince1970 as CKRecordValue
        record["updatedAt"] = note.updatedAt.timeIntervalSince1970 as CKRecordValue
        if let trashed = note.trashedAt {
            record["trashedAt"] = trashed.timeIntervalSince1970 as CKRecordValue
        }
        if let expires = note.expiresAt {
            record["expiresAt"] = expires.timeIntervalSince1970 as CKRecordValue
        }
        return record
    }

    public static func note(from record: CKRecord) -> ContextNote? {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let text = record["text"] as? String,
              let created = record["createdAt"] as? Double,
              let updated = record["updatedAt"] as? Double
        else { return nil }
        return ContextNote(
            id: uuid,
            text: text,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            trashedAt: (record["trashedAt"] as? Double).map { Date(timeIntervalSince1970: $0) },
            expiresAt: (record["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// Zone ID for a container's private database.
    public static func zoneID(covering containerID: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Merge decision shared with SyncPayload: remote wins when newer.
    public static func shouldTakeRemote(local: ContextNote, remote: ContextNote) -> Bool {
        remote.updatedAt > local.updatedAt
    }
}
