#!/usr/bin/env bash
# Reproducibly assemble Sources/CSherpaOnnx/sherpa-onnx.xcframework for the
# prebuilt-static integration path documented in internal design notes.
#
# The official macOS xcframework ships WITHOUT onnxruntime, so we merge the
# universal2 static libonnxruntime.a into libsherpa-onnx.a.
set -euo pipefail

VERSION="v1.13.2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/CSherpaOnnx"
XCF="$DEST/sherpa-onnx.xcframework"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

base="https://github.com/k2-fsa/sherpa-onnx/releases/download/$VERSION"

echo "==> Downloading prebuilt macOS xcframework ($VERSION, static)…"
curl -fL -o "$TMP/xcf.tar.bz2" \
  "$base/sherpa-onnx-$VERSION-macos-xcframework-static.tar.bz2"

echo "==> Downloading universal2 static onnxruntime…"
curl -fL -o "$TMP/u2.tar.bz2" \
  "$base/sherpa-onnx-$VERSION-osx-universal2-static.tar.bz2"

echo "==> Unpacking…"
tar xjf "$TMP/xcf.tar.bz2" -C "$TMP"
tar xjf "$TMP/u2.tar.bz2" -C "$TMP"

rm -rf "$XCF"
mkdir -p "$DEST"
mv "$TMP/sherpa-onnx-$VERSION-macos-xcframework-static/sherpa-onnx.xcframework" "$XCF"

LIB="$XCF/macos-arm64_x86_64/libsherpa-onnx.a"
ORT="$TMP/sherpa-onnx-$VERSION-osx-universal2-static/lib/libonnxruntime.a"

echo "==> Merging onnxruntime into libsherpa-onnx.a…"
# .a files are ar archives, not Mach-O — lipo -create/-extract on .a archives is
# unreliable and corrupts output. Correct approach: ar-extract all .o files,
# thin each fat object to arm64 (CI runner and app target are arm64-only),
# prefix ort objects to avoid name collisions, repack with libtool.
MERGE="$TMP/merge"
mkdir -p "$MERGE/sherpa" "$MERGE/ort"
(cd "$MERGE/sherpa" && ar -x "$LIB")
(cd "$MERGE/ort"    && ar -x "$ORT")

# Thin fat .o objects to arm64 in-place.
for f in "$MERGE/sherpa/"*.o "$MERGE/ort/"*.o; do
    [ -f "$f" ] || continue
    lipo -thin arm64 "$f" -output "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" || true
done

# Prefix ort objects so they never collide with same-named sherpa objects.
for f in "$MERGE/ort/"*.o; do
    [ -f "$f" ] || continue
    mv "$f" "$(dirname "$f")/ort_$(basename "$f")"
done

libtool -static -o "$LIB" "$MERGE/sherpa/"*.o "$MERGE/ort/"*.o

echo "==> Injecting Clang module map into xcframework Headers…"
cp "$DEST/module.modulemap" "$XCF/macos-arm64_x86_64/Headers/module.modulemap"

echo "==> Verifying _OrtGetApiBase is now defined…"
if nm "$LIB" 2>/dev/null | grep -qE " [TtWw] _OrtGetApiBase"; then
    echo "    OK"
else
    echo "    FAILED: onnxruntime symbols not present" >&2
    exit 1
fi

echo "sherpa-onnx.xcframework ready at $XCF"
