# Context Agent Contract

This is the operating contract for humans and coding agents in this repo. Follow it on every turn.

**New here? Start with [`Docs/Quickstart.md`](Docs/Quickstart.md).**

## Branches

`master` is the single line of development. The `pivot` branch was merged into it on 2026-11-12 and is retired; do not commit to it. The pre-pivot Antinote-parity line is kept read-only as the tag `archive/master-parity-2026-11-12`; what was ported from it is in `Plans/active/master-port-triage.md`. Work only on `master`, and push to `origin/master` (cortex02 builds, tests, and installs it; see `Docs/Quickstart.md`).

## Sources of truth

1. `Docs/Vision.md` covers the objective, principles, surfaces, MVP scope, and injection roadmap.
2. `Docs/Design-Guide.md` covers look, feel, and interaction.
3. `Docs/ADR/` holds accepted architectural decisions.
4. `Plans/active/` holds active implementation plans.

If the code and these documents disagree, stop and reconcile them before you add another code path. If a request conflicts with the Vision, say so and ask before you build.

## Product rules that are easy to regress

- The hotkey overlay opens ready to type, with no perceptible delay.
- Clipboard capture never steals focus and never fronts a window.
- Paste strips formatting to clean text or Markdown.
- Context's own data (pads, clipboard, projects) lives only in the base vault. Context never adds folders or files to a linked vault (ADR-0002).
- Vault writes are lossless (ADR-0001). Context:
  - keeps unknown frontmatter keys;
  - keeps `[[wikilinks]]` and `![[embeds]]`;
  - never reformats a file on open;
  - never writes inside `.obsidian/`.
- AI output is a proposal. It applies as one undoable edit and never silently overwrites the user's text.
- Less is more. Do not add a setting, mode, or visible control without a one-sentence justification tied to `Docs/Vision.md`.

## Invariants

- Content lives in Markdown files. Indexes and caches are derived and rebuildable.
- Every vault source goes through the `VaultConnector` interface. Every harness delivery goes through `HarnessConnector`. No app-specific code paths around them.
- One mutation path. Every change to a note, pad, project, or vault is a typed operation that the UI, AI actions, CLI, and MCP share. This is new direction; current controller code migrates incrementally, and new code must follow it.
- SwiftUI views never call model providers, the network, or the file system directly.
- No production dependency without an ADR. There are none today.
- No force unwraps on reachable production paths.
- Never log note bodies, clipboard contents, project context, OCR text, secrets, or full file paths.
- Secrets live in the Keychain only. That includes the model API key and Anytype credentials. Never copy them from `~/.config/opencode/` into the repo or logs.
- The model endpoint is the CXN router (`https://infer.cxn.sh/v1`) with model `gpt-6.1-terra`. Both are configurable. Do not use the deprecated `constellation/auto` route.
- Tests never touch the user's real notes, vaults, Anytype space, clipboard history, or Application Support. Use temp stores, temp vaults, and fake connectors. Tests never call the live model endpoint.

## Stack

- Swift 6, strict concurrency, macOS 15+, Apple Silicon.
- AppKit for windows, the overlay, the menu bar, and the text system. SwiftUI for views.
- SwiftPM is the module source of truth. Use XcodeGen (`project.yml`) only when an Xcode project is needed, as Crew and Cue do.
- Swift Testing. XCTest only where hosted AppKit or UI automation requires it.
- Use the selected Xcode toolchain. On this machine the Command Line Tools lack the Swift Testing module, so do not point `DEVELOPER_DIR` at them for `swift test`.

## Module dependency direction

| Module | Owns | Must not depend on |
| --- | --- | --- |
| `ContextDomain` | Value types, parsing, pure logic (`Note`, `Pad`, `ClipboardPolicy`, settings) | AppKit, SwiftUI, network |
| `ContextVault` | `MarkdownDocument`, `BaseVault`, `VaultConnector` and its Anytype and Obsidian connectors, the linked-vault registry, `SecretStore` | UI, `ContextStore` |
| `ContextStore` | `NoteStore`, `Workspace` + `ContextCommand` (the one mutation path), the project model, migration | UI |
| `ContextHarness` | Context assembly, delivery and the kept-current file, `HarnessConnector`/`RouterSync` interfaces and stubs | UI |
| `ContextAI` | OpenAI-compatible model client, AI actions as proposals, line diff | UI, other Context modules |
| `ContextMath` | Math, unit, and currency evaluation | UI |
| `ContextExport` | Export and handoff | UI |
| `ContextApp` (`Apps/Context`) | Composition root: overlay, Library, Settings, hotkeys | Privileged logic (keep it in modules) |
| *planned* `ContextAutomation` | `contextctl` CLI and MCP | Alternate mutation paths |

Dependency direction: `ContextDomain` and `ContextVault` are foundational. `ContextStore` depends on both. `ContextHarness` depends on `ContextStore` and `ContextVault`. `ContextAI` stands alone. The app composes everything.

Known deviation from the one mutation path: The Void window still calls `NoteStore.restore`, `restoreMany`, and `destroy` directly. Route them through `Workspace.apply` when you next touch that window.

## Development loop

1. Read `Docs/Quickstart.md` and the relevant section of `Docs/Vision.md`.
2. For work that crosses modules, create or update a plan in `Plans/active/`. For a new architectural decision, add an ADR under `Docs/ADR/` with the same sections as ADR-0001.
3. Define types and contracts before UI.
4. Add deterministic tests.
5. Run `swift test`.
6. Do the close-out.

## Close-out: build and run before declaring done

Any change that can affect the running app, including `Apps/Context`, `Sources/`, `Scripts/`, or `Info.plist`, is not complete until the last step of the turn is:

```bash
CONTEXT_REBUILD=1 ./Scripts/run-app.sh
```

Then confirm that `/Applications/Context.app/Contents/Resources/ContextRevision` matches `git rev-parse --short HEAD`. A green test suite with a stale installed app is not done.

Skip the close-out only for docs-only or comment-only changes.

## Honesty

Status claims in `README.md` and in your reports must be true. Mark a feature "Shipped" only after you verify it in the installed app. Otherwise mark it "Partial" and say what is unproven. If you skipped a step or a test failed, say so.

## Repo hygiene

- Never commit build output. `.build/` is gitignored.
- Do not commit or push unless the user asks.
- Keep the conventions aligned with Crew (`~/Projects/Crew`) and Cue (`~/Projects/cue`). When you are unsure, copy their pattern.
