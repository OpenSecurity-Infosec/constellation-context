import AppKit
import ContextDomain
import ContextExport
import ContextMath
import ContextStore
import ContextVault
import SwiftUI
import Vision

/// Main scratchpad window: borderless floating panel with swipe navigation,
/// explicit text commands, OCR drop, and export.
@MainActor
final class ContextWindowController {
    let window: ContextPanel
    private(set) var workspace: Workspace
    private(set) var pad: Pad = .scratch
    /// The current pad's notes. Reads go here; every change goes through
    /// `workspace.apply` (one mutation path).
    var store: NoteStore { workspace.store(for: pad) }
    private let clipboard = ClipboardWatcher()
    let projects = ProjectContextService()
    /// Cached `ProjectInfo` for the current pad; renders run 4× a second.
    var projectInfoCache: (pad: Pad, info: ProjectInfo?)?
    var aiState: AIState = .idle
    var aiTask: Task<Void, Never>?
    private(set) var noteID: UUID
    private var commandTimers: [UUID: Date] = [:]
    private var hosting: NSHostingView<ContextEditorRoot>?
    /// Hover chrome for the zen canvas.
    let chrome = ZenChrome()
    /// Whether the settings panel is open on the right.
    private(set) var inspectorOpen = false

    /// Tests pass a temporary workspace. `live` remains source-compatible; no rate fetch occurs.
    init(workspace: Workspace? = nil, live: Bool = true) {
        self.workspace = workspace ?? Self.openWorkspace()
        for p in [Pad.scratch, .clipboard] { self.workspace.store(for: p).collectGarbage() }
        let scratch = self.workspace.store(for: .scratch)
        let first = scratch.liveNotes.first ?? scratch.create()
        noteID = first.id
        window = ContextPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Context"
        // Zen canvas: no visible title bar. The traffic lights always show;
        // hiding them makes the window look broken.
        // the header when the pointer reaches the top edge.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isFloatingPanel = true
        window.level = .floating
        window.center()
        window.isMovableByWindowBackground = false
        window.onSwipe = { [weak self] direction in self?.applySwipe(direction) }
        ContextTheme.apply(mode: ContextSettings.shared.themeMode)
        render()
        applyLook()
        updatePin()
    }

    /// The base vault from Settings (default `~/Context`), after a one-time
    /// move of legacy `notes.json` content into it.
    static func openWorkspace() -> Workspace {
        let vault = BaseVault(root: ContextSettings.shared.baseVaultPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? BaseVault.defaultRoot)
        if let legacy = NotesJSONMigration.legacyFile {
            _ = try? NotesJSONMigration.run(from: legacy, into: vault)
        }
        return Workspace(vault: vault)
    }

    /// Switches to another base-vault folder. Files in the old folder stay
    /// where they are.
    func switchVault(to url: URL) {
        flushNow()
        ContextSettings.shared.baseVaultPath = url.path
        ContextSettings.shared.save()
        workspace = Self.openWorkspace()
        commandTimers.removeAll()
        pad = .scratch
        noteID = store.liveNotes.first?.id ?? store.create().id
        afterNavigate()
    }

    // MARK: - Pads and commands

    /// Applies one command through the workspace. Failures (a note
    /// deleted under us) are dropped; the next render shows the truth.
    @discardableResult
    func apply(_ command: ContextCommand) -> CommandResult? {
        try? workspace.apply(command)
    }

    private func setText(_ text: String) {
        apply(.setText(pad, id: noteID, text: text))
    }

    var pads: [Pad] { workspace.pads }

    func switchPad(_ next: Pad) {
        flushNow()
        pad = next
        store.reloadFromDisk()
        noteID = store.liveNotes.first?.id ?? store.create().id
        afterNavigate()
        refreshProjectFile()
        show()
    }

    func switchPad(number: Int) {
        let all = pads
        guard number >= 1, number <= all.count else { return }
        switchPad(all[number - 1])
    }

