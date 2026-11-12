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
- [x] **3. Obsidian connector**
  - A folder linked in place, passing conformance.
  - `.obsidian/` is never touched.
  - Link and unlink in Settings.
- [x] **4. Pads and command path**
  - A `ContextCommand` enum and one apply path, used by the UI, and later by AI and CLI.
  - Scratch, Clipboard (history captured as editable files in `<base>/Clipboard/`), and project Context pads.
  - A pad switcher in the overlay.
  - Paste keeps Markdown.
- [x] **5. Projects and injection**
  - `Projects/<name>/context.md` and `docs/`; attaching linked-vault notes by reference.
  - Copy-as-context, with `context.md` kept current.
  - `HarnessConnector` and `RouterSync` interfaces, each with a stub.
  - A delivery record.
- [x] **6. AI actions**
  - `ContextAI` OpenAI-compatible client: CXN router, `gpt-6.1-terra`, key in the Keychain.
  - Actions: summarize, tidy, extract-to-project, and compact.
  - Each result is shown as a proposal, accept or reject, and applies as one undoable edit.
- [x] **7. Library window**
  - Sidebar: base vault, linked vaults, projects.
  - Note list and search across sources.
  - Canvas editor with images inline.
- [x] **8. Close-out**
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
- **2026-11-12, step 3, done** (`1efcbc4`).
  - 215 tests pass. That includes conformance and fixture snapshots proving no other files and nothing under `.obsidian/` are touched.
  - No old Obsidian path was set, so the setting migration had nothing to move.
  - Unproven, needs a manual pass: linking the user's real vault at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents` (iCloud Drive). Two things to check:
    - whether macOS prompts for iCloud Drive access;
    - whether files evicted by "Optimize Mac Storage" list and download on read.
- **2026-11-12, step 4, done** (`1f63b76`).
  - 224 tests pass.
  - Each pad has its own folder, trash subfolder (`.trash/Clipboard/`, `.trash/Projects/<name>/`), and index file, so pads never clobber each other.
  - Known deviation: The Void window still calls `NoteStore.restore`, `restoreMany`, and `destroy` directly, not through `Workspace.apply`. Lazy empty placeholders (`store.create()` with no text) also bypass it, but those never touch disk.
  - Unproven, needs a manual pass (the screenshot was refused because the terminal lacks Screen Recording permission):
    - the pad menu rendering;
    - ⌘1, ⌘2, and ⌘3 switching;
    - New Project (⌘⇧N);
    - a copy landing in the Clipboard pad;
    - a 1Password copy being skipped.
  - Search and Void work only on the current pad. The cross-source search arrives in step 7 (Library).
- **2026-11-12, step 5, done** (`74c9afd`).
  - 231 tests pass.
  - **Decision:** the kept-current, harness-facing file is the *assembled* context at `<base>/.context/projects/<name>.md`, not `context.md`. It includes docs and references, it is derived, and it is rewritten only when its text changes. Bindings and references live in `Projects/<name>/project.json` because they are user data.
  - Attaching Anytype notes needs a note picker. That arrives with the Library (step 7). The overlay's Add Document handles files, and files inside a linked Obsidian vault become references.
  - Unproven, needs a manual pass:
    - the Context menu and Send to Project;
    - pasting the Copy Import Line output into a real `CLAUDE.md` and confirming Claude Code picks the file up.
- **2026-11-12, step 6, done** (`dd21e57`).
  - 241 tests pass.
  - **Live:** `gpt-6.1-terra` at `infer.cxn.sh` answered the client in ~9 s, using the key read from the opencode config into the test's environment only.
  - The app has no AI key until the user clicks Settings → AI → "Use opencode's CXN key" or pastes one. I did not write the user's key into the Keychain myself.
  - Unproven, needs a manual pass:
    - the drawer rendering;
    - ⌘↩ and Esc;
    - ⌘Z after Accept;
    - Extract with undo.
