#!/usr/bin/env bash
# Build Resources/AppIcon.icns from Resources/appicon.svg.
#
# macOS ships no SVG rasterizer, so we render the master SVG once at 1024px via
# headless Chrome (with a transparent background so the squircle's rounded
# corners keep real alpha), then downscale to every iconset size with `sips`
# and assemble the .icns with `iconutil`.
#
# Usage:  scripts/make-appicon.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Resources/appicon.svg"
OUT="$ROOT/Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SVG" ] || { echo "error: $SVG not found" >&2; exit 1; }

# Locate a Chrome/Chromium binary.
CHROME=""
for c in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
  [ -x "$c" ] && CHROME="$c" && break
done
[ -n "$CHROME" ] || { echo "error: no Chrome/Chromium/Edge found to rasterize the SVG" >&2; exit 1; }

# Wrapper HTML that paints the SVG full-bleed at the master size.
MASTER=1024
cat > "$WORK/wrap.html" <<HTML
<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent}
img{display:block;width:${MASTER}px;height:${MASTER}px}</style>
<img src="file://${SVG}">
HTML

echo "Rendering ${MASTER}px master via Chrome..."
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --default-background-color=00000000 \
  --virtual-time-budget=2000 --window-size="${MASTER},${MASTER}" \
  --screenshot="$WORK/master.png" "file://$WORK/wrap.html" >/dev/null 2>&1

[ -s "$WORK/master.png" ] || { echo "error: master render failed" >&2; exit 1; }

# iconset: name -> pixel size
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
emit() { sips -s format png -z "$2" "$2" "$WORK/master.png" --out "$ICONSET/$1" >/dev/null; }
emit icon_16x16.png        16
emit icon_16x16@2x.png     32
emit icon_32x32.png        32
emit icon_32x32@2x.png     64
emit icon_128x128.png     128
emit icon_128x128@2x.png  256
emit icon_256x256.png     256
emit icon_256x256@2x.png  512
emit icon_512x512.png     512
emit icon_512x512@2x.png 1024

echo "Assembling ${OUT} ..."
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote ${OUT} ($(du -h "$OUT" | cut -f1))"
