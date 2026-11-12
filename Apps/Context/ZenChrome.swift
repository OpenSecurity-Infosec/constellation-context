import AppKit
import SwiftUI

/// Zen canvas metrics. The canvas is text only; chrome lives in thin
/// hover bands at the top and bottom edges and never overlaps the text.
enum ZenMetrics {
    /// Space around the text. The top inset clears the hidden title bar.
    static let textInset = NSSize(width: 32, height: 44)
    /// Height of the header row, matched to the title bar so its controls
    /// line up with the traffic lights.
    static let headerHeight: CGFloat = 28
    /// Pointer within this distance of the top edge reveals the header.
    static let headerBand: CGFloat = 44
    /// Pointer within this distance of the bottom edge reveals the footer.
    static let footerBand: CGFloat = 40
    /// How long the note-position dots stay after switching notes.
    static let positionFlash: Duration = .milliseconds(1200)
}

/// What chrome is visible right now. Hidden by default; the pointer near an
/// edge reveals it, and typing hides it again.
@MainActor
final class ZenChrome: ObservableObject {
    @Published private(set) var header = false
    @Published private(set) var footer = false
    @Published private(set) var positionFlash = false
    private var flashTask: Task<Void, Never>?

    /// `point` is measured from the top-left of the canvas; nil means the
    /// pointer left the window.
    func pointer(_ point: CGPoint?, height: CGFloat) {
        setHeader(point.map { $0.y <= ZenMetrics.headerBand } ?? false)
        let nearBottom = point.map { $0.y >= height - ZenMetrics.footerBand } ?? false
        if footer != nearBottom { footer = nearBottom }
    }

    /// Typing hides everything until the pointer moves again.
    func typing() {
        setHeader(false)
        if footer { footer = false }
    }

    /// Briefly shows where this note sits among the pad's notes.
    func flashPosition() {
        positionFlash = true
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: ZenMetrics.positionFlash)
            guard !Task.isCancelled else { return }
            self?.positionFlash = false
        }
    }

    private func setHeader(_ visible: Bool) {
        guard header != visible else { return }
        header = visible
    }
}

/// Window content view that reports the pointer to `ZenChrome`. The
/// tracking area's owner gets moves even while the text view is under the
/// pointer, so the bands work over the full-bleed editor.
@MainActor
final class ZenContainerView: NSView {
    var onPointer: ((CGPoint?, CGFloat) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil, bounds.height) }

    private func report(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Measure from the top so callers don't care about flipping.
        let fromTop = isFlipped ? p.y : bounds.height - p.y
        onPointer?(CGPoint(x: p.x, y: fromTop), bounds.height)
    }
}

/// A menu item that runs a closure. Lets one builder produce the same menu
/// for the menu bar, the canvas's context menu, and the header's ⋯ button.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(
        _ title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        isOn: Bool = false,
        identifier: String? = nil,
        _ handler: @escaping @MainActor () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        state = isOn ? .on : .off
        if let identifier { setAccessibilityIdentifier(identifier) }
    }

    required init(coder: NSCoder) {
        fatalError("ActionMenuItem is built in code only")
    }

    @objc private func fire(_ sender: Any?) { handler() }

    /// A titled item holding a submenu.
    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}
