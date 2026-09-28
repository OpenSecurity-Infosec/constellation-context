import ContextDomain
import SwiftUI

/// SwiftUI editor surface: toolbar, trigger badge, text buffer with math
/// gutter overlay, checklist rows, timer controls, and export menu.
struct ContextEditorRoot: View {
    weak var controller: ContextWindowController?
    var note: ContextNote
    var liveCount: Int
    var mathResults: [MathEngine.LineOutcome]
    var aggregate: String?
    var stats: NoteStats?
    var checklist: [ChecklistItem]
    var autoPasteArmed: Bool
    var elapsed: TimeInterval
    var remaining: TimeInterval?
    var timerRunning: Bool
    var ratesFootnote: String? = nil
    var jsExtensions: [JSExtension.Script] = []

    @State private var text: String = ""
    @State private var isEditing = false
    @State private var slashFragment: String? = nil
    @State private var slashRange: NSRange = NSRange(location: 0, length: 0)
    @State private var slashSelected: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editor
            if note.kind != .plain { modeBar }
            statusBar
        }
        .background(Color.ctxEditorBackground)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { text = note.text }
        .onChange(of: note.id) { text = note.text }
        .onChange(of: note.text) { _, newValue in
            if !isEditing { text = newValue }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("‹") { controller?.prevNote() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Text("\(liveCount)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(minWidth: 20)
            Button("›") { controller?.nextNote() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            if let trigger = note.kind.triggerWord {
                Text(trigger)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.ctxAccent.opacity(0.18))
                    .foregroundStyle(Color.ctxAccent)
                    .clipShape(Capsule())
            }
            if autoPasteArmed {
                Text("collecting pastes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Menu("Export") {
                Button("Copy") { controller?.copyNote() }
                Button("Save .txt") { controller?.export(kind: .txt) }
                Button("Save Markdown") { controller?.export(kind: .markdown) }
                Button("Save PDF") { controller?.export(kind: .pdf) }
                Divider()
                Button("Send to Apple Notes") { controller?.sendToAppleNotes() }
                Button("Send to Obsidian") { controller?.sendToObsidian() }
                Button("Send to Bear") { controller?.sendToBear() }
            }
            Button("Void") { controller?.openVoid() }.buttonStyle(.plain)
            Button("🔍") { controller?.openSearch() }.buttonStyle(.plain)
                .help("Search notes (⌘F)")
            Button("+") { controller?.newNote() }.buttonStyle(.plain)
            Button("🗑") { controller?.trashCurrent() }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.ctxPanelBackground)
    }

    private var editor: some View {
        Group {
            if note.kind == .list {
                checklistView
            } else {
                ZStack(alignment: .topLeading) {
                    mathGutter
                    PlainTextEditor(text: $text, isEditing: $isEditing, onCommit: { controller?.onTextChange(text) }, onCaret: { caret in controller?.trackCaret(caret) }, onIndent: { direction in
                        controller?.indentRowAtCaret(direction: direction)
                    }, onSlash: { fragment, range in
                        slashFragment = fragment
                        slashRange = range
                        slashSelected = 0
                    }, onImagePaste: { image in
                        controller?.handleImageDrop(image)
                    })
                        .font(.system(size: ContextSettings.shared.fontSize))
                    if let fragment = slashFragment, !SlashCommand.completions(matching: fragment, extensions: jsExtensions).isEmpty {
                        slashPopup(fragment: fragment)
                    }
                }
            }
        }
        .onKeyPress(.return) {
            if slashFragment != nil, let fragment = slashFragment {
                let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
                if slashSelected < matches.count {
                    runSlashCommand(matches[slashSelected].name)
                    return .handled
                }
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if slashFragment != nil {
                slashFragment = nil
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            if let fragment = slashFragment {
                let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
                slashSelected = min(slashSelected + 1, matches.count - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            if slashFragment != nil {
                slashSelected = max(slashSelected - 1, 0)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab) {
            if let fragment = slashFragment {
                let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
                if slashSelected < matches.count {
                    runSlashCommand(matches[slashSelected].name)
                    return .handled
                }
            }
            return .ignored
        }
        .onDrop(of: [.fileURL, .tiff, .png], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    if let data, let image = NSImage(data: data) {
                        let captured = image
                        Task { @MainActor in controller?.handleImageDrop(captured) }
                    }
                }
                _ = p.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    if let data, let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString), let image = NSImage(contentsOf: url) {
                        let captured = image
                        Task { @MainActor in controller?.handleImageDrop(captured) }
                    }
                }
            }
            return true
        }
    }

    private var mathGutter: some View {
        // Right-aligned inline results for math notes.
        VStack(alignment: .trailing, spacing: 0) {
            // Offset past the trigger line.
            if note.kind == .math { Color.clear.frame(height: lineHeight) }
            ForEach(mathResults.indices, id: \.self) { i in
                switch mathResults[i] {
                case .value(let r):
                    Text(r.display)
                        .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                        .foregroundStyle(Color.ctxAccent)
                        .frame(height: lineHeight)
                case .error(let e):
                    Text(e.message)
                        .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                        .foregroundStyle(Color.ctxWarning)
                        .frame(height: lineHeight)
                case .blank:
                    Text("")
                        .frame(height: lineHeight)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
    }

    private var lineHeight: CGFloat { ContextSettings.shared.fontSize * 1.35 + 4 }

    private var checklistView: some View {
        List {
            ForEach(checklist) { item in
                HStack {                    Button(item.checked ? "☑" : "☐") { controller?.toggleChecklist(id: item.id) }
                        .buttonStyle(.plain)
                    Text(markerPrefix(item))
                        .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                    TextField("", text: Binding(
                        get: { item.text },
                        set: { _ in }
                    ))
                    .textFieldStyle(.plain)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                }
                .padding(.leading, CGFloat(item.indent) * 16)
                .contextMenu {
                    Button("Nest (Tab)") { controller?.indentChecklist(id: item.id, direction: .in) }
                    Button("Outdent (⇧Tab)") { controller?.indentChecklist(id: item.id, direction: .out) }
                    Button("Cycle marker (⌘⇧M)") { controller?.cycleChecklistMarker(id: item.id) }
                }
            }
            .onMove { from, to in controller?.moveChecklist(from: from, to: to) }
            .onDelete { _ in }
        }
        .listStyle(.plain)
    }

    private func markerPrefix(_ item: ChecklistItem) -> String {
        switch item.marker {
        case .checkbox: return item.checked ? "[x]" : "[ ]"
        case .bullet: return "-"
        case .numbered(let n): return "\(n)."
        }
    }

    /// `::` autocomplete popup: type to filter, Tab/↑↓ to move, Return to run.
    /// Native builtins first, then installed JS extensions.
    private func slashPopup(fragment: String) -> some View {
        let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(matches.indices, id: \.self) { i in
                Button {
                    runSlashCommand(matches[i].name)
                } label: {
                    HStack {
                        Text("::\(matches[i].name)")
                            .font(.system(.body).monospaced())
                        Text(matches[i].hint)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(i == slashSelected ? Color.ctxAccent.opacity(0.25) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.ctxPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .frame(width: 280)
        .offset(x: 24, y: 60)
    }

    private func handleSlashKey(_ event: NSEvent, matches: [SlashCommand.Definition]) -> NSEvent? {
        // Kept for AppKit-level handling if needed; SwiftUI onKeyPress owns keys.
        _ = event
        _ = matches
        return event
    }

    private func runSlashCommand(_ name: String) {
        controller?.runSlashCommand(name: name, tokenRange: slashRange)
        slashFragment = nil
    }

    @ViewBuilder
    private var modeBar: some View {
        Divider()
        HStack(spacing: 12) {
            switch note.kind {
            case .sum, .avg:
                Text("\(note.kind.triggerWord ?? "") = \(aggregate ?? "—")")
                    .font(.system(.body).monospaced())
                    .foregroundStyle(Color.ctxAccent)
            case .count:
                if let stats {
                    Text("\(stats.lines) lines · \(stats.words) words · \(stats.characters) chars")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .timer:
                Text(NoteTimer.format(remaining ?? elapsed))
                    .font(.system(.title2).monospaced())
                Button(timerRunning ? "Stop" : "Start") {
                    timerRunning ? controller?.timerStop() : controller?.timerStart()
                }
                Button("Reset") { controller?.timerReset() }
                Button("Full screen") { controller?.openTimerFullscreen() }
            case .paste:
                Text(autoPasteArmed ? "Everything you copy lands here as plain text." : "Type paste + Return to collect copies.")
                    .font(.caption).foregroundStyle(.secondary)
            case .code:
                Text("Snippet buffer — paste strips styling.")
                    .font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var statusBar: some View {
        HStack {
            if let ratesFootnote {
                Text(ratesFootnote)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("⌥A toggle · ←/→ swipe notes · plain text always")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") { controller?.openSettings() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.ctxPanelBackground)
    }
}

private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    var onCommit: () -> Void
    var onCaret: ((Int) -> Void)?
    var onIndent: ((ChecklistItem.IndentDirection) -> Void)?
    var onSlash: ((String, NSRange) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ContextTextView()
        tv.onChange = { newText in
            text = newText
            onCommit()
        }
        tv.onFocus = { focused in isEditing = focused }
        tv.onCaret = { caret in onCaret?(caret) }
        tv.onIndent = { direction in onIndent?(direction) }
        tv.onSlash = { fragment, range in onSlash?(fragment, range) }
        tv.onOpenURL = { url in NSWorkspace.shared.open(url) }
        tv.onImagePaste = { image in onImagePaste?(image) }
        tv.isAutomaticLinkDetectionEnabled = false
        tv.font = ContextTheme.bodyFont
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.allowsUndo = true
        tv.backgroundColor = .clear
        tv.insertionPointColor = .labelColor
        tv.textContainerInset = NSSize(width: 10, height: 10)
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.view = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selected = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = selected
            (tv as? ContextTextView)?.refreshLinkAttributes()
        }
        tv.font = ContextTheme.bodyFont
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var view: NSTextView? }
}

/// NSTextView that strips formatting on paste and reports changes.
/// Applies Link Shrink: pasted URLs display shortened while the full URL
/// is preserved for open/copy. Links render clickable.
final class ContextTextView: NSTextView {
    var onChange: ((String) -> Void)?
    var onFocus: ((Bool) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onIndent: ((ChecklistItem.IndentDirection) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onSlash: ((String, NSRange) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?
    private var slashCompletion: NSView?

    override func paste(_ sender: Any?) {
        // Plain text only: strip styling, bullets, indentation.
        let board = NSPasteboard.general
        if let s = board.string(forType: .string) {
            let clean = PlainText.sanitizePasteboard(s)
            insertText(clean, replacementRange: selectedRange())
            shrinkURLsAroundSelection()
            return
        }
        // Rich image with no text (screenshots, copied graphics): route to
        // on-device OCR instead of embedding an attachment.
        if let image = board.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            onImagePaste?(image)
            return
        }
        super.paste(sender)
    }

    override func doCommand(by selector: Selector) {
        // Tab nests / Shift+Tab outdents the current checklist line.
        if selector == #selector(insertTab(_:)) {
            onIndent?(.in)
            return
        }
        if selector == #selector(insertBacktab(_:)) {
            onIndent?(.out)
            return
        }
        super.doCommand(by: selector)
    }

    override func didChangeText() {
        super.didChangeText()
        refreshLinkAttributes()
        onChange?(string)
        onCaret?(selectedRange().location)
        checkSlashTrigger()
    }

    /// Fires onSlash while the caret sits on a `::token`.
    private func checkSlashTrigger() {
        let caret = selectedRange().location
        guard let found = SlashCommand.token(at: caret, in: string) else {
            hideSlashCompletion()
            return
        }
        let fragment = String(found.token.dropFirst(2))
        let range = NSRange(location: found.range.lowerBound, length: found.range.upperBound - found.range.lowerBound)
        onSlash?(fragment, range)
        showSlashCompletion(fragment: fragment, tokenRange: range)
    }

    private func showSlashCompletion(fragment: String, tokenRange: NSRange) {
        // SwiftUI owns the popup (see ContextEditorRoot); AppKit just reports
        // the fragment. Hide any stale AppKit view.
        hideSlashCompletion()
        _ = tokenRange
    }

    private func hideSlashCompletion() {
        slashCompletion?.removeFromSuperview()
        slashCompletion = nil
    }

    /// Shortens display of long URLs while keeping full text intact.
    /// Uses link attributes with a shortened tooltip so the buffer stays
    /// plain text and copy/paste preserves the real URL.
    func refreshLinkAttributes() {
        guard let storage = textStorage else { return }
        let full = string as NSString
        let range = NSRange(location: 0, length: full.length)
        storage.removeAttribute(.link, range: range)
        storage.removeAttribute(.toolTip, range: range)
        for urlRange in LinkShrink.urlRanges(in: string) {
            let ns = NSRange(urlRange, in: string)
            let raw = String(string[urlRange])
            guard let url = LinkShrink.openableURL(raw) else { continue }
            storage.addAttribute(.link, value: url, range: ns)
            let short = LinkShrink.shortened(raw)
            if short != raw {
                storage.addAttribute(.toolTip, value: short, range: ns)
            }
        }
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }

    private func shrinkURLsAroundSelection() {
        refreshLinkAttributes()
    }

    /// ⌘↩ opens the URL under the caret in the default browser.
    func openURLAtCaret() -> Bool {
        let caret = selectedRange().location
        let text = string
        for urlRange in LinkShrink.urlRanges(in: text) {
            let ns = NSRange(urlRange, in: text)
            if NSLocationInRange(caret, ns) || NSLocationInRange(max(0, caret - 1), ns) {
                let raw = String(text[urlRange])
                if let url = LinkShrink.openableURL(raw) {
                    onOpenURL?(url)
                    return true
                }
            }
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        // Option-click (or double-click) a link reveals the full URL in place:
        // selection expands to the whole URL so it can be edited/copied.
        if event.modifierFlags.contains(.option) || event.clickCount >= 2 {
            let point = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: point)
            for urlRange in LinkShrink.urlRanges(in: string) {
                let ns = NSRange(urlRange, in: string)
                if NSLocationInRange(idx, ns) {
                    setSelectedRange(ns)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // ⌘↩ opens the URL under the caret.
        if event.modifierFlags.contains(.command),
           event.keyCode == 36 || event.characters == "\r" || event.characters == "\n"
        {
            if openURLAtCaret() { return }
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocus?(false) }
        return ok
    }
}

import ContextMath
import ContextDomain