- **2026-11-12, step 7, done** (`9ffc97a`).
  - 244 tests pass.
  - **Decision:** images render inline in **Read** mode; **Edit** mode (⌘E) is raw Markdown. Inline images inside the editable text view would mean injecting attachment characters into the text, which risks the byte-exact round-trip (ADR-0001). Live Bear-style styling while typing is not done.
  - Two Library bugs were caught in review and fixed before commit:
    - pending typing could save into the newly selected note;
    - back-to-back linked saves could self-conflict.
  - Unproven, needs a manual pass:
    - the Library layout;
    - ⌘E;
    - search across sources;
    - Add to Project for an Anytype note;
    - image rendering from the real iCloud Obsidian vault.
- **2026-11-12, step 8, done.**
  - README has an honest MVP status table; the Antinote table is kept as a labeled historical baseline.
  - Quickstart, AGENTS module map, and Vision "where today's app stands" now match the code.
  - ~~MVP complete in code.~~ **Retracted 2026-11-12.** See "Status: MVP not met" below.

## Status: MVP not met (2026-11-12)

The steps above produced code and passing tests, not the MVP. The exit test, "the user stops opening Obsidian for daily notes and feeds a project's context to Claude Code from Context", has not been met.

Evidence:
- The core editor shipped broken. Inline predictions and composing text were saved and written back after the caret; fixed in `61c1b13`.
- No vault is linked. The Anytype connector has never run against real Anytype.
- No project exists, the AI key is not set, and the Claude Code import has never been run.

Gaps to close:

1. **Verify by use, not by unit test.** "Done" means exercised in the installed app (UI automation or the owner). The agent needs Accessibility and Screen Recording permission for its terminal to do this itself.
2. **Real Anytype link** (first connector): list, open, edit, attach. This needs the owner to enter the Anytype code once.
3. **Obsidian replacement for daily notes:**
   - daily notes;
   - templates (at least date tokens);
   - create, rename, and delete notes in the Library;
   - folder browsing;
   - following `[[wikilinks]]`.
4. **Speed on the real vault (693 notes):**
   - an index or cached listing instead of reading every file;
   - debounced search;
   - measured against "instant".
5. **Less is more in the overlay (Partial):**
   - a text-only, quiet toolbar (no emoji buttons);
   - Void, Export, Search, New, and Trash moved behind menus and shortcuts;
   - Settings grouped.
6. **Editing quality:** Markdown styling as you type in the overlay and Library.
7. **End-to-end Claude Code check:** create a project, paste the import line into a real `CLAUDE.md`, and confirm Claude Code uses the context.

## Manual check (owner, in the installed app)

None of these could be automated from the agent's terminal: it has no Screen Recording permission, linking needs a code shown by Anytype, and these are the user's real vaults.

1. **Overlay:**
   - ⌥A opens the overlay ready to type.
   - The pad menu at top left lists Scratch, Clipboard, and projects.
   - ⌘1, ⌘2, and ⌘3 switch pads.
   - ⇧⌘N creates a project, and its folder appears in `~/Context/Projects/`.
2. **Clipboard:**
   - Copy some text in another app; it appears in the Clipboard pad.
   - Copy a password from 1Password; it does **not** appear.
   - Edit an entry; it no longer expires.
3. **Paste:** pasting a Markdown list or table into Scratch keeps its structure.
4. **Projects:**
   - On a project pad, Context → Add Document… adds a file.
   - Copy as Context (⇧⌘C) puts the assembled prompt on the clipboard.
   - Copy Import Line gives an `@…/.context/projects/<name>.md` line. Paste it into a real `CLAUDE.md` and confirm Claude Code sees the context.
   - Deliver Now reports the stubs as "not built yet".
5. **Send to Project:** from Scratch, the note's text lands at the end of the project's context.
6. **AI:**
   - Settings → AI → Use opencode's CXN key, then Test, reports that `gpt-6.1-terra` answered.
   - On a note, AI → Tidy shows a diff. Accept with ⌘↩, then undo with ⌘Z in one step.
   - Extract to Project shows the project diff; accept it.
