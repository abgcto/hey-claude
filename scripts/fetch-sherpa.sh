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
# Both .a files are lipo-style fat archives (fat header, separate per-arch
# archive slices inside) — ar -x cannot read them directly. Use lipo -thin to
# extract the arm64 slice from each, then merge the two thin archives with
# libtool -static. The CI runner (macos-14) and app distribution target are
# both arm64-only, so replacing the fat lib with a thin arm64 archive is fine.
lipo -thin arm64 "$LIB" -output "$TMP/sherpa_arm64.a"
lipo -thin arm64 "$ORT" -output "$TMP/ort_arm64.a"
libtool -static -o "$LIB" "$TMP/sherpa_arm64.a" "$TMP/ort_arm64.a"

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
