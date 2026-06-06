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
# Both archives are lipo-style fat files. Strategy:
# 1. lipo -thin to extract arm64 thin archives (ar -x fails on fat archives).
# 2. ar -x each thin archive into separate directories.
# 3. Rename ort objects with an ort_ prefix — libtool -static silently drops a
#    defining object when a same-named object from the other archive is seen first,
#    which caused _OrtGetApiBase to vanish from the merged output.
# 4. libtool -static to repack all objects into the final library.
MERGE="$TMP/merge"
mkdir -p "$MERGE/sherpa" "$MERGE/ort"

lipo -thin arm64 "$LIB" -output "$TMP/sherpa_arm64.a"
lipo -thin arm64 "$ORT" -output "$TMP/ort_arm64.a"

(cd "$MERGE/sherpa" && ar -x "$TMP/sherpa_arm64.a")
(cd "$MERGE/ort"    && ar -x "$TMP/ort_arm64.a")

# Rename all ort objects to guarantee no name collision with sherpa objects.
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
