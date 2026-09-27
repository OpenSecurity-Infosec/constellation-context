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
| Unit conversions (length, weight, temperature) | Shipped (currency/crypto rates pending) |
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
| iCloud sync | Not started (local JSON store only) |
| Apple Notes / Obsidian / Bear direct export | Not started |
| Link shrink, themes, extensions/`::` commands, URL schemes, Raycast/Alfred | Not started |

## Notes

- Notes live on this Mac: `~/Library/Application Support/ConstellationContext/notes.json`.
- No accounts, no analytics, no network calls except future opt-in rate fetching.
- License: MIT (see `LICENSE`).
