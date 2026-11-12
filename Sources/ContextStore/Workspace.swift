import ContextDomain
import ContextVault
import Foundation

/// Every change to notes, pads, and projects, as one typed value. The
/// overlay, AI actions, and automation all go through `Workspace.apply`
/// so there is exactly one mutation path (AGENTS.md).
public enum ContextCommand: Equatable, Sendable {
    case createNote(Pad, text: String)
    case renameNote(Pad, id: UUID, name: String)
    case openDailyNote(date: Date, timeZone: TimeZone)
    case createFromTemplate(String, date: Date, timeZone: TimeZone)
    /// Saves now. Use for discrete edits (commands, AI, checklist taps).
    case setText(Pad, id: UUID, text: String)
    /// Keystroke path: memory now, disk on the next flush.
    case stageText(Pad, id: UUID, text: String)
    case append(Pad, id: UUID, text: String)
    /// Replaces a character range (UTF-16, as NSTextView reports it).
    case replace(Pad, id: UUID, range: NSRange, with: String)
    case trash(Pad, id: UUID)
    case restore(Pad, id: UUID)
    case destroy(Pad, id: UUID)
    case createProject(name: String)
    case captureClip(text: String)
    /// Copies a file into the project's `docs/`.
    case addDocument(project: String, file: URL)
    /// Overwrites a text file in the project's `docs/`.
    case writeDocument(project: String, fileName: String, text: String)
    /// Moves a `docs/` file to the vault trash.
    case renameDocument(project: String, fileName: String, name: String)
    case removeDocument(project: String, fileName: String)
    case attachReference(project: String, ProjectReference)
    case detachReference(project: String, VaultNoteRef)
    case setHarness(project: String, HarnessKind, enabled: Bool)
    case setRouterSync(project: String, enabled: Bool)
}

public enum CommandResult: Equatable, Sendable {
    case note(UUID)
    case project(String)
    case none
}

public enum WorkspaceError: Error, Equatable, Sendable {
    case noSuchNote
    case badRange
    case badProjectName
    case noSuchProject
    case noSuchDocument
}

/// The base vault's pads and the single place commands are applied.
public final class Workspace: @unchecked Sendable {
    public let vault: BaseVault
    private let lock = NSLock()
    private var stores: [Pad: NoteStore] = [:]

    public init(vault: BaseVault) {
        self.vault = vault
        try? vault.ensure()
    }

    public func store(for pad: Pad) -> NoteStore {
        lock.withLock {
            if let s = stores[pad] { return s }
            let s = makeStore(pad)
            stores[pad] = s
            return s
        }
    }

    /// Project names, from folders under `Projects/`, sorted.
    public var projects: [String] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: vault.projects, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var pads: [Pad] { [.scratch, .clipboard] + projects.map(Pad.project) }

    public func projectFolder(_ name: String) -> URL {
        vault.projects.appendingPathComponent(name, isDirectory: true)
    }

    public func project(_ name: String) -> ProjectFiles {
        ProjectFiles(vault: vault, name: name)
    }

    /// Flushes every open pad's staged typing.
    public func flushAll() {
        for s in lock.withLock({ Array(stores.values) }) { s.flush() }
    }

