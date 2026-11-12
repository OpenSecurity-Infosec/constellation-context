import ContextAI
import ContextDomain
import ContextStore
import SwiftUI

/// The zen canvas: full-bleed text and nothing else. A header (pad,
/// new, search, ⋯) and the note-position dots live in hover bands at the
/// edges and fade in only when the pointer goes there. Every action is also
/// in the menu bar and the right-click menu.
struct ContextEditorRoot: View {
    weak var controller: ContextWindowController?
    @ObservedObject var chrome: ZenChrome
    var note: ContextNote
    var pad: Pad = .scratch
    var pads: [Pad] = []
    var project: ProjectInfo?
    var inspectorOpen = false
    var aiState: AIState = .idle
    var liveCount: Int
    var noteIndex: Int = 0
    var mathResults: [MathEngine.LineOutcome]
    var aggregate: String?
    var sumAvgLines: [String] = []
    var countLines: [String] = []
    var stats: NoteStats?
    var checklist: [ChecklistItem]
    var autoPasteArmed: Bool
    var elapsed: TimeInterval
    var remaining: TimeInterval?
    var timerRunning: Bool
    var ratesFootnote: String? = nil
    var jsExtensions: [JSExtension.Script] = []

    @State private var slashFragment: String? = nil
    @State private var slashRange: NSRange = NSRange(location: 0, length: 0)
    @State private var slashSelected: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            canvas
            if inspectorOpen {
                NoteInspector(controller: controller, pad: pad, project: project, escCloses: aiState == .idle)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: inspectorOpen)
        .background(Color.ctxEditorBackground)
        .ignoresSafeArea()
        .frame(minWidth: 360, minHeight: 240)
    }

    private var canvas: some View {
        ZStack {
            editor
            VStack(spacing: 0) {
                header
                    .opacity(chrome.header ? 1 : 0)
                    .allowsHitTesting(chrome.header)
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    if aiState != .idle { aiCard }
                    if hasModeCard { modeCard }
                    positionDots
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: chrome.header)
        .animation(.easeOut(duration: 0.18), value: chrome.footer)
        .animation(.easeOut(duration: 0.25), value: chrome.positionFlash)
    }

    // MARK: - Header (hover only)

    private var header: some View {
        HStack(spacing: 14) {
            // Room for the traffic lights, which always show.
            Color.clear.frame(width: 64, height: 1)
            Menu(pad.title) {
                ForEach(Array(pads.enumerated()), id: \.element) { index, p in
                    Button(index < 9 ? "\(p.title)  ⌘\(index + 1)" : p.title) { controller?.switchPad(p) }
                }
                Divider()
                Button("New Project…") { controller?.promptNewProject() }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("overlay.padMenu")
            Spacer(minLength: 0)
            headerIcon("plus", help: "New note (⌘N)", id: "overlay.newNote") { controller?.newNote() }
            headerIcon("magnifyingglass", help: "Search notes (⌘F)", id: "overlay.search") { controller?.openSearch() }
            headerIcon("ellipsis", help: "More", id: "overlay.more") { controller?.showMoreMenu() }
        }
        .padding(.horizontal, 12)
        .frame(height: ZenMetrics.headerHeight)
        .background {
            // Empty header space drags the window, like a title bar.
            Color.ctxEditorBackground
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    private func headerIcon(_ symbol: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityIdentifier(id)
    }

    // MARK: - Footer

    /// Where this note sits in the pad. Shown after a note switch and when
    /// the pointer is near the bottom edge; hidden for a single note.
    @ViewBuilder
    private var positionDots: some View {
        if liveCount > 1 {
            Group {
                if liveCount <= 12 {
                    HStack(spacing: 6) {
                        ForEach(0..<liveCount, id: \.self) { i in
                            Circle()
                                .fill(i == noteIndex ? Color.primary : Color.secondary.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                    }
                } else {
                    Text("\(noteIndex + 1) / \(liveCount)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 12)
            .opacity(chrome.footer || chrome.positionFlash ? 0.8 : 0)
            .allowsHitTesting(false)
            .accessibilityIdentifier("overlay.position")
        }
    }

    private var editor: some View {
        Group {
            if note.kind == .list {
                checklistView
            } else {
                ZStack(alignment: .topLeading) {
                    mathGutter
                    PlainTextEditor(text: note.text, noteID: note.id, titlesFirstLine: pad != .clipboard, onChange: { controller?.onTextChange($0) }, onCaret: { caret in controller?.trackCaret(caret) }, onIndent: { direction in
                        controller?.indentRowAtCaret(direction: direction)
                    }, onSlash: { fragment, range in
                        slashFragment = fragment
                        slashRange = range
                        slashSelected = 0
                    }, onImagePaste: { image in
                        controller?.handleImageDrop(image)
                    }, contextMenuItems: {
                        controller?.noteMenuItems(for: .canvas) ?? []
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
        // Line up with the text view's inset (it adds 10pt of its own).
        .padding(.top, ZenMetrics.textInset.height - 10)
        .padding(.trailing, ZenMetrics.textInset.width)
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
        .scrollContentBackground(.hidden)
        .padding(.top, ZenMetrics.textInset.height - 10)
        .padding(.horizontal, ZenMetrics.textInset.width - 16)
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
        .offset(x: ZenMetrics.textInset.width, y: ZenMetrics.textInset.height + 24)
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

    /// Legacy first-line modes keep a small floating readout. Plain notes
    /// and modes with nothing live to show get none.
    private var hasModeCard: Bool {
        switch note.kind {
        case .sum, .avg, .count, .timer: true
        case .paste: autoPasteArmed
        case .math: ratesFootnote != nil
        default: false
        }
    }

    private var modeCard: some View {
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
                    .font(.system(.title3).monospaced())
                Button(timerRunning ? "Stop" : "Start") {
                    timerRunning ? controller?.timerStop() : controller?.timerStart()
                }
                Button("Reset") { controller?.timerReset() }
                Button("Full Screen") { controller?.openTimerFullscreen() }
            case .paste:
                Text("Collecting copies").font(.caption).foregroundStyle(.secondary)
            case .math:
                if let ratesFootnote {
                    Text(ratesFootnote).font(.caption).foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    /// AI proposals float over the bottom of the canvas until accepted or
    /// rejected.
    @ViewBuilder
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch aiState {
            case .idle:
                EmptyView()
            case .thinking(let label):
                HStack {
                    ProgressView().controlSize(.small)
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { controller?.cancelAI() }
                        .keyboardShortcut(.cancelAction)
                }
            case .failed(let message):
                HStack {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("OK") { controller?.cancelAI() }
                        .keyboardShortcut(.cancelAction)
                }
            case .ready(let proposal, let target):
                HStack {
                    Text("\(proposal.action.title) → \(target.label)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Reject") { controller?.rejectProposal() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("overlay.ai.reject")
                    Button("Accept") { controller?.acceptProposal() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("overlay.ai.accept")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(proposal.diff.enumerated()), id: \.offset) { _, line in
                            diffRow(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("overlay.ai.drawer")
    }

    private func diffRow(_ line: DiffLine) -> some View {
        let marker: String
        let style: Color
        switch line.kind {
        case .same: marker = "  "; style = .secondary
        case .added: marker = "+ "; style = .primary
        case .removed: marker = "− "; style = .secondary
        }
        return Text(marker + line.text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(style)
            .strikethrough(line.kind == .removed)
            .background(line.kind == .added ? Color.ctxAccent.opacity(0.12) : Color.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The note's text view. The store is the single source of truth: typing
/// is reported through `onChange` (which saves synchronously), and
/// `updateNSView` only pushes text that changed somewhere else — a note
/// switch, a command, an AI edit. Provisional (marked) text from input
/// methods and macOS inline predictions is never saved or overwritten.
private struct PlainTextEditor: NSViewRepresentable {
    var text: String
    var noteID: UUID
    /// Clipboard entries are snippets, not documents, so they get no title.
    var titlesFirstLine = true
    var onChange: (String) -> Void
    var onCaret: ((Int) -> Void)?
    var onIndent: ((ChecklistItem.IndentDirection) -> Void)?
    var onSlash: ((String, NSRange) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?
    var contextMenuItems: (() -> [NSMenuItem])?

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ContextTextView()
        ContextTextView.active = tv
        tv.onChange = { newText in context.coordinator.onChange?(newText) }
        tv.onCaret = { caret in onCaret?(caret) }
        tv.onIndent = { direction in onIndent?(direction) }
        tv.onSlash = { fragment, range in onSlash?(fragment, range) }
        tv.onOpenURL = { url in NSWorkspace.shared.open(url) }
        tv.onImagePaste = { image in onImagePaste?(image) }
        tv.contextMenuItems = contextMenuItems
        tv.isAutomaticLinkDetectionEnabled = false
        tv.font = ContextTheme.bodyFont
        tv.titlesFirstLine = titlesFirstLine
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.allowsUndo = true
        tv.backgroundColor = .clear
        tv.insertionPointColor = ContextTheme.ink
        tv.textContainerInset = ZenMetrics.textInset
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        context.coordinator.view = tv
        context.coordinator.onChange = onChange
        context.coordinator.noteID = noteID
        context.coordinator.styleKey = ContextTheme.typographyKey
        tv.string = text
        tv.refreshStyling()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ContextTextView else { return }
        context.coordinator.onChange = onChange
        tv.contextMenuItems = contextMenuItems
        let switched = context.coordinator.noteID != noteID
        context.coordinator.noteID = noteID
        // Restyle when the text size, theme, or pad changes. Renders run
        // several times a second, so only on a real change.
        let key = ContextTheme.typographyKey
        if (context.coordinator.styleKey != key || tv.titlesFirstLine != titlesFirstLine), !tv.hasMarkedText() {
            context.coordinator.styleKey = key
            tv.titlesFirstLine = titlesFirstLine
            tv.insertionPointColor = ContextTheme.ink
            tv.refreshStyling()
        }
        // Mid-composition the view holds provisional text the store
        // deliberately lacks; leave it alone until it resolves.
        guard switched || !tv.hasMarkedText(), tv.string != text else { return }
        let caret = tv.selectedRange()
        tv.string = text
        let length = (text as NSString).length
        tv.setSelectedRange(switched
            ? NSRange(location: length, length: 0)
            : NSRange(location: min(caret.location, length), length: min(caret.length, max(0, length - caret.location))))
        tv.refreshStyling()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var view: NSTextView?
        var noteID: UUID?
        var styleKey: String?
        var onChange: ((String) -> Void)?
    }
}

/// NSTextView that pastes text without styling (Markdown kept) and
/// reports changes.
/// Applies Link Shrink: pasted URLs display shortened while the full URL
/// is preserved for open/copy. Links render clickable.
final class ContextTextView: NSTextView {
    var onChange: ((String) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onIndent: ((ChecklistItem.IndentDirection) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onSlash: ((String, NSRange) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?
    /// Note actions shown above the standard text items on right-click.
    var contextMenuItems: (() -> [NSMenuItem])?
    /// Whether a prose note's first line is set as a title.
    var titlesFirstLine = true
    private var slashCompletion: NSView?
    /// The overlay's text view, so accepted AI proposals can be applied
    /// as a native, undoable edit.
    static weak var active: ContextTextView?

    override func paste(_ sender: Any?) {
        // Text only, Markdown kept: styling is dropped, structure stays.
        let board = NSPasteboard.general
        if let s = board.string(forType: .string) {
            let clean = PlainText.normalizePaste(s)
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
        // Marked text is provisional (an input method mid-composition or a
        // macOS inline prediction). Report only committed text.
        guard !hasMarkedText() else { return }
        refreshStyling()
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

    /// Re-applies display styling: typography, then links.
    func refreshStyling() {
        applyTypography()
        refreshLinkAttributes()
    }

    /// Sets the title and body type. Display attributes only; the string,
    /// and so the file, never changes.
    private func applyTypography() {
        guard let storage = textStorage else { return }
        let prose = CanvasTypography.isProse(string)
        let body: [NSAttributedString.Key: Any] = [
            .font: ContextTheme.bodyFont,
            .foregroundColor: ContextTheme.ink,
            .paragraphStyle: ContextTheme.bodyParagraph(prose: prose),
        ]
        let title: [NSAttributedString.Key: Any] = body.merging([
            .font: ContextTheme.titleFont,
            .paragraphStyle: ContextTheme.titleParagraph,
        ]) { _, new in new }
        let titleRange = titlesFirstLine ? CanvasTypography.titleRange(in: string) : nil
        storage.beginEditing()
        if storage.length > 0 {
            storage.setAttributes(body, range: NSRange(location: 0, length: storage.length))
        }
        if let titleRange {
            storage.addAttributes(title, range: titleRange)
        }
        storage.endEditing()
        defaultParagraphStyle = body[.paragraphStyle] as? NSParagraphStyle
        // An empty note starts typing as a title, so the first word doesn't
        // jump in size after it lands.
        if storage.length == 0 {
            typingAttributes = titlesFirstLine ? title : body
        }
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
        guard let url = LinkShrink.link(atUTF16Offset: selectedRange().location, in: string)?.url
        else { return false }
        onOpenURL?(url)
        return true
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

    override func menu(for event: NSEvent) -> NSMenu? {
        let base = super.menu(for: event) ?? NSMenu()
        let extra = contextMenuItems?() ?? []
        guard !extra.isEmpty else { return base }
        for item in extra.reversed() {
            base.insertItem(item, at: 0)
        }
        base.insertItem(.separator(), at: extra.count)
        return base
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

}

import ContextMath
import ContextDomain
