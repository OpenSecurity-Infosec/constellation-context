import Foundation

/// Void (trash) expiry countdown. Trashed notes auto-delete after 30 days;
/// this surfaces per-note remaining time for the Void rows.
public enum NoteExpiry {
    /// Whole days left before a trashed note is garbage-collected.
    /// Nil for notes that are not trashed. Clamps at zero.
    public static func daysLeft(for note: ContextNote, now: Date = Date()) -> Int? {
        guard let trashedAt = note.trashedAt else { return nil }
        let deadline = trashedAt.addingTimeInterval(30 * 24 * 3600)
        let left = deadline.timeIntervalSince(now)
        if left <= 0 { return 0 }
        return Int(ceil(left / (24 * 3600)))
    }

    /// Short row label, e.g. "29 days left" or "last day".
    public static func label(for note: ContextNote, now: Date = Date()) -> String? {
        guard let days = daysLeft(for: note, now: now) else { return nil }
        if days <= 0 { return "expires soon" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }
}
