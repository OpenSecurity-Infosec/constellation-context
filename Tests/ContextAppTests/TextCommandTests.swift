import AppKit
@testable import ContextApp
import ContextDomain
import ContextStore
import ContextVault
import Foundation
import Testing

@MainActor @Suite(.serialized) struct TextCommandTests {
    @Test func commandsPersistThroughWorkspaceAndLegacyNotesStayPlain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-command-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(vault: BaseVault(root: root))
        let controller = ContextWindowController(workspace: workspace, live: false)
        let original = "📝\n2 + 2\n::math"
        controller.onTextChange(original)
        controller.runSlashCommand(name: "math", tokenRange: (original as NSString).range(of: "::math"))
        #expect(controller.note.text == "📝\n2 + 2\n4")
        let id = controller.note.id
        controller.flushNow()
        #expect(Workspace(vault: BaseVault(root: root)).store(for: .scratch).note(id: id)?.text == controller.note.text)
        for word in ["math", "list", "code", "timer", "paste"] {
            controller.onTextChange(word + "\n[[link]]")
            #expect(controller.note.kind == .plain)
            #expect(controller.note.text == word + "\n[[link]]")
        }
    }

    @Test func commandIsOneNativeUndoableWorkspaceEdit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-command-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        controller.onTextChange("apple\n::list")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        func find(_ view: NSView) -> ContextTextView? {
            if let tv = view as? ContextTextView { return tv }
            return view.subviews.lazy.compactMap(find).first
        }
        let tv = try #require(controller.window.contentView.flatMap(find))
        controller.window.makeFirstResponder(tv)
        let undo = try #require(tv.undoManager)
        undo.removeAllActions()
        undo.beginUndoGrouping()
        controller.runSlashCommand(name: "list", tokenRange: NSRange(location: 6, length: 6))
        undo.endUndoGrouping()
        #expect(controller.note.text == "- [ ] apple")
        undo.undo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        #expect(tv.string == "apple\n::list")
        #expect(controller.note.text == tv.string)
        undo.redo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        #expect(controller.note.text == "- [ ] apple")
        controller.flushNow()
    }

    @Test func stopwatchOnlyChangesTextWhenInvoked() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-command-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        let start = Date(timeIntervalSince1970: 1000)
        controller.onTextChange("::timer")
        controller.runSlashCommand(name: "timer", tokenRange: NSRange(location: 0, length: 7), now: start)
        #expect(controller.note.text == NoteTimer.format(0))
        controller.onTextChange("::timer")
        controller.runSlashCommand(name: "timer", tokenRange: NSRange(location: 0, length: 7), now: start.addingTimeInterval(65))
        #expect(controller.note.text == NoteTimer.format(65))
    }
}
