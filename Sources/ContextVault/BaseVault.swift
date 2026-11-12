import Foundation

/// Context's own Obsidian-compliant vault (ADR-0002). Plain folders of
/// Markdown; Obsidian ignores the dot-folders, so the vault opens there
/// with no conversion. Context never creates `.obsidian/`.
public struct BaseVault: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// `~/Context`. Outside `~/Documents` so ad-hoc-signed development
    /// builds do not re-trigger the Documents privacy prompt every rebuild.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Context", isDirectory: true)
    }

    public var scratch: URL { root.appendingPathComponent("Scratch", isDirectory: true) }
    public var clipboard: URL { root.appendingPathComponent("Clipboard", isDirectory: true) }
    public var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    /// Same name Obsidian uses for its vault trash, so trashed notes stay
    /// recoverable from either app.
    public var trash: URL { root.appendingPathComponent(".trash", isDirectory: true) }
    /// Derived, rebuildable state (ADR-0001). Safe to delete.
    public var state: URL { root.appendingPathComponent(".context", isDirectory: true) }
    public var index: URL { state.appendingPathComponent("index.json") }

    /// Creates the folder layout. Idempotent; never touches existing files.
    public func ensure() throws {
        let fm = FileManager.default
        for dir in [root, scratch, clipboard, projects, trash, state] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Path relative to the vault root, using `/` separators.
    public func relativePath(of url: URL) -> String? {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return nil }
        return String(path.dropFirst(base.count))
    }

    public func url(forRelativePath path: String) -> URL {
        root.appendingPathComponent(path)
    }
}

/// File names for notes Context creates. Timestamp-named so typing never
/// renames a file and links to it stay valid.
public enum NoteFileName {
    public static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// A URL in `folder` named `stem.md` that does not exist yet, adding
    /// " 2", " 3"… on collision.
    public static func available(stem: String, ext: String = "md", in folder: URL, taken: Set<String> = []) -> URL {
        let fm = FileManager.default
        var n = 1
        while true {
            let name = n == 1 ? "\(stem).\(ext)" : "\(stem) \(n).\(ext)"
            let url = folder.appendingPathComponent(name)
            if !taken.contains(name), !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// Filesystem-safe stem from free text: keeps letters, digits, spaces,
    /// and `-`; collapses the rest. Never empty.
    public static func slug(_ text: String, limit: Int = 60) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var out = ""
        for scalar in text.unicodeScalars {
            out.unicodeScalars.append(allowed.contains(scalar) ? scalar : " ")
        }
        let collapsed = out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let trimmed = String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
