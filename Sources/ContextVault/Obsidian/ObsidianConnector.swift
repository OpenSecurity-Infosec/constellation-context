import Foundation

/// An Obsidian vault folder, linked in place (ADR-0002). Notes are the
/// vault's `.md` files, addressed by path relative to the vault root.
///
/// Rules: hidden folders (`.obsidian/`, `.trash/`, `.git/`) are never
/// listed or written; an unchanged note is never rewritten; a write
/// whose file changed on disk since it was read is refused as a
/// conflict; paths that escape the vault are refused.
public struct ObsidianConnector: VaultConnector {
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
        return markdownFiles().compactMap { url in
            guard let rel = relativePath(url) else { return nil }
            let snippet = (try? String(contentsOf: url, encoding: .utf8)).map {
                String(MarkdownDocument(parsing: $0).body.prefix(160))
            } ?? ""
            return VaultNoteSummary(
                ref: VaultNoteRef(vaultID: id, noteID: rel),
                title: url.deletingPathExtension().lastPathComponent,
                snippet: snippet,
                modified: Self.modificationDate(url)
            )
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    public func search(_ query: String) async throws -> [VaultNoteSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return try await list() }
        try ensureRoot()
        var titleHits: [VaultNoteSummary] = []
        var bodyHits: [VaultNoteSummary] = []
        for url in markdownFiles() {
            guard let rel = relativePath(url) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let summary = VaultNoteSummary(
                ref: VaultNoteRef(vaultID: id, noteID: rel), title: title,
                snippet: String(MarkdownDocument(parsing: text).body.prefix(160)),
                modified: Self.modificationDate(url)
            )
            if title.lowercased().contains(q) {
                titleHits.append(summary)
            } else if text.lowercased().contains(q) {
                bodyHits.append(summary)
            }
        }
        return titleHits + bodyHits
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

    // MARK: - Paths

    /// Resolves a note id to a file inside the vault, refusing anything
    /// outside it or inside a hidden folder.
    func fileURL(for noteID: String) throws -> URL {
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
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
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