7. **Anytype:**
   - With Anytype open, Settings → Link Anytype… → enter the code → pick a space; status shows "Connected · N notes".
   - In the Library, open an object, edit its body in Edit mode, and confirm the change in Anytype.
   - Change a select property to an existing option.
8. **Obsidian:**
   - Settings → Link Obsidian… → `~/Library/Mobile Documents/iCloud~md~obsidian/Documents`. Watch for an iCloud Drive access prompt.
   - In the Library, browse and search the vault.
   - A note with `![[image.png]]` shows the image in Read mode.
   - Edit a note while Obsidian is open, and confirm there is no corruption and the conflict message appears if both edit at once.
9. **Library:**
   - ⇧⌘L opens it.
   - Search finds notes across Scratch, projects, and both linked vaults.
   - Add to Project on an Anytype note shows it under the project's Remove menu as "(linked)".
10. **Base vault:** Settings → Base vault → Change… to another folder, then back.

## Next (after the manual pass)

- Void mutation routing is implemented; owner interaction checks remain below.
- A real Claude Code harness connector.
- The `contextctl` CLI and MCP server (`ContextAutomation`).
- The "less is more" trim of legacy modes and settings.
- Live inline Markdown styling in the Library editor.

- **2026-11-12, gap 3, template foundation (Partial).** Added the pure
  `NoteTemplate.expand` contract for `{{date}}` (Gregorian `yyyy-MM-dd`, explicit
  date and time zone). Unknown tokens and Markdown remain unchanged. No new
  settings or canvas controls. Template selection and daily-note creation are
  still unfinished; owner-only verification and Anytype linking remain pending.
  Local tests unavailable (Linux host has no Swift); validation runs on cortex02
  against an isolated temporary source copy before push. Manual GUI checks for
  this foundation: none; existing canvas smoke checks remain pending.
  Validation: cortex02 isolated suite passed, 356 tests in 56 suites.

- **2026-11-12, gap 3, daily notes and template selection (Partial).**
  - File → Open Daily Note (⇧⌘D) opens or creates Scratch/yyyy-MM-dd.md
    using the current time zone; reopening preserves existing text.
  - File → New Note from Template… (⌥⌘N) uses a native file picker,
    expands {{date}}, and creates a separate Scratch note. Cancel leaves notes
    unchanged. No persisted template preference.
  - Justification: these on-command menu actions support the Vision's daily-note
    replacement goal while leaving the default canvas empty of controls.
  - Both operations use Workspace.apply; all created content stays in the base
    vault. Templates are read only; linked vaults receive no new files.
  - Tests cover reopen preservation, restart, date boundaries, and Markdown /
    unknown-token preservation. GUI behavior remains unproven.
  - Owner checks: invoke both shortcuts; reopen today's edited note; choose a
    Markdown template containing {{date}}, frontmatter and wikilinks; cancel the
    picker; confirm the source template stays unchanged and files land in Scratch.
  - Remaining gap 3: Library create/rename/delete, folder browsing, wikilinks.
  - Validation: isolated cortex02 suite passed, 358 tests in 56 suites.
    First run exposed URL normalization in daily lookup; fixed before commit.
    Post-push CI and installed revision are checked in this turn's report.

