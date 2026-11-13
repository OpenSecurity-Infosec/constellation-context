import Foundation
import Testing
import ContextAutomation
import ContextStore
import ContextVault

@Test func automationUsesSharedProjectOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let api = Automation(vault: BaseVault(root: root))
    try api.workspace.apply(.createProject(name: "Example"))
    #expect(try await api.execute("list_projects", arguments: [:]) == "[\"Example\"]")
    let file = root.appendingPathComponent("source.md")
    let original = "---\nunknown: retained\n---\n[[link]] ![[image]]\n"
    try original.write(to: file, atomically: true, encoding: .utf8)
    _ = try await api.execute("add_document", arguments: ["project": "Example", "file": file.path])
    #expect(try String(contentsOf: api.workspace.project("Example").docs.appendingPathComponent("source.md"), encoding: .utf8) == original)
    #expect(try await api.execute("print_context", arguments: ["project": "Example"]).contains("[[link]] ![[image]]"))
    await #expect(throws: (any Error).self) { try await api.execute("print_context", arguments: ["project": "../escape"]) }
    let reply = await MCP.respond(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}"#.utf8), automation: api)
    #expect(reply != nil)
    let notification = await MCP.respond(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), automation: api)
    #expect(notification == nil)
}

@Test func mcpProtocolAndErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let api = Automation(vault: BaseVault(root: root))
    for (request, expected) in [
        (#"{"jsonrpc":"2.0","id":2,"method":"initialize"}"#, "protocolVersion"),
        (#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#, "add_document"),
        (#"{"jsonrpc":"2.0","id":4,"method":"unknown"}"#, "-32601"),
        (#"{"jsonrpc":"2.0","id":5,"method":"tools/call"}"#, "-32602"),
        (#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"print_context","arguments":{"project":"missing"}}}"#, "isError")
    ] {
        let reply = await MCP.respond(Data(request.utf8), automation: api)
        #expect(String(decoding: try #require(reply), as: UTF8.self).contains(expected))
    }
}
