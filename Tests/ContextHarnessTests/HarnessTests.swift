import ContextDomain
import ContextHarness
import ContextStore
import ContextVault
import Foundation
import Testing

func makeWorkspace() -> Workspace {
    Workspace(vault: BaseVault(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("ctx-harness-\(UUID().uuidString)", isDirectory: true)))
}

/// A linked Obsidian vault in a temp folder with one note.
func linkedVault() throws -> ObsidianConnector {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-linked-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "---\nstatus: draft\n---\nThe API uses bearer tokens.\n".write(
        to: root.appendingPathComponent("Auth.md"), atomically: true, encoding: .utf8
    )
    return ObsidianConnector(id: "obs", displayName: "Notes", root: root)
}

@Suite struct ProjectCommandTests {
    @Test func documentsAndReferencesAreProjectData() throws {
        let ws = makeWorkspace()
        try ws.apply(.createProject(name: "Alpha"))
        let p = ws.project("Alpha")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-src-\(UUID().uuidString).md")
        try "spec".write(to: src, atomically: true, encoding: .utf8)
        try ws.apply(.addDocument(project: "Alpha", file: src))
        try ws.apply(.addDocument(project: "Alpha", file: src))
        #expect(p.documents().map(\.lastPathComponent).sorted() == [src.lastPathComponent, src.deletingPathExtension().lastPathComponent + " 2.md"].sorted())
        #expect(FileManager.default.fileExists(atPath: src.path), "the original is copied, not moved")

        let ref = ProjectReference(ref: VaultNoteRef(vaultID: "obs", noteID: "Auth.md"), title: "Auth")
        try ws.apply(.attachReference(project: "Alpha", ref))
        try ws.apply(.attachReference(project: "Alpha", ref))
        try ws.apply(.setHarness(project: "Alpha", .claudeCode, enabled: true))
        try ws.apply(.setRouterSync(project: "Alpha", enabled: true))
        var m = p.manifest()
        #expect(m.references.map(\.title) == ["Auth"], "attaching twice keeps one")
        #expect(m.harnesses == [.claudeCode])
        #expect(m.routerSync)

        try ws.apply(.detachReference(project: "Alpha", ref.ref))
        try ws.apply(.setHarness(project: "Alpha", .claudeCode, enabled: false))
        try ws.apply(.removeDocument(project: "Alpha", fileName: src.lastPathComponent))
        m = p.manifest()
        #expect(m.references.isEmpty && m.harnesses.isEmpty)
        #expect(p.documents().count == 1)
        #expect(throws: WorkspaceError.noSuchDocument) { try ws.apply(.removeDocument(project: "Alpha", fileName: "../context.md")) }
        #expect(throws: WorkspaceError.noSuchProject) { try ws.apply(.setRouterSync(project: "Nope", enabled: true)) }
    }
}

@Suite struct AssemblerTests {
    @Test func assemblesLiveContextDocsAndReferencesInOrder() async throws {
        let ws = makeWorkspace()
        try ws.apply(.createProject(name: "Alpha"))
        let p = ws.project("Alpha")
        try "---\nproject: alpha\n---\nUse Swift 6.\n".write(to: p.contextFile, atomically: true, encoding: .utf8)
        try "---\nkind: spec\n---\nThe spec body.\n".write(to: p.docs.appendingPathComponent("Spec.md"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50]).write(to: p.docs.appendingPathComponent("diagram.png"))
        let linked = try linkedVault()
        try ws.apply(.attachReference(project: "Alpha", ProjectReference(ref: VaultNoteRef(vaultID: "obs", noteID: "Auth.md"), title: "Auth")))

        let out = await ContextAssembler().assemble(p, connectors: ["obs": linked])
        #expect(out.text.hasPrefix("# Alpha\n\nUse Swift 6.\n"))
        #expect(!out.text.contains("project: alpha"), "frontmatter is metadata, not context")
        #expect(!out.text.contains("kind: spec"))
        #expect(out.text.contains("## Spec\n\nThe spec body."))
        #expect(out.text.contains("_Attached file: diagram.png (not text, not included)._"))
        #expect(out.text.contains("## Auth (Notes)\n\nThe API uses bearer tokens."))
        #expect(out.sources == ["Live context", "diagram", "Spec", "Auth (Notes)"])
        #expect(out.warnings.isEmpty)
    }

