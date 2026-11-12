import AppKit
import ContextDomain
import ContextStore
import ContextVault
import Observation
import SwiftUI

/// The full app, opened on purpose: sources on the left, notes in the
/// middle, the canvas on the right (Vision § Library). Base-vault edits
/// go through the shared Workspace; linked notes through their connector.
enum LibrarySource: Hashable {
    case pad(Pad)
    case linked(String)
    case linkedFolder(String, String)
}

enum LibraryItemID: Hashable {
    case note(Pad, UUID)
    case doc(project: String, fileName: String)
    case linked(VaultNoteRef)
}

struct LibraryItem: Identifiable, Hashable {
    var id: LibraryItemID
    var title: String
    var snippet: String
    var modified: Date?
    var source: String
}

@MainActor
@Observable
final class LibraryModel {
    private let workspace: () -> Workspace
    var linked: [LinkedVault] = []
    private var connectors: [String: any VaultConnector] = [:]
    var projects: [String] = []
    var folders: [String: [String]] = [:]

    var source: LibrarySource? = .pad(.scratch) { didSet { if oldValue != source { query = ""; loadItems() } } }
    var items: [LibraryItem] = []
    var query = "" { didSet { if oldValue != query { scheduleSearch() } } }
    var selection: LibraryItemID? {
        didSet {
            guard oldValue != selection else { return }
            commitPending(oldValue)
            open(selection)
            if selection != nil { reveal.openedNote() } else { reveal.showAll() }
        }
    }
    var text = ""
    var editing = false
    /// Which side panels show. Starts as the note alone.
    var reveal = LibraryReveal()

    /// Pointer position from the window's top-left; nil when it left.
    func pointer(_ point: CGPoint?) {
        var next = reveal
        next.pointer(point, hasNote: selection != nil)
        if next != reveal { reveal = next }
    }
    var status: String?
    private var loadedLinked: VaultNote?
    private var saveTask: Task<Void, Never>?
    /// Saves run one after another so each sees the previous write.
    private var lastSave: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    init(workspace: @escaping () -> Workspace) {
        self.workspace = workspace
        reloadSources()
    }

    func reloadSources() {
        linked = LinkedVaultRegistry.standard?.load() ?? []
        let secrets = KeychainSecretStore()
        connectors = Dictionary(uniqueKeysWithValues: linked.compactMap { v in Connectors.make(v, secrets: secrets).map { (v.id, $0) } })
        connectors[Workspace.baseSourceID] = workspace().baseConnector
        folders = [:]
        for (id, connector) in connectors where connector.kind == .obsidian {
            Task {
                guard let notes = try? await connector.list() else { return }
                folders[id] = VaultFolders.paths(in: notes)
            }
        }
        projects = workspace().projects
        loadItems()
    }

    var canRename: Bool {
        if case .doc? = selection { return true }
        guard case .note(let pad, _)? = selection else { return false }
        if case .project = pad { return false }
        return true
    }

    var canDelete: Bool {
        guard let selection else { return false }
        if case .linked = selection { return false }
        return true
    }

    func createNote() {
        saveNow()
        do {
            if case .note(let id) = try workspace().apply(.createNote(.scratch, text: "# Untitled\n")) {
                source = .pad(.scratch)
                query = ""
                loadItems()
                selection = .note(.scratch, id)
                editing = true
            }
        } catch { status = "Couldn't create the note." }
    }

    func renameNote() {
        guard canRename, let selected = selection else { return }
        saveNow()
        let alert = NSAlert()
        alert.messageText = "Rename Note"
        let field = NSTextField(string: selectedFile?.deletingPathExtension().lastPathComponent ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await lastSave?.value
            do {
                switch selected {
                case .note(let pad, let id):
                    try workspace().apply(.renameNote(pad, id: id, name: field.stringValue))
                case .doc(let project, let file):
                    try workspace().apply(.renameDocument(project: project, fileName: file, name: field.stringValue))
                    let name = field.stringValue
                    selection = .doc(project: project, fileName: name.hasSuffix(".md") ? name : name + ".md")
                case .linked: return
                }
                loadItems()
            } catch { status = "Couldn't rename the note. Check the name or an existing file." }
        }
    }

    func deleteNote() {
        guard let id = selection else { return }
        saveNow()
        Task {
            await lastSave?.value
            do {
                switch id {
                case .note(let pad, let note): try workspace().apply(.trash(pad, id: note))
                case .doc(let project, let file): try workspace().apply(.removeDocument(project: project, fileName: file))
                case .linked: return
                }
                if selection == id { selection = nil }
                loadItems()
            } catch { status = "Couldn't move the note to The Void." }
        }
    }

