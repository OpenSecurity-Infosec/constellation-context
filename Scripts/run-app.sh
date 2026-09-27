#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
dest="/Applications/Context.app"
stamp="$dest/Contents/Resources/ContextRevision"
head="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo dev)"
built="$root/.build/debug/Context"
installed="$dest/Contents/MacOS/Context"
need_package=0
if [[ "${CONTEXT_REBUILD:-0}" == "1" ]]; then
  need_package=1
elif [[ ! -d "$dest" || ! -x "$installed" ]]; then
  need_package=1
elif [[ ! -f "$stamp" || "$(tr -d '[:space:]' < "$stamp")" != "$head" ]]; then
  need_package=1
elif [[ -x "$built" && "$built" -nt "$installed" ]]; then
  need_package=1
fi
if [[ "$need_package" == "1" ]]; then
  pkill -x Context >/dev/null 2>&1 || true
  app="$("$root/Scripts/package-app.sh" debug)"
  open "$app"
  echo "Installed revision $head → $app"
  exit 0
fi
open "$dest"
echo "Opened $dest (revision $head already installed)"
