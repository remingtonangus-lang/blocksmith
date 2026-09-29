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
"$BIN" --snapshot snaps/forest.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22
"$BIN" --snapshot snaps/forest_in.png --seed 12345 --find forest --yaw 120 --pitch -5 --time 0.22 --up 1
"$BIN" --snapshot snaps/snowy.png   --seed 12345 --find snowy  --yaw 60 --pitch -25 --time 0.22 --up 20
"$BIN" --snapshot snaps/meadow.png  --seed 12345 --find plains --yaw 200 --pitch -18 --time 0.2 --up 1
"$BIN" --snapshot snaps/stars.png   --seed 12345 --yaw 90  --pitch 35  --time 0.8 --up 5
"$BIN" --snapshot snaps/clouds.png  --seed 12345 --yaw 150 --pitch 18  --time 0.3 --up 5
