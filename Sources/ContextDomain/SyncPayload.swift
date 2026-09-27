import Foundation

/// iCloud sync payload. Notes cross devices through the user's own iCloud
/// (NSUbiquitousKeyValueStore for transport + local JSON as source of truth).
/// Rule: last-writer-wins per note id on `updatedAt`. No Context account,
/// no Context server. Off by default; local store works unchanged when off.
///
/// Two transports, same payload:
/// - KVS (small libraries): chunked JSON records under `context.notes.v1`.
/// - CloudKit (future, same record shape): private DB, encrypted fields.
public enum SyncPayload: Sendable {
    public static let kvKey = "context.notes.v1"
    public static let chunkSize = 900 * 1024 // KVS per-key limit is 1MB.

    /// A single note record. All fields JSON-plist safe.
    public struct Record: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        public var createdAt: Double
        public var updatedAt: Double
        public var trashedAt: Double?
        public var expiresAt: Double?

        public init(note: ContextNote) {
            id = note.id.uuidString
            text = note.text
            createdAt = note.createdAt.timeIntervalSince1970
            updatedAt = note.updatedAt.timeIntervalSince1970
            trashedAt = note.trashedAt?.timeIntervalSince1970
            expiresAt = note.expiresAt?.timeIntervalSince1970
        }

        public func note() -> ContextNote? {
            guard let uuid = UUID(uuidString: id) else { return nil }
            return ContextNote(
                id: uuid,
                text: text,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                trashedAt: trashedAt.map { Date(timeIntervalSince1970: $0) },
                expiresAt: expiresAt.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    public struct Envelope: Codable, Equatable, Sendable {
        public var version: Int
        public var records: [Record]
        public init(records: [Record]) {
            version = 1
            self.records = records
        }
    }

    public static func encode(_ notes: [ContextNote]) throws -> Data {
        try JSONEncoder().encode(Envelope(records: notes.map(Record.init)))
    }

    public static func decode(_ data: Data) throws -> [ContextNote] {
        try JSONDecoder().decode(Envelope.self, from: data).records.compactMap { $0.note() }
    }

    /// Splits encoded data into KVS-safe chunks.
    public static func chunk(_ data: Data) -> [Data] {
        stride(from: 0, to: data.count, by: chunkSize).map { data[$0..<min($0 + chunkSize, data.count)] }
    }

    public static func join(_ chunks: [Data]) -> Data {
        chunks.reduce(Data(), +)
    }

    /// Merges remote notes into local. Last-writer-wins per id on updatedAt.
    /// Returns the merged set plus whether anything changed.
    public static func merge(local: [ContextNote], remote: [ContextNote]) -> (notes: [ContextNote], changed: Bool) {
        var byID: [UUID: ContextNote] = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var changed = false
        for r in remote {
            if let existing = byID[r.id] {
                if r.updatedAt > existing.updatedAt {
                    byID[r.id] = r
                    changed = true
                }
            } else {
                byID[r.id] = r
                changed = true
            }
        }
        return (Array(byID.values), changed)
    }
}