    func followLink(_ target: String) {
        let name = target.components(separatedBy: "|")[0].components(separatedBy: "#")[0]
        guard !name.isEmpty else { return }
        Task {
            var matches: [LibraryItemID] = []
            let ws = workspace()
            for pad in ws.pads {
                for item in padItems(pad) {
                    let file: String
                    switch item.id {
                    case .note(let p, let id): file = ws.store(for: p).fileURL(id: id)?.deletingPathExtension().lastPathComponent ?? ""
                    case .doc(_, let f): file = (f as NSString).deletingPathExtension
                    case .linked: continue
                    }
                    let path: String
                    switch item.id {
                    case .note(let p, let id):
                        path = ws.store(for: p).fileURL(id: id).flatMap { ws.vault.relativePath(of: $0) }.map { ($0 as NSString).deletingPathExtension } ?? ""
                    case .doc(let project, let f): path = "Projects/\(project)/docs/" + (f as NSString).deletingPathExtension
                    case .linked: path = ""
                    }
                    if file == name || path == name || item.title == name { matches.append(item.id) }
                }
            }
            for key in connectors.keys.sorted() {
                guard let connector = connectors[key] else { continue }
                do {
                    for item in try await connector.list() {
                        let path = (item.ref.noteID as NSString).deletingPathExtension
                        if path == name || (path as NSString).lastPathComponent == name || item.title == name {
                            matches.append(itemID(item.ref))
                        }
                    }
                } catch { status = "Couldn't search every linked vault."; return }
            }
            matches = Array(Set(matches))
            guard matches.count == 1, let match = matches.first else {
                status = matches.isEmpty ? "Link target not found." : "More than one note matches this link."
                return
            }
            selection = match
        }
    }

    // MARK: - Listing

    private func scheduleSearch() {
        loadTask?.cancel()
        loadTask = Task {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            loadItems()
        }
    }

