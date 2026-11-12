import AppKit
@testable import ContextApp
import ContextStore
import ContextVault
import Foundation
import Testing

/// The zen canvas shows no chrome until the pointer reaches an edge, and
/// every note action stays reachable from the shared note menu.
@MainActor
@Suite(.serialized) struct ZenChromeTests {
    @Test func chromeIsHiddenUntilThePointerReachesAnEdge() {
        let chrome = ZenChrome()
        #expect(!chrome.header && !chrome.footer)

        chrome.pointer(CGPoint(x: 200, y: 200), height: 480)
        #expect(!chrome.header && !chrome.footer, "the middle of the canvas shows nothing")

        chrome.pointer(CGPoint(x: 200, y: 10), height: 480)
        #expect(chrome.header && !chrome.footer)

        chrome.typing()
        #expect(!chrome.header, "typing hides the header")

        chrome.pointer(CGPoint(x: 200, y: 470), height: 480)
        #expect(chrome.footer && !chrome.header)

        chrome.pointer(nil, height: 480)
        #expect(!chrome.header && !chrome.footer, "leaving the window hides everything")
    }

    @Test func everyNoteActionIsInTheSharedMenu() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-zen-\(UUID().uuidString)", isDirectory: true)
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        defer { controller.window.orderOut(nil) }

        let canvas = controller.noteMenuItems(for: .canvas).map(\.title)
        #expect(canvas.contains("New Note"))
        #expect(canvas.contains("Search…"))
        #expect(canvas.contains("AI"))
        #expect(canvas.contains("Export"))
        #expect(canvas.contains("Move to Trash"))
        #expect(!canvas.contains("Settings…"), "the canvas menu stays about the note")

        let more = controller.noteMenuItems(for: .more).map(\.title)
        #expect(more.contains("The Void"))
        let export = controller.noteMenuItems(for: .menuBar).first { $0.title == "Export" }
        #expect(export?.submenu?.items.first { $0.title == "Save Markdown As…" }?.keyEquivalent == "e")
        #expect(more.contains("Library"))
        #expect(more.contains("Settings…"))
    }

    @Test func inspectorGrowsTheWindowAndGivesTheRoomBack() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-insp-\(UUID().uuidString)", isDirectory: true)
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        defer { controller.window.orderOut(nil) }
        controller.window.setFrame(NSRect(x: 100, y: 100, width: 640, height: 480), display: false)
        let before = controller.window.frame

        #expect(controller.noteMenuItems(for: .canvas).map(\.title).contains("Show Inspector"))
        controller.toggleInspector()
        #expect(controller.inspectorOpen)
        #expect(controller.window.frame.width == before.width + NoteInspector.width)
        #expect(controller.window.frame.minX == before.minX, "the text stays where it was")
        #expect(controller.noteMenuItems(for: .canvas).map(\.title).contains("Hide Inspector"))

        controller.toggleInspector()
        #expect(!controller.inspectorOpen)
        #expect(controller.window.frame.width == before.width)
    }
}

/// Typography is display only: the title is set larger, and the saved
/// text is exactly what was typed.
@MainActor
@Suite(.serialized) struct CanvasTypeTests {
    @Test func firstLineIsSetAsATitleAndTheFileStaysPlain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-type-\(UUID().uuidString)", isDirectory: true)
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        defer { controller.window.orderOut(nil) }
        controller.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func find(_ view: NSView) -> ContextTextView? {
            if let tv = view as? ContextTextView { return tv }
            for sub in view.subviews { if let tv = find(sub) { return tv } }
            return nil
        }
        let tv = try #require(controller.window.contentView.flatMap(find))
        controller.window.makeFirstResponder(tv)
        tv.insertText("Weekly sync", replacementRange: tv.selectedRange())
        tv.insertText("\n", replacementRange: tv.selectedRange())
        tv.insertText("confirm scope", replacementRange: tv.selectedRange())
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let storage = try #require(tv.textStorage)
        let titleFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let bodyFont = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont)
        #expect(titleFont.pointSize > bodyFont.pointSize * 1.5)
        #expect(controller.note.text == "Weekly sync\nconfirm scope")

        // A mode note keeps uniform lines for its gutter.
        tv.setSelectedRange(NSRange(location: 0, length: storage.length))
        tv.insertText("math\n2 + 2", replacementRange: tv.selectedRange())
        let mathFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(mathFont.pointSize == bodyFont.pointSize)
    }
}

/// The zen Library: the note alone at rest, panels from the left edge.
struct LibraryRevealTests {
    @Test func panelsFollowTheLeftEdgeAndTheOpenNote() {
        var reveal = LibraryReveal()
        #expect(reveal.panels == .none, "opens as the note alone")

        reveal.pointer(CGPoint(x: 400, y: 300), hasNote: true)
        #expect(reveal.panels == .none)

        reveal.pointer(CGPoint(x: 4, y: 300), hasNote: true)
        #expect(reveal.panels == .all, "the left edge brings in sources and list")

        reveal.pointer(CGPoint(x: 300, y: 300), hasNote: true)
        #expect(reveal.panels == .all, "moving over the panels keeps them")

        reveal.openedNote()
        #expect(reveal.panels == .list, "opening a note hides the sources")

        reveal.pointer(CGPoint(x: 200, y: 300), hasNote: true)
        #expect(reveal.panels == .list, "the list stays while the pointer is on it")

        reveal.pointer(CGPoint(x: 600, y: 300), hasNote: true)
        #expect(reveal.panels == .none, "moving into the text hides the list")
    }

    @Test func noNoteKeepsPanelsAndTheKeyboardTogglePins() {
        var reveal = LibraryReveal()
        reveal.showAll()
        reveal.pointer(CGPoint(x: 900, y: 300), hasNote: false)
        #expect(reveal.panels == .all, "with nothing open, the panels stay")

        var pinned = LibraryReveal()
        pinned.toggle()
        pinned.pointer(CGPoint(x: 900, y: 300), hasNote: true)
        #expect(pinned.panels == .all, "⌃⌘S panels stay until toggled off")
        pinned.toggle()
        #expect(pinned.panels == .none)
    }

    @Test func headerShowsOnlyOverTheNote() {
        var reveal = LibraryReveal()
        reveal.pointer(CGPoint(x: 400, y: 10), hasNote: true)
        #expect(reveal.header)
        reveal.pointer(CGPoint(x: 4, y: 10), hasNote: true)
        #expect(!reveal.header, "over the panels the header stays hidden")
        reveal.pointer(nil, hasNote: true)
        #expect(!reveal.header)
    }
}
