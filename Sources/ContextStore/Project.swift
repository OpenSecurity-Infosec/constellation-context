import ContextVault
import Foundation

/// AI tools a project's context can be delivered to. Real connectors
/// come later; MVP connectors are stubs (Vision § Injection).
public enum HarnessKind: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case opencode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .opencode: "opencode"
        }
    }
}

/// A linked-vault note attached to a project by reference. Its text is
/// read fresh from the source whenever the context is assembled.
public struct ProjectReference: Codable, Equatable, Sendable {
    public var ref: VaultNoteRef
    public var title: String
    public var addedAt: Date

    public init(ref: VaultNoteRef, title: String, addedAt: Date = Date()) {
        self.ref = ref
        self.title = title
        self.addedAt = addedAt
    }
}

/// `Projects/<name>/project.json`: what is attached and where the
/// context goes. User data, so it lives in the vault, not `.context/`.
public struct ProjectManifest: Codable, Equatable, Sendable {
    public var references: [ProjectReference] = []
    public var harnesses: [HarnessKind] = []
    public var routerSync = false

    public init(references: [ProjectReference] = [], harnesses: [HarnessKind] = [], routerSync: Bool = false) {
        self.references = references
        self.harnesses = harnesses
        self.routerSync = routerSync
    }
}

/// Paths for one project in the base vault.
public struct ProjectFiles: Equatable, Sendable {
    public let vault: BaseVault
    public let name: String

    public init(vault: BaseVault, name: String) {
        self.vault = vault
        self.name = name
    }

    public var folder: URL { vault.projects.appendingPathComponent(name, isDirectory: true) }
    public var contextFile: URL { folder.appendingPathComponent("context.md") }
    public var docs: URL { folder.appendingPathComponent("docs", isDirectory: true) }
    public var manifestURL: URL { folder.appendingPathComponent("project.json") }
    /// The assembled context, kept current for harnesses to import
    /// (`@<path>` in a CLAUDE.md or AGENTS.md). Derived; safe to delete.
    public var output: URL { vault.state.appendingPathComponent("projects/\(name).md") }

    public func manifest() -> ProjectManifest {
        guard let data = try? Data(contentsOf: manifestURL) else { return ProjectManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProjectManifest.self, from: data)) ?? ProjectManifest()
    }

    public func save(_ manifest: ProjectManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    /// Files in `docs/`, newest first. Hidden files are skipped.
    public func documents() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
