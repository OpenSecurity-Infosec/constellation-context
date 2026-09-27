import AppKit
import Foundation

/// Watches the general pasteboard while a `paste` note is armed.
/// Every new string lands in the note as sanitized plain text.
public final class AutoPasteMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var callback: (@Sendable (String) -> Void)?

    public init() {}

    public var isArmed: Bool { lock.withLock { timer != nil } }

    public func start(onPaste: @escaping @Sendable (String) -> Void) {
        lock.withLock {
            stopLocked()
            callback = onPaste
            lastChangeCount = NSPasteboard.general.changeCount
            let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            t.schedule(deadline: .now() + 0.4, repeating: 0.4)
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume()
            timer = t
        }
    }

    public func stop() {
        lock.withLock { stopLocked() }
    }

    private func stopLocked() {
        timer?.cancel()
        timer = nil
        callback = nil
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        guard let s = board.string(forType: .string), !s.isEmpty else { return }
        callback?(s)
    }
}
