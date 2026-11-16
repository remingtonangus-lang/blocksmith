#!/bin/bash
# Incremental host build of questcheck: only the sources that changed (and the files that depend on what changed)
# recompile; object files and dependency records stay in a kept build dir per worktree and per optimization level.
# The full whole-module optimized build (quest/tools/linux-check.sh build with QUEST_OPT=-Ounchecked) stays the one
# the final suite and every timing runs on; this is for proving a change quickly.
#
#   tools/qbuild.sh [onone|o|ounchecked]   default onone; prints the binary's path last
#
# Output: build/quest-inc-<mode>/questcheck. Kept dirs: build/quest-inc-<mode>/{obj,...}. Delete the dir to start clean.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
eval "$(tools/cloud-setup.sh env)"
MODE="${1:-onone}"
case "$MODE" in
  onone) OPT="-Onone" ;;
  o) OPT="-O -enforce-exclusivity=unchecked" ;;
  ounchecked) OPT="-Ounchecked -enforce-exclusivity=unchecked" ;;
  *) echo "qbuild.sh: mode is onone, o or ounchecked"; exit 2 ;;
esac
B="build/quest-inc-$MODE"; mkdir -p "$B/obj" "$B/gen" "$B/shims"
t0=$SECONDS

python3 tools/namecheck.py --coined
# Generated files: write aside, copy over only when they changed, so an unchanged file keeps its date and stays built.
python3 quest/tools/extract_hud.py "$B/gen/HudGenerated.swift.new" >/dev/null
python3 quest/tools/shaders.py "$B/gen/QuestSPIRV.swift.new" >/dev/null
python3 quest/tools/listchecks.py --swift "$B/gen/CheckList.swift"   # writes only when the list changed
for g in HudGenerated QuestSPIRV; do
  if cmp -s "$B/gen/$g.swift.new" "$B/gen/$g.swift"; then rm "$B/gen/$g.swift.new"; else mv "$B/gen/$g.swift.new" "$B/gen/$g.swift"; fi
done

# Shim modules (simd, os, Metal): rebuilt only when their sources change.
for m in simd os Metal; do
  stamp="$B/shims/$m.stamp"; sum=$(cat quest/shims/$m/*.swift | sha1sum | cut -c1-40)
  if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$sum" ] || [ ! -f "$B/shims/lib$m.a" ]; then
    swiftc -parse-as-library -swift-version 5 $OPT -module-name $m -emit-module -emit-module-path "$B/shims/$m.swiftmodule" \
      -emit-library -static -o "$B/shims/lib$m.a" -I "$B/shims" quest/shims/$m/*.swift
    echo "$sum" > "$stamp"
  fi
done

SRCS="$(quest/tools/sources.sh) $(ls quest/src/common/*.swift quest/src/vk/*.swift quest/src/xr/*.swift quest/src/app/*.swift quest/src/test/*.swift quest/src/headless/*.swift) $B/gen/HudGenerated.swift $B/gen/QuestSPIRV.swift $B/gen/CheckList.swift"
# The output file map: one object + dependency record per source, keyed by the path as passed.
python3 - "$B" $SRCS > "$B/ofm.json.new" <<'EOF'
import json, sys, os
b = sys.argv[1]; m = {"": {"swift-dependencies": f"{b}/obj/master.swiftdeps"}}
for s in sys.argv[2:]:
    n = s.replace("/", "_")[:-6]
    o = f"{b}/obj/{n}"
    m[s] = {"object": o + ".o", "swift-dependencies": o + ".swiftdeps", "dependencies": o + ".d", "diagnostics": o + ".dia"}
json.dump(m, sys.stdout, indent=0)
EOF
if cmp -s "$B/ofm.json.new" "$B/ofm.json"; then rm "$B/ofm.json.new"; else mv "$B/ofm.json.new" "$B/ofm.json"; fi

INC="-I $B/shims -I quest/c/CZlib -I quest/c/CVulkan -I quest/c/COpenXR -Xcc -I${OPENXR_INCLUDE:-/opt/openxr/include}"
JOBS="${QBUILD_JOBS:-$(nproc)}"
swiftc $OPT -swift-version 5 -module-name Blocksmith $INC -L "$B/shims" -lsimd -los -lMetal -D QUEST_HEADLESS \
  -incremental -enable-batch-mode -j "$JOBS" -output-file-map "$B/ofm.json" -emit-dependencies \
  ${QBUILD_FLAGS:-} $SRCS -o "$B/questcheck"
echo "qbuild: $MODE built in $((SECONDS - t0)) s"
echo "$ROOT/$B/questcheck"
