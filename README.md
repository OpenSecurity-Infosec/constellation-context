# Constellation Context

Context is a minimalist, Mac-native, AI-first home for notes and memory, and part of the Constellation Project. It keeps plain Markdown files a keystroke away and curates them into the context your AI harnesses work from.

- **Why and where it's going:** [Docs/Vision.md](Docs/Vision.md)
- **Agents start here:** [Docs/Quickstart.md](Docs/Quickstart.md), then [AGENTS.md](AGENTS.md)
- **Look and feel:** [Docs/Design-Guide.md](Docs/Design-Guide.md)

## Clone, build, run

Requirements: macOS 15+, Xcode 26 (Swift 6.1+). On this Mac, Command Line Tools alone lack Swift Testing, so `swift test` needs the selected Xcode.

```bash
git clone <repo-url> context
cd context
swift test
CONTEXT_REBUILD=1 ./Scripts/run-app.sh
```

`run-app.sh` packages the debug build into `/Applications/Context.app` and opens it. The package step stamps the build: `CFBundleVersion` is the short git hash (cortex02's auto-installer compares it to `origin/master`), and **Context › About Context** and the Inspector footer show `<hash> · built <local time>`. The About panel also shows the commit subject. **⌥A** (Option+A) toggles the overlay from anywhere. **⇧⌘L** opens the Library.

## Typing regression tests

`Tests/ContextAppTests/EditorTypingTests` hosts the real overlay on a temporary vault and types into it with key events. They cover typing order and the caret, renders between keys, typing mid-line, the saved file, edits made elsewhere, note switching, and provisional (marked) text from input methods and macOS inline predictions, which must never be saved or written back as real characters. They need a logged-in desktop session, and they run as part of `swift test`.

## MVP status

**The MVP is not met yet.** The gaps are listed in `Plans/active/MVP.md` § Status. "Partial" means automated tests pass, but the installed app has not been exercised by hand for that feature. "Shipped" means verified in the installed app.

| MVP feature | Status |
| --- | --- |
| **Base vault**: notes are Markdown files in `~/Context` (Scratch/, Clipboard/, Projects/), Obsidian-compliant, external edits reload, one-time `notes.json` migration | Shipped for storage and migration (real notes migrated). Partial for Settings → Base vault → Change… |
| **Anytype connector**: link with the 4-digit code or an API key, pick a space, objects as Markdown with properties as frontmatter, edits send only what changed | Partial (tested against a fake of the documented API v1 `2025-11-08`; not yet linked to a real Anytype) |
| **Obsidian connector**: link a vault folder in place, never touches `.obsidian/`, refuses conflicting writes | Partial (fixture-vault tests; the real iCloud vault not yet linked) |
| **Pads**: Scratch, Clipboard (editable history, password-manager copies skipped, untouched entries expire after 30 days), one Context pad per project; ⌘1–⌘9, ⇧⌘N new project | Partial |
| **Projects and injection**: live context, `docs/`, linked references; Copy as Context (⇧⌘C); kept-current `~/Context/.context/projects/<name>.md` for `@` import; delivery log | Partial |
| **Harness connectors** (Claude Code, opencode) and **router sync** | Stubs by design. They report "not built yet" |
| **AI actions** via `gpt-6.1-terra` (CXN router): Summarize, Tidy, Extract to Project, Compact as diff proposals with Accept/Reject and one-step undo | Partial (the client is verified live against the real endpoint; the overlay flow has not been run by hand) |
| **Library**: sources, search across all of them, Read view with images inline, Edit view (⌘E), Add to Project | Partial |
| Paste keeps Markdown (lists, quotes, tables, code) | Partial |

Not in the MVP: the `contextctl` CLI and MCP server, real harness connectors, router-level injection, MCP-backed vaults, widgets, and rich objects beyond images. See [Vision.md](Docs/Vision.md#mvp).

## Baseline: Antinote features (historical)

This is the pre-pivot parity record. Antinote parity work is closed, and the table is not a roadmap.

| Antinote feature | Context status (honest: Partial until proven feelable vs Antinote) |
| --- | --- |
| Global hotkey overlay (⌥A) | Shipped |
| Plain-text notes, formatting stripped on paste | Changed: paste keeps Markdown structure and drops only styling and invisible characters (OCR text still goes through the old cleaner) |
| Swipe/arrow navigation between notes, new note past the end | Partial (‹/› buttons and ⌘[/⌘] work; trackpad swipe untested across hardware) |
| `math` inline evaluation with descriptive text | Partial (per-line errors in the gutter; keystroke path stages to memory with coalesced disk flush, gutter re-evals memoized on unchanged body, 10k-line eval ~0.2s in tests) |
| Unit conversions (length, weight, temperature) | Partial (unit-tested; gutter edge cases unpolished) |
| Currency + crypto conversions in `math` (cached rates, offline fallback) | Partial (live rates + 1h cache; outage keeps last cache with its age in the footnote, honest offline message with no cache, recovers on next refresh) |
| Reactive variables (`name = expr`, recalculates down the note) | Partial (sequential down-the-note: redefinition shadows lines below only, `x = x + 1` increments, failed assignment clears the name instead of leaking a stale value; unknown vs defined-below vs cycle vs bad/reserved name are distinct gutter errors; unicode/underscore names, case-sensitive; `sum`/`avg`/unit/currency words usable, only `in`/`to` reserved; assignment RHS accepts unit/currency conversions and conversion amounts accept variables; `sum`/`avg` count a variable use once and its definition not at all; gutter shows `name = value` on assignment lines; unit-tested on cortex only — live gutter/editor feel in the packaged app vs Antinote unverified; no hoisting, chained assignment, implicit multiplication, equations/comparisons, or trailing `//` comments on math lines) |
| `sum` / `avg` totals | Partial (per-line contribution gutter, live totals, thousands folding, ISO-date ignore, comment skip) |
| `count` lines/words/chars with `//` comments | Partial (per-line word/char gutter with ignored-line marks, live totals derived from the same rows, comment/blank skip) |
| `list` checklists with tick-off | Partial (nesting + marker cycling + drag-reorder with subtree-follow and persisted order; live-drag human verification still open) |
| `code` snippet buffer | Partial (plain-text hold, no per-block highlighting yet) |
| `timer` stopwatch / countdown / pomodoro | Partial (inline controls + named fullscreen with progress ring, elapsed/remaining status line, paused state, Done-in finish line, finish beep; Antinote-grade scene art still missing) |
| `paste` AutoPaste collection | Partial |
| Screenshot-to-text OCR (on-device) | Partial (image drop + ⌥⇧S region capture via Apple Vision into the current note; Esc cancels; Screen Recording permission prompt on first use) |
| One-click export (txt, Markdown, PDF) | Partial (quick export writes to last folder/Downloads with slug names + dedup + Finder reveal; Save As… remembers its folder; write failures alert instead of vanishing) |
| Copy to clipboard | Shipped |
| Recoverable trash (The Void) with expiry | Partial (30-day expiry with per-note days-left countdown; multi-select bulk restore with expired-skip notice) |
| Apple Notes / Obsidian / Bear direct export | Partial. Send to Obsidian now uses the linked Obsidian vault (Settings → Linked vaults) |
| Link shrink (shortened display, click expand, ⌘↩ open) | Partial |
| Native `::` commands (`today`, `now`, `sort_lines`, `uuid`) + JS extensions | Partial (builtins + sandboxed .js work; no extension gallery) |
| Checklist nesting (Tab) + marker cycling (⌘⇧M) | Partial |
| Two-finger swipe navigation | Partial (same as swipe row above) |
| Note search pane (⌘F) | Partial (title+body search with fuzzy match for typos/partial tokens, exact ranked first; no saved searches) |
| iCloud sync | Removed. Notes are Markdown files in the base vault; use iCloud Drive, Obsidian Sync, or git to sync the folder (ADR-0001) |
| URL schemes (`context://`) | Partial (open/new/search/append parse + handle; real Raycast/Alfred flows untested) |
| Raycast/Alfred | Partial via URL schemes (see Automation below; no native extensions) |
| Themes (system / light / dark, instant switch) | Partial (Paper (default)/Mocha/Forest accents, zen canvas with serif first-line title + adjustable text size + optional translucent window; Antinote paper types, separate light+dark colour themes, theme maker, app icon picker missing) |
| Dock + menu bar + pin (dock / menu / both / neither) | Partial (toggles live; menu-bar-only edge cases unproven) |

## Automation (URL schemes, Raycast, Alfred)

Context registers the `context://` scheme. Drive it from Raycast, Alfred,
Shortcuts, or the terminal (`open "context://..."`):

| URL | Action |
| --- | --- |
| `context://open` | Show the overlay |
| `context://new?text=hello` | New note, optionally prefilled |
| `context://search?query=milk` | Open search with a query |
| `context://append?text=more` | Append to the current note |

Raycast: Script Commands or Quicklinks calling `open "context://new?text=…"`.
Alfred: Workflow → Open URL with the same forms.

## Extensions (`::` commands)

Type `::` in any note for autocomplete: native builtins plus installed
JavaScript extensions. Drop `.js` files into the Extensions folder
(Settings → Reveal), each declaring a command:

```js
// name: shout — hint: Uppercase the note body
function run(input) { return { fullText: input.text.toUpperCase() }; }
```

`input` is `{ text, token, selection, now }`. Return `{ replacement }` to
swap the `::token`, `{ fullText }` to rewrite the buffer, `{ append }` to
add, or a bare string. Scripts run sandboxed in JavaScriptCore with no
network bridge; Settings → "Let extensions call their own APIs" stays OFF
unless you opt in.

## Notes

- Notes live on this Mac as Markdown files in the base vault, `~/Context` by default (Settings → Base vault). It opens in Obsidian as-is. Legacy `notes.json` content moves there once, and the old file is kept as `notes.json.migrated-*`.
- Linked vaults are listed in `~/Library/Application Support/ConstellationContext/vaults.json`. The Anytype and AI API keys are in the Keychain.
- No accounts and no analytics. Network calls happen only for currency rates in `math` notes, for AI actions you run (sent to the endpoint in Settings → AI), and for a linked Anytype (localhost).
- License: MIT (see `LICENSE`).
