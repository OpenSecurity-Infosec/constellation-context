import ContextDomain
import ContextStore
import ContextVault
import Foundation
import Testing

@Suite struct WorkspaceTests {
    @Test func dailyNoteReopensWithoutOverwritingAndSurvivesReindex() throws {
        let vault = tempVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let ws = Workspace(vault: vault)
        let date = Date(timeIntervalSince1970: 0)
        let zone = TimeZone(secondsFromGMT: 0) ?? .current
        let command = ContextCommand.openDailyNote(date: date, timeZone: zone)
        guard case .note(let id) = try ws.apply(command) else { Issue.record("Expected note"); return }
        #expect(ws.store(for: .scratch).fileURL(id: id)?.lastPathComponent == "1970-01-01.md")
        try ws.apply(.setText(.scratch, id: id, text: "Edited [[link]]"))
        #expect(try ws.apply(command) == .note(id))
        let again = Workspace(vault: vault)
        guard case .note(let reopened) = try again.apply(command) else { return }
        #expect(again.store(for: .scratch).note(id: reopened)?.text == "Edited [[link]]")
        let west = TimeZone(secondsFromGMT: -3600) ?? .current
        try again.apply(.openDailyNote(date: date, timeZone: west))
        #expect(FileManager.default.fileExists(atPath: vault.scratch.appendingPathComponent("1969-12-31.md").path))
    }

