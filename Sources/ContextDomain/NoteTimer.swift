import Foundation

/// Timer engine for `timer` notes. Stopwatch, countdown, and pomodoro.
public final class NoteTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var durationSeconds: TimeInterval?
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
            if case .countdown(let s) = mode { durationSeconds = s }
            else if case .pomodoro(let s) = mode { durationSeconds = s }
            else { durationSeconds = nil }
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
        guard let durationSeconds else { return nil }
        return max(0, durationSeconds - elapsed)
    }

    public var isRunning: Bool { lock.withLock { running } }

    /// Total duration for countdown/pomodoro modes, nil for stopwatch.
    public var totalDuration: TimeInterval? { lock.withLock { durationSeconds } }

    /// Fraction of the countdown elapsed (0...1), nil for stopwatch.
    public var fractionDone: Double? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return min(1, max(0, elapsed / durationSeconds))
    }
}

/// Fullscreen scene copy: pure status/finish lines so the timer display
/// and tests share one source of truth.
public enum TimerScene: Sendable {
    /// "7:30 in · 12:30 left" while running, "Paused · 12:30 left" when
    /// stopped mid-countdown, "0:05 up" for stopwatches, "" when idle.
    public static func statusLine(elapsed: TimeInterval, remaining: TimeInterval?, running: Bool) -> String {
        if let remaining {
            if remaining <= 0 { return "" }
            let tail = "\(NoteTimer.format(elapsed)) in · \(NoteTimer.format(remaining)) left"
            return running ? tail : "Paused · \(NoteTimer.format(remaining)) left"
        }
        if elapsed > 0 || running { return "\(NoteTimer.format(elapsed)) up" }
        return ""
    }

    /// "Done in 20:00" for the finish state.
    public static func finishLine(total: TimeInterval?) -> String {
        guard let total else { return "Done" }
        return "Done in \(NoteTimer.format(total))"
    }

    /// "36%" ring label for a 0...1 fraction.
    public static func ringLabel(fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }
}

extension NoteTimer {
    /// Timer name from the note: first non-empty body line that is not a
    /// duration spec (e.g. "25m", "10:00", "pomodoro 25m"). Empty when none.
    public static func name(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines).dropFirst()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            let bare = lower
                .replacingOccurrences(of: "pomodoro", with: "")
                .trimmingCharacters(in: .whitespaces)
            if bare.isEmpty { continue }
            if bare.range(of: #"^(\d+\s*[ms]?|\d+:\d+)$"#, options: .regularExpression) != nil { continue }
            return trimmed
        }
        return ""
    }

    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