    @discardableResult
    public func apply(_ command: ContextCommand) throws -> CommandResult {
        switch command {
        case .openDailyNote(let date, let zone):
            let day = NoteTemplate.expand("{{date}}", at: date, timeZone: zone)
            let url = vault.scratch.appendingPathComponent(day + ".md")
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data(("# " + day + "\n\n").utf8).write(to: url, options: .withoutOverwriting)
            }
            let s = store(for: .scratch)
            _ = s.reloadFromDisk()
            guard let note = s.liveNotes.first(where: { s.fileURL(id: $0.id)?.standardizedFileURL.path == url.standardizedFileURL.path }) else {
                throw WorkspaceError.noSuchNote
            }
            return .note(note.id)
        case .createFromTemplate(let template, let date, let zone):
            return .note(store(for: .scratch).create(text: NoteTemplate.expand(template, at: date, timeZone: zone)).id)
        case .createNote(let pad, let text):
            return .note(store(for: pad).create(text: text).id)
        case .renameNote(let pad, let id, let name):
            try existing(pad, id).rename(id: id, name: name)
            return .note(id)
        case .setText(let pad, let id, let text):
            let s = try existing(pad, id)
            s.update(id: id, text: text)
            return .note(id)
        case .stageText(let pad, let id, let text):
            let s = try existing(pad, id)
            s.stage(id: id, text: text)
            return .note(id)
        case .append(let pad, let id, let text):
            let s = try existing(pad, id)
            let base = s.note(id: id)?.text ?? ""
            s.update(id: id, text: base.isEmpty ? text : base + "\n" + text)
            return .note(id)
        case .replace(let pad, let id, let range, let replacement):
            let s = try existing(pad, id)
            let base = (s.note(id: id)?.text ?? "") as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= base.length else { throw WorkspaceError.badRange }
            s.update(id: id, text: base.replacingCharacters(in: range, with: replacement))
            return .note(id)
        case .trash(let pad, let id):
            try existing(pad, id).trash(id: id)
            return .none
        case .restore(let pad, let id):
            try existing(pad, id).restore(id: id)
            return .note(id)
        case .destroy(let pad, let id):
            try existing(pad, id).destroy(id: id)
            return .none
        case .createProject(let name):
            return .project(try createProject(name))
        case .captureClip(let text):
            let s = store(for: .clipboard)
            if s.liveNotes.first?.text == text { return .none }
            return .note(s.create(text: text).id)
        case .addDocument(let name, let file):
            let p = try existingProject(name)
            try FileManager.default.createDirectory(at: p.docs, withIntermediateDirectories: true)
            let stem = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension.isEmpty ? "md" : file.pathExtension
            let dest = NoteFileName.available(stem: stem, ext: ext, in: p.docs)
            try FileManager.default.copyItem(at: file, to: dest)
            return .project(name)
        case .writeDocument(let name, let fileName, let text):
            let p = try existingProject(name)
            let url = p.docs.appendingPathComponent(fileName)
            guard !fileName.contains("/"), !fileName.hasPrefix("."), FileManager.default.fileExists(atPath: url.path) else {
                throw WorkspaceError.noSuchDocument
            }
            if (try? String(contentsOf: url, encoding: .utf8)) != text {
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            return .project(name)
        case .renameDocument(let project, let fileName, let name):
            let p = try existingProject(project)
            guard !fileName.contains("/"), !fileName.hasPrefix("."),
                  !name.isEmpty, !name.contains("/"), !name.contains(":"),
                  !name.hasPrefix(".") else { throw WorkspaceError.noSuchDocument }
            let old = p.docs.appendingPathComponent(fileName)
            let destination = p.docs.appendingPathComponent(name.hasSuffix(".md") ? name : name + ".md")
            if old == destination { return .project(project) }
            guard FileManager.default.fileExists(atPath: old.path),
                  !FileManager.default.fileExists(atPath: destination.path) else { throw WorkspaceError.noSuchDocument }
            try FileManager.default.moveItem(at: old, to: destination)
            return .project(project)
        case .removeDocument(let name, let fileName):
            let p = try existingProject(name)
            let url = p.docs.appendingPathComponent(fileName)
            guard !fileName.contains("/"), FileManager.default.fileExists(atPath: url.path) else {
                throw WorkspaceError.noSuchDocument
            }
            let trash = vault.trash.appendingPathComponent("Projects/\(name)/docs", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let stem = url.deletingPathExtension().lastPathComponent
            try FileManager.default.moveItem(at: url, to: NoteFileName.available(stem: stem, ext: url.pathExtension, in: trash))
            return .project(name)
        case .attachReference(let name, let reference):
            try updateManifest(name) { m in
                m.references.removeAll { $0.ref == reference.ref }
                m.references.append(reference)
            }
            return .project(name)
        case .detachReference(let name, let ref):
            try updateManifest(name) { $0.references.removeAll { $0.ref == ref } }
            return .project(name)
        case .setHarness(let name, let kind, let enabled):
            try updateManifest(name) { m in
                m.harnesses.removeAll { $0 == kind }
                if enabled { m.harnesses.append(kind) }
            }
            return .project(name)
        case .setRouterSync(let name, let enabled):
            try updateManifest(name) { $0.routerSync = enabled }
            return .project(name)
        }
    }

    // MARK: - Private

    private func existingProject(_ name: String) throws -> ProjectFiles {
        let p = project(name)
        guard projects.contains(name) else { throw WorkspaceError.noSuchProject }
        return p
    }

    private func updateManifest(_ name: String, _ change: (inout ProjectManifest) -> Void) throws {
        let p = try existingProject(name)
        var m = p.manifest()
        change(&m)
        try p.save(m)
    }

    private func existing(_ pad: Pad, _ id: UUID) throws -> NoteStore {
        let s = store(for: pad)
        guard s.note(id: id) != nil else { throw WorkspaceError.noSuchNote }
        return s
    }

    private func createProject(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = NoteFileName.slug(trimmed)
        // slug() falls back to "Untitled" when nothing usable is left.
        guard !trimmed.isEmpty, name != "Untitled" || trimmed == "Untitled" else {
            throw WorkspaceError.badProjectName
        }
        let folder = projectFolder(name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
            let context = folder.appendingPathComponent("context.md")
            try "# \(name)\n\n".write(to: context, atomically: true, encoding: .utf8)
        }
        lock.withLock { stores[.project(name)] = nil }
        return name
    }

    private func makeStore(_ pad: Pad) -> NoteStore {
        switch pad {
        case .scratch:
            return NoteStore(vault: vault)
        case .clipboard:
            return NoteStore(
                vault: vault, folder: vault.clipboard,
                trash: vault.trash.appendingPathComponent("Clipboard", isDirectory: true),
                index: vault.state.appendingPathComponent("index-clipboard.json"),
                options: .init(expireAfter: ClipboardPolicy.lifetime)
            )
        case .project(let name):
            return NoteStore(
                vault: vault, folder: projectFolder(name),
                trash: vault.trash.appendingPathComponent("Projects/\(name)", isDirectory: true),
                index: vault.state.appendingPathComponent("index-project-\(name).json"),
                options: .init(singleNoteStem: "context")
            )
        }
    }
}
