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
        var lights: [Bool] = []
        chrome.onHeaderChange = { lights.append($0) }
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
        #expect(lights == [true, false], "traffic lights follow the header")
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