    func loadItems() {
        loadTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            search(q)
            return
        }
        switch source {
        case .pad(let pad)?:
            items = padItems(pad)
        case .linked(let id)?, .linkedFolder(let id, _)?:
            items = []
            guard let connector = connectors[id] else { return }
            loadTask = Task {
                do {
                    let list = try await connector.list()
                    guard !Task.isCancelled else { return }
                    let visible = list.filter { note in
                        if case .linkedFolder(_, let folder)? = source {
                            return VaultFolders.contains(note.ref.noteID, in: folder)
                        }
                        return true
                    }
                    items = visible.map { LibraryItem(id: itemID($0.ref), title: $0.title, snippet: $0.snippet, modified: $0.modified, source: connector.displayName) }
                    status = nil
                } catch let error as VaultError {
                    status = error.message
                } catch {
                    status = "Couldn't list this vault."
                }
            }
        case nil:
            items = []
        }
    }

    private func itemID(_ ref: VaultNoteRef) -> LibraryItemID {
        guard ref.vaultID == Workspace.baseSourceID else { return .linked(ref) }
        let ws = workspace()
        for pad in ws.pads {
            let store = ws.store(for: pad)
            for note in store.liveNotes {
                if let file = store.fileURL(id: note.id), ws.vault.relativePath(of: file) == ref.noteID {
                    return .note(pad, note.id)
                }
            }
            if case .project(let name) = pad {
                for file in ws.project(name).documents() where ws.vault.relativePath(of: file) == ref.noteID {
                    return .doc(project: name, fileName: file.lastPathComponent)
                }
            }
        }
        return .linked(ref)
    }

    private func padItems(_ pad: Pad) -> [LibraryItem] {
        let ws = workspace()
        var out = ws.store(for: pad).liveNotes.filter { !$0.text.isEmpty }.map { note in
            LibraryItem(id: .note(pad, note.id), title: Self.title(note.text), snippet: Self.snippet(note.text), modified: note.updatedAt, source: pad.title)
        }
        if case .project(let name) = pad {
            for url in ws.project(name).documents() {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                out.append(LibraryItem(
                    id: .doc(project: name, fileName: url.lastPathComponent),
                    title: url.deletingPathExtension().lastPathComponent, snippet: Self.snippet(text),
                    modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                    source: "\(name) · docs"
                ))
            }
        }
        return out
    }

    /// Searches every pad, project doc, and linked vault.
    private func search(_ q: String) {
        let ws = workspace()
        let lower = q.lowercased()
        var local: [LibraryItem] = []
        for pad in ws.pads {
            local += padItems(pad).filter { item in
                item.title.lowercased().contains(lower) || {
                    switch item.id {
                    case .note(let p, let id): ws.store(for: p).note(id: id)?.text.lowercased().contains(lower) ?? false
                    case .doc(let project, let file):
                        ((try? String(contentsOf: ws.project(project).docs.appendingPathComponent(file), encoding: .utf8)) ?? "")
                            .lowercased().contains(lower)
                    case .linked: false
                    }
                }()
            }
        }
        items = local
        let connectors = self.connectors
        loadTask = Task {
            for connector in connectors.values {
                guard let hits = try? await connector.search(q), !Task.isCancelled else { continue }
                items += hits.map { LibraryItem(id: itemID($0.ref), title: $0.title, snippet: $0.snippet, modified: $0.modified, source: connector.displayName) }
            }
        }
    }

    // MARK: - Opening and saving

    private func open(_ id: LibraryItemID?) {
        loadedLinked = nil
        status = nil
        guard let id else { text = ""; return }
        switch id {
        case .note(let pad, let noteID):
            text = workspace().store(for: pad).note(id: noteID)?.text ?? ""
        case .doc(let project, let file):
            text = (try? String(contentsOf: workspace().project(project).docs.appendingPathComponent(file), encoding: .utf8)) ?? ""
        case .linked(let ref):
            text = ""
            guard let connector = connectors[ref.vaultID] else { status = "This vault isn't linked anymore."; return }
            Task {
                do {
                    let note = try await connector.read(ref)
                    guard selection == id else { return }
                    loadedLinked = note
                    text = note.document.text
                } catch let error as VaultError {
                    status = error.message
                } catch {
                    status = "Couldn't open this note."
                }
            }
        }
    }

    /// Called on every edit; saves after a short pause.
    func textChanged(_ newText: String) {
        guard newText != text else { return }
        text = newText
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let id = selection else { return }
            saveTask = nil
            enqueueSave(id: id, text: text, loaded: loadedLinked)
        }
    }

    func saveNow() {
        commitPending(selection)
    }

    /// Saves typing still waiting for its pause, for the note it was typed
    /// into (captured now, before the selection moves on).
    private func commitPending(_ id: LibraryItemID?) {
        guard saveTask != nil, let id else { return }
        saveTask?.cancel()
        saveTask = nil
        enqueueSave(id: id, text: text, loaded: loadedLinked)
    }

    private func enqueueSave(id: LibraryItemID, text: String, loaded: VaultNote?) {
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            // A linked note written by the previous save has a newer
            // modification date; use it so our own write isn't a conflict.
            let latest = selection == id ? (loadedLinked ?? loaded) : loaded
            await save(id: id, text: text, loaded: latest)
        }
    }

    private func save(id: LibraryItemID, text: String, loaded: VaultNote?) async {
        let ws = workspace()
        switch id {
        case .note(let pad, let noteID):
            guard ws.store(for: pad).note(id: noteID)?.text != text else { return }
            _ = try? ws.apply(.setText(pad, id: noteID, text: text))
        case .doc(let project, let file):
            _ = try? ws.apply(.writeDocument(project: project, fileName: file, text: text))
        case .linked(let ref):
            guard var note = loaded, note.document.text != text, let connector = connectors[ref.vaultID] else { return }
            note.document = MarkdownDocument(parsing: text)
            do {
                let written = try await (ref.vaultID == Workspace.baseSourceID
                    ? ws.apply(BaseVaultCommand.write(note)) : connector.write(note))
                if selection == id { loadedLinked = written }
                status = nil
            } catch let error as VaultError {
                status = error.message
            } catch {
                status = "Couldn't save to \(connector.displayName)."
            }
        }
    }

    // MARK: - Projects and files

    /// Linked notes attach by reference; base-vault notes are copied into
    /// the project's docs.
    func addToProject(_ project: String) {
        guard let id = selection else { return }
        saveNow()
        let ws = workspace()
        do {
            switch id {
            case .linked(let ref) where ref.vaultID == Workspace.baseSourceID:
                guard let connector = connectors[ref.vaultID] as? ObsidianConnector else { return }
                try ws.apply(.addDocument(project: project, file: connector.fileURL(for: ref.noteID)))
            case .linked(let ref):
                let title = items.first { $0.id == id }?.title ?? ref.noteID
                try ws.apply(.attachReference(project: project, ProjectReference(ref: ref, title: title)))
            case .note(let pad, let noteID):
                guard let url = ws.store(for: pad).fileURL(id: noteID) else { return }
                try ws.apply(.addDocument(project: project, file: url))
            case .doc(let from, let file):
                try ws.apply(.addDocument(project: project, file: ws.project(from).docs.appendingPathComponent(file)))
            }
            status = "Added to \(project)."
        } catch {
            status = "Couldn't add it to \(project)."
        }
    }

    /// Local file behind the selection, for Reveal and image lookup.
    var selectedFile: URL? {
        let ws = workspace()
        switch selection {
        case .note(let pad, let id)?: return ws.store(for: pad).fileURL(id: id)
        case .doc(let project, let file)?: return ws.project(project).docs.appendingPathComponent(file)
        case .linked(let ref)?:
            guard let c = connectors[ref.vaultID] as? ObsidianConnector else { return nil }
            return try? c.fileURL(for: ref.noteID)
        case nil: return nil
        }
    }

    func imageURL(_ target: String) -> URL? {
        if case .linked(let ref)? = selection, let c = connectors[ref.vaultID] as? ObsidianConnector {
            return c.attachmentURL(target, in: ref)
        }
        guard let file = selectedFile else { return nil }
        return MarkdownBlocks.resolve(target, noteFolder: file.deletingLastPathComponent(), vaultRoot: workspace().vault.root)
    }

    static func title(_ text: String) -> String {
        let t = MarkdownDocument(parsing: text).title
        return t.isEmpty ? "Untitled" : String(t.prefix(80))
    }

    static func snippet(_ text: String) -> String {
        let body = MarkdownDocument(parsing: text).body
        let lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return String(lines.dropFirst().joined(separator: " ").prefix(120))
    }
}

