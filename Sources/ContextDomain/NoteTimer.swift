import Foundation

/// Timer engine for `timer` notes. Stopwatch, countdown, and pomodoro.
public final class NoteTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var duration: TimeInterval?
    private var running = false

    public init() {}

    public enum Mode: Equatable, Sendable {
        case stopwatch
        case countdown(seconds: TimeInterval)
        case pomodoro(seconds: TimeInterval)
    }

    public static func parseMode(from text: String) -> Mode {
        // "timer 25m", "timer 10:00", "timer pomodoro", "timer" (stopwatch).
        let body = text.components(separatedBy: .newlines).dropFirst().joined(separator: " ") + " " +
            (text.components(separatedBy: .newlines).first ?? "")
        let lower = body.lowercased()
        if lower.contains("pomodoro") {
            return .pomodoro(seconds: 25 * 60)
        }
        if let m = lower.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let digits = lower[m].filter(\.isNumber)
            if let mins = Double(digits) { return .countdown(seconds: mins * 60) }
        }
        if let m = lower.range(of: #"(\d+):(\d+)"#, options: .regularExpression) {
            let parts = lower[m].split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return .countdown(seconds: parts[0] * 60 + parts[1]) }
        }
        if let m = lower.range(of: #"(\d+)\s*s"#, options: .regularExpression) {
            let digits = lower[m].filter(\.isNumber)
            if let s = Double(digits) { return .countdown(seconds: s) }
        }
        return .stopwatch
    }

    public func start(mode: Mode) {
        lock.withLock {
            if case .countdown(let s) = mode { duration = s }
            else if case .pomodoro(let s) = mode { duration = s }
            else { duration = nil }
            startDate = Date()
            running = true
        }
    }

    public func stop() {
        lock.withLock {
            if let s = startDate { accumulated += Date().timeIntervalSince(s) }
            startDate = nil
            running = false
        }
    }

    public func reset() {
        lock.withLock {
            startDate = running ? Date() : nil
            accumulated = 0
        }
    }

    public var elapsed: TimeInterval {
        lock.withLock {
            if let s = startDate { return accumulated + Date().timeIntervalSince(s) }
            return accumulated
        }
    }

    public var remaining: TimeInterval? {
        guard let duration else { return nil }
        return max(0, duration - elapsed)
    }

    public var isRunning: Bool { lock.withLock { running } }

    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
