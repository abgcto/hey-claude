#!/usr/bin/env bash
# Reproducibly assemble Sources/CSherpaOnnx/sherpa-onnx.xcframework for the
# prebuilt-static integration path documented in internal design notes.
#
# The official macOS xcframework ships WITHOUT onnxruntime, so we merge the
# universal2 static libonnxruntime.a into libsherpa-onnx.a (libtool, because
# xcodebuild -create-xcframework needs full Xcode which is absent under CLT).
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

echo "==> Merging onnxruntime into libsherpa-onnx.a (universal2)…"
libtool -static -o "$LIB.merged" "$LIB" "$ORT"
mv "$LIB.merged" "$LIB"

echo "==> Injecting Clang module map into xcframework Headers…"
cp "$DEST/module.modulemap" "$XCF/macos-arm64_x86_64/Headers/module.modulemap"

echo "==> Verifying _OrtGetApiBase is now defined…"
# Accept T/t (text) and W/w (weak) with any address format (hex case varies by toolchain).
if nm -arch arm64 "$LIB" 2>/dev/null | grep -qE " [TtWw] _OrtGetApiBase"; then
  echo "    OK"
else
  echo "    FAILED: onnxruntime symbols not present" >&2
  exit 1
fi

echo "sherpa-onnx.xcframework ready at $XCF"
