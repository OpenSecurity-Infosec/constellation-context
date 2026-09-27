import Foundation

/// Pure decision logic for two-finger swipe note navigation.
/// UI-free so it is unit-testable; AppKit feeds it gesture deltas.
public struct SwipeNavigation: Sendable {
    public enum Direction: Sendable { case next, previous }

    public var threshold: Double = 80
    public var dominance: Double = 2.0
    private var x: Double = 0
    private var y: Double = 0
    private var tracking = false

    public init() {}

    public mutating func begin() {
        x = 0
        y = 0
        tracking = true
    }

    public mutating func add(deltaX: Double, deltaY: Double) {
        guard tracking else { return }
        x += deltaX
        y += deltaY
    }

    /// Call when the gesture ends. Leftward flick → next note,
    /// rightward flick → previous note, matching Antinote.
    public mutating func end() -> Direction? {
        defer { tracking = false; x = 0; y = 0 }
        guard tracking else { return nil }
        guard abs(x) >= threshold, abs(x) >= dominance * abs(y) else { return nil }
        return x < 0 ? .next : .previous
    }

    public mutating func cancel() {
        tracking = false
        x = 0
        y = 0
    }

    /// Direct mapping for AppKit `swipe(with:)` events.
    public static func swipeEventDirection(deltaX: Double) -> Direction? {
        if deltaX < 0 { return .next }
        if deltaX > 0 { return .previous }
        return nil
    }
}
