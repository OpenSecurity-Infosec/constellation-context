import Foundation

/// Expands the minimal date tokens used by note templates. Unknown tokens and
/// all other Markdown remain verbatim. The caller supplies the date and zone
/// so creating a note is deterministic, including around midnight.
public enum NoteTemplate {
    public static func expand(_ template: String, at date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return template.replacingOccurrences(of: "{{date}}", with: formatter.string(from: date))
    }
}
