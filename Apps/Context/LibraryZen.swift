import AppKit
import ContextDomain
import SwiftUI

/// Which Library panels show. At rest the Library is the note alone. The
/// pointer at the left edge slides in the sources and the note list;
/// opening a note hides the sources; moving into the text hides the list.
struct LibraryReveal: Equatable {
    enum Panels: Equatable {
        case none
        case list
        case all
    }

    static let sourcesWidth: CGFloat = 190
    static let listWidth: CGFloat = 260
    /// Pointer within this distance of the left edge reveals the panels.
    static let edgeBand: CGFloat = 14
    /// How far into the text the pointer goes before the panels leave.
    static let leaveMargin: CGFloat = 24

    private(set) var panels: Panels = .none
    private(set) var header = false
    /// Set by the keyboard toggle, so the panels stay until toggled off.
    private var pinned = false

    var panelsWidth: CGFloat {
        switch panels {
        case .none: 0
        case .list: Self.listWidth
        case .all: Self.sourcesWidth + Self.listWidth
        }
    }

    /// `point` is measured from the window's top-left; nil means it left.
    mutating func pointer(_ point: CGPoint?, hasNote: Bool) {
        guard let point else {
            header = false
            return
        }
        if point.x <= Self.edgeBand {
            panels = .all
            pinned = false
        } else if hasNote, !pinned, panels != .none, point.x > panelsWidth + Self.leaveMargin {
            panels = .none
        }
        header = point.y <= ZenMetrics.headerBand && point.x > panelsWidth
    }

    /// Opening a note hides the sources at once; the list stays until the
    /// pointer moves into the text.
    mutating func openedNote() {
        if panels == .all { panels = .list }
    }

    /// With no note open there is nothing to read, so show where to look.
    mutating func showAll() {
        panels = .all
    }

    /// ⌃⌘S: show or hide the panels from the keyboard.
    mutating func toggle() {
        panels = panels == .none ? .all : .none
        pinned = panels != .none
    }
}

struct LibraryView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            if model.reveal.panels == .all {
                sources
                    .frame(width: LibraryReveal.sourcesWidth)
                    .transition(.move(edge: .leading))
            }
            if model.reveal.panels != .none {
                notes
                    .frame(width: LibraryReveal.listWidth)
                    .transition(.move(edge: .leading))
            }
            LibraryCanvas(model: model)
        }
        .contextMenu {
            Button("New Note") { model.createNote() }.keyboardShortcut("n")
                .accessibilityIdentifier("library.context.new")
            Button("Rename Note…") { model.renameNote() }.disabled(!model.canRename)
                .accessibilityIdentifier("library.context.rename")
            Button("Move to The Void") { model.deleteNote() }.disabled(!model.canDelete)
                .accessibilityIdentifier("library.context.trash")
        }
        .animation(.easeOut(duration: 0.2), value: model.reveal)
        .background(Color.ctxEditorBackground)
        .ignoresSafeArea()
        .frame(minWidth: 520, minHeight: 360)
        .background {
            Button("New Note") { model.createNote() }.keyboardShortcut("n").accessibilityIdentifier("library.new").hidden()
            Button("Toggle Sidebar") { model.reveal.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var sources: some View {
        List(selection: $model.source) {
            Section("Context") {
                Label("Scratch", systemImage: "note.text").tag(LibrarySource.pad(.scratch))
                Label("Clipboard", systemImage: "doc.on.clipboard").tag(LibrarySource.pad(.clipboard))
            }
            if !model.projects.isEmpty {
                Section("Projects") {
                    ForEach(model.projects, id: \.self) { name in
                        Label(name, systemImage: "folder").tag(LibrarySource.pad(.project(name)))
                    }
                }
            }
            if !model.linked.isEmpty {
                Section("Linked") {
                    ForEach(model.linked) { vault in
                        Label(vault.name, systemImage: vault.kind == .anytype ? "square.stack" : "books.vertical")
                            .tag(LibrarySource.linked(vault.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 32)
        .background(Color.ctxPanelBackground)
        .accessibilityIdentifier("library.sources")
    }

    private var notes: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Search everything", text: $model.query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("library.search")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.top, 38)
            .padding(.bottom, 8)
            List(model.items, selection: $model.selection) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).lineLimit(1)
                    if !item.snippet.isEmpty {
                        Text(item.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !model.query.isEmpty {
                        Text(item.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .tag(item.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.ctxEditorBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5)
        }
        .accessibilityIdentifier("library.notes")
    }
}

/// The open note. Read mode renders Markdown with images inline; Edit mode
/// is the raw Markdown. The file on disk is always exactly the Markdown.
/// Controls live in a header that fades in at the top edge.
struct LibraryCanvas: View {
    @Bindable var model: LibraryModel

    var body: some View {
        ZStack(alignment: .top) {
            content
            header
                .opacity(model.reveal.header ? 1 : 0)
                .allowsHitTesting(model.reveal.header)
            if let status = model.status {
                VStack {
                    Spacer()
                    Text(status)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.reveal.header)
        .background(Color.ctxEditorBackground)
        .background {
            Button("Toggle Edit") { model.editing.toggle() }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.selection == nil {
            Color.clear
        } else if model.editing {
            PlainTextEditor(text: model.text, noteID: AnyHashable(model.selection),
                            onChange: { model.textChanged($0) })
                .accessibilityIdentifier("library.editor")
        } else {
            ScrollView {
                CanvasReader(text: model.text, imageURL: model.imageURL, followLink: model.followLink)
                    .padding(.horizontal, ZenMetrics.textInset.width)
                    .padding(.top, ZenMetrics.textInset.height)
                    .padding(.bottom, ZenMetrics.textInset.width)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("library.reader")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            if model.selection != nil {
                Button {
                    model.editing.toggle()
                } label: {
                    Image(systemName: model.editing ? "book" : "pencil")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.editing ? "Read (⌘E)" : "Edit (⌘E)")
                .accessibilityIdentifier("library.mode")
                Menu {
                    Button("New Note") { model.createNote() }.keyboardShortcut("n").accessibilityIdentifier("library.new")
                    Button("Rename Note…") { model.renameNote() }.disabled(!model.canRename).accessibilityIdentifier("library.rename")
                    Button("Move to The Void") { model.deleteNote() }.disabled(!model.canDelete).accessibilityIdentifier("library.trash")
                    if !model.projects.isEmpty {
                        Menu("Add to Project") {
                            ForEach(model.projects, id: \.self) { p in Button(p) { model.addToProject(p) } }
                        }
                        .accessibilityIdentifier("library.addToProject")
                    }
                    if let file = model.selectedFile {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityIdentifier("library.more")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: ZenMetrics.headerHeight)
        .background {
            Color.ctxEditorBackground
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}
