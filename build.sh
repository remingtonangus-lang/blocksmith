#!/bin/bash
# Builds build/Blocksmith.app with the Command Line Tools (no Xcode needed).
#   ./build.sh            optimized build
#   ./build.sh debug      debug build (faster compile, asserts on)
#   ./build.sh fast       unoptimized, no debug info, parallel compile (CI fast lane)
#   BLOCKSMITH_APP=build/debug/Blocksmith.app ./build.sh debug   somewhere else (CI's debug reruns: rebuilding the
#   release app over the debug one afterwards ran out of the smoke step's time, and the benchmarks then measured the
#   debug binary: run 371)
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-release}"
APP="${BLOCKSMITH_APP:-build/Blocksmith.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Debug: line tables only and one module object (-wmo), so the link stays small on CI runners (full -g over ~250
# files failed to link there); enough for lldb backtraces with file:line.
# EXTRA_SWIFTC_FLAGS: CI adds a slow type-check warning (-warn-long-expression-type-checking), reported as warnings.
FRAMEWORKS="-framework Metal -framework MetalKit -framework AppKit -framework GameController -framework AVFoundation"
if [ "$MODE" = "fast" ]; then
  # Fast: the CI fast lane. Unoptimized, no debug info, files compiled in parallel batches into build/obj, then linked
  # (a one-step batch build lost its temporary objects before the link on the runner).
  OBJ=build/obj; rm -rf "$OBJ"; mkdir -p "$OBJ"
  SRC=$(pwd)/Sources
  (cd "$OBJ" && xcrun swiftc -c -Onone -gnone -enable-batch-mode -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" ${EXTRA_SWIFTC_FLAGS:-} \
    -swift-version 5 -target arm64-apple-macos13.0 -module-name Blocksmith "$SRC"/*.swift)
  xcrun swiftc -target arm64-apple-macos13.0 $FRAMEWORKS "$OBJ"/*.o -o "$APP/Contents/MacOS/Blocksmith"
else
  if [ "$MODE" = "debug" ]; then OPT="-Onone -gline-tables-only -wmo"; else OPT="-Ounchecked -wmo"; fi
  xcrun swiftc $OPT ${EXTRA_SWIFTC_FLAGS:-} -swift-version 5 -target arm64-apple-macos13.0 -module-name Blocksmith \
    $FRAMEWORKS Sources/*.swift -o "$APP/Contents/MacOS/Blocksmith"
fi
cp Info.plist "$APP/Contents/Info.plist"
# Imported block textures (tools/teximport.py); each replaces that texture's procedural material.
rm -rf "$APP/Contents/Resources/Textures"
if [ -d Resources/Textures ]; then cp -R Resources/Textures "$APP/Contents/Resources/Textures"; fi
# Commit id for Bug Notes entries (BugNotes.build).
/usr/libexec/PlistBuddy -c "Add :BlocksmithCommit string $(git rev-parse --short HEAD 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP ($MODE)"
