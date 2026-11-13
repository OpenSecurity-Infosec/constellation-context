import AppKit
@testable import ContextApp
import ContextStore
import ContextVault
import Foundation
import SwiftUI
import Testing

/// Renders the real overlay and Library into PNGs for a visual check,
/// without Screen Recording permission (the windows belong to this
/// process). Opt-in: set CONTEXT_SNAPSHOT_DIR to a folder; skipped otherwise.
/// Uses a temp vault and a temp linked-vault registry.
@MainActor
@Suite(.serialized) struct SnapshotTests {
    nonisolated static let dir = ProcessInfo.processInfo.environment["CONTEXT_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    func pump(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// Draws the whole window, title bar included, to `<dir>/<name>.png`.
    func snap(_ window: NSWindow, _ name: String) throws {
        guard let dir = Self.dir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pump(0.4)
        let view = try #require(window.contentView?.superview ?? window.contentView)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func tempWorkspace() -> Workspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-snap-\(UUID().uuidString)", isDirectory: true)
        return Workspace(vault: BaseVault(root: root))
    }

    @Test(.enabled(if: dir != nil)) func overlayStates() throws {
        let workspace = tempWorkspace()
        let controller = ContextWindowController(workspace: workspace, live: false)
        defer { controller.window.orderOut(nil) }
        controller.window.setFrame(NSRect(x: 80, y: 80, width: 640, height: 460), display: true)
        controller.window.makeKeyAndOrderFront(nil)
        controller.appendToCurrent("Weekly sync\nconfirm scope with design\ndeal stalls: get sales input\n\nmessaging rollout, are teams ready?")
        controller.render()
        try snap(controller.window, "01-overlay-rest")

        controller.chrome.pointer(CGPoint(x: 300, y: 10), height: 460)
        try snap(controller.window, "02-overlay-header")
        controller.chrome.pointer(nil, height: 460)

        _ = try workspace.apply(.createProject(name: "Launch"))
        controller.switchPad(.project("Launch"))
        controller.appendToCurrent("Launch\nship the zen canvas\nkeep files plain Markdown")
        controller.toggleInspector()
        try snap(controller.window, "03-overlay-inspector")
        controller.toggleInspector()
    }

    @Test(.enabled(if: dir != nil)) func overlayMarkdown() throws {
        let controller = ContextWindowController(workspace: tempWorkspace(), live: false)
        defer { controller.window.orderOut(nil) }
        controller.window.setFrame(NSRect(x: 80, y: 80, width: 640, height: 560), display: true)
        controller.window.makeKeyAndOrderFront(nil)
        controller.appendToCurrent("""
        Scratch

        ### What
        A **bold** idea, an *aside*, some `code`, and ~~a dropped plan~~.

        ## Next
        - ask [[Design Review]] about scope
        - [ ] draft the brief
        - [x] book the room
        > Less is more.
        """)
        controller.render()
        try snap(controller.window, "07-overlay-markdown")
    }

    @Test(.enabled(if: dir != nil)) func libraryStates() throws {
        let workspace = tempWorkspace()
        _ = try workspace.apply(.createNote(.scratch, text: "Q4 planning notes\nconfirm scope\nrisks and owners"))
        _ = try workspace.apply(.createNote(.scratch, text: "Launch brief\nwho, what, when"))
        let registry = LinkedVaultRegistry(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vaults-\(UUID().uuidString).json"))
        let model = LibraryModel(workspace: { workspace }, registry: registry)
        model.selection = model.items.first?.id
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        defer { window.orderOut(nil) }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ContextTheme.editorBackground
        window.contentView = NSHostingView(rootView: LibraryView(model: model))
        window.makeKeyAndOrderFront(nil)
        try snap(window, "04-library-rest")

        model.pointer(CGPoint(x: 4, y: 300))
        try snap(window, "05-library-edge")

        model.reveal.openedNote()
        try snap(window, "06-library-note-opened")
    }
}
