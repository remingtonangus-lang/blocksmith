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
play() {
  # "24f" = render distance 24 with Fast graphics (separates the Fancy HDR path from the distance).
  if [ "${1%f}" != "$1" ]; then "$BIN" --smoke "$SECS" --rd "${1%f}" --fast; else "$BIN" --smoke "$SECS" --rd "$1"; fi
}
for rd in $RDS; do
  play "$rd" 2>&1 | tee snaps/smoke_run.log
  rc=${PIPESTATUS[0]}
  # The CI runners' virtual GPU driver (AppleParavirtCommandBuffer) sometimes aborts on its own command storage
  # assertion at rd 24 Fancy (runs 354, 362, 371; the lldb rerun of the same scene passed each time). It does not
  # exist on a real Mac: that one signature gets up to two retries; anything else, or a third abort, fails.
  for retry in 1 2; do
    [ $rc -ne 0 ] && grep -q "AppleParavirtCommandBuffer" snaps/smoke_run.log || break
    echo "smoke rd $rd: exit $rc on the virtual GPU driver's command-storage assertion; retry $retry"
    play "$rd" 2>&1 | tee snaps/smoke_run.log
    rc=${PIPESTATUS[0]}
  done
  if [ $rc -ne 0 ]; then
    echo "smoke rd $rd: exit $rc"
    FAILED+=("$rd")
  fi
done
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "smoke: failed at render distance ${FAILED[*]}; rerunning the first under lldb (debug build)"
  # Show every error / linker line of a failed debug build (a plain tail hid the ld message).
  # Into its own app bundle: the release app stays in place for the steps after this one.
  DBG=build/debug/Blocksmith.app
  if ! BLOCKSMITH_APP=$DBG bash ./build.sh debug > debugbuild.log 2>&1; then
    echo "smoke: debug build failed:"; grep -E "error|ld:|Undefined|duplicate|symbol|warning: unable" debugbuild.log | head -60
    tail -20 debugbuild.log
  fi
  rd0="${FAILED[0]}"; extra=""; if [ "${rd0%f}" != "$rd0" ]; then extra="--fast"; rd0="${rd0%f}"; fi
  lldb --batch -o run -o 'bt 40' -o 'thread backtrace all' -- "$DBG/Contents/MacOS/Blocksmith" --smoke "$SECS" --rd "$rd0" $extra 2>&1 | tail -200
  exit 1
fi
echo "smoke: PASS at render distance $RDS"
