# Agent Quickstart

Read this first. It takes five minutes and gets you productive in this repo. Then read [`AGENTS.md`](../AGENTS.md) (the rules) and [`Vision.md`](Vision.md) (the why).

## Context in 30 seconds

- **What:** Context is a minimalist, Mac-native, AI-first home for notes and memory, part of the Constellation Project with Crew and Cue.
- **Primary surface:** a ⌥A hotkey overlay with pads. **Scratch** is your heads-up pad. **Clipboard** is editable clipboard history. **Context pads** hold one project's live context each.
- **Secondary surface:** a minimal Bear-style Library.
- **Storage:** Context always owns an Obsidian-compliant **base vault** for its own data. Anytype (first) and Obsidian (second) attach as **linked vaults** through connectors.
- **The point:** projects are curated context packs that get injected into AI harnesses such as Claude Code. In the MVP, copy-as-context and a kept-current assembled file (`~/Context/.context/projects/<name>.md`) are real. Harness connectors and router sync are stubs behind interfaces.
- **AI:** `gpt-6.1-terra` through the CXN router, an OpenAI-compatible endpoint at `https://infer.cxn.sh/v1`. `constellation/auto` is deprecated.
- **The rules:**
  - Less is more.
  - Markdown files are the truth.
  - Instant.
  - AI edits the page.
  - Humans and agents share the same operations.

## Where things stand

