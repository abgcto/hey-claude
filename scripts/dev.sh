#!/usr/bin/env bash
# Dev loop: build the bundle, INSTALL it to /Applications (the path you actually
# launch from — Spotlight / login item), and relaunch. The point is that the
# binary you run is ALWAYS the one you just built — no stale-copy chase.
#
# Usage:  ./scripts/dev.sh            # debug build (default)
#         ./scripts/dev.sh release    # optimized build
#
# Tip: set HEYCLAUDE_SIGN_ID to your "Developer ID Application: …" identity so the
# signature is STABLE across rebuilds — then macOS keeps the mic / Input-Monitoring
# permission grants instead of forgetting them every build. bundle-app.sh reads it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"

# 1. Build + assemble ./HeyClaude.app (delegates to the existing bundler).
"$ROOT/scripts/bundle-app.sh" "$CONFIG"

# 2. Quit ALL running instances — both the bundled app (process "HeyClaude") AND
#    a bare `swift run` instance (process "HeyClaudeApp"). Killing only one name is
#    what left stale copies on screen before. The sleep avoids macOS's rapid
#    relaunch throttle (kill → immediate open).
pkill -x HeyClaude 2>/dev/null || true
pkill -x HeyClaudeApp 2>/dev/null || true
sleep 2
# Update the bundle IN PLACE — do NOT `rm -rf` the .app. Deleting the app makes
# macOS drop its Input-Monitoring (and Accessibility) TCC grant, so a freshly
# re-copied bundle is un-granted even with stable signing → push-to-talk dies on
# every redeploy. rsync syncs the contents while keeping the .app's path/identity,
# so the grant survives. (Microphone re-matches by signature, which is why only the
# hotkey was affected.)
mkdir -p "/Applications/HeyClaude.app"
rsync -a --delete "$ROOT/HeyClaude.app/" "/Applications/HeyClaude.app/"

# 3. Launch the copy you'll actually use.
open "/Applications/HeyClaude.app"
echo "✓ Installed + launched /Applications/HeyClaude.app ($CONFIG build)"
