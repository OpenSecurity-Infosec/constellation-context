# Agent Quickstart

Read this first. It takes five minutes and gets you productive in this repo. Then read [`AGENTS.md`](../AGENTS.md) (the rules) and [`Vision.md`](Vision.md) (the why).

## Context in 30 seconds

- **What:** Context is a minimalist, Mac-native, AI-first home for notes and memory, part of the Constellation Project with Crew and Cue.
- **Primary surface:** a ⌥A hotkey overlay with pads. **Scratch** is your heads-up pad. **Clipboard** is editable clipboard history. **Context pads** hold one project's live context each.
- **Secondary surface:** a minimal Bear-style Library.
- **Storage:** Context always owns an Obsidian-compliant **base vault** for its own data. Anytype (first) and Obsidian (second) attach as **linked vaults** through connectors.
- **The point:** projects are curated context packs that get injected into AI harnesses such as Claude Code. In the MVP, copy and a kept-current `context.md` are real. Harness connectors and router sync are stubs behind interfaces.
- **AI:** `gpt-6.1-terra` through the CXN router, an OpenAI-compatible endpoint at `https://infer.cxn.sh/v1`. `constellation/auto` is deprecated.
- **The rules:**
  - Less is more.
  - Markdown files are the truth.
  - Instant.
  - AI edits the page.
  - Humans and agents share the same operations.

## Today versus the direction

| Area | Today (in code) | Direction (Vision) |
| --- | --- | --- |
| Storage | One `notes.json` in Application Support | Base vault plus linked vaults ([ADR-0001](ADR/0001-markdown-files-are-the-source-of-truth.md), [ADR-0002](ADR/0002-base-vault-and-linked-vaults.md)) |
| Notes | Plain-text Antinote-style notes with first-line modes | Markdown canvases with embedded objects |
| Surfaces | Hotkey overlay, Void, search, timer, and settings windows | Quick overlay with pads, plus a Library window |
| AI | None | `gpt-6.1-terra` actions as undoable proposals |
| Harnesses | None | Projects → copy and `context.md` (real) → harness connectors and router sync (stubs) |
| Roadmap | Antinote parity polish | **Closed.** Build [Vision.md § MVP](Vision.md#mvp) in order |

Do not do Antinote parity work. The README parity table is a historical record.

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
| `Sources/ContextDomain` | Value types and pure logic: `Note`, modes, checklist, search, slash commands, URL scheme, settings, sync payloads. No AppKit/SwiftUI. |
| `Sources/ContextMath` | `math`/`sum`/`avg` evaluation, units, currency rates |
| `Sources/ContextStore` | `NoteStore`, today's JSON persistence with staged flushes |
| `Sources/ContextExport` | Export (txt/md/pdf) and handoff to Notes/Obsidian/Bear |
| `Apps/Context` | App composition root: `ContextWindowController` (overlay and menu bar), `ContextEditorView`, the other windows, hotkeys, `SyncManager` |
| `Tests/*` | Swift Testing suites |
| `Scripts/` | `package-app.sh` and `run-app.sh` |
| `Docs/` | Vision, design guide, ADRs, and this file |

Planned modules (create each through a plan in `Plans/active/`):

| Module | Owns | Mirrors |
| --- | --- | --- |
| `ContextVault` | Markdown and frontmatter, the base vault, `VaultConnector`, and the Anytype and Obsidian connectors | — |
| `ContextAI` | OpenAI-compatible model client (CXN router, `gpt-6.1-terra`) and AI actions as proposals | Crew's `CrewConstellation` client shape |
| `ContextHarness` | Projects' harness bindings, copy-as-context, the `context.md` writer, and the `HarnessConnector` and router-sync stubs | — |
| `ContextAutomation` | `contextctl` CLI and MCP server (later) | Cue's `CaptureAutomation` |

## Where things live

- **Data:** `~/Library/Application Support/ConstellationContext/` holds `notes.json`, settings, `Extensions/`, and the currency cache. Content moves to the base vault; settings stay here.
- **Bundle and scheme:** bundle id `app.constellation.Context`; URL scheme `context://` (`open`, `new`, `search`, `append`).
- **Global hotkey:** ⌥A. Region OCR: ⌥⇧S.
- **Model config reference:** `~/.config/opencode/opencode.json` (the `cxn-router` provider). Never copy its API key into the repo, logs, or plain-text settings.

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
- **Tests must never touch the user's real notes, vaults, or Anytype space.** Use the existing temp-store pattern, which disables clipboard collection, sync, currency refresh, and timer ticks. Use temp vaults and fake connectors.
- **Status claims stay honest.** Mark a feature "Shipped" only after you verify it in the installed app. Otherwise it is "Partial".

## Where to start

Take the first MVP item in [Vision.md § MVP](Vision.md#mvp) that is not done yet. Open a plan in `Plans/active/` for anything that crosses modules. Item 1, the base vault, comes first; most other items depend on it.