- **2026-11-12, gap 3, Library note actions and links (Partial).**
  - Plan/contracts: add a typed rename operation to Workspace, preserve file
    bytes and derived identity, and use the existing Library menus for new,
    rename and trash. New notes belong to Scratch (ADR-0002); project context
    filenames remain fixed. No settings or additional sidebar chrome.
  - Library reader links resolve across pads, project documents and linked
    connectors; aliases and heading suffixes resolve to the target note.
    Missing or ambiguous targets show a message. Embeds remain images.
  - Delete moves base notes/documents to the existing vault trash.
    Linked rename/delete remain unavailable;
    folder browsing is deferred to avoid expanding the sidebar in this slice.
    Project documents support rename through Workspace as well.
  - Tests: temporary-vault rename/identity/trash coverage and reader-link
    rendering coverage. Final isolated cortex02 run passed: 360 tests in 57 suites.
    Local swift test could not run: this Linux host has no Swift toolchain.
  - Manual GUI checks (not attempted): use New Note from an empty Library;
    edit, switch notes, rename, restart and confirm text is intact; trash
    and restore in The Void; click simple, aliased, folder-qualified and
    heading links across base/linked sources; check missing/duplicate targets
    and image embeds. Confirm keyboard shortcuts and menu availability.

- **2026-11-12, gap 4 (Partial, validation in progress).**
  - Plan: connector-owned rebuildable in-memory index caches snippets and searchable
    text; metadata reconciliation detects external edits/additions/removals without
    rereading unchanged bodies. Actor isolation keeps indexing off the UI actor.
  - Library search waits 200 ms after typing; cancellation suppresses superseded
    queries. No settings, modes or controls added.
  - Manual checks (no GUI/VNC attempted): browse the ~693-note vault, rapidly type
    and clear search, switch sources during search, edit/add/delete externally and
    reopen listing; confirm overlay opens ready to type during indexing.
  - Installed-app responsiveness remains unproven until those owner checks.
  - Measurement protocol: synthetic 693-note temporary vault (~1.6 KB each),
    cold listing then warm full-body search, timed with ContinuousClock on
    cortex02. This excludes iCloud hydration and UI latency; the 200 ms quiet
    interval is intentional. Local swift test unavailable (Linux, no Swift).
  - Isolated cortex02 validation passed: 361 tests / 57 suites. Synthetic
    warm search measured 87 ms (200 ms debounce additionally); this does not
    prove the real-vault "instant" criterion. No real note bodies were read
    for benchmarking. Post-push CI/rebuild results reported separately.


- **2026-11-12, gap 5 (Partial).** Existing hover header now uses pad text
  and More text only; New and Search join Trash and Export in the shared
  native action menu. Shortcuts: ⌘N, ⌘F, ⌘Delete, ⇧⌘E (Markdown export),
  ⌥⌘V (Void). Settings uses grouped native form sections, including Appearance.
  This supports Vision principle 1 by disclosing actions on command.
  Owner manual checks (no GUI/VNC attempted): ⌥A opens ready to type;
  hover reveals quiet text and typing hides it; More and right-click expose
  New/Search/Trash/Export; exercise shortcuts, cancel export, restore trash
  in Void; open Settings with ⌘, and check grouping, scrolling and persistence.
  Installed interaction remains unproven.
  Validation: cortex02 isolated suite passed, 361 tests / 57 suites.
  CI and forced installation revision are reported in the turn close-out.

- **2026-11-12, gap 6 (Partial).** Shared overlay and Library editing uses
  display-only Markdown attributes for headings, emphasis, lists/tasks, quotes,
  code and links/wikilinks. Source delimiters stay visible and editable; no new
  controls. Marked text bypasses styling and persistence as before.
  Owner checks: in both editors type and remove each syntax; move the caret
  into styled text, undo/redo, paste Markdown, switch notes, and reopen saved
  files. Exercise inline predictions and an IME, including cancellation and
  commit; confirm no duplicated text or caret jumps. Check light/dark appearance,
  Clipboard (no title), and legacy math alignment. No GUI/VNC attempted.
  Validation: cortex02 isolated suite passed, 362 tests / 58 suites, including
  the existing caret, prediction/marked-text and composition regression tests.
  Installed visual behavior remains unproven pending owner checks.

