# Master parity work: port triage

On 2026-11-12 `pivot` became the base of `master` (merge `1eb20af`, `-s ours`: the tree is exactly pivot). The 22 pre-pivot commits on master since `0800ba3` are archived as the tag `archive/master-parity-2026-11-12` (`2cdc7cd`). Each one is triaged below against `Docs/Vision.md`, the Design Guide, ADR-0001/0002, and `AGENTS.md`.

Rule of thumb: port engine or domain work that adds no setting, mode, or visible control, and that fits the Markdown base vault. Skip anything that adds settings or modes the Vision does not justify, rewrites the editor string, or depends on CloudKit or `notes.json`.

| Archived commit | Feature | Fit? | Reasoning | Result |
| --- | --- | --- | --- | --- |
| `12ec82b` | Build identity stamp | Fit | Every cortex02 install must be verifiable by hash; About and the Inspector are on-command surfaces, so no chrome is added. | **Ported** (`e9ad296`). Status-bar label dropped: the zen canvas has no status bar. |
| `27c3bcb` | Reactive variables in `math` | Fit | Pure `ContextMath` engine work; no setting or control, and `math` notes are plain text in the vault. | **Ported** (`92810bb`) |
| `30348a2` | Unit conversion breadth, gutter errors | Fit | Same engine, no new surface. | **Ported** (`9f3f30d`) |
| `e06f9ff` | `//` comments on math lines | Fit | Same engine. | **Ported** (`1e84260`) |
| `bb11299` | Pressure/energy units, absolute-zero check | Fit | Same engine. | **Ported** (`3c90491`) |
| `24613a1` | Link shrink display and toggle | Partial fit | Detection and ⌘↩ lookup are domain-only and fit; the collapsed display replaced the editor string and cleared undo, which breaks "typography is display only" and the typing fixes. | **Ported detection only** (`839b7fc`) |
| `40d3c01` | `context://` validation + editor selections | Partial fit | URL validation is input hardening on an existing automation path (principle 5); the editor-selection part is tied to the old editor. | **Ported validation only** (`335c4ab`) |
| `82a92e7`, `363e733`, `44d5546` | Code highlighting + persisted language picker | Not now | Fenced-block highlighting could fit "Markdown styled inline", but the language picker is a new persisted setting, and the integration was written against the old editor. Revisit as part of canvas inline styling. | Skipped |
| `47fb6b5` | `paste` AutoPaste collection mode | No | Adds a first-line mode and ⌘⇧C, which collides with Copy as Context (⇧⌘C); the Clipboard pad covers collection. | Skipped |
| `b29e756` | 25 `::` builtins + JS sandbox limits | No | `::` commands and JS extensions are frozen trim candidates (Vision § Where today's app stands); breadth adds surface. If JS extensions survive the trim, port the 2 s execution limit. | Skipped |
| `cb1d987` | Separate light/dark theme choices | No | New settings; the Design Guide says appearance follows the system and no theme work before the consolidation pass. | Skipped |
| `2cdc7cd` | Paper types picker | No | New persisted setting and editor control; Paper is already the default theme. | Skipped |
| `f8d72b7` | Timer aurora scene | No | Decorative art on a frozen mode; conflicts with "restrained, typographic". | Skipped |
| `b88ac6b`, `71591b1` | Saved searches | No | Persisted UI state in `NoteStore` for the old search window; Library search across vaults replaces it. | Skipped |
| `8646809` | Note links by UUID + targeted append | No | Note UUIDs live in a derived, rebuildable index (ADR-0001), so UUID links would not survive a rebuild; `[[wikilinks]]` are the Vision's link model. | Skipped |
| `33e0d7f`, `4ff81dd`, `6ac7bad`, `3f07ccf` | AGENTS.md dev guide, cortex flags, project manifest, untrack `.build` | Superseded | Pivot's `AGENTS.md`, `Docs/Quickstart.md`, `Scripts/test.sh`, and `.gitignore` already cover these; the cortex02 CI path is now in Quickstart. | Not ported |

## Kept behaviour

`Scripts/package-app.sh` still sets `CFBundleVersion` to the short git hash (cortex02's auto-installer compares it to `origin/master`), and now also stamps `ContextBuildDate` and `ContextCommitSubject`.

## Unverified

All ports pass the automated suite on cortex02. None has been exercised by hand in the installed app yet; see the manual checks in the reconcile report.
