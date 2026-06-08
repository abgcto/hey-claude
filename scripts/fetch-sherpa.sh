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
# Both archives are lipo-style fat files. lipo -thin extracts the arm64 slice.
# ar -x cannot be used on the thin ort archive because it contains duplicate
# member names (e.g. onnxruntime_c_api.cc.o appears multiple times); ar -x
# overwrites by name, landing on the LAST occurrence which is a stub, not the
# defining object. Instead, use Python to extract every member with a unique
# counter prefix so no occurrence is silently dropped.
MERGE="$TMP/merge"
mkdir -p "$MERGE/sherpa" "$MERGE/ort"

lipo -thin arm64 "$LIB" -output "$TMP/sherpa_arm64.a"
lipo -thin arm64 "$ORT" -output "$TMP/ort_arm64.a"

# Extract sherpa with plain ar (no duplicates there).
(cd "$MERGE/sherpa" && ar -x "$TMP/sherpa_arm64.a")

# Extract ort with Python: give each member a unique counter prefix so
# duplicate filenames all survive as separate .o files.
python3 - "$TMP/ort_arm64.a" "$MERGE/ort" << 'PYEOF'
import sys, os

ar_path, out_dir = sys.argv[1], sys.argv[2]
skip = frozenset(['/', '//', '__.SYMDEF', '__.SYMDEF SORTED',
                  '__.SYMDEF_64', '__.SYMDEF_64 SORTED'])
with open(ar_path, 'rb') as f:
    assert f.read(8) == b'!<arch>\n', "not an ar archive"
    counts = {}
    while True:
        hdr = f.read(60)
        if len(hdr) < 60:
            break
        raw_name = hdr[:16].decode('ascii', errors='replace').strip()
        size = int(hdr[48:58].decode('ascii').strip())
        data = f.read(size)
        if size % 2:
            f.read(1)  # even-alignment padding
        # BSD extended-name format: #1/N means the real name occupies the first
        # N bytes of the data section (used for names longer than 15 characters).
        if raw_name.startswith('#1/'):
            name_len = int(raw_name[3:])
            name = data[:name_len].decode('ascii', errors='replace').rstrip('\x00')
            data = data[name_len:]
        else:
            name = raw_name.rstrip('/')
        if not name or name in skip:
            continue
        base = os.path.basename(name)
        idx = counts.get(base, 0)
        counts[base] = idx + 1
        with open(os.path.join(out_dir, f'{idx:04d}_{base}'), 'wb') as out:
            out.write(data)
print(f"    extracted {sum(counts.values())} ort members ({len(counts)} unique names)")
PYEOF

# Start from the sherpa arm64 archive, then blindly append all ort objects.
# We use 'ar -q' (quick-append) rather than libtool -static because Apple's
# libtool filters out objects that don't resolve any undefined reference in the
# input set — it silently drops ort symbols like _OrtGetApiBase that sherpa
# doesn't directly reference (the app linker pulls them in later).
# The ort objects already have unique counter-prefixed names from the Python
# step above, so ar -q has no duplicate-name problem.
ORT_OBJS=( "$MERGE/ort"/*.o )
echo "    ort .o count: ${#ORT_OBJS[@]}"
CAPI_OBJ=$(ls "$MERGE/ort/" | grep onnxruntime_c_api | head -1)
echo "    capi obj: $CAPI_OBJ"
echo "    capi file type: $(file "$MERGE/ort/$CAPI_OBJ" | cut -d: -f2-)"
echo "    capi nm direct: $(nm "$MERGE/ort/$CAPI_OBJ" 2>/dev/null | grep OrtGetApiBase | head -3 || echo NOT FOUND)"
echo "    ort total size: $(du -sh "$MERGE/ort" | cut -f1)"

cp "$TMP/sherpa_arm64.a" "$LIB"
find "$MERGE/ort" -name '*.o' | xargs ar -q "$LIB"
ranlib "$LIB"
echo "    merged lib size: $(wc -c < "$LIB" | tr -d ' ') bytes"
echo "    merged member count: $(ar -t "$LIB" | wc -l | tr -d ' ')"
echo "    capi in merged: $(ar -t "$LIB" | grep onnxruntime_c_api | head -5 || echo NOT FOUND)"
# Extract the stored capi member and nm it directly — does the stored copy still define T?
XDIR="$TMP/xcheck"; mkdir -p "$XDIR"
(cd "$XDIR" && ar -x "$LIB" 0000_onnxruntime_c_api.cc.o 2>/dev/null)
echo "    extracted capi size: $(wc -c < "$XDIR/0000_onnxruntime_c_api.cc.o" 2>/dev/null || echo missing)"
echo "    extracted capi nm: $(nm "$XDIR/0000_onnxruntime_c_api.cc.o" 2>/dev/null | grep OrtGetApiBase | head -3 || echo NOT FOUND)"
# Also try nm -arch arm64 on the merged lib in case nm defaults to wrong arch
echo "    nm -arch arm64 merged: $(nm -arch arm64 "$LIB" 2>/dev/null | grep OrtGetApiBase | head -5 || echo NOT FOUND)"
echo "    nm OrtGetApiBase in merged: $(nm "$LIB" 2>/dev/null | grep OrtGetApiBase | head -5 || echo NOT FOUND)"

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
