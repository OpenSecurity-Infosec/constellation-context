# MVP execution plan

Source: [Docs/Vision.md § MVP](../../Docs/Vision.md#mvp). This file is the loop's memory. Update it at the end of every iteration: tick items, note decisions, and record anything left unproven.

Each step ships tests, passes `swift test`, ends with `CONTEXT_REBUILD=1 ./Scripts/run-app.sh` and a revision-stamp check, and is committed locally (never pushed).

## Steps

- [x] **1. Base vault**
  - New `ContextVault` module with three pieces:
    - `MarkdownDocument`: lossless frontmatter split, read, and edit;
    - `BaseVault` layout;
    - file naming.
  - `NoteStore` rewritten over files:
    - Scratch notes are `.md` files in `<base>/Scratch/`;
    - The Void is `<base>/.trash/`;
    - derived ids and trash state live in `<base>/.context/index.json`;
    - external edits reload on show, with a conflict copy when needed.
  - One-time `notes.json` migration that keeps ids and dates. The old file is renamed, never deleted.
  - CloudKit/KV sync removed (ADR-0001: file sync replaces it).
  - Settings: base-vault location with Reveal and Change.
- [x] **2. Connector interface and Anytype connector**
  - `VaultConnector` protocol and a shared conformance suite.
  - An Anytype local-API client behind a transport protocol, so tests use a fake.
  - Object to Markdown mapping: body, plus relations as frontmatter.
  - Keychain credential storage.
  - Link Anytype in Settings.
- [ ] **3. Obsidian connector**
  - A folder linked in place, passing conformance.
  - `.obsidian/` is never touched.
  - Link and unlink in Settings.
- [ ] **4. Pads and command path**
  - A `ContextCommand` enum and one apply path, used by the UI, and later by AI and CLI.
  - Scratch, Clipboard (history captured as editable files in `<base>/Clipboard/`), and project Context pads.
  - A pad switcher in the overlay.
  - Paste keeps Markdown.
- [ ] **5. Projects and injection**
  - `Projects/<name>/context.md` and `docs/`; attaching linked-vault notes by reference.
  - Copy-as-context, with `context.md` kept current.
  - `HarnessConnector` and `RouterSync` interfaces, each with a stub.
  - A delivery record.
- [ ] **6. AI actions**
  - `ContextAI` OpenAI-compatible client: CXN router, `gpt-6.1-terra`, key in the Keychain.
  - Actions: summarize, tidy, extract-to-project, and compact.
  - Each result is shown as a proposal, accept or reject, and applies as one undoable edit.
- [ ] **7. Library window**
  - Sidebar: base vault, linked vaults, projects.
  - Note list and search across sources.
  - Canvas editor with images inline.
- [ ] **8. Close-out**
  - README status, written honestly.
  - Quickstart "today" table updated.
  - Manual-check list for the user.

## Decisions made during the loop

- **Base vault default is `~/Context`, changeable in Settings.** `~/Documents` is TCC-protected, and an ad-hoc-signed dev build would re-prompt for access after every rebuild.
- **Scratch is a folder of notes, not one `Scratch.md`.** That keeps today's swipe-between-notes and ⌘N behavior.
- **Scratch notes are timestamp-named** (`2026-11-12 093142.md`), are created lazily on first text, and carry no frontmatter. The first line is the title. Files are never renamed while you type.
- **Note ids are not stored in note files.** They live in the rebuildable index, and losing the index only resets session identity.

## Log

(Each iteration appends: date, step, result, and anything unproven.)

- **2026-11-12, step 1, done** (`e5cbadd`).
  - 193 tests pass.
  - The installed app migrated the real `notes.json` (2 live notes) into `~/Context/Scratch/`. Ids and dates were kept, and the backup is `notes.json.migrated-2026-11-12-110125`.
  - Unproven: the overlay was not visually inspected this iteration, and Settings → Base vault → Change… was not clicked through in the installed app.
  - Known leftover: `PlainText.sanitize` still strips Markdown bullets and quotes on paste. Step 4 changes paste to keep Markdown.
- **2026-11-12, step 2, done** (`17f6db0`).
  - 205 tests pass.
  - The Anytype client follows the official v1 OpenAPI spec (`2025-11-08`).
  - Verified only against an in-memory fake of that API. Anytype was not running and linking needs the user to read a 4-digit code.
  - Unproven, needs a manual pass:
    - Settings → Link Anytype… against the real app;
    - the real markdown round-trip fidelity of Anytype's `markdown` field;
    - whether `last_modified_date` is present on list results.
  - Limits by design: edits that Anytype can't hold are refused with a message. That covers unknown keys, options not in Anytype, and non-numeric numbers. Clearing a number or date is refused.
