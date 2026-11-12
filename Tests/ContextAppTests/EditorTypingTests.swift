import AppKit
@testable import ContextApp
import ContextStore
import ContextVault
import Foundation
import Testing

/// Hosts the real overlay on a temp vault and types into it with key
/// events, the way a person does. Needs a logged-in desktop session.
@MainActor
@Suite(.serialized) struct EditorTypingTests {
    func makeController() -> ContextWindowController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-typing-\(UUID().uuidString)", isDirectory: true)
        let controller = ContextWindowController(workspace: Workspace(vault: BaseVault(root: root)), live: false)
        controller.window.makeKeyAndOrderFront(nil)
        pump(0.2)
        return controller
    }

    func textView(_ controller: ContextWindowController) throws -> ContextTextView {
        func find(_ view: NSView) -> ContextTextView? {
            if let tv = view as? ContextTextView { return tv }
            for sub in view.subviews { if let tv = find(sub) { return tv } }
            return nil
        }
        let tv = try #require(controller.window.contentView.flatMap(find))
        controller.window.makeFirstResponder(tv)
        pump(0.05)
        return tv
    }

    func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Sends one character as a real key-down through the window.
    func type(_ string: String, into window: NSWindow, pause: TimeInterval = 0.01) {
        for ch in string {
            let s = String(ch)
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: s, charactersIgnoringModifiers: s,
                isARepeat: false, keyCode: 0
            ) else { continue }
            window.sendEvent(event)
            pump(pause)
        }
    }

    @Test func typingASentenceReadsBackInOrder() throws {
        let controller = makeController()
        let tv = try textView(controller)
        let sentence = "the quick brown fox jumps over the lazy dog"
        type(sentence, into: controller.window)
        pump(0.3)
        #expect(tv.string == sentence)
        #expect(tv.selectedRange().location == (sentence as NSString).length, "caret stays at the end")
        #expect(controller.note.text == sentence)
    }

    @Test func typingSurvivesTimerRendersBetweenKeys() throws {
        let controller = makeController()
        let tv = try textView(controller)
        let sentence = "slow typing across many timer ticks"
        // Longer than the 0.25 s render tick between some keys.
        type(sentence, into: controller.window, pause: 0.09)
        pump(0.3)
        #expect(tv.string == sentence)
        #expect(controller.note.text == sentence)
    }

    @Test func typingInTheMiddleKeepsTheCaretThere() throws {
        let controller = makeController()
        let tv = try textView(controller)
        type("hello world", into: controller.window)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        type(", big", into: controller.window)
        pump(0.3)
        #expect(tv.string == "hello, big world")
        #expect(tv.selectedRange().location == 10)
    }

    @Test func savedFileMatchesWhatWasTyped() throws {
        let controller = makeController()
        _ = try textView(controller)
        let sentence = "the quick brown fox"
        type(sentence, into: controller.window)
        controller.flushNow()
        let url = try #require(controller.store.fileURL(id: controller.noteID))
        #expect(try String(contentsOf: url, encoding: .utf8) == sentence)
    }

    /// macOS inline predictions and input methods show provisional text as
    /// marked text after the caret. It must never be saved or written back
    /// as real characters.
    @Test func markedTextIsNeverCommitted() throws {
        let controller = makeController()
        let tv = try textView(controller)
        type("asdfdd", into: controller.window)
        tv.setMarkedText("da", selectedRange: NSRange(location: 0, length: 0), replacementRange: tv.selectedRange())
        pump(0.8) // several timer renders and a flush
        #expect(controller.note.text == "asdfdd", "provisional text is not saved")
        #expect(tv.string == "asdfddda", "the view still shows it until it resolves")
        #expect(tv.selectedRange().location == 6, "caret stays before the provisional text")
        // Typing on replaces the provisional text.
        tv.insertText("x", replacementRange: tv.markedRange())
        pump(0.3)
        #expect(tv.string == "asdfddx")
        #expect(controller.note.text == "asdfddx")
    }

    @Test func committedCompositionIsSaved() throws {
        let controller = makeController()
        let tv = try textView(controller)
        type("caf", into: controller.window)
        tv.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: tv.selectedRange())
        pump(0.4)
        tv.insertText("é", replacementRange: tv.markedRange())
        pump(0.3)
        #expect(tv.string == "café")
        #expect(controller.note.text == "café")
        #expect(tv.selectedRange().location == 4)
    }

    @Test func editsFromElsewhereShowUpAndNoteSwitchesLoadTheRightText() throws {
        let controller = makeController()
        let tv = try textView(controller)
        type("first", into: controller.window)
        controller.appendToCurrent("appended by a command")
        pump(0.2)
        #expect(tv.string == "first\nappended by a command")
        controller.newNote()
        pump(0.2)
        #expect(tv.string == "")
        type("second", into: controller.window)
        controller.nextNote() // notes are newest first; "first" is next
        pump(0.2)
        pump(0.2)
        #expect(tv.string == "first\nappended by a command")
        #expect(tv.selectedRange().location == ("first\nappended by a command" as NSString).length)
    }
}

@MainActor
struct MarkdownStylingTests {
    @Test func stylingPreservesSourceSelectionAndResetsRemovedSyntax() throws {
        let view = ContextTextView()
        view.string = "Title\n# Heading\n**bold** _italic_\n- [x] task\n> quote\n[[note]] [site](https://example.com)\n`code`"
        let original = view.string
        view.setSelectedRange(NSRange(location: 12, length: 3))
        view.refreshStyling()
        #expect(view.string == original)
        #expect(view.selectedRange() == NSRange(location: 12, length: 3))
        let storage = try #require(view.textStorage)
        let link = (original as NSString).range(of: "[[note]]")
        #expect(storage.attribute(.underlineStyle, at: link.location, effectiveRange: nil) != nil)
        view.string = "plain"
        view.refreshStyling()
        #expect(storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }
}

@MainActor
struct FencedCodeStylingTests {
    @Test func longerClosingFencesRestoreProseStyling() throws {
        for marker in ["`", "~"] {
            let fence = String(repeating: marker, count: 3)
            let source = "Title\n" + fence + "swift\n[[inside]] **literal**\n" + fence + marker + "\n[[outside]]"
            let storage = NSTextStorage(string: source)
            MarkdownStyling.apply(to: storage)
            let inside = (source as NSString).range(of: "[[inside]]").location
            let outside = (source as NSString).range(of: "[[outside]]").location
            #expect(storage.attribute(.underlineStyle, at: inside, effectiveRange: nil) == nil)
            #expect(storage.attribute(.underlineStyle, at: outside, effectiveRange: nil) != nil)
            #expect(storage.string == source)
        }
    }
}
