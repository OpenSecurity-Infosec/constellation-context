import AppKit
import ContextDomain

/// Floating scratchpad panel with two-finger trackpad swipe navigation.
/// Left swipe advances to the next note; right swipe goes back.
@MainActor
final class ContextPanel: NSPanel {
    var onSwipe: ((SwipeNavigation.Direction) -> Void)?
    private var navigator = SwipeNavigation()

    override func swipe(with event: NSEvent) {
        if let direction = SwipeNavigation.swipeEventDirection(deltaX: event.deltaX) {
            onSwipe?(direction)
            return
        }
        super.swipe(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Fallback for trackpads reporting horizontal swipes as scrolls.
        // Vertical scrolling is consumed by the editor's scroll view and
        // never reaches the window; horizontal motion propagates up.
        guard event.subtype == .touch else {
            super.scrollWheel(with: event)
            return
        }
        switch event.phase {
        case .began:
            navigator.begin()
            navigator.add(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY))
        case .changed:
            navigator.add(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY))
        case .ended:
            navigator.add(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY))
            if let direction = navigator.end() {
                onSwipe?(direction)
                return
            }
            super.scrollWheel(with: event)
        case .cancelled:
            navigator.cancel()
            super.scrollWheel(with: event)
        default:
            super.scrollWheel(with: event)
        }
    }

    override func touchesEnded(with event: NSEvent) {
        if let direction = navigator.end() {
            onSwipe?(direction)
        } else {
            super.touchesEnded(with: event)
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        navigator.cancel()
        super.touchesCancelled(with: event)
    }
}
