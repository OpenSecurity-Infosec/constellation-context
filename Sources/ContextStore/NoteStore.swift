import ContextDomain
import ContextVault
import Foundation

/// One pad's notes as Markdown files in the base vault (ADR-0001).
///
/// Live notes are files in `folder`; The Void is `trash`. Ids, trash
/// dates, and expiry live in a derived index under `.context/`; losing it
/// only resets ids and trash ages. File contents are exactly what the
/// user typed — no frontmatter is added.
public final class NoteStore: @unchecked Sendable {
    public struct Options: Sendable {
        /// Fixed file stem for single-note pads (a project's `context`).
        public var singleNoteStem: String?
        /// New notes expire after this long unless edited (clipboard).
        public var expireAfter: TimeInterval?

        public init(singleNoteStem: String? = nil, expireAfter: TimeInterval? = nil) {
            self.singleNoteStem = singleNoteStem
            self.expireAfter = expireAfter
        }
    }

    public let vault: BaseVault
    public let folder: URL
    public let trashFolder: URL
    public let indexURL: URL
    public let options: Options
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var index = Index()

    struct Entry {
        var note: ContextNote
        /// Nil until the note first has text; empty notes never litter disk.
        var url: URL?
        /// Modification date we last read or wrote, to spot external edits.
        var diskDate: Date?
        var dirty = false
    }

    struct Index: Codable {
        var version = 1
        var notes: [String: Record] = [:]

        struct Record: Codable {
            var id: UUID
            var createdAt: Date?
            var trashedAt: Date?
            var expiresAt: Date?
        }
    }

    /// The Scratch pad: `Scratch/`, the vault's top-level `.trash/`, and
    /// `.context/index.json`.
    public convenience init(vault: BaseVault) {
        self.init(vault: vault, folder: vault.scratch, trash: vault.trash, index: vault.index)
    }

    public init(vault: BaseVault, folder: URL, trash: URL, index: URL, options: Options = Options()) {
        self.vault = vault
        self.folder = folder
        self.trashFolder = trash
        self.indexURL = index
        self.options = options
        try? vault.ensure()
        for dir in [folder, trash] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        lock.withLock {
            loadIndex()
            scan()
        }
    }

