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

    var source: LibrarySource? = .pad(.scratch) { didSet { if oldValue != source { query = ""; loadItems() } } }
    var items: [LibraryItem] = []
    var query = "" { didSet { if oldValue != query { loadItems() } } }
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
        projects = workspace().projects
        loadItems()
    }

    // MARK: - Listing

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
        case .linked(let id)?:
            items = []
            guard let connector = connectors[id] else { return }
            loadTask = Task {
                do {
                    let list = try await connector.list()
                    guard !Task.isCancelled else { return }
                    items = list.map { LibraryItem(id: .linked($0.ref), title: $0.title, snippet: $0.snippet, modified: $0.modified, source: connector.displayName) }
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
                items += hits.map { LibraryItem(id: .linked($0.ref), title: $0.title, snippet: $0.snippet, modified: $0.modified, source: connector.displayName) }
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
                let written = try await connector.write(note)
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

    static func line(_ line: String) -> some View {
        var level = 0
        var rest = Substring(line)
        while rest.hasPrefix("#"), level < 6 { level += 1; rest = rest.dropFirst() }
        let isHeading = level > 0 && rest.hasPrefix(" ")
        let content = isHeading ? String(rest.dropFirst()) : line
        let attributed = (try? AttributedString(
            markdown: content,
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
