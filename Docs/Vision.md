# Context — Vision

Context is part of the **Constellation Project**, alongside Crew and Cue.

## The objective in one sentence

**Context is a minimalist, Mac-native, AI-first home for notes and memory. It keeps plain Markdown files a keystroke away and curates them into the context your AI harnesses work from.**

## Why it exists

1. **Replace Obsidian for daily notes and memory.** Obsidian is clunky and slow, and it was not built around agents. Context should be faster to reach, quieter to look at, and easy for agents to read and write. It still works with the Markdown you already have in Obsidian and Anytype.
2. **Own the memory that AI harnesses keep for themselves.** Claude Code and other harnesses each keep their own memory, siloed and hard to curate. Context pulls that into one tool the user controls. The user curates pinned context there, and any harness can consume it.

Context is not a notebook that happens to have AI features. It is a **source of context**: deliberately kept, always current, and ready to be injected.

## Principles

These are decision rules. When a choice is unclear, the principle higher in the list wins.

1. **Less is more.** The default state of every surface is text and nothing else. Features stay hidden until called. A feature that cannot justify itself in one sentence does not ship.
2. **Files are the truth.** Content is Markdown with optional YAML frontmatter. There is no proprietary content database. Round-trips are lossless: Context never drops frontmatter keys, wikilinks, or files it does not understand. See [ADR-0001](ADR/0001-markdown-files-are-the-source-of-truth.md).
3. **Instant.** From hotkey to typing there is no perceptible delay. A large vault never blocks the editor. Speed is a feature, and Obsidian's slowness is part of why Context exists.
4. **AI works on the page.** AI actions show up as visible edits on the note. The user can accept, reject, or undo them. Context does not produce chat transcripts to copy out of, and it does not put a sparkle on every button.
5. **Humans and agents use the same operations.** Anything the UI can do to a note, pad, or project is a typed operation. AI actions, the CLI, and MCP call those same operations, as in Cue and Crew.
6. **Local-first and private.** No accounts and no analytics. Context only touches the network for the model endpoint the user configures and for vault connectors the user links.
7. **Native Mac, Constellation family.** AppKit and SwiftUI, system typography and materials. Context shares the look, feel, and engineering conventions of Crew and Cue. See [Design-Guide.md](Design-Guide.md).

## The product

### Two surfaces, both minimal

| Surface | Role | Reference |
| --- | --- | --- |
| **Quick surface** (primary) | A global-hotkey overlay plus the menu bar, and widgets later. You swipe between **pads**. This is where most of the time is spent. | Antinote |
| **Library** (full app) | A sidebar of the base vault, linked vaults, projects, and tags, then a note list, then the editor. You open it on purpose to browse, organize, or write longer pieces. | Bear |

### Pads

| Pad | What it is | Character |
| --- | --- | --- |
| **Scratch** | Your heads-up pad and the primary pad. It holds what you are keeping in mind right now: notes, pasted snippets, half-thoughts. | Deterministic; AI on demand |
| **Clipboard** | Clipboard history. Each entry starts as a clipboard event and then becomes an editable note like any other. You can trim it, merge it, or promote it into a project. | Deterministic; AI on demand |
| **Context** (one per project) | An AI scratch pad holding a project's live context. This is the core of the product. | AI-centric |

### Projects

A **project** is a context pack. It has three parts:

- **Live context.** One directly editable Markdown document. It is the pinned context: what any harness working on this project should know right now.
- **Documents.** Notes, files, and objects (images, PDFs, links, audio) that count as part of the project's context. Each one lives in the base vault or is referenced from a linked vault.
- **Harness bindings.** Where the project's context is delivered. See [Injection](#injection-getting-context-into-harnesses).

AI helps maintain a project. It summarizes and compacts the live context, pulls material from Scratch, Clipboard, and linked vaults into it, and flags stale lines. The user stays editor-in-chief: AI proposes edits on the page and the user decides.

### The canvas

A note is a canvas. Markdown text comes first, and objects (images, PDFs, audio, links, files) are embedded inline. Objects are stored as files next to the note and referenced with standard Markdown or Obsidian embed syntax, so other tools still read them. AI reads the whole canvas, text and objects together, as one document. It can summarize the canvas, rewrite it, or update it in place. This is the canvas idea Granola is good at. Context leaves out Granola's meeting features.

### Vaults: one base vault, any number of linked vaults

See [ADR-0002](ADR/0002-base-vault-and-linked-vaults.md).

**The base vault** is Context's own home, and Context always has one. It holds the pads, projects, and anything else Context creates. It is **Obsidian-compliant**:

- a plain folder of Markdown files with YAML frontmatter;
- `[[wikilinks]]` and `![[embeds]]`;
- attachments as ordinary files.

You can open it in Obsidian as a vault with no conversion. Context creates the base vault on first run, and the user picks where it goes.

```text
<base vault>/
  Scratch.md
  Clipboard/                 # one file per kept entry
  Projects/<project>/
    context.md               # live context; frontmatter holds bindings and metadata
    docs/                    # documents created or copied into the project
```

**Linked vaults** are external note stores that Context attaches through a **connector**. Context builds against the connector interface, not against any one app. Linked vaults are sources: you can browse, search, and edit their notes, and attach their notes to projects by reference. Context never adds its own folders or files to a linked vault.

