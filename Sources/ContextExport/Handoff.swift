import ContextDomain
import Foundation

/// One-click handoff targets: Apple Notes, Obsidian, Bear.
/// Pure helpers stay testable; AppKit/Process calls live in the app layer.
public enum Handoff: Sendable {
    /// First non-empty line becomes the title; the rest is the body.
    public static func titleAndBody(for note: ContextNote) -> (title: String, body: String) {
        let lines = note.text.components(separatedBy: .newlines)
        guard let first = lines.first else { return ("Context note", "") }
        let title = first.trimmingCharacters(in: .whitespaces)
        let body = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? "Context note" : title, body)
    }

    /// Bear x-callback-url for creating a note. Opened via NSWorkspace.
    public static func bearURL(for note: ContextNote) -> URL? {
        let (title, body) = titleAndBody(for: note)
        var parts = URLComponents(string: "bear://x-callback-url/create")
        var items = [URLQueryItem(name: "title", value: title)]
        if !body.isEmpty { items.append(URLQueryItem(name: "text", value: body)) }
        parts?.queryItems = items
        return parts?.url
    }

    /// Obsidian vault file URL for a note, slugified from the title.
    public static func obsidianFileURL(for note: ContextNote, vault: URL) -> URL {
        let (title, _) = titleAndBody(for: note)
        return vault.appendingPathComponent("\(slug(title)).md")
    }

    /// AppleScript source creating a Notes.app note. Run via `osascript`.
    public static func appleNotesScript(title: String, body: String) -> String {
        let t = appleScriptString(title)
        let b = appleScriptString(body.isEmpty ? title : "\(title)\n\n\(body)")
        return "tell application \"Notes\" to make new note at folder \"Notes\" with properties {name:\(t), body:\(b)}"
    }

    public static func slug(_ title: String) -> String {
        var s = title.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.isEmpty { s = "context-note" }
        return String(s.prefix(80))
    }

    private static func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
