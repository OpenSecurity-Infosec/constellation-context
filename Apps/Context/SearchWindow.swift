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
        let hits = NoteSearch.search(query: query, in: store.liveNotes)
        let view = SearchListView(
            query: query,
            hits: hits,
            onQuery: { [weak self] q in self?.render(query: q) },
            onOpen: { [weak self] id in
                self?.onOpen(id)
                self?.window.orderOut(nil)
            }
        )
        window.contentView = NSHostingView(rootView: view)
    }
}

private struct SearchListView: View {
    var query: String
    var hits: [NoteSearch.Hit]
    var onQuery: (String) -> Void
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
                    onQuery(new)
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
                            Text(hits[i].title)
                                .font(.body).lineLimit(1)
                            if !hits[i].snippet.isEmpty {
                                Text(hits[i].snippet)
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
        .frame(minWidth: 420, minHeight: 320)
        .onKeyPress(.escape) {
            NSApp.keyWindow?.orderOut(nil)
            return .handled
        }
        .onKeyPress(.return) {
            if selected < hits.count {
                onOpen(hits[selected].id)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            selected = min(selected + 1, hits.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selected = max(selected - 1, 0)
            return .handled
        }
    }
}
