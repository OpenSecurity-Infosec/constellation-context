import ContextDomain
import ContextVault
import Foundation

/// One-time move from the legacy single `notes.json` into the base vault.
/// Ids, creation, modification, and trash dates carry over. The JSON file
/// is renamed, never deleted, so the move can be checked or redone.
public enum NotesJSONMigration {
    public struct Result: Equatable, Sendable {
        public var live: Int
        public var trashed: Int
        public var skippedEmpty: Int
        public var backup: URL?
    }

    /// `~/Library/Application Support/ConstellationContext/notes.json`.
    public static var legacyFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ConstellationContext/notes.json")
    }

    /// Migrates when `source` exists. Returns nil when there is nothing to
    /// do or the file cannot be decoded (then it is left untouched).
    @discardableResult
    public static func run(from source: URL, into vault: BaseVault) throws -> Result? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return nil }
        let data = try Data(contentsOf: source)
        guard let notes = try? JSONDecoder().decode([ContextNote].self, from: data) else { return nil }
        try vault.ensure()

        var index = (try? JSONDecoder.iso.decode(NoteStore.Index.self, from: Data(contentsOf: vault.index)))
            ?? NoteStore.Index()
        var result = Result(live: 0, trashed: 0, skippedEmpty: 0, backup: nil)
        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard !note.text.isEmpty else {
                result.skippedEmpty += 1
                continue
            }
            let folder = note.isTrashed ? vault.trash : vault.scratch
            let url = NoteFileName.available(stem: NoteFileName.timestamp(note.createdAt), in: folder)
            try note.text.write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes(
                [.creationDate: note.createdAt, .modificationDate: note.updatedAt],
                ofItemAtPath: url.path
            )
            if let rel = vault.relativePath(of: url) {
                index.notes[rel] = NoteStore.Index.Record(
                    id: note.id, createdAt: note.createdAt,
                    trashedAt: note.trashedAt, expiresAt: note.expiresAt
                )
            }
            if note.isTrashed { result.trashed += 1 } else { result.live += 1 }
        }
        try JSONEncoder.iso.encode(index).write(to: vault.index, options: .atomic)

        let stamp = NoteFileName.timestamp(Date()).replacingOccurrences(of: " ", with: "-")
        let backup = source.deletingLastPathComponent()
            .appendingPathComponent("notes.json.migrated-\(stamp)")
        try fm.moveItem(at: source, to: backup)
        result.backup = backup
        return result
    }
}
