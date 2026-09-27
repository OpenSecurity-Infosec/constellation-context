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
        startTimerTick()
        updatePin()
    }

    private func refreshRates() {
        if let snap = rates.current { math = MathEngine(rates: snap) }
        Task { [weak self] in
            await self?.rates.refreshIfNeeded()
            await MainActor.run {
                if let snap = self?.rates.current {
                    self?.math = MathEngine(rates: snap)
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
        guard let snap = rates.current else { return "rates unavailable offline" }
        let age = Int(Date().timeIntervalSince(snap.fetchedAt) / 60)
        if age < 1 { return "rates just now" }
        if age < 60 { return "rates \(age)m ago" }
        return "rates \(age / 60)h ago"
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

    // MARK: - Note ops

    func newNote() {
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
        store.update(id: noteID, text: text)
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

    // MARK: - Slash commands

    /// Runs a `::` command: replaces the token range, or applies the
    /// whole-buffer transform for commands like sort_lines.
    func runSlashCommand(name: String, tokenRange: NSRange) {
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

    // MARK: - Timer controls

    private func startTimerTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render(preservingFocus: true) }
        }
    }

    func timerStart() { timerMode = NoteTimer.parseMode(from: note.text); timer.start(mode: timerMode) }
    func timerStop() { timer.stop() }
    func timerReset() { timer.reset() }

    // MARK: - OCR

    func handleImageDrop(_ image: NSImage) {
        Task { @MainActor in
            guard let text = await recognize(image) else { return }
            let clean = PlainText.sanitize(text)
            let base = store.note(id: noteID)?.text ?? ""
            let next = base.isEmpty ? clean : base + "\n" + clean
            store.update(id: noteID, text: next)
            render(preservingFocus: true)
        }
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
        let results = current.kind == .math ? math.evaluate(note: current.bodyWithoutTrigger) : []
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
            ratesFootnote: ratesFootnote
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

/// Thin status-bar extra. No dock icon requirement — menu bar keeps it alive.
@MainActor
final class ContextStatusItem {
    private var item: NSStatusItem?

    func install(toggle: @escaping () -> Void, newNote: @escaping () -> Void) {
        guard ContextSettings.shared.showMenuBarExtra else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◍"
        item.button?.action = #selector(handle(_:))
        item.button?.target = nil
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Context", action: #selector(showAction(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Note", action: #selector(newAction(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.item = item
        _ = toggle
        _ = newNote
    }

    @objc private func handle(_ sender: Any?) {}
    @objc private func showAction(_ sender: Any?) {}
    @objc private func newAction(_ sender: Any?) {}
}
