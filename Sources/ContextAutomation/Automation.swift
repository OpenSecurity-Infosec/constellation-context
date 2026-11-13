import Foundation
import ContextStore
import ContextVault
import ContextHarness

/// Shared operations for the command line and local stdio MCP transport.
public struct Automation: Sendable {
    public let workspace: Workspace
    public init(vault: BaseVault) { workspace = Workspace(vault: vault) }

    public func execute(_ name: String, arguments: [String: String]) async throws -> String {
        if name == "list_projects" {
            return String(decoding: try JSONSerialization.data(withJSONObject: workspace.projects), as: UTF8.self)
        }
        guard let project = arguments["project"], workspace.projects.contains(project),
              !project.contains("/"), !project.hasPrefix(".") else { throw WorkspaceError.noSuchProject }
        switch name {
        case "print_context":
            let context = await ContextAssembler().assemble(workspace.project(project))
            // Never silently return an incomplete context pack.
            guard context.warnings.isEmpty else { throw AutomationError.incompleteContext }
            return context.text
        case "add_document":
            guard let file = arguments["file"], file.hasPrefix("/"),
                  (try? URL(fileURLWithPath: file).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw AutomationError.invalidFile
            }
            try workspace.apply(.addDocument(project: project, file: URL(fileURLWithPath: file)))
            return "Document added."
        default: throw AutomationError.unknownOperation
        }
    }
}

public enum AutomationError: Error { case invalidFile, unknownOperation, incompleteContext }

public enum MCP {
    public static func respond(_ data: Data, automation: Automation) async -> Data? {
        func encode(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        guard let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
        guard let id = request["id"] else { return nil }
        func result(_ value: Any) -> Data? { encode(["jsonrpc": "2.0", "id": id, "result": value]) }
        switch method {
        case "initialize":
            return result(["protocolVersion": "2024-11-05", "capabilities": ["tools": [:]], "serverInfo": ["name": "contextctl", "version": "1.0"]])
        case "ping": return result([:])
        case "tools/list":
            let tools: [[String: Any]] = [
                tool("list_projects", properties: [:], required: []),
                tool("print_context", properties: ["project": ["type": "string"]], required: ["project"]),
                tool("add_document", properties: ["project": ["type": "string"], "file": ["type": "string", "description": "Absolute path to a local regular file to copy into the project"]], required: ["project", "file"])
            ]
            return result(["tools": tools])
        case "tools/call":
            guard let params = request["params"] as? [String: Any], let name = params["name"] as? String,
                  let args = params["arguments"] as? [String: String] else {
                return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Invalid parameters"]])
            }
            do { return result(["content": [["type": "text", "text": try await automation.execute(name, arguments: args)]]]) }
            catch { return result(["isError": true, "content": [["type": "text", "text": "Operation failed. Check the project, file, and linked references."]]]) }
        default: return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
        }
    }

    private static func tool(_ name: String, properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": name.replacingOccurrences(of: "_", with: " "),
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
         "annotations": ["readOnlyHint": name != "add_document", "destructiveHint": false, "openWorldHint": false]]
    }
}