    public func rename(id: UUID, name: String) throws {
        try lock.withLock {
            guard var entry = entries[id], let old = entry.url,
                  !entry.note.isTrashed, options.singleNoteStem == nil else {
                throw WorkspaceError.noSuchNote
            }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
                  !name.contains(":") else { throw WorkspaceError.badRange }
            let stem = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
            guard !stem.isEmpty else { throw WorkspaceError.badRange }
            let destination = folder.appendingPathComponent(stem + ".md")
            if old == destination { return }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw WorkspaceError.badRange
            }
            try FileManager.default.moveItem(at: old, to: destination)
            if let oldKey = vault.relativePath(of: old), let newKey = vault.relativePath(of: destination) {
                index.notes[newKey] = index.notes.removeValue(forKey: oldKey)
            }
            entry.url = destination
            entries[id] = entry
            saveIndex()
        }
    }

    // MARK: - Reads

    public var liveNotes: [ContextNote] {
        lock.withLock {
            entries.values.map(\.note)
                .filter { !$0.isTrashed && !isExpired($0) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public var voidNotes: [ContextNote] {
        lock.withLock {
            entries.values.map(\.note)
                .filter(\.isTrashed)
                .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
        }
    }

    public func note(id: UUID) -> ContextNote? {
        lock.withLock { entries[id]?.note }
    }

    public var allNotes: [ContextNote] {
        lock.withLock { entries.values.map(\.note) }
    }

    /// File backing a note, once it has been written.
    public func fileURL(id: UUID) -> URL? {
        lock.withLock { entries[id]?.url }
    }

    // MARK: - Writes

    @discardableResult
    public func create(text: String = "") -> ContextNote {
        lock.withLock {
            if options.singleNoteStem != nil, let existing = entries.values.first(where: { !$0.note.isTrashed }) {
                return existing.note
            }
            var note = ContextNote(text: text)
            note.expiresAt = options.expireAfter.map { note.createdAt.addingTimeInterval($0) }
            entries[note.id] = Entry(note: note)
            if !text.isEmpty { write(note.id) }
            if note.expiresAt != nil { record(note.id) { $0.expiresAt = note.expiresAt } }
            return note
        }
    }

    public func update(id: UUID, text: String) {
        lock.withLock {
            guard entries[id] != nil else { return }
            edit(id, text: text)
            write(id)
        }
    }

    /// Memory-only text update for the keystroke path. The caller coalesces
    /// disk writes via flush() so typing never blocks on file I/O.
    public func stage(id: UUID, text: String) {
        lock.withLock {
            guard entries[id] != nil else { return }
            edit(id, text: text)
            entries[id]?.dirty = true
        }
    }

    /// Text change shared by update and stage. Editing a note that would
    /// expire (a clipboard entry) keeps it.
    private func edit(_ id: UUID, text: String) {
        guard entries[id]?.note.text != text else { return }
        entries[id]?.note.text = text
        entries[id]?.note.updatedAt = Date()
        if options.expireAfter != nil, entries[id]?.note.expiresAt != nil {
            entries[id]?.note.expiresAt = nil
            record(id) { $0.expiresAt = nil }
        }
    }

    /// Writes staged changes to disk. Safe to call redundantly.
    public func flush() {
        lock.withLock {
            for id in entries.keys where entries[id]?.dirty == true { write(id) }
        }
    }

    public func trash(id: UUID) {
        lock.withLock {
            guard entries[id] != nil else { return }
            if entries[id]?.dirty == true { write(id) }
            let now = Date()
            entries[id]?.note.trashedAt = now
            guard let url = entries[id]?.url else {
                // Never written: nothing to keep.
                entries[id] = nil
                return
            }
            move(id, from: url, to: trashFolder)
            record(id) { $0.trashedAt = now }
        }
    }

    public func restore(id: UUID) {
        lock.withLock { restoreLocked(id: id, now: Date()) }
    }

    public struct BulkRestoreResult: Equatable, Sendable {
        public var restored: Int
        public var skippedExpired: Int

        public init(restored: Int, skippedExpired: Int) {
            self.restored = restored
            self.skippedExpired = skippedExpired
        }
    }

    /// Restores several trashed notes in one action. Notes past `expiresAt`
    /// are skipped (left for garbage collection) and counted.
    public func restoreMany(ids: [UUID], now: Date = Date()) -> BulkRestoreResult {
        lock.withLock {
            var restored = 0, skipped = 0
            for id in ids {
                guard let note = entries[id]?.note, note.isTrashed else { continue }
                if let exp = note.expiresAt, exp <= now {
                    skipped += 1
                    continue
                }
                restoreLocked(id: id, now: now)
                restored += 1
            }
            return BulkRestoreResult(restored: restored, skippedExpired: skipped)
        }
    }

    /// Sets or clears a hard expiry on a note.
    public func setExpiry(id: UUID, at date: Date?) {
        lock.withLock {
            guard entries[id] != nil else { return }
            entries[id]?.note.expiresAt = date
            record(id) { $0.expiresAt = date }
        }
    }

    public func destroy(id: UUID) {
        lock.withLock { destroyLocked(id: id) }
    }

    /// Deletes trashed notes older than 30 days and notes past `expiresAt`.
    public func collectGarbage(now: Date = Date()) {
        lock.withLock {
            let doomed = entries.values.map(\.note).filter { note in
                if let exp = note.expiresAt, exp <= now { return true }
                if let t = note.trashedAt, now.timeIntervalSince(t) > 30 * 24 * 3600 { return true }
                return false
            }
            for note in doomed { destroyLocked(id: note.id) }
        }
    }

    /// Picks up edits made by other apps (Obsidian, an editor, sync).
    /// A file changed on disk replaces the in-memory note unless that note
    /// has unsaved typing; then ours is written and the disk version is
    /// kept beside it as a conflict copy, so nothing is lost.
    @discardableResult
    public func reloadFromDisk() -> Bool {
        lock.withLock { scan() }
    }

    // MARK: - Private

    private func restoreLocked(id: UUID, now: Date) {
        guard let entry = entries[id], entry.note.isTrashed else { return }
        entries[id]?.note.trashedAt = nil
        entries[id]?.note.updatedAt = now
        if let url = entry.url { move(id, from: url, to: folder) }
        record(id) { $0.trashedAt = nil }
    }

    private func destroyLocked(id: UUID) {
        if let url = entries[id]?.url {
            try? FileManager.default.removeItem(at: url)
            if let rel = vault.relativePath(of: url) { index.notes[rel] = nil }
            saveIndex()
        }
        entries[id] = nil
    }

    private func write(_ id: UUID) {
        guard var entry = entries[id] else { return }
        entry.dirty = false
        if entry.url == nil {
            guard !entry.note.text.isEmpty else {
                entries[id] = entry
                return
            }
            let target = entry.note.isTrashed ? trashFolder : folder
            let stem = options.singleNoteStem ?? NoteFileName.timestamp(entry.note.createdAt)
            let url = NoteFileName.available(stem: stem, in: target)
            entry.url = url
            if let rel = vault.relativePath(of: url) {
                index.notes[rel] = Index.Record(id: id, createdAt: entry.note.createdAt, expiresAt: entry.note.expiresAt)
                saveIndex()
            }
        }
        if let url = entry.url {
            try? entry.note.text.write(to: url, atomically: true, encoding: .utf8)
            entry.diskDate = Self.modificationDate(url)
        }
        entries[id] = entry
    }

    private func move(_ id: UUID, from url: URL, to folder: URL) {
        let stem = url.deletingPathExtension().lastPathComponent
        let dest = NoteFileName.available(stem: stem, ext: url.pathExtension, in: folder)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            return
        }
        if let old = vault.relativePath(of: url), let new = vault.relativePath(of: dest) {
            index.notes[new] = index.notes.removeValue(forKey: old)
        }
        entries[id]?.url = dest
        saveIndex()
    }

    private func record(_ id: UUID, _ change: (inout Index.Record) -> Void) {
        guard let url = entries[id]?.url, let rel = vault.relativePath(of: url) else { return }
        var rec = index.notes[rel] ?? Index.Record(id: id)
        change(&rec)
        index.notes[rel] = rec
        saveIndex()
    }

    private func isExpired(_ note: ContextNote) -> Bool {
        if let exp = note.expiresAt { return exp <= Date() }
        return false
    }

    /// Reconciles memory with the Scratch and trash folders. Returns true
    /// when anything changed.
    @discardableResult
    private func scan() -> Bool {
        var changed = false
        var seen = Set<UUID>()
        var byPath: [String: UUID] = [:]
        for (id, entry) in entries {
            if let url = entry.url, let rel = vault.relativePath(of: url) { byPath[rel] = id }
        }
        for (dir, trashed) in [(folder, false), (trashFolder, true)] {
            for url in Self.markdownFiles(in: dir) {
                guard let rel = vault.relativePath(of: url) else { continue }
                let diskDate = Self.modificationDate(url)
                if let id = byPath[rel], let entry = entries[id] {
                    seen.insert(id)
                    guard diskDate != entry.diskDate else { continue }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    if entry.dirty {
                        keepConflictCopy(of: text, beside: url)
                        write(id)
                    } else if text != entry.note.text {
                        entries[id]?.note.text = text
                        entries[id]?.note.updatedAt = diskDate ?? Date()
                        entries[id]?.diskDate = diskDate
                    } else {
                        entries[id]?.diskDate = diskDate
                    }
                    changed = true
                    continue
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let rec = index.notes[rel]
                let id = rec?.id ?? UUID()
                let created = rec?.createdAt ?? Self.creationDate(url) ?? diskDate ?? Date()
                let note = ContextNote(
                    id: id,
                    text: text,
                    createdAt: created,
                    updatedAt: diskDate ?? created,
                    trashedAt: trashed ? (rec?.trashedAt ?? diskDate ?? Date()) : nil,
                    expiresAt: rec?.expiresAt
                )
                if rec == nil { index.notes[rel] = Index.Record(id: id, createdAt: created) }
                entries[id] = Entry(note: note, url: url, diskDate: diskDate)
                seen.insert(id)
                changed = true
            }
        }
        // Files deleted by another app disappear, unless we hold unsaved
        // text for them — then the note is written back.
        for (id, entry) in entries where entry.url != nil && !seen.contains(id) {
            if entry.dirty {
                entries[id]?.url = nil
                write(id)
            } else {
                entries[id] = nil
            }
            changed = true
        }
        let live = Set(entries.values.compactMap { $0.url.flatMap(vault.relativePath(of:)) })
        let stale = index.notes.keys.filter { !live.contains($0) }
        for key in stale { index.notes[key] = nil }
        if changed || !stale.isEmpty { saveIndex() }
        return changed
    }

    private func keepConflictCopy(of text: String, beside url: URL) {
        let stem = url.deletingPathExtension().lastPathComponent + " (conflict)"
        let dest = NoteFileName.available(stem: stem, in: url.deletingLastPathComponent())
        try? text.write(to: dest, atomically: true, encoding: .utf8)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.iso.decode(Index.self, from: data)
        else { return }
        index = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder.iso.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static func markdownFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { $0.pathExtension.lowercased() == "md" }
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func creationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
