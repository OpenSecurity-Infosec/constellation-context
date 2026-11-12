#!/usr/bin/env bash
# Runs `swift test` on any Mac. With full Xcode selected it is plain
# `swift test`. With Command Line Tools only (cortex02), SwiftPM can't find
# the Testing module, so point it at the CLT frameworks. Extra arguments
# pass through, e.g. `./Scripts/test.sh --filter EditorTypingTests`.
set -euo pipefail
cd "$(dirname "$0")/.."
dev="$(xcode-select -p 2>/dev/null || true)"
if [[ "$dev" == *CommandLineTools* ]]; then
  clt="$dev/Library/Developer"
  export DYLD_LIBRARY_PATH="$clt/usr/lib:$clt/Frameworks${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  exec swift test \
    -Xswiftc -F -Xswiftc "$clt/Frameworks" \
    -Xlinker -F"$clt/Frameworks" \
    -Xlinker -rpath -Xlinker "$clt/usr/lib" \
    -Xlinker -rpath -Xlinker "$clt/Frameworks" \
    "$@"
fi
exec swift test "$@"
