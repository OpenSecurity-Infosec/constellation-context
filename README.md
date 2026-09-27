# Constellation Context

Open-source Mac-native scratchpad. Antinote-style instant notes with IDE-friendly plain text.

## Clone, build, run

Requirements: macOS 15+, Swift 6.1+ (Command Line Tools is enough).

```bash
git clone <repo-url> context
cd context
swift test
CONTEXT_REBUILD=1 ./Scripts/run-app.sh
```

`run-app.sh` packages the debug build into `/Applications/Context.app` and opens it. The global hotkey is **⌥A** (Option+A) from anywhere.

## Features vs Antinote (antinote.io/features)

| Antinote feature | Context MVP status |
| --- | --- |
| Global hotkey overlay (⌥A) | Shipped |
| Plain-text notes, formatting stripped on paste | Shipped |
| Swipe/arrow navigation between notes, new note past the end | Shipped (‹/› buttons, ⌘[/⌘]) |
| `math` inline evaluation with descriptive text | Shipped |
| Unit conversions (length, weight, temperature) | Shipped |
| Currency + crypto conversions in `math` (cached rates, offline fallback) | Shipped |
| Reactive variables (`name = expr`, recalculates down the note) | Shipped |
| `sum` / `avg` totals | Shipped |
| `count` lines/words/chars with `//` comments | Shipped |
| `list` checklists with tick-off | Shipped |
| `code` snippet buffer | Shipped (plain-text hold, no per-block highlighting yet) |
| `timer` stopwatch / countdown / pomodoro | Shipped |
| `paste` AutoPaste collection | Shipped |
| Screenshot-to-text OCR (on-device) | Shipped (image drop, Apple Vision) |
| One-click export (txt, Markdown, PDF) | Shipped |
| Copy to clipboard | Shipped |
| Recoverable trash (The Void) with expiry | Shipped (30 days) |
| Apple Notes / Obsidian / Bear direct export | Shipped |
| Link shrink (shortened display, click expand, ⌘↩ open) | Shipped |
| Native `::` commands (`today`, `now`, `sort_lines`, `uuid`) + JS extensions | Shipped (sandboxed .js in the Extensions folder; network toggle off by default) |
| Checklist nesting (Tab) + marker cycling (⌘⇧M) | Shipped |
| Two-finger swipe navigation | Shipped |
| Note search pane (⌘F) | Shipped |
| iCloud sync (your own iCloud, off by default, last-writer-wins) | Shipped (CloudKit private DB with key-value fallback) |
| URL schemes (`context://`) | Shipped (open, new, search, append) |
| Raycast/Alfred | Shipped via URL schemes (see Automation below) |
| Themes (system / light / dark, instant switch) | Shipped |
| Dock + menu bar + pin (dock / menu / both / neither) | Shipped |

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

- Notes live on this Mac: `~/Library/Application Support/ConstellationContext/notes.json`.
- No accounts, no analytics, no network calls except future opt-in rate fetching.
- License: MIT (see `LICENSE`).