    @Test func missingSourcesBecomeWarningsNotFailures() async throws {
        let ws = makeWorkspace()
        try ws.apply(.createProject(name: "Beta"))
        let p = ws.project("Beta")
        try "".write(to: p.contextFile, atomically: true, encoding: .utf8)
        try ws.apply(.attachReference(project: "Beta", ProjectReference(ref: VaultNoteRef(vaultID: "gone", noteID: "x.md"), title: "Old")))
        try ws.apply(.attachReference(project: "Beta", ProjectReference(ref: VaultNoteRef(vaultID: "obs", noteID: "Missing.md"), title: "Missing")))
        let out = await ContextAssembler().assemble(p, connectors: ["obs": try linkedVault()])
        #expect(out.text == "# Beta\n\n")
        #expect(out.warnings.count == 3)
        #expect(out.warnings.contains { $0.contains("isn't linked") })
        #expect(out.warnings.contains { $0.contains("no longer exists") })
    }

    @Test func budgetKeepsLiveContextAndDropsTrailingDocs() async throws {
        let ws = makeWorkspace()
        try ws.apply(.createProject(name: "Gamma"))
        let p = ws.project("Gamma")
        try "Keep me.\n".write(to: p.contextFile, atomically: true, encoding: .utf8)
        try String(repeating: "a", count: 300).write(to: p.docs.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 300).write(to: p.docs.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        let out = await ContextAssembler(budget: 400).assemble(p)
        #expect(out.text.contains("Keep me."))
        #expect(out.text.contains("## A"))
        #expect(!out.text.contains("## B"))
        #expect(out.truncated)
    }
}

@Suite struct DeliveryTests {
    func context(_ text: String = "# Alpha\n\nctx\n") -> AssembledContext {
        AssembledContext(project: "Alpha", text: text, sources: [], warnings: [], truncated: false)
    }

    @Test func fileIsWrittenOnlyWhenItChanges() throws {
        let ws = makeWorkspace()
        try ws.apply(.createProject(name: "Alpha"))
        let p = ws.project("Alpha")
        let delivery = ContextDelivery(log: DeliveryLog(fileURL: ws.vault.state.appendingPathComponent("deliveries.jsonl")))
        #expect(try delivery.writeFile(context(), for: p))
        #expect(try String(contentsOf: p.output, encoding: .utf8) == "# Alpha\n\nctx\n")
        #expect(try !delivery.writeFile(context(), for: p), "same text, no rewrite")
        #expect(try delivery.writeFile(context("# Alpha\n\nnew\n"), for: p))
        #expect(p.output.path.contains("/.context/projects/Alpha.md"))
    }

    @Test func stubsReportNotConnectedAndEverythingIsLoggedWithoutText() async throws {
        let ws = makeWorkspace()
        let log = DeliveryLog(fileURL: ws.vault.state.appendingPathComponent("deliveries.jsonl"))
        let delivery = ContextDelivery(log: log)
        let results = await delivery.deliverBound(
            context("# Alpha\n\nsecret plan\n"),
            manifest: ProjectManifest(harnesses: [.claudeCode, .opencode], routerSync: true)
        )
        #expect(results.map(\.0) == [.harness(.claudeCode), .harness(.opencode), .router])
        #expect(results.allSatisfy { if case .notConnected? = $0.1 { true } else { false } })
        delivery.recordClipboard(context())
        let records = log.records()
        #expect(records.count == 4)
        #expect(records.filter(\.ok).map(\.target) == [.clipboard])
        let raw = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(!raw.contains("secret plan"), "the log never holds context text")
    }

    @Test func aRealConnectorIsUsedWhenProvided() async {
        struct Recorder: HarnessConnector {
            let kind = HarnessKind.claudeCode
            func deliver(_ context: AssembledContext) async throws {}
        }
        let log = DeliveryLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ctx-log-\(UUID().uuidString).jsonl"))
        var delivery = ContextDelivery(log: log)
        delivery.harnesses[.claudeCode] = Recorder()
        let results = await delivery.deliverBound(context(), manifest: ProjectManifest(harnesses: [.claudeCode]))
        #expect(results.count == 1 && results[0].1 == nil)
        #expect(log.records().first?.ok == true)
    }
}
