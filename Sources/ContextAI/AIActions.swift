import Foundation

/// What the AI can do to a note. Each produces a proposal the user
/// accepts or rejects; nothing is applied silently (Vision principle 4).
public enum AIAction: Equatable, Hashable, Sendable {
    case summarize
    case tidy
    /// Pull durable facts and decisions from the note into a project's
    /// live context.
    case extract(project: String)
    /// Shorten a project's live context without losing what is still true.
    case compact

    public var title: String {
        switch self {
        case .summarize: "Summarize"
        case .tidy: "Tidy"
        case .extract(let project): "Extract to \(project)"
        case .compact: "Compact"
        }
    }

    static let rules = """
    Reply with Markdown only: no preamble, no closing remarks, no code fence around the whole reply. \
    Keep the author's voice, facts, links, code, and checklist state. Never invent facts.
    """

    var system: String {
        switch self {
        case .summarize:
            return "You summarize a note in a few short bullet points capturing decisions, facts, and open questions. " + Self.rules
        case .tidy:
            return "You tidy a note: fix structure, headings, lists, and typos so it reads clearly. Keep every fact and the first line exactly as written. " + Self.rules
        case .extract(let project):
            return "You extract from a note only what someone working on the project \"\(project)\" must keep in mind: decisions, constraints, facts, and open questions, as short bullets. Skip anything the existing project context already says. If nothing qualifies, reply with nothing. " + Self.rules
        case .compact:
            return "You compact a project's live context: merge duplicates, drop what is clearly obsolete, and tighten wording, while keeping every fact that may still be true. Keep the first line exactly as written. " + Self.rules
        }
    }

    func user(note: String, projectContext: String?) -> String {
        switch self {
        case .extract:
            return "Existing project context:\n\n\(projectContext ?? "(empty)")\n\n---\n\nNote to extract from:\n\n\(note)"
        default:
            return note
        }
    }
}

/// A proposed edit: the full new text of the target and how it differs.
public struct Proposal: Equatable, Sendable {
    public var action: AIAction
    public var original: String
    public var proposed: String

    public init(action: AIAction, original: String, proposed: String) {
        self.action = action
        self.original = original
        self.proposed = proposed
    }

    public var diff: [DiffLine] { LineDiff.compute(original, proposed) }
    public var isNoChange: Bool { original == proposed }
}

public struct AIActions: Sendable {
    public var client: ModelClient

    public init(client: ModelClient) {
        self.client = client
    }

    /// For `.extract`, `original` and `proposed` are the project's live
    /// context before and after; otherwise they are the note itself.
    public func propose(_ action: AIAction, note: String, projectContext: String? = nil) async throws -> Proposal {
        let reply = Self.clean(try await client.complete(system: action.system, user: action.user(note: note, projectContext: projectContext)))
        switch action {
        case .summarize:
            guard !reply.isEmpty else { return Proposal(action: action, original: note, proposed: note) }
            return Proposal(action: action, original: note, proposed: Self.join(note, "## Summary\n\n" + reply))
        case .tidy, .compact:
            return Proposal(action: action, original: note, proposed: reply.isEmpty ? note : reply + (note.hasSuffix("\n") ? "\n" : ""))
        case .extract:
            let base = projectContext ?? ""
            return Proposal(action: action, original: base, proposed: reply.isEmpty ? base : Self.join(base, reply))
        }
    }

    static func join(_ base: String, _ addition: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? addition + "\n" : trimmed + "\n\n" + addition + "\n"
    }

    /// Trims and unwraps a reply the model fenced as a whole.
    static func clean(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case same, added, removed }
    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line diff by longest common subsequence, for showing proposals.
public enum LineDiff {
    public static func compute(_ a: String, _ b: String) -> [DiffLine] {
        let x = a.components(separatedBy: "\n")
        let y = b.components(separatedBy: "\n")
        guard x.count * y.count <= 4_000_000 else {
            return x.map { DiffLine(.removed, $0) } + y.map { DiffLine(.added, $0) }
        }
        var lcs = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < x.count, j < y.count {
            if x[i] == y[j] {
                out.append(DiffLine(.same, x[i])); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                out.append(DiffLine(.removed, x[i])); i += 1
            } else {
                out.append(DiffLine(.added, y[j])); j += 1
            }
        }
        out += x[i...].map { DiffLine(.removed, $0) }
        out += y[j...].map { DiffLine(.added, $0) }
        return out
    }
}
