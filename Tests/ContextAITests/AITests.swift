@testable import ContextAI
import Foundation
import Testing

final class FakeModel: ModelTransport, @unchecked Sendable {
    var status = 200
    var reply: Any = "ok"
    private(set) var lastURL: URL?
    private(set) var lastHeaders: [String: String] = [:]
    private(set) var lastBody: [String: Any] = [:]

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, data: Data) {
        lastURL = url
        lastHeaders = headers
        lastBody = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let payload: [String: Any] = ["choices": [["message": ["role": "assistant", "content": reply]]]]
        return (status, try JSONSerialization.data(withJSONObject: payload))
    }

    var messages: [[String: String]] { lastBody["messages"] as? [[String: String]] ?? [] }
}

@Suite struct ModelClientTests {
    @Test func sendsAnOpenAICompatibleRequest() async throws {
        let fake = FakeModel()
        let client = ModelClient(apiKey: "k", transport: fake)
        #expect(try await client.complete(system: "sys", user: "hello") == "ok")
        #expect(fake.lastURL?.absoluteString == "https://infer.cxn.sh/v1/chat/completions")
        #expect(fake.lastHeaders["Authorization"] == "Bearer k")
        #expect(fake.lastBody["model"] as? String == "gpt-6.1-terra")
        #expect(fake.lastBody["stream"] as? Bool == false)
        #expect(fake.messages == [["role": "system", "content": "sys"], ["role": "user", "content": "hello"]])
    }

    @Test func mapsFailures() async {
        let fake = FakeModel()
        await #expect(throws: ModelError.missingKey) { try await ModelClient(apiKey: nil, transport: fake).complete(system: "", user: "") }
        fake.status = 401
        await #expect(throws: ModelError.unauthorized) { try await ModelClient(apiKey: "k", transport: fake).complete(system: "", user: "") }
        fake.status = 429
        await #expect(throws: ModelError.rateLimited) { try await ModelClient(apiKey: "k", transport: fake).complete(system: "", user: "") }
        fake.status = 502
        await #expect(throws: ModelError.self) { try await ModelClient(apiKey: "k", transport: fake).complete(system: "", user: "") }
    }

    @Test func readsTextPartsReplies() async throws {
        let fake = FakeModel()
        fake.reply = [["type": "text", "text": "a"], ["type": "text", "text": "b"]]
        #expect(try await ModelClient(apiKey: "k", transport: fake).complete(system: "", user: "") == "ab")
        #expect(throws: ModelError.self) { try ModelClient.text(from: Data("{}".utf8)) }
    }
}

@Suite struct AIActionTests {
    func actions(_ reply: String) -> (AIActions, FakeModel) {
        let fake = FakeModel()
        fake.reply = reply
        return (AIActions(client: ModelClient(apiKey: "k", transport: fake)), fake)
    }

    @Test func summarizeAppendsASummarySection() async throws {
        let (ai, fake) = actions("- shipped v1\n- next: docs")
        let p = try await ai.propose(.summarize, note: "Long note\nabout things\n")
        #expect(p.proposed == "Long note\nabout things\n\n## Summary\n\n- shipped v1\n- next: docs\n")
        #expect(p.original == "Long note\nabout things\n")
        #expect(fake.messages.last?["content"] == "Long note\nabout things\n")
    }

    @Test func tidyReplacesAndUnwrapsAFencedReply() async throws {
        let (ai, _) = actions("```markdown\n# Title\n\n- item\n```")
        let p = try await ai.propose(.tidy, note: "Title\n* item\n")
        #expect(p.proposed == "# Title\n\n- item\n")
    }

    @Test func extractAppendsToTheProjectContextAndSendsBoth() async throws {
        let (ai, fake) = actions("- Use Swift 6")
        let p = try await ai.propose(.extract(project: "Alpha"), note: "we decided Swift 6", projectContext: "# Alpha\n\nExisting.\n")
        #expect(p.original == "# Alpha\n\nExisting.\n")
        #expect(p.proposed == "# Alpha\n\nExisting.\n\n- Use Swift 6\n")
        let user = fake.messages.last?["content"] ?? ""
        #expect(user.contains("Existing.") && user.contains("we decided Swift 6"))
        #expect(fake.messages.first?["content"]?.contains("\"Alpha\"") == true)
    }

    @Test func emptyRepliesProposeNoChange() async throws {
        let (ai, _) = actions("   ")
        #expect(try await ai.propose(.extract(project: "A"), note: "n", projectContext: "ctx").isNoChange)
        #expect(try await ai.propose(.tidy, note: "n").isNoChange)
        #expect(try await ai.propose(.summarize, note: "n").isNoChange)
    }
}

@Suite struct LineDiffTests {
    @Test func marksAddedRemovedAndSame() {
        let d = LineDiff.compute("a\nb\nc", "a\nB\nc\nd")
        #expect(d == [DiffLine(.same, "a"), DiffLine(.removed, "b"), DiffLine(.added, "B"), DiffLine(.same, "c"), DiffLine(.added, "d")])
        #expect(LineDiff.compute("x", "x") == [DiffLine(.same, "x")])
    }
}

/// Talks to the real endpoint only when CONTEXT_LIVE_AI_KEY is set.
@Suite struct LiveModelTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONTEXT_LIVE_AI_KEY"] != nil))
    func realEndpointAnswers() async throws {
        let key = ProcessInfo.processInfo.environment["CONTEXT_LIVE_AI_KEY"]
        let reply = try await ModelClient(apiKey: key).complete(system: "Reply with the single word: pong", user: "ping")
        #expect(reply.lowercased().contains("pong"))
    }
}

@Suite struct OpencodeConfigTests {
    @Test func readsTheCXNRouterProvider() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-opencode-\(UUID().uuidString).json")
        try Data(#"{"providers":{"cxn-router":{"settings":{"baseURL":"https://infer.cxn.sh/v1","apiKey":"sk-test"}}}}"#.utf8).write(to: file)
        #expect(OpencodeConfig.provider(in: file) == .init(baseURL: "https://infer.cxn.sh/v1", apiKey: "sk-test"))
        #expect(OpencodeConfig.provider(named: "other", in: file) == nil)
        #expect(OpencodeConfig.provider(in: file.appendingPathExtension("missing")) == nil)
    }
}
