import Foundation

/// An Obsidian vault folder, linked in place (ADR-0002). Notes are the
/// vault's `.md` files, addressed by path relative to the vault root.
///
/// Rules: hidden folders (`.obsidian/`, `.trash/`, `.git/`) are never
/// listed or written; an unchanged note is never rewritten; a write
/// whose file changed on disk since it was read is refused as a
/// conflict; paths that escape the vault are refused.
public struct ObsidianConnector: VaultConnector {
    private let index = ListingIndex()
    public let id: String
    public let displayName: String
    public let root: URL
    public var kind: VaultKind { .obsidian }

    public init(id: String, displayName: String, root: URL) {
        self.id = id
        self.displayName = displayName
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func list() async throws -> [VaultNoteSummary] {
        try ensureRoot()
        return try await index.entries(self).map(\.summary)
    }

    public func search(_ query: String) async throws -> [VaultNoteSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().precomposedStringWithCanonicalMapping
        let entries = try await index.entries(self)
        guard !q.isEmpty else { return entries.map(\.summary) }
        // Canonically composed UTF-8 permits fast literal substring matching without
        // repeating Unicode normalization for every body on every keystroke.
        let needle = Data(q.utf8)
        var titles: [VaultNoteSummary] = []
        var bodies: [VaultNoteSummary] = []
        for entry in entries {
            if entry.title.range(of: needle) != nil {
                titles.append(entry.summary)
            } else if entry.text.range(of: needle) != nil {
                bodies.append(entry.summary)
            }
        }
        return titles + bodies
    }

    /// Memory-only, rebuildable index. Metadata is checked on every request so
    /// external additions, edits, renames and removals remain visible.
    private actor ListingIndex {
        struct Entry {
            let summary: VaultNoteSummary
            let title: Data
            let text: Data
            let size: Int?
        }
        private var cached: [String: Entry] = [:]
        private var ordered: [Entry] = []

        func entries(_ connector: ObsidianConnector) throws -> [Entry] {
            try connector.ensureRoot()
            var next: [String: Entry] = [:]
            var changed = false
            var enumerationPrefix: String?
            for url in connector.markdownFiles() {
                try Task.checkCancellation()
                let filePath = url.path
                // Resolve the enumeration root once, retaining Foundation's /private aliases.
                // The walker excludes symlinks and does not descend symlink directories.
                if enumerationPrefix == nil {
                    guard let relative = connector.relativePath(url) else { continue }
                    enumerationPrefix = String(filePath.dropLast(relative.count))
                }
                guard let prefix = enumerationPrefix, filePath.hasPrefix(prefix) else { continue }
                let path = String(filePath.dropFirst(prefix.count))
                let metadata = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                if let old = cached[path], old.summary.modified == metadata.contentModificationDate,
                   old.size == metadata.fileSize {
                    next[path] = old
                    continue
                }
                changed = true
                let text = try String(contentsOf: url, encoding: .utf8)
                next[path] = Entry(summary: VaultNoteSummary(
                    ref: VaultNoteRef(vaultID: connector.id, noteID: path),
                    title: url.deletingPathExtension().lastPathComponent,
                    snippet: String(MarkdownDocument(parsing: text).body.prefix(160)),
                    modified: metadata.contentModificationDate), title: Data(url.deletingPathExtension().lastPathComponent.lowercased().precomposedStringWithCanonicalMapping.utf8), text: Data(text.lowercased().precomposedStringWithCanonicalMapping.utf8), size: metadata.fileSize)
            }
            changed = changed || next.count != cached.count
            cached = next
            if changed {
                ordered = next.values.sorted {
                    if $0.summary.modified == $1.summary.modified { return $0.summary.ref.noteID < $1.summary.ref.noteID }
                    return ($0.summary.modified ?? .distantPast) > ($1.summary.modified ?? .distantPast)
                }
            }
            return ordered
        }
    }

    public func read(_ ref: VaultNoteRef) async throws -> VaultNote {
        let url = try fileURL(for: ref.noteID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw VaultError.notFound }
        return VaultNote(
            ref: VaultNoteRef(vaultID: id, noteID: ref.noteID),
            document: MarkdownDocument(parsing: text),
            modified: Self.modificationDate(url),
            name: url.deletingPathExtension().lastPathComponent
        )
    }

    @discardableResult
    public func write(_ note: VaultNote) async throws -> VaultNote {
        let url = try fileURL(for: note.ref.noteID)
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else { throw VaultError.notFound }
        if disk == note.document.text { return try await read(note.ref) }
        if let readAt = note.modified, let now = Self.modificationDate(url), now > readAt.addingTimeInterval(0.001) {
            throw VaultError.conflict
        }
        try write(note.document.text, to: url)
        return try await read(note.ref)
    }

    public func create(title: String, body: String) async throws -> VaultNote {
        try ensureRoot()
        let folder = try newNoteFolder()
        let url = NoteFileName.available(stem: NoteFileName.slug(title), in: folder)
        try write(body, to: url)
        guard let rel = relativePath(url) else { throw VaultError.invalid("Could not create the note.") }
        return try await read(VaultNoteRef(vaultID: id, noteID: rel))
    }

    /// Local file for an embed in a note, if it exists in the vault.
    public func attachmentURL(_ target: String, in ref: VaultNoteRef) -> URL? {
        guard let note = try? fileURL(for: ref.noteID) else { return nil }
        return MarkdownBlocks.resolve(target, noteFolder: note.deletingLastPathComponent(), vaultRoot: root)
    }

    // MARK: - Paths

    /// Resolves a note id to a file inside the vault, refusing anything
    /// outside it or inside a hidden folder.
    public func fileURL(for noteID: String) throws -> URL {
        let parts = noteID.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty,
              parts.allSatisfy({ $0 != ".." && $0 != "." && !$0.hasPrefix(".") }),
              noteID.lowercased().hasSuffix(".md")
        else { throw VaultError.notFound }
        let url = root.appendingPathComponent(noteID).standardizedFileURL
        guard relativePath(url) != nil else { throw VaultError.notFound }
        return url
    }

    func relativePath(_ url: URL) -> String? {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(base) else { return nil }
        return String(path.dropFirst(base.count))
    }

    /// Obsidian's "Default location for new notes" when it is a folder
    /// (read from `.obsidian/app.json`, never written); else the root.
    func newNoteFolder() throws -> URL {
        let config = root.appendingPathComponent(".obsidian/app.json")
        if let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["newFileLocation"] as? String == "folder",
           let folder = json["newFileFolderPath"] as? String, !folder.isEmpty,
           !folder.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix(".") })
        {
            let url = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        return root
    }

    func ensureRoot() throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw VaultError.unavailable("The vault folder \(root.lastPathComponent) is missing. Link it again.")
        }
    }

    func markdownFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            out.append(url)
        }
        return out
    }

    private func write(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw VaultError.unavailable("Could not write \(url.lastPathComponent). Check the vault folder's permissions.")
        }
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
