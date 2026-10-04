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
OPT="${QUEST_OPT:--Onone}"
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
