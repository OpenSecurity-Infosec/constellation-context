import Foundation
import ContextAutomation
import ContextVault

@main struct ContextCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var root = BaseVault.defaultRoot
        if args.first == "--vault", args.count >= 2 {
            root = URL(fileURLWithPath: args[1]); args.removeFirst(2)
        }
        let automation = Automation(vault: BaseVault(root: root))
        if args == ["mcp"] {
            while let line = readLine() {
                if let reply = await MCP.respond(Data(line.utf8), automation: automation) {
                    FileHandle.standardOutput.write(reply + Data([10]))
                }
            }
            return
        }
        do {
            let name: String
            var parameters: [String: String] = [:]
            switch args.first {
            case "list-projects" where args.count == 1: name = "list_projects"
            case "print-context" where args.count == 2:
                name = "print_context"; parameters["project"] = args[1]
            case "add-document" where args.count == 3:
                name = "add_document"; parameters = ["project": args[1], "file": URL(fileURLWithPath: args[2]).path]
            default: throw AutomationError.unknownOperation
            }
            print(try await automation.execute(name, arguments: parameters))
        } catch {
            FileHandle.standardError.write(Data("contextctl: operation failed. Usage: contextctl [--vault PATH] list-projects | print-context PROJECT | add-document PROJECT FILE | mcp\nContext printing requires all linked references to be available.\n".utf8))
            exit(1)
        }
    }
}
