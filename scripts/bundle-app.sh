#!/usr/bin/env bash
# Assemble HeyClaude.app — a minimal menu-bar agent bundle so MenuBarExtra
# actually shows its status item (a bare `swift run` executable does not).
# This is the dev/Phase-3A bundler; Phase 3B hardens it (notarization, real
# bundled Models, DMG). For dev we symlink the repo Models to avoid a 650MB copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"   # debug (default) or release
swift build --product HeyClaudeApp -c "$CONFIG"
BIN="$(swift build --product HeyClaudeApp -c "$CONFIG" --show-bin-path)/HeyClaudeApp"

APP="$ROOT/HeyClaude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HeyClaude"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"

# Dev: point the app at the repo's Models via symlink (Bundle.main.resourceURL/Models).
ln -sfn "$ROOT/Models" "$APP/Contents/Resources/Models"

# Ad-hoc sign so it launches (Phase 3B swaps in Developer ID + notarization).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Launch it with:  open \"$APP\""
