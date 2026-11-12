# ADR-0001: Markdown files are the source of truth

Status: accepted
Date: 2026-11-12

## Context

Context stores every note in one `notes.json` under `~/Library/Application Support/ConstellationContext/`. The product direction ([Vision](../Vision.md)) requires three things:

- attaching to existing vaults (Obsidian, then others);
- other tools and agents reading the same notes;
- Context replacing Obsidian without locking content in.

A private JSON blob blocks all three.

## Decision

- All content lives in Markdown files with optional YAML frontmatter, inside a vault folder the user chooses. Content means notes, pads, project live context, and attached documents.
- Objects such as images and files are stored as files and referenced with standard Markdown or Obsidian embed syntax.
- Any index, cache, or search database is derived from the files and must be rebuildable by deleting it.
- Writes are lossless. Context preserves unknown frontmatter keys, Obsidian syntax, and files it does not understand. It never rewrites a file the user did not change. It never writes inside `.obsidian/`.
- App settings, secrets, and UI state are not content. They stay in Application Support or the Keychain.

## Consequences

- Context needs a one-time, lossless migration from `notes.json`.
- External edits must be detected and reloaded. The file can change under the editor.
- Some current behavior needs a file representation or a rethink, for example The Void trash and expiry, and CloudKit sync of a JSON payload.
- Vault sync becomes the user's file-sync tool's job until there is a reason to build our own.

## Alternatives considered

- **Keep JSON and export Markdown.** Rejected: it creates two sources of truth and cannot attach to an Obsidian vault.
- **A SQLite content store with a Markdown mirror.** Rejected for the same reason. A derived SQLite index is still allowed.

## Verification

- Round-trip tests over an Obsidian-style fixture vault show byte-identical output for unchanged notes, with frontmatter, wikilinks, and embeds preserved.
- A migration test shows `notes.json` becomes files with no lost text or timestamps.
- Tests use temporary vaults only.
