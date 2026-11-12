# ADR-0002: Base vault and linked vaults

Status: accepted
Date: 2026-11-12

## Context

Context must work with notes the user already keeps in Anytype and Obsidian ([Vision](../Vision.md)). It also needs a place for its own data: pads, clipboard history, and projects. Writing that data into a user's existing vault would clutter it, and would tie Context's code to one app's conventions.

## Decision

- **Context always owns one base vault.** It holds pads, clipboard entries, projects, and anything else Context creates. The base vault is Obsidian-compliant: a plain folder of Markdown files with YAML frontmatter, `[[wikilinks]]`, `![[embeds]]`, and attachments as ordinary files, so it opens in Obsidian as a vault with no conversion. Context does not create a `.obsidian/` folder in it; Obsidian does that when the user opens the folder.
- **External note stores are linked vaults.** They are reached through a `VaultConnector` interface: list, search, read, write, and watch for changes, with notes exchanged as Markdown plus frontmatter. Context code depends on the interface, not on any one app.
- **Linked vaults are sources.** The user can browse, search, and edit their notes, and attach them to projects. Context stores those attachments as references in the base vault. Context never adds its own folders or files to a linked vault.
- **Connector order:** Anytype first, through its local API and MCP server, mapping object relations to frontmatter. Obsidian second, as a folder linked in place. MCP-backed vaults later.
- The lossless-write rules in ADR-0001 apply to every connector.

## Consequences

- Project documents can live in two places, so project rendering must resolve references across connectors and handle a missing or unlinked source gracefully.
- Anytype is not file-based, so "lossless" there means round-tripping body and relations through its API. That needs its own fixture tests.
- Search spans the base vault plus linked vaults, so a derived index (ADR-0001) must track the source of each entry.

## Alternatives considered

- **Use a linked Obsidian vault as Context's home, with a `Context/` folder inside it.** Rejected: it writes into the user's vault and couples Context to Obsidian.
- **Treat Obsidian as built-in rather than a connector.** Rejected: Anytype comes first, and every source should go through one interface.

## Verification

- A connector conformance test suite that every connector must pass: round-trip, unknown-key preservation, and change detection.
- A test that writing to a linked Obsidian fixture vault never creates files outside the notes being edited and never touches `.obsidian/`.
- A test that the base vault created on first run opens as a valid Obsidian vault structure (Markdown and attachments only).
