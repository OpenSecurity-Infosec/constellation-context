import AppKit
import ContextDomain

/// Feeds the Clipboard pad. Polls the general pasteboard's change count
/// on the main run loop and hands new text to `onCopy`, skipping what
/// `ClipboardPolicy` rules out (password-manager secrets, huge blobs,
/// repeats).
@MainActor
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastText: String?

    var isRunning: Bool { timer != nil }

    func start(onCopy: @escaping @MainActor (String) -> Void) {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(onCopy) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll(_ onCopy: @MainActor (String) -> Void) {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        let types = board.types?.map(\.rawValue) ?? []
        let text = board.string(forType: .string)
        guard ClipboardPolicy.shouldCapture(text: text, types: types, previous: lastText), let text else { return }
        lastText = text
        onCopy(PlainText.normalizePaste(text))
    }
}
