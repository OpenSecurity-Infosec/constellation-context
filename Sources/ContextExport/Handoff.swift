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

    // MARK: - Availability

    /// Why a handoff target cannot receive the note right now.
    public enum UnavailableReason: Equatable, Sendable {
        case notesMissing
        case notesScriptFailed
        case bearMissing
        case vaultUnset
        case vaultMissing(path: String)
        case vaultNotDirectory(path: String)
        case vaultUnwritable(path: String)

        /// Honest alert text. Names the problem and the fix, never a
        /// generic "not available".
        public var message: String {
            switch self {
            case .notesMissing:
                return "Apple Notes is not installed on this Mac, so Context could not hand off the note."
            case .notesScriptFailed:
                return "Apple Notes did not accept the note. Open Notes once, then try again."
            case .bearMissing:
                return "Bear is not installed, so Context could not hand off the note. Install Bear, then try again."
            case .vaultUnset:
                return "No Obsidian vault is set. Pick your vault folder to continue."
            case .vaultMissing(let path):
                return "The Obsidian vault folder is missing (\(path)). Pick your vault folder in Settings."
            case .vaultNotDirectory(let path):
                return "The Obsidian vault path is not a folder (\(path)). Pick your vault folder in Settings."
            case .vaultUnwritable(let path):
                return "Context cannot write to the Obsidian vault folder (\(path)). Check its permissions or pick another folder in Settings."
            }
        }
    }

    public struct Environment: Sendable {
        public var notesAppPresent: Bool
        public var bearSchemeOpenable: Bool
        public var fileExists: @Sendable (String) -> Bool
        public var isDirectory: @Sendable (String) -> Bool
        public var isWritable: @Sendable (String) -> Bool

        public init(
            notesAppPresent: Bool = true,
            bearSchemeOpenable: Bool = true,
            fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
            isDirectory: @escaping @Sendable (String) -> Bool = {
                (try? FileManager.default.attributesOfItem(atPath: $0)[.type] as? FileAttributeType) == .typeDirectory
            },
            isWritable: @escaping @Sendable (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }
        ) {
            self.notesAppPresent = notesAppPresent
            self.bearSchemeOpenable = bearSchemeOpenable
            self.fileExists = fileExists
            self.isDirectory = isDirectory
            self.isWritable = isWritable
        }

        /// Default live-ish environment using FileManager only.
        /// NSWorkspace checks (Bear scheme) are filled in by the app layer.
        public static func live() -> Environment {
            Environment(
                notesAppPresent: FileManager.default.fileExists(atPath: "/System/Applications/Notes.app")
                    || FileManager.default.fileExists(atPath: "/Applications/Notes.app"),
                bearSchemeOpenable: true
            )
        }
    }

    /// Pre-flight check for Apple Notes. Nil means go.
    public static func checkNotes(env: Environment) -> UnavailableReason? {
        env.notesAppPresent ? nil : .notesMissing
    }

    /// Pre-flight check for Bear. Nil means go.
    public static func checkBear(env: Environment) -> UnavailableReason? {
        env.bearSchemeOpenable ? nil : .bearMissing
    }

    /// Pre-flight check for an Obsidian vault path. Nil means go.
    /// Never creates anything: a bad path is reported, not materialized.
    public static func checkVault(path: String?, env: Environment) -> UnavailableReason? {
        guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else { return .vaultUnset }
        guard env.fileExists(path) else { return .vaultMissing(path: path) }
        guard env.isDirectory(path) else { return .vaultNotDirectory(path: path) }
        guard env.isWritable(path) else { return .vaultUnwritable(path: path) }
        return nil
    }
}
