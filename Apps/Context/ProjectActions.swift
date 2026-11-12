import AppKit
import ContextDomain
import ContextHarness
import ContextStore
import ContextVault

/// What the overlay shows about the current project.
struct ProjectInfo: Equatable {
    var name: String
    var documents: [String]
    var references: [ProjectReference]
    var harnesses: [HarnessKind]
    var routerSync: Bool
    var outputPath: String
}

/// Assembles project context and keeps each project's context file
/// current. Connectors come from the linked-vault registry.
@MainActor
final class ProjectContextService {
    private var pending: [String: Task<Void, Never>] = [:]

    func delivery(for workspace: Workspace) -> ContextDelivery {
        ContextDelivery(log: DeliveryLog(fileURL: workspace.vault.state.appendingPathComponent("deliveries.jsonl")))
    }

    func connectors() -> [String: any VaultConnector] {
        let secrets = KeychainSecretStore()
        var out: [String: any VaultConnector] = [:]
        for vault in LinkedVaultRegistry.standard?.load() ?? [] {
            if let c = Connectors.make(vault, secrets: secrets) { out[vault.id] = c }
        }
        return out
    }

    func assemble(_ project: ProjectFiles) async -> AssembledContext {
        await ContextAssembler().assemble(project, connectors: connectors())
    }

    /// Rewrites the context file shortly after changes settle.
    func refreshSoon(_ project: ProjectFiles, workspace: Workspace) {
        pending[project.name]?.cancel()
        pending[project.name] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            let context = await self.assemble(project)
            _ = try? self.delivery(for: workspace).writeFile(context, for: project)
        }
    }
}

extension ContextWindowController {
    var projectName: String? {
        if case .project(let name) = pad { return name }
        return nil
    }

    var cachedProjectInfo: ProjectInfo? {
        if let cache = projectInfoCache, cache.pad == pad { return cache.info }
        let info = projectInfo
        projectInfoCache = (pad, info)
        return info
    }

    /// Re-reads project info and redraws after a project changes.
    func projectChanged() {
        projectInfoCache = nil
        refreshProjectFile()
        render(preservingFocus: true)
    }

    var projectInfo: ProjectInfo? {
        guard let name = projectName else { return nil }
        let p = workspace.project(name)
        let m = p.manifest()
        return ProjectInfo(
            name: name,
            documents: p.documents().map(\.lastPathComponent),
            references: m.references,
            harnesses: m.harnesses,
            routerSync: m.routerSync,
            outputPath: p.output.path
        )
    }

    func refreshProjectFile() {
        guard let name = projectName else { return }
        projects.refreshSoon(workspace.project(name), workspace: workspace)
    }

    func copyProjectContext() {
        guard let name = projectName else { return }
        flushNow()
        let project = workspace.project(name)
        Task { @MainActor in
            let context = await projects.assemble(project)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(context.text, forType: .string)
            projects.delivery(for: workspace).recordClipboard(context)
            if !context.warnings.isEmpty {
                alert("Copied, with notes:\n\n" + context.warnings.joined(separator: "\n"))
            }
        }
    }

    /// `@path` line for a CLAUDE.md or AGENTS.md that imports the file.
    func copyImportLine() {
        guard let info = projectInfo else { return }
        refreshProjectFile()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("@\(info.outputPath)", forType: .string)
    }

    func revealProjectFile() {
        guard let name = projectName else { return }
        let project = workspace.project(name)
        Task { @MainActor in
            let context = await projects.assemble(project)
            _ = try? projects.delivery(for: workspace).writeFile(context, for: project)
            NSWorkspace.shared.activateFileViewerSelecting([project.output])
        }
    }

    /// A file inside a linked Obsidian vault is attached by reference
    /// (read fresh each time); anything else is copied into `docs/`.
    func addProjectDocument() {
        guard let name = projectName else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Add documents to \(name)"
        guard panel.runModal() == .OK else { return }
        let linked = (LinkedVaultRegistry.standard?.load() ?? []).filter { $0.kind == .obsidian }
        for url in panel.urls {
            if let vault = linked.first(where: { v in v.path.map { url.standardizedFileURL.path.hasPrefix($0 + "/") } ?? false }),
               let root = vault.path, url.pathExtension.lowercased() == "md"
            {
                let rel = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
                apply(.attachReference(project: name, ProjectReference(
                    ref: VaultNoteRef(vaultID: vault.id, noteID: rel),
                    title: url.deletingPathExtension().lastPathComponent
                )))
            } else {
                apply(.addDocument(project: name, file: url))
            }
        }
        projectChanged()
    }

    func removeProjectDocument(_ fileName: String) {
        guard let name = projectName else { return }
        apply(.removeDocument(project: name, fileName: fileName))
        projectChanged()
    }

    func detachProjectReference(_ ref: VaultNoteRef) {
        guard let name = projectName else { return }
        apply(.detachReference(project: name, ref))
        projectChanged()
    }

    func toggleHarness(_ kind: HarnessKind) {
        guard let info = projectInfo else { return }
        apply(.setHarness(project: info.name, kind, enabled: !info.harnesses.contains(kind)))
        projectChanged()
    }

    func toggleRouterSync() {
        guard let info = projectInfo else { return }
        apply(.setRouterSync(project: info.name, enabled: !info.routerSync))
        projectChanged()
    }

    /// Sends to every bound harness and the router, then says plainly
    /// what happened (MVP connectors are stubs and say so).
    func deliverNow() {
        guard let name = projectName else { return }
        flushNow()
        let project = workspace.project(name)
        Task { @MainActor in
            let context = await projects.assemble(project)
            let delivery = projects.delivery(for: workspace)
            _ = try? delivery.writeFile(context, for: project)
            let results = await delivery.deliverBound(context, manifest: project.manifest())
            var lines = ["Context file: up to date."]
            for (target, error) in results {
                lines.append("\(target.displayName): \(error?.message ?? "delivered.")")
            }
            if results.isEmpty { lines.append("No tools are bound. Turn one on under Deliver To.") }
            alert(lines.joined(separator: "\n"))
        }
    }

    /// Appends the current Scratch or Clipboard note to a project's
    /// live context.
    func sendToProject(_ name: String) {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        flushNow()
        let store = workspace.store(for: .project(name))
        let contextID = store.liveNotes.first?.id ?? store.create().id
        if apply(.append(.project(name), id: contextID, text: "\n" + text)) == nil {
            apply(.setText(.project(name), id: contextID, text: text))
        }
        projects.refreshSoon(workspace.project(name), workspace: workspace)
    }
}