struct CanvasReader: View {
    var text: String
    var imageURL: (String) -> URL?
    var followLink: (String) -> Void = { _ in }

    var body: some View {
        let doc = MarkdownDocument(parsing: text)
        VStack(alignment: .leading, spacing: 10) {
            if !doc.keys.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(doc.keys, id: \.self) { key in
                        Text("\(key): \(doc.value(for: key) ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            let title = CanvasTypography.titleRange(in: doc.body) != nil
            ForEach(Array(MarkdownBlocks.parse(doc.body).enumerated()), id: \.offset) { blockIndex, block in
                switch block {
                case .text(let s):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(s.components(separatedBy: "\n").enumerated()), id: \.offset) { lineIndex, line in
                            if title, blockIndex == 0, lineIndex == 0, !line.hasPrefix("#") {
                                Self.title(line)
                            } else {
                                Self.line(line)
                                    .environment(\.openURL, OpenURLAction { url in
                                        guard url.scheme == "context-wiki", let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "target" })?.value else { return .systemAction }
                                        followLink(target)
                                        return .handled
                                    })
                            }
                        }
                    }
                case .image(let target, let alt):
                    image(target: target, alt: alt)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func image(target: String, alt: String) -> some View {
        if let url = imageURL(target) {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 420)
                    .accessibilityLabel(alt)
            } else if !url.isFileURL {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxHeight: 420)
            } else {
                Text("Image not found: \(target)").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Image not found: \(target)").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A prose note's first line, set like the overlay's title.
    static func title(_ line: String) -> some View {
        Text(line)
            .font(.system(size: (ContextSettings.shared.fontSize * CanvasTypography.titleScale).rounded(), design: .serif))
            .padding(.bottom, ContextSettings.shared.fontSize * CanvasTypography.titleSpacing)
    }

    static func wikiTargets(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!!)\[\[([^\]]+)\]\]"#) else { return [] }
        let string = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: string.length))
            .map { string.substring(with: $0.range(at: 1)) }
    }

    static func linkedMarkdown(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!!)\[\[([^\]]+)\]\]"#) else { return text }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let target = (text as NSString).substring(with: match.range(at: 1))
            let parts = target.components(separatedBy: "|")
            let label = parts.last ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            result.replaceCharacters(in: match.range, with: "[\(label)](context-wiki://open?target=\(encoded))")
        }
        return result as String
    }

    static func line(_ line: String) -> some View {
        var level = 0
        var rest = Substring(line)
        while rest.hasPrefix("#"), level < 6 { level += 1; rest = rest.dropFirst() }
        let isHeading = level > 0 && rest.hasPrefix(" ")
        let content = isHeading ? String(rest.dropFirst()) : line
        let attributed = (try? AttributedString(
            markdown: linkedMarkdown(content),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
        let font: Font = switch isHeading ? level : 0 {
        case 1: .title.weight(.semibold)
        case 2: .title2.weight(.semibold)
        case 3: .title3.weight(.semibold)
        case 4, 5, 6: .headline
        default: .body
        }
        return Text(attributed).font(font)
    }
}

@MainActor
final class LibraryWindowController {
    private var window: NSWindow?
    private var model: LibraryModel?
    private let workspace: () -> Workspace

    init(workspace: @escaping () -> Workspace) {
        self.workspace = workspace
    }

    func show() {
        if let window, let model {
            model.reloadSources()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = LibraryModel(workspace: workspace)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Library"
        // Zen: no visible title bar; the traffic lights always show.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = ContextTheme.editorBackground
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ContextLibrary")
        // Open on a note, so the Library starts as the note alone.
        model.selection = model.items.first?.id
        if model.selection == nil { model.reveal.showAll() }
        let hosting = NSHostingView(rootView: LibraryView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let container = ZenContainerView(frame: NSRect(x: 0, y: 0, width: 1040, height: 660))
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onPointer = { [weak model] point, _ in model?.pointer(point) }
        window.contentView = container
        window.center()
        self.window = window
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