| Connector | Reaches the notes through | Order |
| --- | --- | --- |
| **Anytype** | Anytype's local API and MCP server. Anytype keeps objects in its own store, but their content is Markdown-shaped: a Markdown body with typed relations, which map to frontmatter. | **First connector** |
| **Obsidian** | The vault folder, linked in place. Context preserves frontmatter and properties, `[[wikilinks]]`, `![[embeds]]`, and tags. It never writes inside `.obsidian/` and coexists safely with Obsidian running on the same folder. | Second |
| **MCP-backed** | Any MCP server that can list, read, and write documents | Later |

The note format is CommonMark plus GFM (task lists, tables) with YAML frontmatter. Context reads Obsidian-flavored extensions and writes them back unchanged.

### AI

AI actions call an OpenAI-compatible endpoint through the CXN router. The default comes from the local opencode configuration:

- provider: `cxn-router`;
- base URL: `https://infer.cxn.sh/v1`;
- model: `gpt-6.1-terra`.

The base URL and model are settings. The credential lives in the Keychain. The old `constellation/auto` route is deprecated; do not use it.

### Injection: getting context into harnesses

The injection pipeline is built into the app in the MVP. Each project has bindings, a delivery step, and a record of what was delivered. The pipeline is real, but the external endpoints start as stubs.

| Delivery | What it does | MVP status |
| --- | --- | --- |
| **Copy as context** | One keystroke copies a project's context as a prompt | Real |
| **Context file** | Context keeps each project's `context.md` current on disk, so a harness can reference it (for example, an `@path` import in a project's `CLAUDE.md` or `AGENTS.md`) | Real |
| **Harness connectors** | Per-harness delivery (Claude Code, opencode, and so on) behind one `HarnessConnector` interface | **Stub** |
| **Router sync** | Pushes project context into the Constellation router's store | **Stub** |
| **`contextctl` CLI and local MCP server** | Harnesses read, search, and append to project context and pads on demand | Later |

**Router-level injection, the long-term vision.** The Constellation router (`cxn-router`) already sits between every harness that uses its API and the model provider. Its own north star includes *inbound prompt shaping* (see `constellation-router/README.md`, "Vision / North star"). Once router sync is real, Context becomes the human-curated source for that shaping. The router compacts the conversation and injects the right project context into any harness, with no per-harness integration. Questions to answer before building it:

- How does a harness session identify its project? Options include seat, header, working directory, or an explicit binding.
- What is the compaction policy, and who controls the injection budget?
- How does the user see exactly what was injected into a given call?
- How does Context sync with the router's store: push, pull, and conflicts?

## MVP

**Exit test:** the user stops opening Obsidian for daily notes and feeds a project's context to Claude Code from Context.

**In, in build order:**

1. **Base vault.** An Obsidian-compliant folder created on first run. Notes, pads, and projects are Markdown files in it. Existing `notes.json` content migrates once, without loss.
2. **Connector interface and the Anytype connector.** Browse, search, read, and edit Anytype objects as Markdown, and attach them to projects.
3. **The Obsidian connector.** Link a vault in place, round-trip safe.
4. **Quick surface with three pad types:** Scratch, Clipboard (editable history), and project Context pads.
5. **Projects and injection.**
   - Real: live context, documents, copy-as-context, and the kept-current `context.md`.
   - Stubbed behind interfaces: harness connectors and router sync.
6. **AI actions on any pad or note** through `gpt-6.1-terra`: summarize, tidy or rewrite, extract into project context, and compact live context. Results arrive as proposals and apply as undoable edits.
7. **A minimal Library window.** Browse and search the base vault and linked vaults, and open a note in the canvas editor with images shown inline.

**Later:**

- real harness connectors, router sync, and router-level injection;
- the `contextctl` CLI and MCP server;
- MCP-backed vaults;
- widgets;
- rich objects beyond images (audio, video, PDF);
- mobile.

For syncing the base vault, rely on the user's existing file sync (iCloud Drive, Obsidian Sync, git) before building any of our own.

**Not planned:** meeting recording or transcription (explicitly out), a plugin marketplace, a graph view, multi-user collaboration, and any proprietary storage format.

## Where today's app stands

**The MVP is not met yet.** Each item has code and tests, but the exit test has not been met. See `Plans/active/MVP.md` § Status for the gaps. Status is in `README.md` § MVP status. Each step's log, including what is still unproven by hand, is in `Plans/active/MVP.md`.

The app now has:

- a base vault at `~/Context` (migrated from the old `notes.json`);
- Anytype and Obsidian connectors behind one interface;
- Scratch, Clipboard, and project Context pads in the ⌥A overlay;
- project context assembly with a kept-current file for `@` import;
- stubbed harness and router delivery;
- `gpt-6.1-terra` AI actions as diff proposals;
- a Library window with cross-source search and a canvas that shows images inline in Read mode.

Antinote-era features still work in Scratch: first-line modes, OCR, The Void, builtin `::` commands, URL schemes, and export. They are frozen and are candidates for the "less is more" trim. iCloud sync was removed in favor of file sync (ADR-0001).

## Open questions

- Which first-line modes survive the "less is more" cut?
- Should the base vault default stay at `~/Context`? It was chosen to avoid the Documents privacy prompt on ad-hoc-signed builds. The other options are iCloud Drive, or asking on first run.
- Anytype's real markdown round-trip fidelity. The connector follows API v1 `2025-11-08`, but it has only been tested against a fake.
- Live inline styling while typing in the Library (Bear-style). Today, images show only in Read mode.
- Should Constellation apps share a Swift package for the model client, the Keychain credential, and design tokens? Decide by ADR.
