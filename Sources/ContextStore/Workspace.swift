import ContextDomain
import ContextVault
import Foundation

/// Every change to notes, pads, and projects, as one typed value. The
/// overlay, AI actions, and automation all go through `Workspace.apply`
/// so there is exactly one mutation path (AGENTS.md).
public enum ContextCommand: Equatable, Sendable {
    case createNote(Pad, text: String)
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

    /// Flushes every open pad's staged typing.
    public func flushAll() {
        for s in lock.withLock({ Array(stores.values) }) { s.flush() }
    }

    @discardableResult
    public func apply(_ command: ContextCommand) throws -> CommandResult {
        switch command {
        case .createNote(let pad, let text):
            return .note(store(for: pad).create(text: text).id)
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
        }
    }

    // MARK: - Private

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