    @Test func templateCreationPreservesMarkdownAndUnknownTokens() throws {
        let vault = tempVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let ws = Workspace(vault: vault)
        let template = "---\ncustom: yes\n---\n# {{date}}\n[[link]] ![[image]] {{unknown}}"
        guard case .note(let id) = try ws.apply(.createFromTemplate(template, date: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0) ?? .current)) else { return }
        #expect(ws.store(for: .scratch).note(id: id)?.text == template.replacingOccurrences(of: "{{date}}", with: "1970-01-01"))
    }

    @Test func padsLiveInTheirOwnFolders() throws {
        let vault = tempVault()
        let ws = Workspace(vault: vault)
        guard case .note(let s) = try ws.apply(.createNote(.scratch, text: "scratch")),
              case .note(let c) = try ws.apply(.captureClip(text: "copied"))
        else { Issue.record("expected notes"); return }
        #expect(ws.store(for: .scratch).fileURL(id: s)?.deletingLastPathComponent().standardizedFileURL == vault.scratch.standardizedFileURL)
        #expect(ws.store(for: .clipboard).fileURL(id: c)?.deletingLastPathComponent().standardizedFileURL == vault.clipboard.standardizedFileURL)
        #expect(ws.store(for: .scratch).liveNotes.map(\.text) == ["scratch"])
        #expect(ws.store(for: .clipboard).liveNotes.map(\.text) == ["copied"])
    }

    @Test func trashAndRestoreReturnToTheRightPad() throws {
        let ws = Workspace(vault: tempVault())
        guard case .note(let c) = try ws.apply(.captureClip(text: "clip")) else { return }
        try ws.apply(.trash(.clipboard, id: c))
        #expect(ws.store(for: .clipboard).voidNotes.count == 1)
        #expect(ws.store(for: .scratch).voidNotes.isEmpty, "Scratch's Void does not show clipboard trash")
        // A fresh workspace (relaunch) still sees it in the right place.
        let again = Workspace(vault: ws.vault)
        #expect(again.store(for: .clipboard).voidNotes.map(\.text) == ["clip"])
        #expect(again.store(for: .scratch).voidNotes.isEmpty)
        try again.apply(.restore(.clipboard, id: c))
        #expect(again.store(for: .clipboard).liveNotes.map(\.text) == ["clip"])
    }

    @Test func clipboardCaptureSkipsRepeatsAndExpiresUnlessEdited() throws {
        let ws = Workspace(vault: tempVault())
        guard case .note(let a) = try ws.apply(.captureClip(text: "one")) else { return }
        #expect(try ws.apply(.captureClip(text: "one")) == CommandResult.none)
        try ws.apply(.captureClip(text: "two"))
        let clips = ws.store(for: .clipboard)
        #expect(clips.liveNotes.count == 2)
        #expect(clips.note(id: a)?.expiresAt != nil)
        try ws.apply(.setText(.clipboard, id: a, text: "one, edited"))
        #expect(clips.note(id: a)?.expiresAt == nil, "editing keeps the entry")
        clips.collectGarbage(now: Date().addingTimeInterval(ClipboardPolicy.lifetime + 60))
        #expect(clips.liveNotes.map(\.text) == ["one, edited"])
    }

    @Test func projectsAreFoldersWithOneContextNote() throws {
        let vault = tempVault()
        let ws = Workspace(vault: vault)
        #expect(try ws.apply(.createProject(name: "Context App")) == .project("Context App"))
        #expect(ws.projects == ["Context App"])
        #expect(ws.pads == [.scratch, .clipboard, .project("Context App")])
        let folder = vault.projects.appendingPathComponent("Context App")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("docs").path))
        let store = ws.store(for: .project("Context App"))
        let context = try #require(store.liveNotes.first)
        #expect(context.text == "# Context App\n\n")
        #expect(store.fileURL(id: context.id)?.lastPathComponent == "context.md")
        // A single-note pad hands back the same note instead of a new one.
        #expect(store.create().id == context.id)
        // Creating again is idempotent and keeps edits.
        try ws.apply(.setText(.project("Context App"), id: context.id, text: "# Context App\n\nUse Swift 6.\n"))
        try ws.apply(.createProject(name: "Context App"))
        #expect(ws.store(for: .project("Context App")).liveNotes.first?.text == "# Context App\n\nUse Swift 6.\n")
    }

    @Test func badProjectNamesAreRefused() {
        let ws = Workspace(vault: tempVault())
        for bad in ["", "   ", "///"] {
            #expect(throws: WorkspaceError.badProjectName) { try ws.apply(.createProject(name: bad)) }
        }
    }

    @Test func replaceAndAppendEditText() throws {
        let ws = Workspace(vault: tempVault())
        guard case .note(let id) = try ws.apply(.createNote(.scratch, text: "hello world")) else { return }
        try ws.apply(.replace(.scratch, id: id, range: NSRange(location: 6, length: 5), with: "there"))
        try ws.apply(.append(.scratch, id: id, text: "bye"))
        #expect(ws.store(for: .scratch).note(id: id)?.text == "hello there\nbye")
        #expect(throws: WorkspaceError.badRange) {
            try ws.apply(.replace(.scratch, id: id, range: NSRange(location: 99, length: 1), with: ""))
        }
        #expect(throws: WorkspaceError.noSuchNote) { try ws.apply(.setText(.clipboard, id: id, text: "x")) }
    }

    @Test func stagedTypingFlushesAcrossPads() throws {
        let ws = Workspace(vault: tempVault())
        guard case .note(let id) = try ws.apply(.createNote(.scratch, text: "a")) else { return }
        try ws.apply(.stageText(.scratch, id: id, text: "typed"))
        let url = ws.store(for: .scratch).fileURL(id: id)
        #expect(read(url) == "a")
        ws.flushAll()
        #expect(read(url) == "typed")
    }
}

@Suite struct ClipboardPolicyTests {
    @Test func skipsSecretsBlanksAndRepeats() {
        #expect(ClipboardPolicy.shouldCapture(text: "hi", types: ["public.utf8-plain-text"], previous: nil))
        #expect(!ClipboardPolicy.shouldCapture(text: "hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], previous: nil))
        #expect(!ClipboardPolicy.shouldCapture(text: "otp", types: ["org.nspasteboard.TransientType"], previous: nil))
        #expect(!ClipboardPolicy.shouldCapture(text: "  \n", types: [], previous: nil))
        #expect(!ClipboardPolicy.shouldCapture(text: nil, types: [], previous: nil))
        #expect(!ClipboardPolicy.shouldCapture(text: "same", types: [], previous: "same"))
        #expect(!ClipboardPolicy.shouldCapture(text: String(repeating: "x", count: ClipboardPolicy.maxCharacters + 1), types: [], previous: nil))
    }

    @Test func pasteKeepsMarkdown() {
        let md = "- one\n  - nested\n> quote\n| a | b |\n|---|---|\n```swift\nlet x = 1\n```"
        #expect(PlainText.normalizePaste(md) == md)
        #expect(PlainText.normalizePaste("a\r\nb\u{00A0}c\u{200B}") == "a\nb c")
    }
}
