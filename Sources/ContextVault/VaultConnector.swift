import Foundation

/// Points at one note inside one linked vault. `noteID` is connector
/// specific: a relative path for folders, an object id for Anytype.
public struct VaultNoteRef: Hashable, Codable, Sendable {
    public var vaultID: String
    public var noteID: String

    public init(vaultID: String, noteID: String) {
        self.vaultID = vaultID
        self.noteID = noteID
    }
}

public struct VaultNoteSummary: Identifiable, Equatable, Sendable {
    public var ref: VaultNoteRef
    public var title: String
    public var snippet: String
    public var modified: Date?

    public var id: VaultNoteRef { ref }

    public init(ref: VaultNoteRef, title: String, snippet: String = "", modified: Date? = nil) {
        self.ref = ref
        self.title = title
        self.snippet = snippet
        self.modified = modified
    }
}

/// A note as Markdown: frontmatter carries the source's metadata, the
/// body carries the content. `document.text` is what Context shows.
public struct VaultNote: Equatable, Sendable {
    public var ref: VaultNoteRef
    public var document: MarkdownDocument
    public var modified: Date?
    /// The source's own name for the note: a file name without `.md`,
    /// or an Anytype object name.
    public var name: String?

    public init(ref: VaultNoteRef, document: MarkdownDocument, modified: Date? = nil, name: String? = nil) {
        self.ref = ref
        self.document = document
        self.modified = modified
        self.name = name
    }

    public var title: String {
        for candidate in [document.value(for: "title"), name] {
            if let c = candidate, !c.isEmpty { return c }
        }
        return document.title
    }
}

public enum VaultError: Error, Equatable, Sendable {
    /// The source app is not running or the folder is gone.
    case unavailable(String)
    /// Credentials missing, revoked, or wrong.
    case unauthorized
    case notFound
    /// The note changed in another app after Context read it.
    case conflict
    case rateLimited
    /// The edit cannot be represented in the source without losing data.
    case unsupported(String)
    case invalid(String)

    public var message: String {
        switch self {
        case .unavailable(let why): why
        case .unauthorized: "Context isn't authorized. Link the vault again."
        case .notFound: "That note no longer exists."
        case .conflict: "This note changed in another app. Reopen it to see the latest version."
        case .rateLimited: "The vault is busy. Try again in a moment."
        case .unsupported(let why): why
        case .invalid(let why): why
        }
    }
}

public enum VaultKind: String, Codable, Sendable, CaseIterable {
    case anytype
    case obsidian
}

/// An external note store reached through one interface (ADR-0002).
/// Context code depends on this protocol, never on a specific app.
public protocol VaultConnector: Sendable {
    var id: String { get }
    var kind: VaultKind { get }
    var displayName: String { get }

    func list() async throws -> [VaultNoteSummary]
    func search(_ query: String) async throws -> [VaultNoteSummary]
    func read(_ ref: VaultNoteRef) async throws -> VaultNote
    /// Writes an edited note back. Unchanged parts must stay byte- or
    /// value-identical in the source; edits that cannot be represented
    /// throw `.unsupported` instead of being dropped.
    @discardableResult
    func write(_ note: VaultNote) async throws -> VaultNote
    func create(title: String, body: String) async throws -> VaultNote
}
