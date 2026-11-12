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
    var sumAvgLines: [String] = []
    var countLines: [String] = []
    var stats: NoteStats?
    var checklist: [ChecklistItem]
    var autoPasteArmed: Bool
    var pasteCanUndo: Bool = false
    var elapsed: TimeInterval
    var remaining: TimeInterval?
    var timerRunning: Bool
    var ratesFootnote: String? = nil
    var jsExtensions: [JSExtension.Script] = []
    var slashError: String? = nil

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
                Button("Quick Export .txt") { controller?.quickExport(kind: .txt) }
                Button("Quick Export Markdown") { controller?.quickExport(kind: .markdown) }
                Button("Quick Export PDF") { controller?.quickExport(kind: .pdf) }
                Divider()
                Button("Save .txt As…") { controller?.export(kind: .txt) }
                Button("Save Markdown As…") { controller?.export(kind: .markdown) }
                Button("Save PDF As…") { controller?.export(kind: .pdf) }
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
                    }, onCollectPaste: note.kind == .paste ? { pasted in
                        controller?.collectPaste(pasted)
                    } : nil)
                        .font(.system(size: ContextSettings.shared.fontSize))
                    if let fragment = slashFragment {
                        slashPopup(fragment: fragment)
                    }
                }
            }
        }
        .onKeyPress(.return) {
            if let fragment = slashFragment, let name = slashActionName(fragment: fragment) {
                runSlashCommand(name)
                return .handled
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
                let count = slashActionNames(fragment: fragment).count
                if count > 0 { slashSelected = min(slashSelected + 1, count - 1) }
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
            if let fragment = slashFragment, let name = slashActionName(fragment: fragment) {
                runSlashCommand(name)
                return .handled
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
        // Right-aligned inline results for math notes, per-line
        // contributions for sum/avg notes.
        VStack(alignment: .trailing, spacing: 0) {
            // Offset past the trigger line.
            if note.kind == .math || note.kind == .sum || note.kind == .avg || note.kind == .count {
                Color.clear.frame(height: lineHeight)
            }
            switch note.kind {
            case .count:
                ForEach(countLines.indices, id: \.self) { i in
                    Text(countLines[i])
                        .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(height: lineHeight)
                }
            case .sum, .avg:
                ForEach(sumAvgLines.indices, id: \.self) { i in
                    Text(sumAvgLines[i])
                        .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(height: lineHeight)
                }
            default:
                if mathResults.isEmpty {
                    // Unknown `::command` gutter for non-math notes: one
                    // warning row per offending line, blank elsewhere.
                    let slashGutter = SlashCommand.gutterLines(in: note.text, extensions: jsExtensions)
                    ForEach(slashGutter.indices, id: \.self) { i in
                        Text(slashGutter[i])
                            .font(.system(size: ContextSettings.shared.fontSize).monospaced())
                            .foregroundStyle(Color.ctxWarning)
                            .lineLimit(1)
                            .frame(height: lineHeight)
                    }
                }
                ForEach(mathResults.indices, id: \.self) { i in
                    switch mathResults[i] {
                case .value(let r):
                    // gutterDisplay names the variable on assignment
                    // lines ("price = 10"), plain value elsewhere.
                    Text(r.gutterDisplay)
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
            .onMove { from, to in controller?.moveChecklistBlock(from: from, to: to) }
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

    /// Names Return/Tab/↑↓ act on: completions, or did-you-mean
    /// suggestions when the fragment matches nothing.
    private func slashActionNames(fragment: String) -> [String] {
        let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
        if !matches.isEmpty { return matches.map(\.name) }
        return SlashCommand.suggestions(for: fragment, extensions: jsExtensions)
    }

    private func slashActionName(fragment: String) -> String? {
        let names = slashActionNames(fragment: fragment)
        guard slashSelected >= 0, slashSelected < names.count else { return nil }
        return names[slashSelected]
    }

    /// `::` autocomplete popup: type to filter, Tab/↑↓ to move, Return to run.
    /// Native builtins first, then installed JS extensions. An unknown
    /// fragment gets an explicit error row with suggested commands instead
    /// of the popup silently vanishing.
    private func slashPopup(fragment: String) -> some View {
        let matches = SlashCommand.completions(matching: fragment, extensions: jsExtensions)
        let suggestions = matches.isEmpty
            ? SlashCommand.suggestions(for: fragment, extensions: jsExtensions)
            : []
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if matches.isEmpty {
                    Text("unknown command ::\(fragment)")
                        .font(.system(.body).monospaced())
                        .foregroundStyle(Color.ctxWarning)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                    if suggestions.isEmpty {
                        Text("::help lists commands")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    ForEach(suggestions.indices, id: \.self) { i in
                        Button {
                            runSlashCommand(suggestions[i])
                        } label: {
                            HStack {
                                Text("did you mean ::\(suggestions[i])?")
                                    .font(.system(.body).monospaced())
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(i == slashSelected ? Color.ctxAccent.opacity(0.25) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(matches.indices, id: \.self) { i in
                    Button {
                        runSlashCommand(matches[i].name)
                    } label: {
                        HStack {
                            Text("::\(matches[i].name)")
                                .font(.system(.body).monospaced())
                            Text(matches[i].hint)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(i == slashSelected ? Color.ctxAccent.opacity(0.25) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(4)
        .background(Color.ctxPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .frame(width: 320)
        .frame(maxHeight: 280)
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
                let itemCount = PasteCollection.items(in: note.text).count
                Text(PasteCollection.statusLine(itemCount: itemCount, armed: autoPasteArmed))
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy all") { controller?.copyAllPasteItems() }
                    .help("Copy all pastes joined (⌘⇧C)")
                    .disabled(itemCount == 0)
                Button("Undo") { controller?.undoPasteChange() }
                    .help("Undo last paste change (⌥⌘Z)")
                    .disabled(!pasteCanUndo)
                Button("Clear") { controller?.clearPasteCollection() }
                    .help("Clear collected pastes (⌘⇧⌫)")
                    .disabled(itemCount == 0)
            case .code:
                Text("Snippet buffer — syntax highlighting on; fence with ```swift / ```python / ```js / ```sh to pick a language.")
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
            if let slashError {
                Text(slashError)
                    .font(.caption).foregroundStyle(Color.ctxWarning)
                    .lineLimit(2)
            } else if let ratesFootnote {
                Text(ratesFootnote)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("⌥A toggle · ←/→ swipe notes · plain text always")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(BuildInfo.label(from: Bundle.main.infoDictionary ?? [:]))
                .font(.caption2).foregroundStyle(.secondary)
                .help("Build identity: git revision and build time")
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
    /// Set only in `paste` notes: ⌘V collects the clipboard as a new
    /// item at the end instead of inserting at the caret.
    var onCollectPaste: ((String) -> Void)?

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
        tv.onCollectPaste = onCollectPaste
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
        (tv as? ContextTextView)?.onCollectPaste = onCollectPaste
        // Compare against reconstructed source text: the view may be
        // showing collapsed link displays while `text` is the full note.
        let current = (tv as? ContextTextView)?.sourceTextForSaving() ?? tv.string
        if current != text {
            let selected = tv.selectedRanges
            (tv as? ContextTextView)?.resetLinkExpansion()
            tv.string = text
            tv.selectedRanges = selected
            (tv as? ContextTextView)?.refreshLinkAttributes(collapsingAtCaret: true)
        }
        tv.font = ContextTheme.bodyFont
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var view: NSTextView? }
}

/// NSTextView that strips formatting on paste and reports changes.
/// Applies Link Shrink: long URLs render in their shortened display
/// form while the full URL is preserved (custom attribute + domain
/// presentation) for save/copy/open. A plain click on a shortened
/// link expands it in place; clicking the expanded link collapses it
/// again. ⌘↩ opens the link under the caret.
final class ContextTextView: NSTextView {
    var onChange: ((String) -> Void)?
    var onFocus: ((Bool) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onIndent: ((ChecklistItem.IndentDirection) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onSlash: ((String, NSRange) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?
    var onCollectPaste: ((String) -> Void)?
    private var slashCompletion: NSView?

    /// Raw URLs the user clicked to expand; all other shortened links
    /// render collapsed. Identical URLs toggle together.
    private var expandedLinkRawValues: Set<String> = []
    private var lastLinkPresentation: LinkShrink.Presentation?
    private var applyingLinkDisplay = false
    /// Carries the full raw URL over its collapsed display span so the
    /// source text can be reconstructed for save/copy even after the
    /// surrounding text (and thus every range) shifts.
    private static let fullURLKey = NSAttributedString.Key("ContextLinkShrinkFullURL")

    override func paste(_ sender: Any?) {
        // Plain text only: strip styling, bullets, indentation.
        let board = NSPasteboard.general
        // In a `paste` note, ⌘V collects the clipboard as its own item
        // (sanitized downstream) rather than inserting at the caret.
        if let onCollectPaste, let s = board.string(forType: .string) {
            onCollectPaste(s)
            return
        }
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
        guard !applyingLinkDisplay else { return }
        refreshLinkAttributes()
        let source = sourceTextForSaving()
        onChange?(source)
        onCaret?(sourceCaretCharacterOffset(in: source))
        checkSlashTrigger()
    }

    /// Fires onSlash while the caret sits on a `::token`. Runs against
    /// reconstructed source text so a collapsed link earlier on the
    /// line cannot shift the token range the controller applies.
    private func checkSlashTrigger() {
        let source = sourceTextForSaving()
        let caret = sourceCaretCharacterOffset(in: source)
        guard let found = SlashCommand.token(at: caret, in: source) else {
            hideSlashCompletion()
            return
        }
        let fragment = SlashCommand.fragment(fromToken: found.token)
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

    /// Full note text with every collapsed link span restored to its
    /// raw URL. This — not `string` — is what gets saved and copied.
    func sourceTextForSaving() -> String {
        reconstructedSource(in: NSRange(location: 0, length: (string as NSString).length))
    }

    private func reconstructedSource(in range: NSRange) -> String {
        guard let storage = textStorage, range.length > 0 else {
            return (string as NSString).substring(with: range)
        }
        let full = string as NSString
        var out = ""
        storage.enumerateAttribute(Self.fullURLKey, in: range, options: []) { value, runRange, _ in
            let piece = full.substring(with: runRange)
            guard let raw = value as? String else { out += piece; return }
            let shown = LinkShrink.shortened(raw)
            if piece == shown {
                out += raw
            } else if piece.hasPrefix(shown) {
                // Characters typed glued to the end inherit the
                // attribute; the URL itself is still intact.
                out += raw + String(piece.dropFirst(shown.count))
            } else {
                // The collapsed span itself was edited: keep the
                // literal text rather than resurrecting the old URL.
                out += piece
            }
        }
        return out
    }

    func resetLinkExpansion() {
        expandedLinkRawValues = []
        lastLinkPresentation = nil
    }

    var commandSelection: Range<Int>? {
        let selected = selectedRange()
        guard selected.length > 0 else { return nil }
        let source = sourceTextForSaving()
        let start = lastLinkPresentation?.sourceOffset(forDisplayOffset: selected.location) ?? selected.location
        let end = lastLinkPresentation?.sourceOffset(forDisplayOffset: NSMaxRange(selected)) ?? NSMaxRange(selected)
        guard let range = Range(NSRange(location: start, length: end - start), in: source) else { return nil }
        return source.distance(from: source.startIndex, to: range.lowerBound)..<source.distance(from: source.startIndex, to: range.upperBound)
    }

    private func sourceCaretUTF16Offset() -> Int {
        lastLinkPresentation?.sourceOffset(forDisplayOffset: selectedRange().location)
            ?? selectedRange().location
    }

    private func sourceCaretCharacterOffset(in source: String) -> Int {
        let clamped = min(max(sourceCaretUTF16Offset(), 0), source.utf16.count)
        return source.distance(from: source.startIndex, to: String.Index(utf16Offset: clamped, in: source))
    }

    /// Renders the domain presentation: long URLs shown shortened
    /// (full URL in the tooltip and the reconstruction attribute),
    /// expanded ones in full. Unless `collapsingAtCaret` is set
    /// (paste, note load, click toggle), the link under the caret
    /// stays full so typing a URL never shrinks it mid-edit; it
    /// collapses on the next edit after the caret leaves it.
    func refreshLinkAttributes(collapsingAtCaret: Bool = false) {
        guard !applyingLinkDisplay, let storage = textStorage else { return }
        applyingLinkDisplay = true
        defer { applyingLinkDisplay = false }
        if hasMarkedText() { return } // never rebuild during IME composition
        let source = sourceTextForSaving()
        var expanded = expandedLinkRawValues
        if !collapsingAtCaret,
           let editing = LinkShrink.link(atUTF16Offset: sourceCaretUTF16Offset(), in: source),
           editing.isShortened
        {
            expanded.insert(editing.raw)
        }
        let presentation = LinkShrink.presentation(for: source, expanded: expanded)
        if presentation.text != string {
            let old = selectedRange()
            let srcStart = lastLinkPresentation?.sourceOffset(forDisplayOffset: old.location) ?? old.location
            let srcEnd = lastLinkPresentation?.sourceOffset(forDisplayOffset: old.location + old.length)
                ?? (old.location + old.length)
            let newStart = presentation.displayOffset(forSourceOffset: srcStart)
            let newEnd = presentation.displayOffset(forSourceOffset: srcEnd)
            storage.mutableString.setString(presentation.text)
            setSelectedRange(NSRange(location: newStart, length: max(0, newEnd - newStart)))
            // A display rebuild invalidates ranges recorded by undo.
            undoManager?.removeAllActions()
        }
        lastLinkPresentation = presentation
        let range = NSRange(location: 0, length: (string as NSString).length)
        storage.removeAttribute(.link, range: range)
        storage.removeAttribute(.toolTip, range: range)
        storage.removeAttribute(.foregroundColor, range: range)
        storage.removeAttribute(Self.fullURLKey, range: range)
        storage.addAttribute(.font, value: ContextTheme.bodyFont, range: range)
        applyCodeHighlighting(storage: storage, presentation: presentation, source: source)
        for link in presentation.links {
            guard let url = link.url else { continue }
            let ns = NSRange(location: link.displayUTF16Range.lowerBound, length: link.displayUTF16Range.count)
            storage.addAttribute(.link, value: url, range: ns)
            if link.isCollapsed {
                storage.addAttribute(.toolTip, value: link.raw, range: ns)
                storage.addAttribute(Self.fullURLKey, value: link.raw, range: ns)
            }
        }
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        var typing = typingAttributes
        typing.removeValue(forKey: Self.fullURLKey)
        typing.removeValue(forKey: .link)
        typingAttributes = typing
    }

    /// Per-block syntax highlighting: mono font over each code block, token
    /// colors inside it. The buffer text itself stays plain — these are
    /// display attributes only, recomputed with the link attributes on
    /// every edit. Block/kind derivation is shared with the domain tests
    /// via `CodeHighlight` (a `code` first line makes the body one block).
    /// Block/token ranges derive from source text and are mapped into
    /// display coordinates so a collapsed link before a block cannot
    /// shift its colors.
    private func applyCodeHighlighting(storage: NSTextStorage, presentation: LinkShrink.Presentation, source: String) {
        func mapped(_ ns: NSRange) -> NSRange {
            let start = presentation.displayOffset(forSourceOffset: ns.location)
            let end = presentation.displayOffset(forSourceOffset: ns.location + ns.length)
            return NSRange(location: start, length: max(0, end - start))
        }
        let note = ContextNote(text: source)
        for block in CodeHighlight.blocks(for: note) {
            storage.addAttribute(.font, value: ContextTheme.monoFont, range: mapped(NSRange(block.range, in: source)))
            for token in CodeHighlight.tokens(in: source, range: block.range, language: block.language) {
                storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: mapped(NSRange(token.range, in: source)))
            }
        }
    }

    private static func color(for kind: CodeHighlight.TokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPurple
        case .string: .systemGreen
        case .comment: .secondaryLabelColor
        case .number: .systemOrange
        }
    }

    private func shrinkURLsAroundSelection() {
        // A paste lands complete: collapse immediately, caret included.
        refreshLinkAttributes(collapsingAtCaret: true)
    }

    /// ⌘↩ opens the URL under the caret in the default browser. The
    /// caret is converted to source coordinates first, so it works
    /// the same on a collapsed or expanded link.
    func openURLAtCaret() -> Bool {
        let source = sourceTextForSaving()
        guard let link = LinkShrink.link(atUTF16Offset: sourceCaretUTF16Offset(), in: source),
              let url = link.url
        else { return false }
        onOpenURL?(url)
        return true
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { super.copy(sender); return }
        // Copying a collapsed link copies the full URL, not the `…` form.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reconstructedSource(in: range), forType: .string)
    }

    override func cut(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { super.cut(sender); return }
        copy(sender)
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Plain click on a shortened link toggles expand/collapse in
        // place (⌘↩ is how a link opens). Modified or multi clicks
        // keep their usual selection behavior.
        let plainClick = event.clickCount == 1
            && event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty
        if plainClick, let presentation = lastLinkPresentation {
            let point = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: point)
            if let hit = presentation.presentedLink(atDisplayUTF16Offset: idx),
               LinkShrink.shortened(hit.raw).contains("…")
            {
                expandedLinkRawValues = LinkShrink.toggled(expandedLinkRawValues, raw: hit.raw)
                refreshLinkAttributes(collapsingAtCaret: true)
                if let now = lastLinkPresentation?.links.first(where: {
                    $0.raw == hit.raw && $0.sourceUTF16Range == hit.sourceUTF16Range
                }) {
                    setSelectedRange(NSRange(
                        location: now.displayUTF16Range.lowerBound,
                        length: now.displayUTF16Range.count))
                }
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // ⌘↩ (Return or keypad Enter) opens the URL under the caret.
        if event.modifierFlags.contains(.command),
           event.keyCode == 36 || event.keyCode == 76 || event.characters == "\r" || event.characters == "\n"
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
