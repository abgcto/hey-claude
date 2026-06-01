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

# App icon (Finder / About panel / .app file icon). Build it if missing.
[ -f "$ROOT/Resources/AppIcon.icns" ] || "$ROOT/scripts/make-appicon.sh"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Dev: point the app at the repo's Models via symlink (Bundle.main.resourceURL/Models).
ln -sfn "$ROOT/Models" "$APP/Contents/Resources/Models"

# Bundle the General Sans fonts (registered via Info.plist ATSApplicationFontsPath).
mkdir -p "$APP/Contents/Resources/Fonts"
cp "$ROOT/Resources/Fonts/"*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true

# Code signing. Prefer the Developer ID identity: a STABLE signature means macOS
# keeps the microphone/automation TCC grants across rebuilds (no re-prompt churn),
# and it's the same identity notarization requires. Set HEYCLAUDE_SIGN_ID to your
# "Developer ID Application: NAME (TEAMID)" identity for a stable signature;
# leave it unset to ad-hoc sign (works anywhere; TCC grants won't persist).
SIGN_ID="${HEYCLAUDE_SIGN_ID:-}"
if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    echo "Signing with: $SIGN_ID"
    codesign --force --deep --sign "$SIGN_ID" "$APP"
else
    echo "warn: '$SIGN_ID' not found — ad-hoc signing (TCC grants won't persist)."
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
echo "Launch it with:  open \"$APP\""
