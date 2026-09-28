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

| Antinote feature | Context status (honest: Partial until proven feelable vs Antinote) |
| --- | --- |
| Global hotkey overlay (⌥A) | Shipped |
| Plain-text notes, formatting stripped on paste | Partial (nested-list indent, tables, quotes, entities, smart punctuation, CRLF, image-to-OCR all strip clean; exotic word-processor layouts still unproven) |
| Swipe/arrow navigation between notes, new note past the end | Partial (‹/› buttons and ⌘[/⌘] work; trackpad swipe untested across hardware) |
| `math` inline evaluation with descriptive text | Partial (core eval works; error states and large-note polish missing) |
| Unit conversions (length, weight, temperature) | Partial (unit-tested; gutter edge cases unpolished) |
| Currency + crypto conversions in `math` (cached rates, offline fallback) | Partial (live rates + 1h cache; outage keeps last cache with its age in the footnote, honest offline message with no cache, recovers on next refresh) |
| Reactive variables (`name = expr`, recalculates down the note) | Partial |
| `sum` / `avg` totals | Partial |
| `count` lines/words/chars with `//` comments | Partial |
| `list` checklists with tick-off | Partial (nesting + marker cycling work; Antinote drag-reorder missing) |
| `code` snippet buffer | Partial (plain-text hold, no per-block highlighting yet) |
| `timer` stopwatch / countdown / pomodoro | Partial (inline controls + named fullscreen display with progress and finish beep; no Antinote-grade fullscreen scene polish yet) |
| `paste` AutoPaste collection | Partial |
| Screenshot-to-text OCR (on-device) | Partial (image drop + ⌥⇧S region capture via Apple Vision into the current note; Esc cancels; Screen Recording permission prompt on first use) |
| One-click export (txt, Markdown, PDF) | Partial (works via save panel; not one-click) |
| Copy to clipboard | Shipped |
| Recoverable trash (The Void) with expiry | Partial (30-day expiry works; rows now show per-note days-left countdown) |
| Apple Notes / Obsidian / Bear direct export | Partial (all three wired; clean-Mac missing-app paths thinly tested) |
| Link shrink (shortened display, click expand, ⌘↩ open) | Partial |
| Native `::` commands (`today`, `now`, `sort_lines`, `uuid`) + JS extensions | Partial (builtins + sandboxed .js work; no extension gallery) |
| Checklist nesting (Tab) + marker cycling (⌘⇧M) | Partial |
| Two-finger swipe navigation | Partial (same as swipe row above) |
| Note search pane (⌘F) | Partial (title+body search with fuzzy match for typos/partial tokens, exact ranked first; no saved searches) |
| iCloud sync (your own iCloud, off by default, last-writer-wins) | Partial (CloudKit private DB coded + key-value fallback; two-Mac round-trip unproven) |
| URL schemes (`context://`) | Partial (open/new/search/append parse + handle; real Raycast/Alfred flows untested) |
| Raycast/Alfred | Partial via URL schemes (see Automation below; no native extensions) |
| Themes (system / light / dark, instant switch) | Partial (Mocha/Paper/Forest accents + adjustable text size + optional translucent window; Antinote paper types, separate light+dark colour themes, theme maker, app icon picker missing) |
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

- Notes live on this Mac: `~/Library/Application Support/ConstellationContext/notes.json`.
- No accounts, no analytics, no network calls except future opt-in rate fetching.
- License: MIT (see `LICENSE`).
