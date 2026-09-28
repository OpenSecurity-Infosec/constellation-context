import AppKit
import ContextDomain
import ContextExport
import ContextMath
import ContextStore
import SwiftUI
import Vision

/// Main scratchpad window: borderless floating panel with swipe navigation,
/// inline math gutter, checklist rows, OCR drop, and export.
@MainActor
final class ContextWindowController {
    let window: ContextPanel
    private let store = NoteStore()
    private let rates = RateStore()
    private var math = MathEngine()
    private let autoPaste = AutoPasteMonitor()
    private var noteID: UUID
    private var timer = NoteTimer()
    private var timerMode: NoteTimer.Mode = .stopwatch
    private var tickTimer: Timer?
    private var hosting: NSHostingView<ContextEditorRoot>?
    private var lastMathBody = ""
    private var lastMathResults: [MathEngine.LineOutcome] = []

    init() {
        store.collectGarbage()
        let first = store.liveNotes.first ?? store.create()
        noteID = first.id
        window = ContextPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Context"
        window.isFloatingPanel = true
        window.level = .floating
        window.center()
        window.isMovableByWindowBackground = false
        window.onSwipe = { [weak self] direction in self?.applySwipe(direction) }
        ContextTheme.apply(mode: ContextSettings.shared.themeMode)
        refreshRates()
        render()
        applyLook()
        startTimerTick()
        updatePin()
    }

    private func refreshRates() {
        if let snap = rates.current { math = MathEngine(rates: snap) }
        lastMathBody = ""
        Task { [weak self] in
            await self?.rates.refreshIfNeeded()
            await MainActor.run {
                if let snap = self?.rates.current {
                    self?.math = MathEngine(rates: snap)
                    self?.lastMathBody = ""
                    self?.render(preservingFocus: true)
                }
            }
        }
    }

    var ratesFootnote: String? {
        // Show only in math notes mentioning a currency code.
        let body = note.bodyWithoutTrigger.uppercased()
        let mentionsCurrency = (CurrencyRates.fiat.union(CurrencyRates.crypto)).contains { body.contains($0) }
        guard note.kind == .math, mentionsCurrency else { return nil }
        switch CurrencyRates.freshness(of: rates.current) {
        case .unavailable:
            return "rates unavailable offline — connect once to fetch"
        case .live:
            return "rates \(CurrencyRates.ageLabel(since: rates.current!.fetchedAt))"
        case .cachedStale:
            return "rates \(CurrencyRates.ageLabel(since: rates.current!.fetchedAt)) (cached — provider unreachable)"
        }
    }

