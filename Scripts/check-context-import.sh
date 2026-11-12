#!/usr/bin/env bash
# Deterministic temp-vault import contract; no Claude session or GUI required.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./Scripts/test.sh --filter ImportResolutionTests
