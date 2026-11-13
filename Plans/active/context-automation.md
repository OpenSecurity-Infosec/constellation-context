# Minimal project automation

Vision principle 5 and the Later automation roadmap justify a local CLI and
stdio MCP server sharing three operations: list projects, print assembled
context, and add a document. ContextAutomation depends on Store, Vault and
Harness; additions call Workspace.apply and assembly uses ContextAssembler.
No UI, network listener, settings, secrets or dependencies are added.

Use `swift run contextctl --vault /absolute/base/vault list-projects`,
`print-context PROJECT`, `add-document PROJECT FILE`, or `mcp` for newline JSON-RPC
stdio. The default vault is ~/Context; pass --vault for a relocated base vault.
Linked connectors are not loaded in this slice: printing fails explicitly when
assembly reports missing references or other warnings. No partial context is
silently delivered. MCP clients launch the executable with `mcp` as argument.

Owner checks: use a disposable project to compare CLI context with app copy,
add a document while the app is open and verify refresh/restart, and connect an
MCP client to list tools, list projects, read context and add a temporary file.
