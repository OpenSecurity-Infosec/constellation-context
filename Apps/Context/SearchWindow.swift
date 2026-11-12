import ContextDomain
import ContextStore
import SwiftUI

/// ⌘F note search pane: Antinote-style find across titles + bodies.
/// Type to filter, ↑/↓ to move, Return to open, Esc to dismiss.
@MainActor
final class SearchWindowController {
    private let window: NSWindow
    private let store: NoteStore
    private let onOpen: (UUID) -> Void

    init(store: NoteStore, onOpen: @escaping (UUID) -> Void) {
        self.store = store
        self.onOpen = onOpen
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Search Notes  (⌘F)"
        window.center()
        render(query: "")
    }

    func open(query: String) {
        render(query: query)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func show() {
        render(query: "")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func render(query: String) {
        let view = SearchListView(query: query, store: store, onOpen: { [weak self] id in
            self?.onOpen(id)
            self?.window.orderOut(nil)
        })
        window.contentView = NSHostingView(rootView: view)
    }
}

private struct SearchListView: View {
    var query: String
    var store: NoteStore
    private var hits: [NoteSearch.Hit] { NoteSearch.search(query: text, in: store.liveNotes) }
    @State private var revision = 0
    @State private var renaming: NoteStore.SavedSearch?
    @State private var name = ""
    @State private var browsingSaved = false
    private var saved: [NoteStore.SavedSearch] { store.savedSearches }

    private func highlight(_ value: String) -> Text {
        var result = AttributedString(value)
        for range in NoteSearch.highlightRanges(query: text, in: value) {
            if let range = Range(range, in: result) {
                result[range].backgroundColor = .yellow.opacity(0.35)
                result[range].font = .body.bold()
            }
        }
        return Text(result)
    }
    var onOpen: (UUID) -> Void

    @State private var text: String = ""
    @State private var selected: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search notes…", text: $text)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .focused($focused)
                .onAppear { text = query; focused = true }
                .onChange(of: text) { _, new in
                    selected = 0
                    browsingSaved = false
                }
            HStack {
                Button("Save Query") { store.saveSearch(query: text); revision += 1 }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Toggle("Saved searches", isOn: $browsingSaved).toggleStyle(.button)
                    .onChange(of: browsingSaved) { _, _ in selected = 0 }
            }.padding(.horizontal, 10)
            if browsingSaved {
                List(saved.indices, id: \.self) { i in
                    HStack {
                        Button(saved[i].name) { text = saved[i].query }
                        Spacer()
                        Button(saved[i].pinned ? "Unpin" : "Pin") {
                            store.editSearch(id: saved[i].id, togglePin: true); revision += 1
                        }
                        Button("Rename") { renaming = saved[i]; name = saved[i].name }
                        Button("Delete") { store.editSearch(id: saved[i].id, delete: true); selected = 0; revision += 1 }
                    }.background(i == selected ? Color.accentColor.opacity(0.15) : Color.clear)
                }.frame(height: 130)
            }
            Divider()
            if hits.isEmpty {
                Text("No matches. Esc to dismiss.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(hits.indices, id: \.self) { i in
                    Button {
                        onOpen(hits[i].id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            highlight(hits[i].title)
                                .font(.body).lineLimit(1)
                            if !hits[i].snippet.isEmpty {
                                highlight(hits[i].snippet)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                        .background(i == selected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .id(revision)
        .alert("Rename saved search", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let search = renaming { store.editSearch(id: search.id, name: name); revision += 1 }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onKeyPress(.escape) {
            NSApp.keyWindow?.orderOut(nil)
            return .handled
        }
        .onKeyPress(.return) {
            if browsingSaved {
                if saved.indices.contains(selected) { text = saved[selected].query }
                return .handled
            }
            if hits.indices.contains(selected) {
                onOpen(hits[selected].id)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            selected = max(0, min(selected + 1, (browsingSaved ? saved.count : hits.count) - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selected = max(selected - 1, 0)
            return .handled
        }
    }
}
