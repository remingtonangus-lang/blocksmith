#!/bin/bash
# Type-checks / builds the Quest port's Swift code on a Linux host toolchain (no Android SDK needed): the shim
# modules, the shared game sources (minus the Mac platform files listed in quest/mac-only.txt), quest/src (common,
# vk, test, headless) and the generated HUD/shader files. Needs Vulkan headers + glslangValidator (or glslc).
#   quest/tools/linux-check.sh            type-check only
#   quest/tools/linux-check.sh build      build build/quest-linux/questcheck (headless tests; --render needs a
#                                         Vulkan driver, e.g. lavapipe)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/quest-linux; GEN=build/quest-gen; mkdir -p "$OUT" "$GEN"
MODE="${1:-typecheck}"
# IP: no flagged coined names (UNSC, MAC, ...; tools/coined-terms.txt) in player-visible strings (docs/status/ip-renames.md).
python3 tools/namecheck.py --coined
OPT="${QUEST_OPT:--Onone}"
# An optimized host build compiles like the APK (build-apk.sh: one whole module, exclusivity unchecked): file by file,
# nothing crossed a file (no inlining of Math.swift's hashes, a once-check on every read of a global like CH or AIR),
# and host profiles blamed costs the headset never pays. QUEST_FAST=1: file by file anyway.
case "$OPT" in *-Onone*|*-wmo*) ;; *-O*) [ "${QUEST_FAST:-0}" = 1 ] || OPT="$OPT -wmo -enforce-exclusivity=unchecked" ;; esac
python3 quest/tools/extract_hud.py "$GEN/HudGenerated.swift" >/dev/null
python3 quest/tools/shaders.py "$GEN/QuestSPIRV.swift" >/dev/null
for m in simd os Metal; do
  swiftc -parse-as-library -swift-version 5 $OPT -module-name $m -emit-module -emit-module-path "$OUT/$m.swiftmodule" \
    -emit-library -static -o "$OUT/lib$m.a" -I "$OUT" quest/shims/$m/*.swift
done
SRCS="$(quest/tools/sources.sh) $(ls quest/src/common/*.swift quest/src/vk/*.swift quest/src/xr/*.swift quest/src/app/*.swift quest/src/test/*.swift quest/src/headless/*.swift) $GEN/HudGenerated.swift $GEN/QuestSPIRV.swift"
INC="-I $OUT -I quest/c/CZlib -I quest/c/CVulkan -I quest/c/COpenXR -Xcc -I${OPENXR_INCLUDE:-/opt/openxr/include}"
if [ "$MODE" = typecheck ]; then
  swiftc -typecheck -swift-version 5 -module-name Blocksmith $INC -D QUEST_HEADLESS $SRCS
else
  swiftc $OPT -swift-version 5 -module-name Blocksmith $INC -L "$OUT" -lsimd -los -lMetal -D QUEST_HEADLESS $SRCS -o "$OUT/questcheck"
fi
