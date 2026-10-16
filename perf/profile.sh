#!/bin/bash
# CPU profile of one bench scene with macOS `sample` (all threads, 1 ms interval).
#   perf/profile.sh flight16 [seconds]   -> snaps/profile_flight16.txt, prints the hottest functions
set -uo pipefail
cd "$(dirname "$0")/.."
SCENE="${1:-flight16}"; SECS="${2:-10}"
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
OUT="snaps/profile_$SCENE.txt"
mkdir -p snaps
"$BIN" --bench "snaps/prof_$SCENE.json" --scenes "$SCENE" > "snaps/prof_$SCENE.log" 2>&1 &
PID=$!
sleep 2
sample "$PID" "$SECS" 1 -file "$OUT" > /dev/null 2>&1 || true
wait "$PID" || true
echo "== $SCENE: hottest functions (samples at top of stack, all threads) =="
# The report ends with "Sort by top of stack, same collapsed (when >= 5):" followed by "  symbol  (in image)  count".
awk '/Sort by top of stack/{on=1; next} /^Binary Images/{exit} on && NF' "$OUT" | head -45 || true
