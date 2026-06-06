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

echo "==> Debug: library formats"
lipo -info "$LIB" 2>&1 || true
lipo -info "$ORT" 2>&1 || true

echo "==> Merging onnxruntime into libsherpa-onnx.a…"
lipo -thin arm64 "$LIB" -output "$TMP/sherpa_arm64.a"
echo "    sherpa_arm64.a: $(wc -c < "$TMP/sherpa_arm64.a") bytes"
lipo -thin arm64 "$ORT" -output "$TMP/ort_arm64.a"
echo "    ort_arm64.a: $(wc -c < "$TMP/ort_arm64.a") bytes"

echo "==> Debug: OrtGetApiBase in ort_arm64.a before merge"
nm "$TMP/ort_arm64.a" 2>/dev/null | grep "_OrtGetApiBase" | head -5 || echo "    NOT FOUND"

libtool -static -o "$LIB" "$TMP/sherpa_arm64.a" "$TMP/ort_arm64.a"
echo "    merged lib: $(wc -c < "$LIB") bytes"

echo "==> Injecting Clang module map into xcframework Headers…"
cp "$DEST/module.modulemap" "$XCF/macos-arm64_x86_64/Headers/module.modulemap"

echo "==> Debug: nm output for _OrtGetApiBase in merged lib"
nm "$LIB" 2>/dev/null | grep "_OrtGetApiBase" | head -5 || echo "    (no matches at all)"
echo "    total nm lines: $(nm "$LIB" 2>/dev/null | wc -l)"

echo "==> Verifying _OrtGetApiBase is now defined…"
if nm "$LIB" 2>/dev/null | grep -qE " [TtWw] _OrtGetApiBase"; then
    echo "    OK"
else
    echo "    FAILED: onnxruntime symbols not present" >&2
    exit 1
fi

echo "sherpa-onnx.xcframework ready at $XCF"
