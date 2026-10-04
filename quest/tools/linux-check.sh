#!/bin/bash
# Type-checks / builds the Quest port's Swift code on a Linux host toolchain (no Android SDK needed): the shim
# modules, the shared game sources (minus the Mac platform files listed in quest/mac-only.txt) and quest/src.
#   quest/tools/linux-check.sh            type-check only
#   quest/tools/linux-check.sh build      build build/quest-linux/questcheck (runs the headless tests)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/quest-linux; mkdir -p "$OUT"
MODE="${1:-typecheck}"
OPT="${QUEST_OPT:--Onone}"
for m in simd os Metal; do
  swiftc -parse-as-library -swift-version 5 $OPT -module-name $m -emit-module -emit-module-path "$OUT/$m.swiftmodule" \
    -emit-library -static -o "$OUT/lib$m.a" -I "$OUT" quest/shims/$m/*.swift
done
SRCS=$(quest/tools/sources.sh)
if [ "$MODE" = typecheck ]; then
  swiftc -typecheck -swift-version 5 -module-name Blocksmith -I "$OUT" -I quest/c/CZlib -D QUEST_HEADLESS $SRCS quest/src/common/*.swift quest/src/headless/*.swift
else
  swiftc $OPT -swift-version 5 -module-name Blocksmith -I "$OUT" -L "$OUT" -lsimd -los -lMetal -I quest/c/CZlib -D QUEST_HEADLESS \
    $SRCS quest/src/common/*.swift quest/src/headless/*.swift -o "$OUT/questcheck"
fi
