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

## Test Mac

Use cortex02: `ssh oz@192.168.123.153` (Intel x86_64, macOS 26, Swift 6.3, CLT only).
Checkout: `/Users/oz/Projects/constellation-context`. After pushing, run
`ssh oz@192.168.123.153 ~/bin/context-ci.sh`; it pulls, builds, runs tests
with the Testing-framework flags, and relaunches `/Applications/Context.app`.
This supersedes the historical Cortex surface above for build/test. Hands-on GUI
testing happens separately outside T3: do not look for VNC or a GUI testing service.
End summaries with concrete manual app checks.

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

.build/ is gitignored; never commit it. Use the cortex02 CI command above.
Report its result line; distinguish automated checks from unverified GUI feel.

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

