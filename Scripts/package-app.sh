#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
config="${1:-debug}"
swift build -c "$config" --product Context >&2
bin="$root/.build/${config}/Context"
if [[ ! -x "$bin" ]]; then
  bin="$(find .build -path "*${config}/Context" -type f -perm -111 ! -path "*.app/*" | head -n 1)"
fi
if [[ -z "${bin:-}" || ! -x "${bin:-}" ]]; then
  echo "Context binary not found" >&2
  exit 1
fi
app="$root/.build/Context.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Context"
cp Apps/Context/Info.plist "$app/Contents/Info.plist"
if [[ -f Apps/Context/Context.entitlements ]]; then
  cp Apps/Context/Context.entitlements "$app/Contents/Resources/Context.entitlements"
fi
rev="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo dev)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $rev" "$app/Contents/Info.plist" >/dev/null
printf '%s\n' "$rev" > "$app/Contents/Resources/ContextRevision"
chmod +x "$app/Contents/MacOS/Context"
xattr -cr "$app" >/dev/null 2>&1 || true
codesign --force --sign - --identifier app.constellation.Context --timestamp=none "$app" >&2 || true
dest="/Applications/Context.app"
rm -rf "$dest"
ditto "$app" "$dest"
xattr -cr "$dest" >/dev/null 2>&1 || true
codesign --force --sign - --identifier app.constellation.Context --timestamp=none "$dest" >&2 || true
printf '%s\n' "$dest"
