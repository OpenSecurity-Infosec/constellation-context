# Constellation Context

<!-- apps01:surfaces:start -->
## Development environment

Project: Constellation Context
Host: apps01

### Cortex
- Endpoint: ssh://oz@192.168.123.231
- Access: Connect to oz@192.168.123.231 using a separately provisioned SSH key. apps01 has no cortex01 SSH alias configured. Confirm the key and the application testing service before use.
- Notes: Computer-use testing target. Endpoint configuration does not imply service availability.

These assignments document intended access; they do not provision credentials or enforce infrastructure permissions. Keep secrets outside the repository. Use credential references, inspect shared resources, and avoid interrupting other projects.
<!-- apps01:surfaces:end -->

## Dev guide

Open-source Mac-native Antinote-style scratchpad in Swift (SwiftPM, no Xcode
project). Remote: `origin` = https://github.com/OpenSecurity-Infosec/constellation-context,
branch `master`. Move fast, everything is dev: commit and push to `origin`
when done. Stay DRY, reuse existing helpers, no security over-engineering.

### Layout

- `Package.swift` — SwiftPM manifest (swift-tools 6.1, macOS 15+). Products:
  libraries `ContextDomain`, `ContextMath`, `ContextStore`, `ContextExport`,
  executable `Context`.
- `Apps/Context/` — the `ContextApp` executable target (AppKit/SwiftUI UI:
  editor, windows, hotkeys, themes, sync manager). Not a separate Xcode app.
- `Sources/ContextDomain/` — platform-light domain logic (notes, triggers,
  checklists, search, timer, `::` commands, themes). Put testable logic here.
- `Sources/ContextMath/` — math engine + currency rates (depends on Domain).
- `Sources/ContextStore/` — note persistence (depends on Domain).
- `Sources/ContextExport/` — export + Apple Notes/Obsidian/Bear handoff.
- `Tests/ContextDomainTests/`, `Tests/ContextMathTests/`,
  `Tests/ContextStoreTests/` — Swift Testing (`@Suite`/`@Test`/`#expect`),
  mirroring the `Sources/` targets.
- `Scripts/package-app.sh` — build + assemble/sign `/Applications/Context.app`.
- `Scripts/run-app.sh` — (re)package if stale (or `CONTEXT_REBUILD=1`) and open it.

### Build and test

apps01 is Linux with no Swift toolchain, and `Package.swift` declares
`.macOS(.v15)` plus AppKit/SwiftUI/CloudKit types — `swift build` /
`swift test` do not run here. Build and test on a Mac instead.

The cortex Mac in the surfaces block above (`oz@192.168.123.231`, macOS,
Swift 6.3.x) is reachable from apps01 when the provisioned key is present:
use the `crew-cortex01` SSH alias (or `-i ~/.ssh/crew_cortex01`); a bare
`ssh oz@192.168.123.231` without that key/agent will be denied. There is
no standing checkout on cortex — sync the tree over first, then build:

```bash
# from apps01, in this repo (excluding local build products)
rsync -a --exclude .git --exclude .build ./ crew-cortex01:~/constellation-context/
ssh crew-cortex01 'cd ~/constellation-context && swift build'
```

`.build/` is gitignored and untracked; never commit it.

`swift build` works as-is on cortex. Plain `swift test` does not: cortex has
Command Line Tools only (no Xcode), so SwiftPM cannot find the `Testing`
module. Point it at the CLT frameworks (verified: 181 tests pass):

```bash
ssh crew-cortex01 'cd ~/constellation-context && \
  DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib:/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  swift test \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks'
```

On any Mac with Command Line Tools: `swift test`, `swift build`, then
`CONTEXT_REBUILD=1 ./Scripts/run-app.sh` to install/open the app. UI feel,
hotkeys, paste/OCR, sync round-trips, and the packaged `.app` can only be
verified interactively on a Mac — say so when a change was only unit-tested.

### Commits

One focused slice per commit, subject in the established `git log` style:

```
<Short feature title>, Partial: <what actually landed> + tests + README honest
```

i.e. title-case noun phrase, then the honest status word, then a terse
`+`-joined list of what shipped (drop `+ tests` only when there are none).
Commit and push to `origin/master` when a slice is done.

### README honest-status rule

The README feature table is the source of truth for status, and rows stay
**Partial until proven feelable vs Antinote** (see the table header).
Implementation + unit tests alone do not earn `Shipped`; update the row in
the same commit, describing only what the code now does and naming what is
still missing or unverified. Never widen a claim beyond what was exercised.