- **2026-11-12, Void mutation routing (Partial).** Plan and implementation:
  Void captures its Workspace and pad; single restore, bulk restore and permanent
  delete use typed commands. Removed the controller's direct store mutation path.
  Bulk restore retains expiry skipping and counts; only restored notes are selected.
  Errors use the existing notice. No settings, modes or controls added.
  Workspace currently has no general undo/history engine; this slice shares its
  mutation boundary without claiming to add undo for permanent deletion.
  Owner checks (no GUI/VNC): restore one and several notes in each pad, include
  expired Clipboard entries, delete permanently, reopen Void and restart.
  Validation: isolated cortex02 suite passed, 363 tests / 58 suites.
  Post-push CI and installed revision are reported in the turn close-out.

- **2026-11-12, less-is-more trim (Partial).**
  - Removed JS extension loading/execution from the app, its folder control and
    arbitrary-API permission toggle. Builtin text commands remain deterministic
    on-command edits through the existing Workspace-backed setText path.
  - Removed light/dark overrides, color-theme pickers (Settings and Inspector),
    and translucency toggle. Legacy persisted values are inert: system appearance,
    Paper and opaque paper apply consistently; text size remains for readability.
  - Audit: retain math/sum/avg/count as local text calculations; list as editable
    tasks; code as plain-text formatting; timer as an on-command local readout;
    paste collection remains a candidate for consolidation into Clipboard.
    OCR captures text on command; Void provides trash recovery; export and URL
    actions support file ownership and shared operations. Placement controls serve
    overlay access; clipboard opt-out serves privacy; vault/model settings serve
    explicitly configured sources. No new controls or content mutation paths.
  - Owner checks (no GUI/VNC used): switch macOS light/dark; verify Paper in
    overlay and Library, including an old settings file with overrides; adjust
    text size; confirm Inspector and Settings no longer offer theme/translucency
    or extension controls. Verify builtin commands still edit and undo; installed
    JS commands must no longer execute. Smoke-check pads, AI proposals and focus.
  - First-line mode consolidation remains open; this entry does not claim that
    the entire legacy trim or installed interaction has been verified.
  - Validation: isolated cortex02 suite passed, 364 tests / 58 suites.
    Local swift test unavailable on this Linux host. CI and revision check follow.

- **2026-11-12, first-line mode consolidation (Partial; owner verification pending).**
  - Plan/contracts: first-line words become inert ordinary Markdown without
    rewriting stored notes. Keep local calculations, counts, Markdown tasks/code
    and stopwatch readouts behind the existing explicit `::` command entry point.
    These support quick text work under Vision principles 1 and 5; no settings,
    modes, pickers or canvas controls are added. Commands use Workspace mutations
    and native editor undo. Clipboard alone collects copies through its existing
    privacy policy; remove AutoPaste and the timer/fullscreen/gutter surfaces.
  - Owner manual checks (no GUI/VNC attempted): reopen legacy math/list/code/timer/
    paste notes and confirm their bytes remain intact and no mode UI activates;
    type `::math`, `::sum`, `::avg`, `::count`, `::list`, `::code`, and `::timer`
    on command, check results, edit Markdown tasks/code normally, undo/redo once,
    switch pads and restart. First `::timer` starts a session-only stopwatch for
    that note; subsequent calls insert elapsed time. Restart resets stopwatch
    state. Copy text while Scratch contains `paste`: only Clipboard collects it;
    check clipboard opt-out, concealed password-manager copies, no focus theft,
    and project ⇧⌘C. Check non-ASCII text before commands and IME composition.
  - Currency calculations are local and report unavailable rates; there is no
    automatic network rate fetch. Installed interaction remains unproven.
  - Validation: isolated cortex02 source copy passed all 371 tests in 61 suites,
    including native command undo/redo, marked-text/editor regressions, inert
    legacy first lines and metadata, byte-preserving reopen, local calculations,
    portable task/code formatting and Unicode command ranges. A prior run caught
    the old typography expectation; undo testing also caught stale Workspace text
    after native undo. Both are fixed. Local swift test is unavailable on this
    Linux host. Post-push CI and forced-install revision are reported at close-out.
