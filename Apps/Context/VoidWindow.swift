import ContextStore
import SwiftUI

/// The Void: recoverable trash for deleted notes.
@MainActor
final class VoidWindowController {
    private let window: NSWindow
    private let workspace: Workspace
    private let pad: Pad
    private var store: NoteStore { workspace.store(for: pad) }
    private let onRestore: (UUID) -> Void

    init(workspace: Workspace, pad: Pad, onRestore: @escaping (UUID) -> Void) {
        self.workspace = workspace
        self.pad = pad
        self.onRestore = onRestore
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "The Void"
        window.center()
        render()
    }

    func show() {
        render()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var lastNotice = ""

    private func perform(_ action: () throws -> Void) {
        lastNotice = ""
        do { try action() } catch { lastNotice = "The note could not be changed." }
        render()
    }

    private func render() {
        let void = store.voidNotes
        let view = VoidListView(notes: void, notice: lastNotice, onRestore: { [weak self] id in
            guard let self else { return }
            perform {
                try workspace.apply(.restore(pad, id: id))
                onRestore(id)
            }
        }, onRestoreMany: { [weak self] ids in
            guard let self else { return }
            perform {
                guard case .restored(let result) = try workspace.apply(.restoreMany(pad, ids: ids, now: Date())) else { return }
                if let first = ids.first(where: { store.note(id: $0)?.isTrashed == false }) { onRestore(first) }
                lastNotice = "Restored \(result.restored); \(result.skippedExpired) expired left behind."
            }
        }, onDestroy: { [weak self] id in
            guard let self else { return }
            perform { try workspace.apply(.destroy(pad, id: id)) }
        })
        window.contentView = NSHostingView(rootView: view)
    }
}

private struct VoidListView: View {
    var notes: [ContextNote]
    var notice: String
    var onRestore: (UUID) -> Void
    var onRestoreMany: ([UUID]) -> Void
    var onDestroy: (UUID) -> Void
    @State private var selection: Set<UUID> = []
    var body: some View {
        VStack(alignment: .leading) {
            Text("Deleted notes linger here for 30 days.")
                .font(.caption).foregroundStyle(.secondary)
                .padding([.top, .horizontal])
            if !notice.isEmpty {
                Text(notice)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            if notes.isEmpty {
                Text("The Void is empty.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Button("Restore Selected (\(selection.count))") {
                        onRestoreMany(Array(selection))
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                    Button("Clear Selection") { selection = [] }
                        .disabled(selection.isEmpty)
                }
                .padding(.horizontal)
                List(notes, id: \.id, selection: $selection) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.text.components(separatedBy: .newlines).first ?? "(empty)")
                                .lineLimit(1)
                            if let label = NoteExpiry.label(for: note) {
                                Text(label)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Restore") { onRestore(note.id) }
                        Button("Delete") { onDestroy(note.id) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

import ContextDomain
