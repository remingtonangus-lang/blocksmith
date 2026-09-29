#!/bin/bash
# Test harness: renders headless snapshots to snaps/ and prints timings.
#   ./snap.sh                  default set of views
#   ./snap.sh name [args...]   one shot, e.g. ./snap.sh cave --x 100 --z 40 --pitch -60
set -euo pipefail
cd "$(dirname "$0")"
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
mkdir -p snaps
if [ $# -gt 0 ]; then n="$1"; shift; "$BIN" --snapshot "snaps/$n.png" "$@"; exit; fi
"$BIN" --snapshot snaps/spawn.png   --seed 12345 --yaw 30  --pitch -12 --time 0.2
"$BIN" --snapshot snaps/aerial.png  --seed 12345 --yaw 200 --pitch -35 --time 0.25 --up 45 --rd 12
"$BIN" --snapshot snaps/sunset.png  --seed 12345 --yaw 270 --pitch 0   --time 0.47 --up 10
"$BIN" --snapshot snaps/night.png   --seed 12345 --yaw 90  --pitch -10 --time 0.75 --up 5
"$BIN" --snapshot snaps/down.png    --seed 12345 --yaw 0   --pitch -80 --time 0.25 --up 3
