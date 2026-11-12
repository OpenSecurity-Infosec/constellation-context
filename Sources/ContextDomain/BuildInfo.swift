import Foundation

/// Human-readable build identity stamped into Info.plist by
/// `Scripts/package-app.sh` (`CFBundleVersion` = short git hash,
/// `ContextBuildDate` = ISO8601 UTC build time, `ContextCommitSubject`).
public enum BuildInfo {
    /// `"<hash> · built <local time>"`, or just the hash when the build time
    /// is missing or unparseable (e.g. a plain `swift run`).
    public static func label(from info: [String: Any], timeZone: TimeZone = .current) -> String {
        let revision = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
        guard let built = (info["ContextBuildDate"] as? String).flatMap(parseISO8601) else {
            return revision
        }
        return "\(revision) · built \(localStamp(built, timeZone: timeZone))"
    }

    /// Longer form for the About panel: label plus the commit subject when stamped.
    public static func aboutText(from info: [String: Any], timeZone: TimeZone = .current) -> String {
        let base = label(from: info, timeZone: timeZone)
        guard let subject = info["ContextCommitSubject"] as? String, !subject.isEmpty else { return base }
        return "\(base)\n\(subject)"
    }

    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func localStamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