The MVP in [Vision.md § MVP](Vision.md#mvp) is built. All eight steps are recorded in [`Plans/active/MVP.md`](../Plans/active/MVP.md), with commits and anything still unproven. Most features are **Partial**: tests pass, but the installed app hasn't been exercised by hand. The manual-check list is at the end of that plan, and the per-feature status is in `README.md` § MVP status.

The Antinote-parity era is over. The first-line modes (`math`, `list`, `timer`, …), OCR, The Void, and `::` commands still work in Scratch, but they get no new investment. Expect a "less is more" trim (Vision § Open questions).

## Build, test, run

Use the selected Xcode toolchain (`xcode-select -p`, currently Xcode 26.6). On this machine the Command Line Tools have no Swift Testing module, so do **not** set `DEVELOPER_DIR` to the Command Line Tools before running `swift test`.

```bash
swift build
swift test                                   # all suites; uses temp stores, never touches real notes
CONTEXT_REBUILD=1 ./Scripts/run-app.sh       # package, codesign, install /Applications/Context.app, launch
```

`run-app.sh` stamps `Contents/Resources/ContextRevision` with `git rev-parse --short HEAD`. If the stamp does not match HEAD, the installed app is stale.

## Repo map

| Path | Owns |
| --- | --- |
| `Sources/ContextDomain` | Value types and pure logic: `Note`, `Pad`, `ClipboardPolicy`, paste normalizing, modes, checklist, search, slash commands, URL scheme, settings. No AppKit/SwiftUI. |
| `Sources/ContextVault` | `MarkdownDocument` (lossless frontmatter), `MarkdownBlocks`, `BaseVault` layout, `VaultConnector` + `ObsidianConnector` + `AnytypeConnector`/`AnytypeClient`, the linked-vault registry, and `SecretStore` (Keychain) |
| `Sources/ContextStore` | `NoteStore` (one pad's files, trash, and index), `Workspace` + `ContextCommand` (**the single mutation path**), the project model (`ProjectFiles`, `project.json`), and the `notes.json` migration |
| `Sources/ContextHarness` | `ContextAssembler`, `ContextDelivery` (kept-current file and delivery log), and the `HarnessConnector`/`RouterSync` interfaces with stubs |
| `Sources/ContextAI` | OpenAI-compatible `ModelClient`, `AIActions` → `Proposal`, `LineDiff`, and `OpencodeConfig` |
| `Sources/ContextMath` | `math`/`sum`/`avg` evaluation, units, currency rates |
| `Sources/ContextExport` | Export (txt/md/pdf) and handoff to Notes/Obsidian/Bear |
| `Apps/Context` | App composition root: `ContextWindowController` (overlay, pads, menu bar), `ContextEditorView`, `ProjectActions`, `AIFlow`, `Library`, `ClipboardWatcher`, Settings (`LinkedVaultsSettings`, `AISettings`), and the other windows |
| `Tests/*` | Swift Testing suites, including the connector conformance suite (`Tests/ContextVaultTests/ConnectorConformance.swift`) |
| `Scripts/` | `package-app.sh` and `run-app.sh` |
| `Docs/` | Vision, design guide, ADRs, and this file |
| `Plans/active/` | Implementation plans and the MVP log |

Not built yet: `ContextAutomation` (the `contextctl` CLI and MCP server, mirroring Cue's `CaptureAutomation`).

## Where things live

- **Content:** the base vault, `~/Context` by default, contains:
  - `Scratch/` and `Clipboard/`;
  - `Projects/<name>/` with `context.md`, `docs/`, and `project.json`;
  - `.trash/`, Obsidian's own trash name, with per-pad subfolders;
  - `.context/`, which is derived and safe to delete: the indexes, `projects/<name>.md` (the assembled context), and `deliveries.jsonl`.
- **App data:** `~/Library/Application Support/ConstellationContext/` holds `settings.json`, `vaults.json` (linked vaults), `Extensions/`, the currency cache, and `notes.json.migrated-*` (the pre-vault backup).
- **Secrets:** the Keychain, service `app.constellation.Context`, with accounts `anytype.apiKey` and `ai.apiKey`.
- **Bundle and scheme:** bundle id `app.constellation.Context`; URL scheme `context://` (`open`, `new`, `search`, `append`).
- **Global hotkey:** ⌥A. Region OCR: ⌥⇧S.
- **Model config reference:** `~/.config/opencode/opencode.json`, the `cxn-router` provider. Settings → AI can import its key into the Keychain. Never copy the key into the repo, logs, or plain-text settings.
- **Live AI test:** `CONTEXT_LIVE_AI_KEY=… swift test --filter LiveModelTests`. It is skipped without the variable.

## The Constellation family

Context should look, build, and behave like its siblings. When unsure how to do something, check how they do it.

| | Crew | Cue |
| --- | --- | --- |
| Path | `~/Projects/Crew` | `~/Projects/cue` |
| Agent contract | `AGENTS.md` | `AGENTS.md` |
| Look and feel | `Docs/Design-System.md` | `Docs/Design-Guide.md` §16 (visual system) |
| One mutation path | `CrewCommand` → `CrewEngine` | CommandCore (`CaptureCommands`) |
| Model client | `Sources/CrewConstellation` (its default endpoint and model are outdated) | — |
| ADRs | `Docs/ADR/` | `Docs/ADR/` |

Shared conventions:

- Swift 6 with strict concurrency, macOS 15+.
- SwiftPM is the module source of truth; XcodeGen generates an `.xcodeproj` only when one is needed.
- Swift Testing.
- `Domain` modules stay free of UI imports.
- No production dependency without an ADR.
- A `run-app.sh` close-out with a revision stamp.

The Constellation router lives at `~/Projects/constellation-workspace/constellation-router`.

The apps share no Swift package yet. Do not create one without an ADR.

## Gotchas

- **Global hotkeys and input-method candidate windows** cannot be tested automatically. They need a manual pass in the installed app.
- **Tests must never touch the user's real notes, vaults, Anytype space, or Keychain.**
  - Use `tempVault()` and `Workspace` on temp folders.
  - Use `FakeAnytype` for Anytype.
  - Use `MemorySecretStore` for secrets.
  - Use `FakeModel` for AI.
- **A new vault connector must pass `checkConnectorConformance`** before it ships.
- **Screenshots of the app need Screen Recording permission** for the terminal. Without it, visual checks are manual.
- **Status claims stay honest.** Mark a feature "Shipped" only after you verify it in the installed app. Otherwise it is "Partial".

## Where to start

1. Read the open items in `Plans/active/MVP.md`, starting with the manual-check list. Fix what fails there before building anything new.
2. Then take the next work from [Vision.md § MVP](Vision.md#mvp) "Later". The likely order:
   - a real Claude Code harness connector;
   - the `contextctl` CLI and MCP server;
   - the "less is more" trim of legacy modes.
3. Open a plan in `Plans/active/` for anything that crosses modules. Add an ADR for architectural decisions.
