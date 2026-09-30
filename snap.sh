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
"$BIN" --snapshot snaps/clouds.png  --seed 12345 --yaw 150 --pitch 28  --time 0.3 --up 5
"$BIN" --snapshot snaps/torches.png --seed 12345 --yaw 0 --pitch -35 --time 0.75 --up 6 --torches
"$BIN" --snapshot snaps/torches_near.png --seed 12345 --yaw 20 --pitch -50 --time 0.75 --up 3 --torches
"$BIN" --snapshot snaps/water_flow.png --seed 12345 --yaw 10 --pitch -40 --time 0.25 --up 7 --flood
"$BIN" --snapshot snaps/inventory.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu inventory --slot 3
"$BIN" --snapshot snaps/creative.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu creative
"$BIN" --snapshot snaps/crafting.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu crafting
"$BIN" --snapshot snaps/furnace.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu furnace
"$BIN" --snapshot snaps/drops.png --seed 12345 --yaw 30 --pitch -30 --time 0.22 --up 1 --drops
"$BIN" --snapshot snaps/survival.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --survival 13 --slot 8 --debug
"$BIN" --snapshot snaps/sim.png --seed 12345 --sim 12 --yaw 30 --pitch -10 --time 0.25
"$BIN" --sounds snaps/sounds
"$BIN" --snapshot snaps/mobs.png --seed 12345 --yaw 30 --pitch -14 --time 0.22 --up 1 --mobs
"$BIN" --snapshot snaps/hostile.png --seed 12345 --yaw 30 --pitch -12 --time 0.22 --up 1 --mobs --hostile
"$BIN" --snapshot snaps/nether.png --seed 12345 --dim nether --yaw 30 --pitch -10 --up 2
"$BIN" --snapshot snaps/nether_wide.png --seed 12345 --dim nether --x 300 --z -200 --yaw 200 --pitch -5 --up 6
"$BIN" --snapshot snaps/fortress.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -25 --rd 6
"$BIN" --snapshot snaps/fortress_far.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -30 --up 20 --rd 8
"$BIN" --snapshot snaps/portal.png --seed 12345 --yaw 30 --pitch -5 --time 0.3 --up 1 --portal
