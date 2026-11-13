#!/bin/bash
set -euo pipefail
if [[ $# != 1 ]]; then
  echo 'Usage: Scripts/bench-vault.sh <vault-path>' >&2
  exit 2
fi
vault=$(cd "$1" && pwd)
cd "$(dirname "$0")/.."
swift build -c release --product context-bench >&2
exec "$(swift build -c release --show-bin-path)/context-bench" "$vault"
