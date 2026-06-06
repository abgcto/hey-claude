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

# Embed Sparkle.framework — locate the slice SwiftPM fetched for this arch.
SPARKLE_FW=$(find .build/artifacts -name "Sparkle.framework" -type d \
    \( -path "*/macos-arm64_x86_64/*" -o -path "*/macos-arm64/*" \) 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    # Fix the binary's rpath so dyld finds the embedded framework at runtime.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/HeyClaude" 2>/dev/null || true
    echo "Embedded Sparkle.framework from $SPARKLE_FW"
else
    echo "warn: Sparkle.framework not found in .build/artifacts — run 'swift package resolve' first." >&2
fi

# Code signing. Prefer the Developer ID identity: a STABLE signature means macOS
# keeps the microphone/automation TCC grants across rebuilds (no re-prompt churn),
# and it's the same identity notarization requires. Set HEYCLAUDE_SIGN_ID to your
# "Developer ID Application: NAME (TEAMID)" identity for a stable signature;
# leave it unset to ad-hoc sign (works anywhere; TCC grants won't persist).
#
# Signing order matters when Sparkle is embedded: sign nested XPC services and
# Autoupdate.app inside Sparkle.framework first, then the framework, then the app.
SIGN_ID="${HEYCLAUDE_SIGN_ID:-}"
if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    echo "Signing with: $SIGN_ID"
    EMBEDDED_FW="$APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$EMBEDDED_FW" ]; then
        # Inside-out: XPC services → Autoupdate → framework → app.
        for xpc in "$EMBEDDED_FW/Versions/B/XPCServices/"*.xpc; do
            [ -d "$xpc" ] && codesign --force --sign "$SIGN_ID" "$xpc"
        done
        [ -d "$EMBEDDED_FW/Versions/B/Autoupdate" ] && \
            codesign --force --sign "$SIGN_ID" "$EMBEDDED_FW/Versions/B/Autoupdate"
        codesign --force --sign "$SIGN_ID" "$EMBEDDED_FW"
    fi
    codesign --force --sign "$SIGN_ID" "$APP"
else
    echo "warn: '$SIGN_ID' not found — ad-hoc signing (TCC grants won't persist)."
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
echo "Launch it with:  open \"$APP\""
