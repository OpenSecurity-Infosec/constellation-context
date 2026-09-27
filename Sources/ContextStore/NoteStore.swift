import ContextDomain
import Foundation

/// Local JSON note store. No accounts, no servers — mirrors Antinote's
/// local-first promise. SQLite migration can follow without changing callers.
public final class NoteStore: @unchecked Sendable {
    private let lock = NSLock()
    private var notes: [ContextNote] = []
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ConstellationContext", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("notes.json")
        }
        load()
    }

    // MARK: - Reads

    public var liveNotes: [ContextNote] {
        lock.withLock { notes.filter { !$0.isTrashed && !isExpired($0) }.sorted { $0.updatedAt > $1.updatedAt } }
    }

    public var voidNotes: [ContextNote] {
        lock.withLock { notes.filter { $0.isTrashed }.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) } }
    }

    public func note(id: UUID) -> ContextNote? {
        lock.withLock { notes.first { $0.id == id } }
    }

    public var allNotes: [ContextNote] {
        lock.withLock { notes }
    }

    /// Replaces the full set (iCloud merge result). Last-writer-wins already
    /// resolved by the caller.
    public func replaceAll(_ merged: [ContextNote]) {
        lock.withLock {
            notes = merged
            save()
        }
    }

    // MARK: - Writes

    @discardableResult
    public func create(text: String = "") -> ContextNote {
        lock.withLock {
            let note = ContextNote(text: text)
            notes.append(note)
            save()
            return note
        }
    }

    public func update(id: UUID, text: String) {
        lock.withLock {
            guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[i].text = text
            notes[i].updatedAt = Date()
            save()
        }
    }

    public func trash(id: UUID) {
        lock.withLock {
            guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[i].trashedAt = Date()
            save()
        }
    }

    public func restore(id: UUID) {
        lock.withLock {
            guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[i].trashedAt = nil
            notes[i].updatedAt = Date()
            save()
        }
    }

    public func destroy(id: UUID) {
        lock.withLock {
            notes.removeAll { $0.id == id }
            save()
        }
    }

    /// Deletes trashed notes older than 30 days and notes past `expiresAt`.
    public func collectGarbage(now: Date = Date()) {
        lock.withLock {
            notes.removeAll { note in
                if let exp = note.expiresAt, exp <= now { return true }
                if let t = note.trashedAt, now.timeIntervalSince(t) > 30 * 24 * 3600 { return true }
                return false
            }
            save()
        }
    }

    private func isExpired(_ note: ContextNote) -> Bool {
        if let exp = note.expiresAt { return exp <= Date() }
        return false
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([ContextNote].self, from: data) {
            notes = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
