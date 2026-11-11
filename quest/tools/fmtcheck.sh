#!/bin/bash
# Checks every String(format:) against its arguments' types (quest/tools/fmtcheck.py). Needs the host Swift toolchain
# and the shim modules linux-check.sh builds (build/quest-linux/*.swiftmodule). About a minute.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/quest-linux; GEN=build/quest-gen; mkdir -p "$GEN"
python3 quest/tools/extract_hud.py "$GEN/HudGenerated.swift" >/dev/null
python3 quest/tools/shaders.py "$GEN/QuestSPIRV.swift" >/dev/null
LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
for f in $(quest/tools/sources.sh) $(ls quest/src/common/*.swift quest/src/vk/*.swift quest/src/xr/*.swift quest/src/app/*.swift quest/src/test/*.swift quest/src/headless/*.swift) $GEN/HudGenerated.swift $GEN/QuestSPIRV.swift; do echo "$f"; done > "$LIST"
PRIM=$(grep -l "String(format:\|appendingFormat" $(cat "$LIST") | sed 's/^/-primary-file /' | tr '\n' ' ')
# (the tree runs to gigabytes: streamed, never written)
swift-frontend -frontend -dump-ast -filelist "$LIST" $PRIM -I $OUT -I quest/c/CZlib -I quest/c/CVulkan -I quest/c/COpenXR \
  -Xcc -I${OPENXR_INCLUDE:-/opt/openxr/include} -swift-version 5 -D QUEST_HEADLESS -module-name Blocksmith 2>/dev/null | python3 quest/tools/fmtcheck.py