    func promptNewProject() {
        let alert = NSAlert()
        alert.messageText = "New Project"
        alert.informativeText = "A project keeps the live context you want your AI tools to see."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Project name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard case .project(let name)? = apply(.createProject(name: field.stringValue)) else {
            self.alert("Use a name with letters or numbers.")
            return
        }
        switchPad(.project(name))
    }

    /// Clipboard history: every copy becomes an editable note in the
    /// Clipboard pad, except secrets password managers mark as concealed.
    func startClipboardHistory() {
        guard ContextSettings.shared.clipboardHistory else {
            clipboard.stop()
            return
        }
        clipboard.start { [weak self] text in
            guard let self else { return }
            guard case .note? = self.apply(.captureClip(text: text)) else { return }
            if self.pad == .clipboard, !self.window.isKeyWindow {
                self.noteID = self.store.liveNotes.first?.id ?? self.noteID
                self.render()
            }
        }
    }

    var note: ContextNote { store.note(id: noteID) ?? ContextNote(text: "") }

    func show() {
        flushNow()
        projectInfoCache = nil
        refreshProjectFile()
        if store.reloadFromDisk() {
            if store.note(id: noteID) == nil {
                noteID = store.liveNotes.first?.id ?? store.create().id
            }
            render(preservingFocus: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens or closes the settings panel. The window grows to the right to
    /// make room, so the text doesn't move, and gives the room back after.
    func toggleInspector() {
        inspectorOpen.toggle()
        var frame = window.frame
        frame.size.width += inspectorOpen ? NoteInspector.width : -NoteInspector.width
        if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - frame.width)
        }
        window.setFrame(frame, display: true, animate: true)
        render(preservingFocus: true)
    }

    func toggle() {
        if window.isVisible { window.orderOut(nil) } else { show() }
    }

    func updatePin() {
        window.level = ContextSettings.shared.pinOnTop ? .screenSaver : .floating
    }

    func applyLook() {
        render(preservingFocus: true)
        ContextTheme.applyLook(
            theme: ContextSettings.shared.colorTheme,
            translucent: ContextSettings.shared.translucentWindow,
            to: window
        )
    }

    // MARK: - Note ops

    func openDailyNote() {
        flushNow()
        do {
            let result = try workspace.apply(.openDailyNote(date: Date(), timeZone: .current))
            switchPad(.scratch)
            if case .note(let id) = result { noteID = id }
            render()
            show()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open the daily note."
            alert.runModal()
        }
    }

    func newNoteFromTemplate() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.text]
        picker.allowsMultipleSelection = false
        picker.message = "Choose a Markdown or text template. {{date}} expands to today's date."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let template = try String(contentsOf: url, encoding: .utf8)
            flushNow()
            let result = try workspace.apply(.createFromTemplate(template, date: Date(), timeZone: .current))
            switchPad(.scratch)
            if case .note(let id) = result { noteID = id }
            render()
            show()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't create a note from this template."
            alert.runModal()
        }
    }

    func newNote() {
        flushNow()
        if pad.isProject { pad = .scratch }
        guard case .note(let id)? = apply(.createNote(pad, text: "")) else { return }
        noteID = id
        render()
        show()
    }

    func nextNote() {
        let live = store.liveNotes
        guard let idx = live.firstIndex(where: { $0.id == noteID }) else {
            if live.isEmpty { newNote() }
            return
        }
        if idx + 1 < live.count {
            noteID = live[idx + 1].id
            afterNavigate()
        } else if !pad.isProject {
            newNote()
        }
    }

    func prevNote() {
        let live = store.liveNotes
        guard let idx = live.firstIndex(where: { $0.id == noteID }), idx > 0 else { return }
        noteID = live[idx - 1].id
        afterNavigate()
    }

    private func afterNavigate() {
        flushNow()
        render()
        chrome.flashPosition()
    }

    func trashCurrent() {
        apply(.trash(pad, id: noteID))
        if let next = store.liveNotes.first {
            noteID = next.id
        } else {
            noteID = store.create().id
        }
        render()
    }

    func onTextChange(_ text: String) {
        apply(.stageText(pad, id: noteID, text: text))
        scheduleFlush()
        chrome.typing()
        render(preservingFocus: true)
    }

    // MARK: - Coalesced persistence

    private var flushWork: DispatchWorkItem?

    /// Coalesces per-keystroke disk writes: memory update now,
    /// atomic Markdown write at most ~0.6s after typing pauses.
    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.workspace.flushAll()
            self?.refreshProjectFile()
        }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Immediate flush for navigate/new/terminate paths.
    func flushNow() {
        flushWork?.cancel()
        flushWork = nil
        workspace.flushAll()
    }

    // MARK: - Extensions

    var jsExtensions: [JSExtension.Script] { [] }

    // MARK: - Slash commands

    /// Explicit text commands share the Workspace mutation path and native undo.
    func runSlashCommand(name: String, tokenRange: NSRange, now: Date = Date()) {
        if let tv = ContextTextView.active, tv.window === window, tv.hasMarkedText() { return }
        let fullText = note.text
        let chars = Array(fullText)
        let intRange = Range(tokenRange, in: fullText).map {
            fullText.distance(from: fullText.startIndex, to: $0.lowerBound)..<fullText.distance(from: fullText.startIndex, to: $0.upperBound)
        }
        guard let range = intRange else { return }
        let input = String(chars[..<range.lowerBound]) + String(chars[range.upperBound...])
        let edit: SlashCommand.Edit
        if let result = TextCalculation.run(name: name, text: input) {
            edit = SlashCommand.Edit(tokenRange: range, replacement: result, fullText: nil)
        } else if name == "timer" {
            let started = commandTimers[noteID] ?? now
            commandTimers[noteID] = started
            edit = SlashCommand.Edit(tokenRange: range, replacement: NoteTimer.format(now.timeIntervalSince(started)), fullText: nil)
        } else if let result = SlashCommand.run(name: name, tokenRange: range, fullText: fullText, selection: nil) {
            edit = result
        } else { return }
        if let transformed = edit.fullText {
            applyCommandText(transformed, name: name)
        } else if let range = edit.tokenRange {
            var updated = fullText
            let start = updated.index(updated.startIndex, offsetBy: range.lowerBound)
            let end = updated.index(updated.startIndex, offsetBy: range.upperBound)
            updated.replaceSubrange(start..<end, with: edit.replacement)
            applyCommandText(updated, name: name)
        }
        render(preservingFocus: true)
    }


    private func applyCommandText(_ text: String, name: String) {
        if let tv = ContextTextView.active, tv.window === window, tv.string == note.text, !tv.hasMarkedText() {
            let all = NSRange(location: 0, length: (tv.string as NSString).length)
            if tv.shouldChangeText(in: all, replacementString: text) {
                tv.replaceCharacters(in: all, with: text)
                tv.didChangeText() // stageText through Workspace, including native undo/redo
                tv.undoManager?.setActionName(name)
            }
        } else {
            setText(text)
        }
    }

    // MARK: - OCR

    func handleImageDrop(_ image: NSImage) {
        Task { @MainActor in
            guard let text = await recognize(image) else { return }
            appendRecognizedText(text)
        }
    }

    /// Appends OCR text to the current note via the sanitize path.
    func appendRecognizedText(_ text: String) {
        let clean = PlainText.sanitize(text)
        guard !clean.isEmpty else { return }
        let base = store.note(id: noteID)?.text ?? ""
        let next = base.isEmpty ? clean : base + "\n" + clean
        setText(next)
        render(preservingFocus: true)
    }

    /// Screenshot region → text: hides the overlay so it is not in the
    /// shot, runs the system crosshair picker, OCRs the capture into the
    /// current note, then reshows. Esc in the picker cancels cleanly.
    func captureScreenshotToText() {
        window.orderOut(nil)
        // Small delay so the panel is gone before the picker arms.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.runCapture()
                self.show()
            }
        }
    }

    private func runCapture() async {
        let output = ScreenshotCapture.tempFileURL()
        defer { ScreenshotCapture.cleanup(at: output) }
        let ok = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                proc.arguments = ScreenshotCapture.arguments(outputPath: output.path)
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    cont.resume(returning: proc.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
        guard ok, ScreenshotCapture.isUsableCapture(at: output),
              let image = NSImage(contentsOf: output),
              let text = await recognize(image), !text.isEmpty
        else { return }
        appendRecognizedText(text)
    }

    private func recognize(_ image: NSImage) async -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, _ in
                let s = req.results?.compactMap({ $0 as? VNRecognizedTextObservation })
                    .compactMap({ $0.topCandidates(1).first?.string }).joined(separator: "\n")
                cont.resume(returning: s)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            }
        }
    }

    // MARK: - Export

    func export(kind: NoteExport.ExportKind) {
        let panel = NSSavePanel()
        switch kind {
        case .txt: panel.nameFieldStringValue = "note.txt"
        case .markdown: panel.nameFieldStringValue = "note.md"
        case .pdf: panel.nameFieldStringValue = "note.pdf"
        }
        if let last = ContextSettings.shared.lastExportDirectory {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ContextSettings.shared.lastExportDirectory = url.deletingLastPathComponent().path
        ContextSettings.shared.save()
        do {
            try NoteExport.writeFile(note, kind: kind, to: url)
        } catch {
            alert("Could not write that export. Check the folder and try again.")
        }
    }

    /// One-click export: writes straight to the last folder (else
    /// Downloads) with a title-slug name, reveals in Finder. No panel.
    func quickExport(kind: NoteExport.ExportKind) {
        let dir = NoteExport.defaultFolder(lastUsed: ContextSettings.shared.lastExportDirectory)
        let dest = NoteExport.quickDestination(for: note, kind: kind, in: dir)
        do {
            try NoteExport.writeFile(note, kind: kind, to: dest)
            ContextSettings.shared.lastExportDirectory = dir.path
            ContextSettings.shared.save()
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            alert("Could not write \(dest.lastPathComponent) to \(dir.path). Check the folder and try again.")
        }
    }

    func copyNote() { NoteExport.copyToClipboard(note) }

    func sendToAppleNotes() {
        do {
            try NoteExport.sendToAppleNotes(note)
        } catch let e as NoteExport.ExportError {
            alert(e.message)
        } catch {
            alert(Handoff.UnavailableReason.notesScriptFailed.message)
        }
    }

    func sendToObsidian() {
        let env = Handoff.Environment.live()
        let path = LinkedVaultRegistry.standard?.obsidianFolder?.path
        let reason = Handoff.checkVault(path: path, env: env)
        switch reason {
        case nil:
            do {
                try NoteExport.sendToObsidian(note, vault: URL(fileURLWithPath: path!))
            } catch let e as NoteExport.ExportError {
                alert(e.message)
            } catch {
                alert("Could not write to the Obsidian vault folder.")
            }
        case .vaultUnset, .vaultMissing:
            // No usable vault: offer the picker once, then send.
            pickVaultAndSend()
        case .some(let r):
            alert(r.message)
        }
    }

    private func pickVaultAndSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose your Obsidian vault folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? LinkedVaultRegistry.standard?.linkObsidian(folder: url)
        do {
            try NoteExport.sendToObsidian(note, vault: url, createIfMissing: true)
        } catch let e as NoteExport.ExportError {
            alert(e.message)
        } catch {
            alert("Could not write to the Obsidian vault folder.")
        }
    }

    func sendToBear() {
        do {
            try NoteExport.sendToBear(note)
        } catch let e as NoteExport.ExportError {
            alert(e.message)
        } catch {
            alert(Handoff.UnavailableReason.bearMissing.message)
        }
    }

    func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = "Context"
        a.informativeText = message
        a.runModal()
    }

    func openVoid() {
        let vc = VoidWindowController(workspace: workspace, pad: pad) { [weak self] id in
            self?.noteID = id
            self?.afterNavigate()
            self?.show()
        }
        vc.show()
    }

    func openSettings() { SettingsWindowController.shared.show() }

    private(set) lazy var library = LibraryWindowController { [unowned self] in self.workspace }

    func openLibrary() {
        flushNow()
        library.show()
    }

    // MARK: - Search

    func openSearch(query: String? = nil) {
        let vc = SearchWindowController(store: store) { [weak self] id in
            self?.noteID = id
            self?.afterNavigate()
            self?.show()
        }
        if let query, !query.isEmpty {
            vc.open(query: query)
        } else {
            vc.show()
        }
    }

    // MARK: - URL scheme actions

    func newNoteWithText(_ text: String?) {
        pad = .scratch
        if case .note(let id)? = apply(.createNote(.scratch, text: text ?? "")) { noteID = id }
        render()
        show()
    }

    func appendToCurrent(_ text: String) {
        let base = note.text
        let next = base.isEmpty ? text : base + "\n" + text
        setText(next)
        render(preservingFocus: true)
        show()
    }

    // MARK: - Swipe

    private func applySwipe(_ direction: SwipeNavigation.Direction) {
        switch direction {
        case .next: nextNote()
        case .previous: prevNote()
        }
    }

    // MARK: - Render

    func render(preservingFocus: Bool = false) {
        let current = note
        let live = store.liveNotes
        let view = ContextEditorRoot(
            controller: self,
            chrome: chrome,
            note: current,
            pad: pad,
            pads: pads,
            project: cachedProjectInfo,
            inspectorOpen: inspectorOpen,
            aiState: aiState,
            liveCount: live.count,
            noteIndex: live.firstIndex(where: { $0.id == noteID }) ?? 0

        )
        if let hosting {
            hosting.rootView = view
        } else {
            let h = NSHostingView(rootView: view)
            h.translatesAutoresizingMaskIntoConstraints = false
            let container = ZenContainerView(frame: window.contentLayoutRect)
            container.onPointer = { [weak self] point, height in self?.chrome.pointer(point, height: height) }
            container.addSubview(h)
            NSLayoutConstraint.activate([
                h.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                h.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                h.topAnchor.constraint(equalTo: container.topAnchor),
                h.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            window.contentView = container
            hosting = h
        }
        _ = preservingFocus
    }
}

/// Status-bar extra. Click toggles the overlay; menu offers show/new/quit.
/// Lives in the same file as the window controller so actions stay wired.
@MainActor
final class ContextStatusItem: NSObject {
    private var item: NSStatusItem?
    private var onToggle: (() -> Void)?
    private var onNewNote: (() -> Void)?

    func install(toggle: @escaping () -> Void, newNote: @escaping () -> Void) {
        guard ContextSettings.shared.showMenuBarExtra else { return }
        remove()
        onToggle = toggle
        onNewNote = newNote
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◍"
        item.button?.action = #selector(handle(_:))
        item.button?.target = self
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Context", action: #selector(showAction(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let fresh = NSMenuItem(title: "New Note", action: #selector(newAction(_:)), keyEquivalent: "")
        fresh.target = self
        menu.addItem(fresh)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.item = item
    }

    /// Live add/remove when Settings toggles the icon. No restart needed.
    func refresh(toggle: @escaping () -> Void, newNote: @escaping () -> Void) {
        if ContextSettings.shared.showMenuBarExtra {
            install(toggle: toggle, newNote: newNote)
        } else {
            remove()
        }
    }

    func remove() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
        onToggle = nil
        onNewNote = nil
    }

    @objc private func handle(_ sender: Any?) { onToggle?() }
    @objc private func showAction(_ sender: Any?) { onToggle?() }
    @objc private func newAction(_ sender: Any?) { onNewNote?() }
}
