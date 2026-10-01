#!/bin/bash
# Launch-and-play smoke test: plays the built app headless for N seconds (default 60) at render
# distances 8, 16 and 24 (Sources/Smoke.swift), each in its own process. A crashed or failed run is
# rerun once in a debug build under lldb for a backtrace; the script fails if any distance failed.
#   ./smoke.sh            60 s at 8, 16 and 24
#   ./smoke.sh 20 24      20 s at render distance 24 only
set -uo pipefail
cd "$(dirname "$0")"
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
SECS="${1:-60}"; shift || true
RDS="${*:-8 16 24 24f}"
mkdir -p snaps
FAILED=()
for rd in $RDS; do
  # "24f" = render distance 24 with Fast graphics (separates the Fancy HDR path from the distance).
  if [ "${rd%f}" != "$rd" ]; then "$BIN" --smoke "$SECS" --rd "${rd%f}" --fast; else "$BIN" --smoke "$SECS" --rd "$rd"; fi
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "smoke rd $rd: exit $rc"
    FAILED+=("$rd")
  fi
done
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "smoke: failed at render distance ${FAILED[*]}; rerunning the first under lldb (debug build)"
  bash ./build.sh debug 2>&1 | tail -30
  rd0="${FAILED[0]}"; extra=""; if [ "${rd0%f}" != "$rd0" ]; then extra="--fast"; rd0="${rd0%f}"; fi
  lldb --batch -o run -o 'bt 40' -o 'thread backtrace all' -- "$BIN" --smoke "$SECS" --rd "$rd0" $extra 2>&1 | tail -200
  bash ./build.sh 2>&1 | tail -1
  exit 1
fi
echo "smoke: PASS at render distance $RDS"
