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
| `math` inline evaluation with descriptive text | Partial (per-line errors in the gutter; keystroke path stages to memory with coalesced disk flush, gutter re-evals memoized on unchanged body, 10k-line eval ~0.2s in tests) |
| Unit conversions (length, weight, temperature) | Partial (length/mass/temperature joined by volume, area, speed, time, and data size; temperature offsets for every C/F/K pair; abbreviated/plural/case/glued/multiword forms (`10km`, `°F`, `square feet`, `miles per hour`) plus compound quantities (`5 ft 6 in in cm`), `in`/`to` phrasing (inch `in` included), variables and descriptive labels around the conversion; incompatible units read `can't convert kg to mi` in the gutter and an unknown unit names the side that is unknown, while prose with in/to stays blank; thousands/scientific amounts parse and tiny/huge results display in scientific notation instead of rounding to 0; fluid measures and `ton` are US customary unless spelled imperial/metric, `yr` is 365.25 days, KB/MB are decimal vs KiB/MiB binary and `Mb` ≠ `MB`; unit-tested on cortex only — live gutter/editor feel in the packaged app vs Antinote unverified; no months, pressure/energy units, absolute-zero validation, or spaced expressions as compound-quantity amounts) |
| Currency + crypto conversions in `math` (cached rates, offline fallback) | Partial (live rates + 1h cache; outage keeps last cache with its age in the footnote, honest offline message with no cache, recovers on next refresh) |
| Reactive variables (`name = expr`, recalculates down the note) | Partial (sequential down-the-note: redefinition shadows lines below only, `x = x + 1` increments, failed assignment clears the name instead of leaking a stale value; unknown vs defined-below vs cycle vs bad/reserved name are distinct gutter errors; unicode/underscore names, case-sensitive; `sum`/`avg`/unit/currency words usable, only `in`/`to` reserved; assignment RHS accepts unit/currency conversions and conversion amounts accept variables; `sum`/`avg` count a variable use once and its definition not at all; gutter shows `name = value` on assignment lines; unit-tested on cortex only — live gutter/editor feel in the packaged app vs Antinote unverified; no hoisting, chained assignment, implicit multiplication, equations/comparisons, or trailing `//` comments on math lines) |
| `sum` / `avg` totals | Partial (per-line contribution gutter, live totals, thousands folding, ISO-date ignore, comment skip) |
| `count` lines/words/chars with `//` comments | Partial (per-line word/char gutter with ignored-line marks, live totals derived from the same rows, comment/blank skip) |
| `list` checklists with tick-off | Partial (nesting + marker cycling + drag-reorder with subtree-follow and persisted order; live-drag human verification still open) |
| `code` snippet buffer | Partial (per-block highlighting: fenced ```lang blocks in any note + whole-body `code` mode with inferred language; Swift/Python/JS/shell keyword/string/comment/number coloring in mono, tokenizer unit-tested; no type/function coloring, no language picker, look-and-feel vs Antinote unproven) |
| `timer` stopwatch / countdown / pomodoro | Partial (inline controls + named fullscreen with progress ring, elapsed/remaining status line, paused state, Done-in finish line, finish beep; Antinote-grade scene art still missing) |
| `paste` AutoPaste collection | Partial (each clipboard entry collected as its own `---`-delimited item, sanitized on the way in, live item count in the mode bar; ⌘⇧C copies all items joined without re-collecting the payload, ⌘⇧⌫ clears, ⌥⌘Z undoes, ⌘V in a paste note collects instead of inserting at the caret; domain logic unit-tested, live clipboard/menu feel and packaged-app comparison vs Antinote unverified; pre-delimiter notes read as one item and undo history is session-only) |
| Screenshot-to-text OCR (on-device) | Partial (image drop + ⌥⇧S region capture via Apple Vision into the current note; Esc cancels; Screen Recording permission prompt on first use) |
| One-click export (txt, Markdown, PDF) | Partial (quick export writes to last folder/Downloads with slug names + dedup + Finder reveal; Save As… remembers its folder; write failures alert instead of vanishing) |
| Copy to clipboard | Shipped |
| Recoverable trash (The Void) with expiry | Partial (30-day expiry with per-note days-left countdown; multi-select bulk restore with expired-skip notice) |
| Apple Notes / Obsidian / Bear direct export | Partial (all three wired; missing-app paths now specific — Notes/Bear install prompts, vault unset/missing/not-a-folder/unwritable each named, picker only when no usable vault, no fake vault creation) |
| Link shrink (shortened display, click expand, ⌘↩ open) | Partial (long URLs render shortened in the editor with the full URL as tooltip; plain click expands/collapses in place, ⌘↩ opens the link under the caret, and copy/save/export always carry the full URL — the `…` form never reaches disk; detection covers scheme URLs incl. non-http (`ftp:`, `context:`, `obsidian:`…), `mailto:`/`tel:`, `www.`, bare domains with port/path/query/fragment, localhost, IPv4, and e-mail-as-mailto, with trailing-punctuation trimming and balanced-parentheses handling, domain-unit-tested; the link being typed stays full until the caret leaves it and identical URLs toggle together; live click/keyboard feel in the packaged app vs Antinote unverified) |
| Native `::` commands (`today`, `now`, `sort_lines`, `uuid`) + JS extensions | Partial (25 builtins: date/time variants (`today`/`tomorrow`/`yesterday`/`now`/`time`/`timestamp`, custom formats via `today(yyyy/MM/dd)`), line transforms (`sort_lines` incl. `(desc)`, `reverse_lines`, `dedupe_lines`, `trim_lines`, `remove_blank_lines`, `shuffle_lines`), text transforms (`upper`/`lower`/`title`/`trim`, `base64_encode`/`base64_decode`, `hash` (SHA-256), `md5`, `json_format`), `random` ranges/picks, `count`, `uuid`, `help`, plus aliases (`date`, `sort`, `sha256`, `json`, …); arguments are parenthesised (`::random(1, 10)`, quotes protect commas) and reach JS scripts as `input.args`; unknown commands never fail silently — the popup shows the error with did-you-mean suggestions (prefix/edit-distance/substring), non-math notes mark unknown `::tokens` in the gutter, and run/argument/JSON/base64 errors land in the status bar; JS sandbox surfaces syntax/thrown errors, missing `run`, unusable returns, and unreadable files, terminates scripts at a 2s wall-clock limit (unit-tested with infinite loops), and keeps fetch/XHR/WebSocket absent; domain logic unit-tested on cortex only (343 tests) — live popup/gutter/status-bar feel in the packaged app vs Antinote unverified; editor now forwards nonempty source selections (including collapsed-link offset mapping) to domain transforms; interactive selection/popup behavior remains unverified; no extension gallery, no network bridge for scripts) |
| Checklist nesting (Tab) + marker cycling (⌘⇧M) | Partial |
| Two-finger swipe navigation | Partial (same as swipe row above) |
| Note search pane (⌘F) | Partial (title+body search with fuzzy match for typos/partial tokens, exact ranked first; no saved searches) |
| iCloud sync (your own iCloud, off by default, last-writer-wins) | Partial (CloudKit private DB coded + key-value fallback; two-Mac round-trip unproven) |
| URL schemes (`context://`) | Partial (open/new/search/append parse + handle; single percent decode, Unicode, empty/missing parameters and invalid routes covered by unit tests; invalid requests show an alert; note IDs unsupported and rejected; packaged alerts and real Raycast/Alfred flows untested) |
| Raycast/Alfred | Partial via URL schemes (see Automation below; no native extensions) |
| Themes (system / light / dark, instant switch) | Partial (Mocha/Paper/Forest accents + adjustable text size + optional translucent window; separate persisted light/dark colour choices follow system appearance, migrating the previous accent to both; interactive appearance switching unverified; Antinote paper types, theme maker, app icon picker missing) |
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
JavaScript extensions. `::help` lists every builtin in the note. Many
builtins take parenthesised arguments — `::random(1, 10)`,
`::today(yyyy/MM/dd)`, `::upper(some text)`, `::hash(abc)`,
`::sort_lines(desc)` (quote an argument to protect commas). Text commands
(`upper`, `base64_encode`, `json_format`, …) act on their argument, else
on the note body. An unknown command shows did-you-mean suggestions in the
popup instead of failing silently.

Drop `.js` files into the Extensions folder (Settings → Reveal), each
declaring a command:

```js
// name: shout — hint: Uppercase the note body
function run(input) { return { fullText: input.text.toUpperCase() }; }
```

`input` is `{ text, token, selection, now, args }` (`args` is the
parenthesised argument list). Return `{ replacement }` to swap the
`::token`, `{ fullText }` to rewrite the buffer, `{ append }` to add, or a
bare string; return `{ error: "…" }` (or throw) to show an error in the
status bar. Scripts run sandboxed in JavaScriptCore with no network
bridge (Settings → "Let extensions call their own APIs" stays OFF unless
you opt in) and are terminated after 2 seconds, so a runaway script
cannot hang the app.

## Notes

- Notes live on this Mac: `~/Library/Application Support/ConstellationContext/notes.json`.
- No accounts, no analytics, no network calls except future opt-in rate fetching.
- License: MIT (see `LICENSE`).

### Raycast / Alfred URL recipes

Install the packaged app first so macOS registers the scheme. Paste these into Terminal:

```sh
open 'context://open'
open 'context://new?text=Hello%20world%0A%E9%9B%AA%20%F0%9F%98%80'
open 'context://search?query=shopping%20list'
open 'context://append?text=Milk%20%26%20bread'
```

Raycast Quicklinks: use any URL above as the link. Alfred: connect a Keyword
input to an Open URL action containing one of those URLs. For arbitrary input,
use this Bash Run Script in Alfred (input as argv), or save it as a Raycast Script
Command; Python 3 must be available:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title New Context Note
# @raycast.mode silent
# @raycast.argument1 {"type":"text","placeholder":"Note text"}
encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1")
open "context://new?text=$encoded"
```

Encode parameter values once as UTF-8 percent escapes. `+` stays a literal plus;
use `%20` for spaces, `%26` for ampersands, `%25` for percent signs.
`new` accepts missing/empty text; search requires `query` (empty opens search);
append requires nonempty text and targets the current note. Open shows the overlay.
Note identifiers are unsupported: unknown parameters, duplicate parameters,
unknown actions, extra paths and fragments are rejected with a visible alert.
Real Raycast/Alfred execution and packaged-app alert/selection feel have not been verified.