    var note: ContextNote { store.note(id: noteID) ?? ContextNote(text: "") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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

    func newNote() {
        flushNow()
        let n = store.create()
        noteID = n.id
        autoPaste.stop()
        timer = NoteTimer()
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
        } else {
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
        autoPaste.stop()
        timer = NoteTimer()
        render()
    }

    func trashCurrent() {
        store.trash(id: noteID)
        autoPaste.stop()
        if let next = store.liveNotes.first {
            noteID = next.id
        } else {
            noteID = store.create().id
        }
        render()
    }

    func onTextChange(_ text: String) {
        store.stage(id: noteID, text: text)
        scheduleFlush()
        let kind = ContextNote(text: text).kind
        // Arm/disarm AutoPaste with the `paste` trigger.
        if kind == .paste, !autoPaste.isArmed {
            autoPaste.start { [weak self] pasted in
                Task { @MainActor in self?.appendAutoPaste(pasted) }
            }
        } else if kind != .paste, autoPaste.isArmed {
            autoPaste.stop()
        }
        render(preservingFocus: true)
        // Opportunistic push when sync is on; SyncManager no-ops when off.
        Task { @MainActor in SyncManager.shared.sync(
            localNotes: { [weak self] in self?.store.allNotes ?? [] },
            applyMerged: { _ in }
        ) }
    }

    private func appendAutoPaste(_ pasted: String) {
        guard let current = store.note(id: noteID), current.kind == .paste else { return }
        let clean = PlainText.sanitizePasteboard(pasted)
        let next = current.text.isEmpty ? clean : current.text + "\n" + clean
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    func toggleChecklist(id: Int) {
        let next = ChecklistItem.toggle(text: note.text, id: id)
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    func indentChecklist(id: Int, direction: ChecklistItem.IndentDirection) {
        let next = ChecklistItem.indent(text: note.text, id: id, direction: direction)
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    func cycleChecklistMarker(id: Int) {
        let next = ChecklistItem.cycleMarker(text: note.text, id: id)
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    /// Drag-reorder: moves one checklist row. IndexSet comes from SwiftUI
    /// .onMove in display order, which matches body-line order from parse.
    func moveChecklist(from: IndexSet, to: Int) {
        guard let src = from.first else { return }
        // SwiftUI reports `to` post-removal; domain move takes a final index.
        var dst = to
        if to > src { dst -= 1 }
        let next = ChecklistItem.move(text: note.text, from: src, to: dst)
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    /// Drag-reorder with subtree-follow: the dragged row carries its nested
    /// children. Display positions translate to body ids via parse order.
    func moveChecklistBlock(from: IndexSet, to displayTo: Int) {
        let text = note.text
        let lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let ids = ChecklistItem.parse(text).map(\.id)
        let (srcId, anchor) = ChecklistItem.moveDisplay(
            ids: ids, from: from, to: displayTo, bodyLineCount: lines.count - offset
        )
        let next = ChecklistItem.moveBlock(text: text, from: srcId, to: anchor, bodyLineCount: lines.count - offset)
        store.update(id: noteID, text: next)
        render(preservingFocus: true)
    }

    /// Current checklist row id under the caret in the plain text buffer.
    func rowIDForCaret(_ caret: Int) -> Int {
        let text = note.text
        let lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        var pos = 0
        for (i, line) in lines.enumerated() {
            if caret <= pos + line.count { return max(0, i - offset) }
            pos += line.count + 1
        }
        return max(0, lines.count - 1 - offset)
    }

    func indentRowAtCaret(direction: ChecklistItem.IndentDirection) {
        indentChecklist(id: rowIDForCaret(lastCaret), direction: direction)
    }

    private var lastCaret: Int = 0

    func trackCaret(_ caret: Int) { lastCaret = caret }

    func cycleMarkerAtCaret(_ caret: Int) {
        cycleChecklistMarker(id: rowIDForCaret(caret))
    }

    func cycleMarkerAtCaret() {
        cycleChecklistMarker(id: rowIDForCaret(lastCaret))
    }

    // MARK: - Coalesced persistence

    private var flushWork: DispatchWorkItem?

    /// Coalesces per-keystroke disk writes: memory + gutter update now,
    /// JSON encode + atomic write at most ~0.6s after typing pauses.
    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.flush() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Immediate flush for navigate/new/terminate paths.
    func flushNow() {
        flushWork?.cancel()
        flushWork = nil
        store.flush()
    }

    // MARK: - Extensions

    /// Installed JS extensions, reloaded each render so dropped files appear.
    var jsExtensions: [JSExtension.Script] {
        JSExtension.load(from: JSExtension.defaultFolder())
    }

    // MARK: - Slash commands

    /// Runs a `::` command: native builtins first, then installed JS scripts.
    /// JS `replacement` swaps the token; `fullText` rewrites the buffer;
    /// `append` adds to the end.
    func runSlashCommand(name: String, tokenRange: NSRange) {
        if runJSExtension(name: name, tokenRange: tokenRange) { return }
        let fullText = note.text
        let chars = Array(fullText)
        let intRange: Range<Int>? = {
            guard tokenRange.location >= 0,
                  tokenRange.location + tokenRange.length <= chars.count
            else { return nil }
            return tokenRange.location..<(tokenRange.location + tokenRange.length)
        }()
        guard let edit = SlashCommand.run(
            name: name,
            tokenRange: intRange,
            fullText: fullText,
            selection: nil
        ) else { return }
        if let transformed = edit.fullText {
            store.update(id: noteID, text: transformed)
        } else if let range = edit.tokenRange {
            var updated = fullText
            let start = updated.index(updated.startIndex, offsetBy: range.lowerBound)
            let end = updated.index(updated.startIndex, offsetBy: range.upperBound)
            updated.replaceSubrange(start..<end, with: edit.replacement)
            store.update(id: noteID, text: updated)
        }
        render(preservingFocus: true)
    }

    @discardableResult
    private func runJSExtension(name: String, tokenRange: NSRange) -> Bool {
        let scripts = jsExtensions
        guard let script = SlashCommand.extensionScript(named: name, in: scripts) else { return false }
        let fullText = note.text
        let chars = Array(fullText)
        let token: String = {
            guard tokenRange.location >= 0,
                  tokenRange.location + tokenRange.length <= chars.count
            else { return "::\(name)" }
            return String(chars[tokenRange.location..<(tokenRange.location + tokenRange.length)])
        }()
        let input = JSExtension.Input(
            text: fullText,
            token: token,
            selection: "",
            nowISO: ISO8601DateFormatter().string(from: Date())
        )
        guard let output = JSExtension.run(
            script, input: input,
            allowNetwork: ContextSettings.shared.extensionsAllowNetwork
        ) else { return true }
        switch output {
        case .replacement(let rep):
            var updated = fullText
            if tokenRange.location >= 0, tokenRange.location + tokenRange.length <= chars.count {
                let start = updated.index(updated.startIndex, offsetBy: tokenRange.location)
                let end = updated.index(updated.startIndex, offsetBy: tokenRange.location + tokenRange.length)
                updated.replaceSubrange(start..<end, with: rep)
            } else {
                updated += rep
            }
            store.update(id: noteID, text: updated)
        case .fullText(let full):
            store.update(id: noteID, text: full)
        case .append(let extra):
            let base = note.text
            store.update(id: noteID, text: base.isEmpty ? extra : base + "\n" + extra)
        }
        render(preservingFocus: true)
        return true
    }

    // MARK: - Timer controls

    private func startTimerTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render(preservingFocus: true) }
        }
    }

    func timerStart() { timerMode = NoteTimer.parseMode(from: note.text); timer.start(mode: timerMode) }
    func timerStop() { timer.stop() }
    func timerReset() { timer.reset() }

    // MARK: - Fullscreen timer

    private var timerWindow: TimerWindowController?

    /// Named fullscreen display for the current `timer` note. Nil unless
    /// the note is a timer note.
    func timerSnapshot() -> TimerSnapshot? {
        guard note.kind == .timer else { return nil }
        let mode = NoteTimer.parseMode(from: note.text)
        let raw = NoteTimer.name(from: note.text)
        let name = raw.isEmpty ? "Timer" : raw
        let label: String = switch mode {
        case .stopwatch: "stopwatch"
        case .countdown: "countdown"
        case .pomodoro: "pomodoro"
        }
        let display: String
        let finished: Bool
        switch mode {
        case .stopwatch:
            display = NoteTimer.format(timer.elapsed)
            finished = false
        case .countdown, .pomodoro:
            let left = timer.remaining ?? {
                if case .countdown(let s) = mode { return s }
                if case .pomodoro(let s) = mode { return s }
                return 0
            }()
            display = NoteTimer.format(left)
            finished = timer.totalDuration != nil && left <= 0
        }
        return TimerSnapshot(
            name: name, display: display, fraction: timer.fractionDone,
            running: timer.isRunning, modeLabel: label, finished: finished
        )
    }

    func openTimerFullscreen() {
        guard note.kind == .timer else { return }
        if let open = timerWindow {
            open.show()
            return
        }
        let wc = TimerWindowController(
            read: { [weak self] in self?.timerSnapshot() },
            onStart: { [weak self] in self?.timerStart() },
            onStop: { [weak self] in self?.timerStop() },
            onReset: { [weak self] in self?.timerReset() },
            onClose: { [weak self] in self?.timerWindow = nil }
        )
        timerWindow = wc
        wc.show()
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
        store.update(id: noteID, text: next)
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? NoteExport.writeFile(note, kind: kind, to: url)
    }

    func copyNote() { NoteExport.copyToClipboard(note) }

    func sendToAppleNotes() {
        do {
            try NoteExport.sendToAppleNotes(note)
        } catch {
            alert("Apple Notes is not available right now.")
        }
    }

    func sendToObsidian() {
        if let path = ContextSettings.shared.obsidianVaultPath, !path.isEmpty {
            do {
                try NoteExport.sendToObsidian(note, vault: URL(fileURLWithPath: path))
            } catch {
                alert("Could not write to the Obsidian vault folder.")
            }
            return
        }
        // No vault configured yet: prompt once, then send.
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose your Obsidian vault folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ContextSettings.shared.obsidianVaultPath = url.path
        ContextSettings.shared.save()
        do {
            try NoteExport.sendToObsidian(note, vault: url)
        } catch {
            alert("Could not write to the Obsidian vault folder.")
        }
    }

    func sendToBear() {
        do {
            try NoteExport.sendToBear(note)
        } catch {
            alert("Bear is not installed or did not open.")
        }
    }

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = "Context"
        a.informativeText = message
        a.runModal()
    }

    func openVoid() {
        let vc = VoidWindowController(store: store) { [weak self] id in
            self?.noteID = id
            self?.afterNavigate()
            self?.show()
        }
        vc.show()
    }

    func openSettings() { SettingsWindowController.shared.show() }

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

    func syncNow() {
        SyncManager.shared.sync(
            localNotes: { [weak self] in self?.store.allNotes ?? [] },
            applyMerged: { [weak self] merged in
                guard let notes = merged as? [ContextNote] else { return }
                self?.store.replaceAll(notes)
                if let current = self?.noteID, !notes.contains(where: { $0.id == current }) {
                    self?.noteID = notes.first?.id ?? self?.store.create().id ?? UUID()
                }
                self?.render(preservingFocus: true)
            }
        )
    }

    // MARK: - URL scheme actions

    func newNoteWithText(_ text: String?) {
        if let text, !text.isEmpty {
            let n = store.create(text: text)
            noteID = n.id
        } else {
            noteID = store.create().id
        }
        autoPaste.stop()
        timer = NoteTimer()
        render()
        show()
    }

    func appendToCurrent(_ text: String) {
        let base = note.text
        let next = base.isEmpty ? text : base + "\n" + text
        store.update(id: noteID, text: next)
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

    private func render(preservingFocus: Bool = false) {
        let current = note
        // Math memo: the 0.25s timer tick re-renders constantly; skip the
        // full re-eval when the math body is byte-identical so idle notes
        // cost nothing and typing only pays for real changes.
        let mathBody = current.kind == .math ? current.bodyWithoutTrigger : ""
        let results: [MathEngine.LineOutcome]
        if mathBody == lastMathBody {
            results = lastMathResults
        } else {
            results = current.kind == .math ? math.evaluateLines(note: mathBody) : []
            lastMathBody = mathBody
            lastMathResults = results
        }
        let sumAvg: Double? = {
            switch current.kind {
            case .sum: return math.aggregate(current.bodyWithoutTrigger, mode: .sum)
            case .avg: return math.aggregate(current.bodyWithoutTrigger, mode: .avg)
            default: return nil
            }
        }()
        let stats = current.kind == .count ? NoteStats.compute(for: current.bodyWithoutTrigger) : nil
        let items = current.kind == .list ? ChecklistItem.parse(current.text) : []
        let view = ContextEditorRoot(
            controller: self,
            note: current,
            liveCount: store.liveNotes.count,
            mathResults: results,
            aggregate: sumAvg.map(math.format),
            stats: stats,
            checklist: items,
            autoPasteArmed: autoPaste.isArmed,
            elapsed: timer.elapsed,
            remaining: timer.remaining,
            timerRunning: timer.isRunning,
            ratesFootnote: ratesFootnote,
            jsExtensions: jsExtensions
        )
        if let hosting {
            hosting.rootView = view
        } else {
            let h = NSHostingView(rootView: view)
            h.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView(frame: window.contentLayoutRect)
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
