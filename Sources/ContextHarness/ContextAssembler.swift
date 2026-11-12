import ContextStore
import ContextVault
import Foundation

/// A project's context, ready to hand to a harness.
public struct AssembledContext: Equatable, Sendable {
    public var project: String
    public var text: String
    /// Titles of what went in, in order.
    public var sources: [String]
    /// Things that could not be included, in words a person can act on.
    public var warnings: [String]
    public var truncated: Bool

    public init(project: String, text: String, sources: [String], warnings: [String], truncated: Bool) {
        self.project = project
        self.text = text
        self.sources = sources
        self.warnings = warnings
        self.truncated = truncated
    }
}

/// Builds one Markdown prompt from a project's live context, its `docs/`
/// files, and its linked-vault references. Frontmatter is dropped (it is
/// metadata, not context); bodies are included verbatim.
public struct ContextAssembler: Sendable {
    /// Upper bound on assembled characters. The live context always fits
    /// first; documents fill what is left in order.
    public var budget: Int

    public init(budget: Int = 60_000) {
        self.budget = budget
    }

    static let textExtensions: Set<String> = ["md", "markdown", "txt"]

    public func assemble(
        _ project: ProjectFiles,
        connectors: [String: any VaultConnector] = [:]
    ) async -> AssembledContext {
        var sources: [String] = []
        var warnings: [String] = []
        var sections: [(title: String, body: String)] = []

        let live = (try? String(contentsOf: project.contextFile, encoding: .utf8)).map {
            MarkdownDocument(parsing: $0).body.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        if live.isEmpty { warnings.append("The live context is empty.") }

        for url in project.documents() {
            let title = url.deletingPathExtension().lastPathComponent
            guard Self.textExtensions.contains(url.pathExtension.lowercased()) else {
                sections.append((title, "_Attached file: \(url.lastPathComponent) (not text, not included)._"))
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                warnings.append("Couldn't read \(url.lastPathComponent).")
                continue
            }
            sections.append((title, MarkdownDocument(parsing: text).body))
        }

        for reference in project.manifest().references {
            guard let connector = connectors[reference.ref.vaultID] else {
                warnings.append("“\(reference.title)” is in a vault that isn't linked anymore.")
                continue
            }
            do {
                let note = try await connector.read(reference.ref)
                sections.append(("\(note.title) (\(connector.displayName))", note.document.body))
            } catch let error as VaultError {
                warnings.append("“\(reference.title)”: \(error.message)")
            } catch {
                warnings.append("“\(reference.title)” couldn't be read.")
            }
        }

        var text = "# \(project.name)\n\n" + (live.isEmpty ? "" : live + "\n")
        sources.append("Live context")
        var truncated = false
        for section in sections {
            let block = "\n---\n\n## \(section.title)\n\n" + section.body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            if text.count + block.count > budget {
                truncated = true
                warnings.append("Left out “\(section.title)” and anything after it to stay under \(budget) characters.")
                break
            }
            text += block
            sources.append(section.title)
        }
        return AssembledContext(project: project.name, text: text, sources: sources, warnings: warnings, truncated: truncated)
    }
}
