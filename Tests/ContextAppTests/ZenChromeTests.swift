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
        #expect(canvas.contains("AI"))
        #expect(canvas.contains("Export"))
        #expect(canvas.contains("Move to Trash"))
        #expect(!canvas.contains("Settings…"), "the canvas menu stays about the note")

        let more = controller.noteMenuItems(for: .more).map(\.title)
        #expect(more.contains("Library"))
        #expect(more.contains("Settings…"))
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
