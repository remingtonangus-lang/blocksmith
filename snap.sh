#!/bin/bash
# Test harness: renders headless snapshots to snaps/ and prints timings.
#   ./snap.sh                  default set of views
#   ./snap.sh name [args...]   one shot, e.g. ./snap.sh cave --x 100 --z 40 --pitch -60
set -euo pipefail
cd "$(dirname "$0")"
# A failing shot names its line (the CI debug step reruns that line under lldb).
trap 'echo "snap.sh: line $LINENO: exit $?" >&2' ERR
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
mkdir -p snaps
if [ $# -eq 0 ]; then rm -f snaps/imagecheck.log; fi
if [ $# -gt 0 ]; then n="$1"; shift; "$BIN" --snapshot "snaps/$n.png" "$@"; exit; fi
# Full run: a failing shot or test is recorded and the rest still run; the script fails at the end.
set +e
FAILED=()
trap 'rc=$?; FAILED+=("$LINENO"); echo "snap.sh: line $LINENO: failed (exit $rc)"' ERR
# Shards (CI heavy lane runs them as parallel jobs): SNAP_SHARD=checks | tours | shots; unset runs all three.
SHARD="${SNAP_SHARD:-all}"
on() { [ "$SHARD" = all ] || [ "$SHARD" = "$1" ]; }
if on checks; then
# Audio (first, so the sound and music checks always run): every sound is rendered and checked into build/sounds (not published); a sampler, the soundscapes
# and 10 s of every music mood go to snaps/sounds for listening on ci-snaps.
rm -rf build/sounds snaps/sounds; mkdir -p snaps/sounds
"$BIN" --sounds build/sounds
for f in step_stone step_wood step_gravel break_glass break_wood place_metal doorOpen chestOpen pistonExtend lever explode thunder \
         mob_cow_ambient mob_zombie_ambient mob_skeleton_hurt mob_enderman_ambient mob_ghast_ambient mob_villager_ambient mob_warden_death \
         dragonGrowl wardenRoar witherSpawn villager_work_0 birdCall owlHoot bell levelUp note_0_12 \
         gun_0 gun_1 gun_2 gun_3 gun_4 gun_5 gun_9 gun_10 gun_reload_0 gun_distant_0 bulletWhizz bullet_impact_metal soldier_1_alert soldier_3_death \
         engineFullLoop propFastLoop wingRushLoop frigateDroneLoop carriageTreadLoop hullCreak shipCollideHard waterfallLoop riverLoop mountainWindLoop thunderFar; do
  cp "build/sounds/$f.wav" snaps/sounds/ 2>/dev/null || true
done
cp -r build/sounds/scapes snaps/sounds/scapes
"$BIN" --music snaps/sounds/music --seconds 10
# The audio director (headless, record mode): vehicle, vessel, terrain and weather loops, and combat music.
"$BIN" --snapshot snaps/audiotest.png --seed 12345 --time 0.3 --rd 6 --audiotest

# Terrain: top-down maps of five seeds (8 km square, spawn marked), neighbour check, chunk generation timing.
"$BIN" --terrainmap snaps
"$BIN" --genbench --seed 12345
"$BIN" --kelpcheck --seed 777 --x 600 --z 300 --radius 18
# Structure walkability: every structure kind in every dimension, 3 seeds x 3 instances (report: snaps/structcheck.md).
"$BIN" --structcheck --seeds 12345,777,424242 --per 3 --out snaps/structcheck.md
# Issue gallery: the first ten structcheck views, from the walk's closest cell toward an unreachable chest or bed.
k=0
grep -o 'view: `[^`]*`' snaps/structcheck.md 2>/dev/null | sed 's/^view: `//; s/`$//' | head -10 | while read -r v; do
  k=$((k + 1))
  # shellcheck disable=SC2086
  "$BIN" --snapshot "snaps/issue_$k.png" $v --rd 4 --nightvision || true      # underground views were black
done
# Bots playing the real Game.tick (Agent.swift): oracles every tick, replays for every finding (snaps/agent_*.md).
"$BIN" --behaviorsim --seeds 12345,777 --minutes 20 --out snaps/behaviorsim.md
"$BIN" --gencheck --seeds 12345,777,424242 --areas 6 --out snaps/gencheck.md
# Leak gallery: the first two gencheck leaks, seen from a little above (gencheck_leak_N.png).
k=0
grep '\*\*leak\*\*' snaps/gencheck.md 2>/dev/null | grep -o '`--snapshot [^`]*`' | sed 's/^`--snapshot [^ ]* //; s/`$//' | head -2 | while read -r v; do
  k=$((k + 1))
  # shellcheck disable=SC2086
  "$BIN" --snapshot "snaps/gencheck_leak_$k.png" $v --rd 4 || true
done
"$BIN" --collisiontest --out snaps/collisiontest.md
"$BIN" --agent village --seeds 12345,777,424242 --ticks 4800 --out snaps
"$BIN" --agent explorer --seeds 12345,777 --ticks 3600 --out snaps
"$BIN" --agent life --seeds 12345,777 --ticks 6600 --out snaps
"$BIN" --agent cave --seeds 12345,777,424242 --ticks 14400 --out snaps      # 4 min: room to walk on and search again
"$BIN" --agent monkey --seeds 12345,424242,777,31337 --runs 3 --ticks 7200 --minimize --out snaps
# Replay determinism: the same recording played in two separate processes must end in the same state.
R=$(ls snaps/replay_*.jsonl 2>/dev/null | grep -v replay_min | head -1 || true)
if [ -n "$R" ]; then
  H1=$("$BIN" --agent replay "$R" | grep -o "end-state hash [0-9]*" || true)
  H2=$("$BIN" --agent replay "$R" | grep -o "end-state hash [0-9]*" || true)
  if [ -n "$H1" ] && [ "$H1" = "$H2" ]; then echo "replay determinism: same ($H1, $R)"; else echo "replay determinism: DIFFERENT ($H1 vs $H2, $R)"; fi
fi
fi
if on tours; then
# Far-ocean kelp streaks in tour_777_aerial: the same view in Fast graphics and at render distance 8 (no far LOD).
"$BIN" --snapshot snaps/tour_777_aerial_fast.png --seed 777 --x 600 --z 300 --onland --yaw 200 --pitch -28 --time 0.23 --up 55 --rd 16 --fast
"$BIN" --snapshot snaps/tour_777_aerial_nocull.png --seed 777 --x 600 --z 300 --onland --yaw 200 --pitch -28 --time 0.23 --up 55 --rd 16 --nocull
# Terrain tours: high aerial, mountain range, river valley and ground level for several seeds.
for s in 12345 777 424242 1 98765; do
  "$BIN" --snapshot snaps/tour_${s}_aerial.png --seed $s --x 600 --z 300 --onland --yaw 200 --pitch -28 --time 0.23 --up 55 --rd 16
  "$BIN" --snapshot snaps/tour_${s}_low.png --seed $s --yaw 120 --pitch -6 --time 0.22 --up 14 --rd 12
done
"$BIN" --snapshot snaps/tour_peaks.png --seed 12345 --find jagged_peaks --yaw 60 --pitch -22 --time 0.23 --up 25 --rd 16 || true
"$BIN" --snapshot snaps/tour_forest_floor.png --seed 12345 --find forest --yaw 30 --pitch 0 --time 0.22 --ground --up 0.2 --rd 8 || true
"$BIN" --snapshot snaps/tour_desert.png --seed 12345 --find desert --yaw biome --pitch -15 --time 0.24 --up 20 --rd 12 --lodcheck || true
"$BIN" --snapshot snaps/cactus_mid.png --seed 12345 --find desert --yaw biome --pitch -4 --time 0.25 --up 2 --rd 8 --cactusprobe || true
"$BIN" --snapshot snaps/cactus_mid_fast.png --seed 12345 --find desert --yaw biome --pitch -4 --time 0.25 --up 2 --rd 8 --cactusprobe --fast || true
"$BIN" --snapshot snaps/cactus_far.png --seed 12345 --x -560 --z 1060 --yaw 0 --pitch -8 --time 0.25 --up 14 --rd 16 || true
"$BIN" --snapshot snaps/cactus_far_nolod.png --seed 12345 --x -560 --z 1060 --yaw 0 --pitch -8 --time 0.25 --up 14 --rd 16 --nolod || true
"$BIN" --snapshot snaps/tour_jungle.png --seed 424242 --find jungle --yaw 80 --pitch -10 --time 0.24 --up 12 --rd 12 || true
"$BIN" --snapshot snaps/tour_river.png --seed 12345 --find river --yaw 30 --pitch -35 --time 0.23 --up 30 --rd 12 || true
"$BIN" --snapshot snaps/tour_river_777.png --seed 777 --find river --yaw 30 --pitch -35 --time 0.23 --up 30 --rd 12 || true
"$BIN" --snapshot snaps/tour_lake.png --seed 12345 --feature lake --yaw 30 --pitch -35 --time 0.23 --up 40 --rd 12 || true
"$BIN" --snapshot snaps/tour_lake_424242.png --seed 424242 --feature lake --yaw 30 --pitch -35 --time 0.23 --up 40 --rd 12 || true
"$BIN" --snapshot snaps/tour_delta.png --seed 12345 --feature delta --yaw 0 --pitch -45 --time 0.23 --up 50 --rd 12 || true
"$BIN" --snapshot snaps/tour_delta_777.png --seed 777 --feature delta --yaw 0 --pitch -45 --time 0.23 --up 50 --rd 12 || true
"$BIN" --snapshot snaps/tour_mesa.png --seed 12345 --find badlands --yaw biome --pitch -25 --time 0.23 --up 35 --rd 12 || true
"$BIN" --snapshot snaps/tour_coast.png --seed 12345 --find beach --yaw 0 --pitch -25 --time 0.23 --up 30 --rd 12 || true
"$BIN" --snapshot snaps/tour_snowline.png --seed 424242 --find snowy_slopes --yaw 180 --pitch -25 --time 0.23 --up 2 --rd 16 || true
"$BIN" --snapshot snaps/spawn.png   --seed 12345 --yaw 30  --pitch -12 --time 0.2
"$BIN" --snapshot snaps/ship_boat.png --seed 12345 --find ocean --time 0.3 --ship boat
"$BIN" --snapshot snaps/ship_deck.png --seed 12345 --find ocean --time 0.3 --ship deck
"$BIN" --snapshot snaps/ship_airship.png --seed 12345 --find plains --time 0.3 --ship airship
"$BIN" --snapshot snaps/ship_car.png --seed 12345 --find plains --time 0.3 --ship car
"$BIN" --snapshot snaps/ship_plane.png --seed 12345 --find plains --time 0.3 --ship plane
"$BIN" --snapshot snaps/ship_gunboat.png --seed 12345 --find ocean --time 0.3 --ship gunboat
"$BIN" --snapshot snaps/ship_frigate.png --seed 12345 --find plains --time 0.3 --rd 10 --ship frigate
"$BIN" --snapshot snaps/ship_frigate_bow.png --seed 12345 --find plains --time 0.3 --rd 10 --ship frigate:bow
"$BIN" --snapshot snaps/ship_frigate_side.png --seed 12345 --find plains --time 0.3 --rd 10 --ship frigate:side
"$BIN" --snapshot snaps/ship_frigate_top.png --seed 12345 --find plains --time 0.3 --rd 10 --ship frigate:top
"$BIN" --snapshot snaps/ship_frigate_deck.png --seed 12345 --find plains --time 0.3 --rd 10 --ship frigate:deck
"$BIN" --snapshot snaps/ship_carriage.png --seed 12345 --find plains --time 0.3 --ship carriage
"$BIN" --snapshot snaps/ship_battle.png --seed 12345 --find plains --time 0.3 --rd 10 --ship battle
"$BIN" --snapshot snaps/physicstest.png --seed 12345 --time 0.3 --physicstest
"$BIN" --snapshot snaps/ship_warfrigate.png --seed 12345 --find plains --time 0.3 --rd 20 --ship warfrigate
"$BIN" --snapshot snaps/ship_crawler.png --seed 12345 --find plains --time 0.3 --rd 10 --ship crawler
"$BIN" --snapshot snaps/ship_capitalbattle.png --seed 12345 --find plains --time 0.3 --rd 16 --ship capitalbattle
"$BIN" --snapshot snaps/capitaltest.png --seed 12345 --find plains --time 0.3 --rd 12 --capitaltest || echo "::error::capitaltest failed (new: reported, not gating yet)"
"$BIN" --snapshot snaps/ridetest.png --seed 12345 --find plains --time 0.3 --rd 8 --ridetest || echo "::error::ridetest failed (new: reported, not gating yet)"
"$BIN" --snapshot snaps/aerial.png  --seed 12345 --yaw 200 --pitch -35 --time 0.25 --up 45 --rd 12
"$BIN" --snapshot snaps/aerial16.png --seed 12345 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/aerial16_fast.png --seed 12345 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16 --fast
"$BIN" --snapshot snaps/ground16.png --seed 12345 --yaw 200 --pitch -5 --time 0.3 --up 1 --rd 16 --w 1440 --h 900
"$BIN" --snapshot snaps/ground16_fast.png --seed 12345 --yaw 200 --pitch -5 --time 0.3 --up 1 --rd 16 --w 1440 --h 900 --fast
"$BIN" --snapshot snaps/aerial16_777.png --seed 777 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/ocean_night_777.png --seed 777 --yaw 200 --pitch -12 --time 0.8 --up 30 --rd 16
"$BIN" --snapshot snaps/ocean_night_777_fast.png --seed 777 --yaw 200 --pitch -12 --time 0.8 --up 30 --rd 16 --fast
"$BIN" --snapshot snaps/aerial16_424242.png --seed 424242 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/aerial24.png --seed 424242 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 24
"$BIN" --snapshot snaps/sunset.png  --seed 12345 --yaw 270 --pitch 0   --time 0.47 --up 10
"$BIN" --snapshot snaps/sunset_fast.png --seed 12345 --yaw 270 --pitch 0 --time 0.47 --up 10 --fast
"$BIN" --snapshot snaps/sunset_sun.png --seed 12345 --yaw 90 --pitch 4 --time 0.49 --up 10
"$BIN" --snapshot snaps/night.png   --seed 12345 --yaw 90  --pitch -10 --time 0.75 --up 5 --unblock
"$BIN" --snapshot snaps/lake.png --seed 12345 --find ocean --yaw 30 --pitch -6 --time 0.25 --up 2
"$BIN" --snapshot snaps/lake_glint.png --seed 12345 --find ocean --yaw 90 --pitch -5 --time 0.48 --up 2
"$BIN" --snapshot snaps/shore.png --seed 12345 --find beach --yaw 30 --pitch -30 --time 0.22 --up 4
"$BIN" --snapshot snaps/underwater_up.png --seed 12345 --find ocean --yaw 90 --pitch 45 --time 0.3 --underwater
"$BIN" --snapshot snaps/underwater.png --seed 12345 --find ocean --yaw 30 --pitch -10 --time 0.25 --underwater
"$BIN" --snapshot snaps/down.png    --seed 12345 --yaw 0   --pitch -80 --time 0.25 --up 3
"$BIN" --snapshot snaps/forest.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22
# Same view in Fast graphics (playtest QA: black blocks/holes seen in combined-build Fancy shots).
"$BIN" --snapshot snaps/forest_fast.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22 --fast
"$BIN" --snapshot snaps/forest_nocull.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22 --nocull
"$BIN" --snapshot snaps/forest_nobase.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22 --nobase
"$BIN" --snapshot snaps/forest_verify.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22 --verifyworld
"$BIN" --snapshot snaps/forest_in.png --seed 12345 --find forest --yaw 120 --pitch -5 --time 0.22 --ground --up 1   # under the canopy (it stood on the treetops)
"$BIN" --snapshot snaps/crack.png --seed 12345 --find forest --yaw 120 --pitch -50 --time 0.22 --ground --up 1.6 --crack 0.7
"$BIN" --snapshot snaps/snowy.png   --seed 12345 --find snowy_taiga --yaw 60 --pitch -25 --time 0.22 --up 20
for b in desert jungle badlands dark_forest cherry_grove jagged_peaks savanna swamp taiga warm_ocean birch_forest mangrove_swamp; do
  "$BIN" --snapshot snaps/biome_$b.png --seed 12345 --find $b --yaw biome --pitch -22 --time 0.22 --up 18 || true
done
"$BIN" --snapshot snaps/meadow.png  --seed 12345 --find plains --yaw 200 --pitch -18 --time 0.2 --up 1
"$BIN" --snapshot snaps/stars.png   --seed 12345 --yaw 90  --pitch 35  --time 0.8 --up 5
"$BIN" --snapshot snaps/clouds.png  --seed 12345 --yaw 150 --pitch 28  --time 0.3 --up 5
"$BIN" --snapshot snaps/torches.png --seed 12345 --find plains --yaw 0 --pitch -35 --time 0.75 --up 6 --torches
"$BIN" --snapshot snaps/torches_near.png --seed 12345 --find plains --yaw 20 --pitch -50 --time 0.75 --up 3 --torches --ambient
"$BIN" --snapshot snaps/torches_day.png --seed 12345 --find plains --yaw 20 --pitch -50 --time 0.3 --up 3 --torches
"$BIN" --snapshot snaps/water_flow.png --seed 12345 --yaw 10 --pitch -40 --time 0.25 --up 7 --flood
"$BIN" --snapshot snaps/inventory.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu inventory --slot 3
"$BIN" --snapshot snaps/creative.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu creative
"$BIN" --snapshot snaps/crafting.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu crafting
"$BIN" --snapshot snaps/bugnotes.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --bugnotetest
"$BIN" --snapshot snaps/padtest.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --padtest
"$BIN" --snapshot snaps/inventory_pad.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu inventory --slot 3 --pad
"$BIN" --snapshot snaps/tv_options.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --safe 5 --padview video
"$BIN" --snapshot snaps/tv_keyboard.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --padview keyboard
"$BIN" --snapshot snaps/tv_worlds.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --padview worlds
"$BIN" --snapshot snaps/tv_confirm.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --padview confirm
"$BIN" --snapshot snaps/tv_title.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --padview title
"$BIN" --snapshot snaps/padmap.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --padview padmap
"$BIN" --snapshot snaps/tv_combat.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --pad --padview combat
"$BIN" --snapshot snaps/vehicle_hud.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --pad --padview vehicle
"$BIN" --snapshot snaps/tv_map.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --pad --padview map
"$BIN" --snapshot snaps/controls_ref.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --padview controls
"$BIN" --snapshot snaps/tv_hud.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --w 1920 --h 1080 --couch --safe 5 --survival 13 --slot 2 --pad --hints
"$BIN" --snapshot snaps/furnace.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu furnace
"$BIN" --snapshot snaps/drops.png --seed 12345 --yaw 30 --pitch -30 --time 0.22 --up 1 --drops
"$BIN" --snapshot snaps/subtitles.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --subtitles
"$BIN" --snapshot snaps/survival.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --survival 13 --slot 8 --debug
"$BIN" --snapshot snaps/sim.png --seed 12345 --sim 12 --yaw 30 --pitch -10 --time 0.25
"$BIN" --atlas snaps/atlas
BLOCKSMITH_TEXRES=128 "$BIN" --hdatlas snaps/hdatlas.png
fi
if on shots; then
# Texture sources side by side (docs/textures): procedural vs the imported CC0 trial set at 128 px, same views.
# gemini: Remington's generated sheets run through tools/teximport.py (assets/gemini/processed, not adopted yet).
for SRC in procedural cc0 gemini; do
  if [ "$SRC" = procedural ]; then F="--procedural"; elif [ "$SRC" = gemini ]; then F="--texdir assets/gemini/processed"; else F="--texdir docs/textures/trials/$SRC"; fi
  BLOCKSMITH_TEXRES=128 "$BIN" --snapshot snaps/texsrc_${SRC}_forest.png --seed 12345 --find forest --yaw 30 --pitch -12 --time 0.22 --ground --up 1.6 --rd 8 $F || true
  BLOCKSMITH_TEXRES=128 "$BIN" --snapshot snaps/texsrc_${SRC}_cliff.png --seed 12345 --find stony_shore --yaw 120 --pitch -10 --time 0.22 --ground --up 1.6 --rd 8 $F || true
  BLOCKSMITH_TEXRES=128 "$BIN" --snapshot snaps/texsrc_${SRC}_village.png --seed 12345 --structure village --frame 0.6 --time 0.25 --rd 8 $F || true
done
"$BIN" --snapshot snaps/mobs.png --seed 12345 --yaw 30 --pitch -14 --time 0.22 --up 1 --mobs
"$BIN" --snapshot snaps/mob_shadows.png --seed 12345 --yaw 30 --pitch -14 --time 0.07 --up 1 --mobs
"$BIN" --snapshot snaps/hostile.png --seed 12345 --yaw 30 --pitch -12 --time 0.22 --up 1 --mobs --hostile
"$BIN" --snapshot snaps/nether.png --seed 12345 --dim nether --yaw 30 --pitch -10 --up 2 --ambient
"$BIN" --snapshot snaps/ember_crimson.png --seed 12345 --dim nether --find crimson_forest --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/ember_warped.png --seed 12345 --dim nether --find warped_forest --yaw 210 --pitch -12 --up 6 --ambient
"$BIN" --snapshot snaps/ember_soul.png --seed 12345 --dim nether --find soul_sand_valley --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/ember_basalt.png --seed 12345 --dim nether --find basalt_deltas --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/nether_wide.png --seed 12345 --dim nether --x 300 --z -200 --yaw 200 --pitch -5 --up 6 --ambient
"$BIN" --snapshot snaps/fortress.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -8 --up 1 --rd 6
"$BIN" --snapshot snaps/fortress_far.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -35 --up 9 --rd 8
"$BIN" --snapshot snaps/nether_mobs.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -2 --up 1 --rd 6 --mobs --nethermobs
"$BIN" --snapshot snaps/bastion.png --seed 12345 --dim nether --structure bastion --yaw 150 --pitch -10 --up 1 --rd 6
"$BIN" --snapshot snaps/bastion_far.png --seed 12345 --dim nether --structure bastion --yaw 150 --pitch -35 --up 14 --rd 8
"$BIN" --snapshot snaps/citadel_far.png --seed 12345 --structure military_base --frame 1.1 --time 0.3 --rd 12
"$BIN" --snapshot snaps/citadel_gate.png --seed 12345 --structure military_base --yaw 0 --pitch 12 --up 1 --time 0.3 --rd 10
"$BIN" --snapshot snaps/citadel_top.png --seed 12345 --structure military_base --yaw 20 --pitch -45 --up 70 --time 0.3 --rd 10
"$BIN" --snapshot snaps/citadel_turret.png --seed 12345 --structure military_base --offset -12,7,-6 --yaw 52 --pitch -8 --time 0.3 --rd 10
"$BIN" --snapshot snaps/citadel_plaza.png --seed 12345 --structure military_base --offset 3,6,-12 --yaw 10 --pitch 10 --time 0.3 --rd 10
"$BIN" --snapshot snaps/village.png --seed 12345 --structure village --yaw 45 --pitch -28 --up 14 --time 0.25
"$BIN" --snapshot snaps/village_top.png --seed 12345 --structure village --yaw 0 --pitch -89 --up 70 --time 0.25
"$BIN" --snapshot snaps/village2.png --seed 12345 --structure village --x 1500 --z -900 --yaw 45 --pitch -30 --up 16 --time 0.25
"$BIN" --snapshot snaps/village3.png --seed 12345 --structure village --x -1200 --z 600 --yaw 45 --pitch -30 --up 16 --time 0.25
"$BIN" --snapshot snaps/village_street.png --seed 12345 --structure village --yaw 135 --pitch -8 --up 1 --time 0.25 --rd 6
"$BIN" --snapshot snaps/temple.png --seed 12345 --structure temple --frame 1 --time 0.25
"$BIN" --snapshot snaps/temple2.png --seed 12345 --structure temple --x 3000 --z 3000 --frame 1 --time 0.25
"$BIN" --snapshot snaps/desert_temple.png --seed 12345 --structure temple --subkind desert_pyramid --frame 1.7 --time 0.25
"$BIN" --snapshot snaps/desert_temple_inside.png --seed 12345 --structure temple --subkind desert_pyramid --offset 0,0,9 --yaw 180 --pitch 12 --time 0.25
"$BIN" --snapshot snaps/jungle_temple.png --seed 12345 --structure temple --subkind jungle_temple --frame 1 --time 0.25
"$BIN" --snapshot snaps/outpost.png --seed 12345 --structure pillager_outpost --frame 1.2 --time 0.25
"$BIN" --snapshot snaps/outpost_close.png --seed 12345 --structure pillager_outpost --frame 0.5 --time 0.25
"$BIN" --snapshot snaps/snowslope.png --seed 12345 --find snowy_slopes --yaw 45 --pitch -35 --time 0.25 --up 6
"$BIN" --snapshot snaps/ruined_portal.png --seed 12345 --structure ruined_portal --land --frame 1 --time 0.25
"$BIN" --snapshot snaps/shipwreck.png --seed 12345 --structure shipwreck --frame 1 --time 0.25 --slice
# Small structures with no shot before (eyes-on coverage for the "everything similar" rework).
"$BIN" --snapshot snaps/desert_well.png --seed 12345 --structure desert_well --frame 0.7 --time 0.25 || true
"$BIN" --snapshot snaps/ocean_ruin.png --seed 12345 --structure ocean_ruin --frame 1 --time 0.25 || true
"$BIN" --snapshot snaps/trail_ruins.png --seed 12345 --structure trail_ruins --frame 1 --time 0.25 || true
"$BIN" --snapshot snaps/mineshaft.png --seed 12345 --structure mineshaft --frame 0.4 --time 0.25 --nightvision
"$BIN" --snapshot snaps/stronghold.png --seed 12345 --structure stronghold --yaw 180 --pitch 5 --up 0.5 --rd 4
"$BIN" --snapshot snaps/end.png --seed 12345 --dim end --x 70 --z 35 --yaw 63 --pitch 2 --up 16 --dragon
"$BIN" --snapshot snaps/end_top.png --seed 12345 --dim end --x 0 --z 60 --yaw 0 --pitch -45 --up 50
"$BIN" --snapshot snaps/end_outer.png --seed 12345 --dim end --x 1250 --z 40 --yaw 90 --pitch -15 --up 10
"$BIN" --snapshot snaps/end_city.png --seed 12345 --dim end --structure end_city --yaw 45 --pitch -18 --up 25 --rd 8
"$BIN" --snapshot snaps/portal.png --seed 12345 --yaw 30 --pitch -5 --time 0.3 --up 1 --portal
"$BIN" --snapshot snaps/redstone.png --seed 12345 --yaw 225 --pitch -38 --time 0.3 --up 7 --redstone
"$BIN" --snapshot snaps/brewing.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu brewing
"$BIN" --snapshot snaps/enchant.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu enchant
"$BIN" --snapshot snaps/anvil.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu anvil
"$BIN" --snapshot snaps/effects.png --seed 12345 --yaw 30 --pitch -12 --time 0.75 --effects --slot 2
"$BIN" --snapshot snaps/magic_blocks.png --seed 12345 --yaw 30 --pitch -25 --time 0.3 --up 1 --find plains --place brewing_stand:5,enchanting_table,beacon,anvil,chipped_anvil,water_cauldron:2,lava_cauldron,bookshelf
"$BIN" --snapshot snaps/trade.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu trade
"$BIN" --snapshot snaps/villagers.png --seed 12345 --structure village --frame 0.7 --time 0.3 --ticks 12
"$BIN" --snapshot snaps/mobs_g.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn wither,ravager,evoker,vex,snow_golem,zombie_villager,witch --stage
"$BIN" --snapshot snaps/villager_jobs.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn villager:farmer,villager:librarian,villager:cleric,villager:armorer,villager:butcher,villager:fisherman,villager:nitwit --stage
"$BIN" --snapshot snaps/hisser.png --seed 12345 --find plains --yaw 30 --pitch -6 --time 0.3 --up 1 --spawn creeper,creeper --stage
"$BIN" --snapshot snaps/heads.png --seed 12345 --find plains --yaw 30 --pitch -25 --time 0.3 --up 1 --place skeleton_skull,wither_skeleton_skull:1,zombie_head,creeper_head:1,piglin_head,dragon_head:1,carved_pumpkin,jack_o_lantern:1
"$BIN" --snapshot snaps/beacon.png --seed 12345 --find plains --yaw 30 --pitch 10 --time 0.55 --up 3 --beacon
"$BIN" --snapshot snaps/rain.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --weather rain
"$BIN" --snapshot snaps/thunder.png --seed 12345 --find plains --yaw 30 --pitch 5 --time 0.3 --up 1 --weather thunder
"$BIN" --snapshot snaps/snowfall.png --seed 12345 --find snowy_plains --yaw 30 --pitch -5 --time 0.3 --up 1 --weather rain
"$BIN" --snapshot snaps/animals1.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --spawn rabbit,fox,wolf,cat,horse,donkey,llama,goat,panda --stage
"$BIN" --snapshot snaps/animals2.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --spawn polar_bear,turtle,frog,armadillo,sniffer,mooshroom,camel,wandering_trader --stage
"$BIN" --snapshot snaps/animals3.png --seed 12345 --find plains --yaw 30 --pitch 0 --time 0.3 --up 1 --spawn bee,parrot,bat,allay,phantom,endermite,breeze,bogged,zoglin,warden --stage
"$BIN" --snapshot snaps/aquatic.png --seed 12345 --find warm_ocean --yaw 30 --pitch -30 --time 0.3 --up 1 --spawn squid,glow_squid,dolphin,cod,salmon,tropical_fish,pufferfish,axolotl,guardian,elder_guardian
"$BIN" --snapshot snaps/boats.png --seed 12345 --find ocean --yaw 30 --pitch -25 --time 0.3 --up 1 --ticks 3 --spawn boat:0,boat:1:c,boat:2,boat:3,boat:4:c,boat:5,boat:6,boat:7,boat:8:c
"$BIN" --snapshot snaps/armor.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn armor_stand:leather,armor_stand:golden,zombie:chainmail,skeleton:iron,armor_stand:diamond,husk:netherite,armor_stand --stage
"$BIN" --snapshot snaps/banners.png --seed 12345 --find plains --yaw 30 --pitch -22 --time 0.3 --up 3 --banners
"$BIN" --snapshot snaps/loom.png --seed 12345 --menu loom
"$BIN" --snapshot snaps/book.png --seed 12345 --menu book
"$BIN" --snapshot snaps/advancements.png --seed 12345 --menu advancements
"$BIN" --snapshot snaps/credits.png --seed 12345 --menu credits
"$BIN" --snapshot snaps/pause.png --seed 12345 --menu pause
"$BIN" --snapshot snaps/options.png --seed 12345 --menu options
"$BIN" --snapshot snaps/death.png --seed 12345 --menu death
"$BIN" --snapshot snaps/title.png --seed 12345 --menu title
"$BIN" --snapshot snaps/create.png --seed 12345 --menu create
"$BIN" --snapshot snaps/recipes.png --seed 12345 --menu recipes
"$BIN" --snapshot snaps/commands.png --seed 12345 --menu commands
"$BIN" --snapshot snaps/boom_night.png --seed 12345 --find plains --yaw 30 --pitch -15 --time 0.78 --up 2 --boom
"$BIN" --snapshot snaps/fireworks.png --seed 12345 --find plains --yaw 30 --pitch 20 --time 0.8 --up 1 --fireworks
"$BIN" --snapshot snaps/monument.png --seed 12345 --structure monument --frame 1 --time 0.25
"$BIN" --snapshot snaps/mansion.png --seed 12345 --structure mansion --frame 1.7 --time 0.25
# Inside: through the front door into the ground-floor hall (anchor is 6 blocks before the door).
"$BIN" --snapshot snaps/mansion_inside.png --seed 12345 --structure mansion --offset 0,0,9 --yaw 180 --pitch -8 --time 0.3
"$BIN" --snapshot snaps/ancient_city.png --seed 12345 --structure ancient_city --offset 0,13,-18 --yaw 180 --pitch -18 --rd 5 --nightvision
"$BIN" --snapshot snaps/trial_chambers.png --seed 12345 --structure trial_chambers --yaw 45 --pitch -25 --up 6 --rd 5
"$BIN" --snapshot snaps/copper.png --seed 12345 --find plains --yaw 30 --pitch -25 --time 0.3 --up 1 --place copper_block,exposed_copper,weathered_copper,oxidized_copper,cut_copper,copper_grate,copper_bulb:1,campfire,bee_nest:5,scaffolding --ambient
"$BIN" --snapshot snaps/decor.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --decor --listframes
"$BIN" --snapshot snaps/chips.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --chips
"$BIN" --snapshot snaps/map.png --seed 12345 --yaw 30 --pitch -10 --time 0.3 --up 20 --map
"$BIN" --snapshot snaps/third_back.png --seed 12345 --find plains --yaw 30 --pitch -15 --time 0.3 --up 1 --camera 1
"$BIN" --snapshot snaps/third_swim.png --seed 12345 --find ocean --yaw 30 --pitch -20 --time 0.3 --camera 1 --swim
"$BIN" --snapshot snaps/third_front.png --seed 12345 --find plains --yaw 30 --pitch 5 --time 0.3 --up 1 --camera 2
"$BIN" --snapshot snaps/mobs_new.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn zombie_horse,illusioner,happy_ghast,parched,camel_husk,nautilus,zombie_nautilus,skeleton --stage
"$BIN" --snapshot snaps/soldiers.png --seed 12345 --find plains --yaw 30 --pitch -18 --time 0.3 --up 1 --facecam --spawn soldier_recruit:aggro:0,soldier_recruit,soldier_trooper:aggro:2,soldier_marksman:aggro:3,soldier_ironclad:aggro:4,soldier_ironclad:aggro:5 --stage
# The Capital's six ranks (SoldierRig.swift): front, side and back by day and at night, stances, crew stations, a squad.
"$BIN" --snapshot snaps/soldier_ranks_front.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_recruit:0:back=0:turn=0,soldier_trooper:2:back=0:turn=0,soldier_marksman:3:back=0:turn=0,soldier_ironclad:4:back=0:turn=0,soldier_officer:6:back=0:turn=0,soldier_crew:6:back=0:turn=0
"$BIN" --snapshot snaps/soldier_ranks_side.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_recruit:0:back=0:turn=90,soldier_trooper:2:back=0:turn=90,soldier_marksman:3:back=0:turn=90,soldier_ironclad:4:back=0:turn=90,soldier_officer:6:back=0:turn=90,soldier_crew:6:back=0:turn=90
"$BIN" --snapshot snaps/soldier_ranks_back.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_recruit:0:back=0:turn=180,soldier_trooper:2:back=0:turn=180,soldier_marksman:3:back=0:turn=180,soldier_ironclad:4:back=0:turn=180,soldier_officer:6:back=0:turn=180,soldier_crew:6:back=0:turn=180
"$BIN" --snapshot snaps/soldier_ranks_night_front.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.75 --up 1 --rd 4 --facecam --stage --torches --spawn soldier_recruit:0:back=0:turn=0,soldier_trooper:2:back=0:turn=0,soldier_marksman:3:back=0:turn=0,soldier_ironclad:4:back=0:turn=0,soldier_officer:6:back=0:turn=0,soldier_crew:6:back=0:turn=0
"$BIN" --snapshot snaps/soldier_ranks_night_side.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.75 --up 1 --rd 4 --facecam --stage --torches --spawn soldier_recruit:0:back=0:turn=90,soldier_trooper:2:back=0:turn=90,soldier_marksman:3:back=0:turn=90,soldier_ironclad:4:back=0:turn=90,soldier_officer:6:back=0:turn=90,soldier_crew:6:back=0:turn=90
"$BIN" --snapshot snaps/soldier_ranks_night_back.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.75 --up 1 --rd 4 --facecam --stage --torches --spawn soldier_recruit:0:back=0:turn=180,soldier_trooper:2:back=0:turn=180,soldier_marksman:3:back=0:turn=180,soldier_ironclad:4:back=0:turn=180,soldier_officer:6:back=0:turn=180,soldier_crew:6:back=0:turn=180
"$BIN" --snapshot snaps/soldier_ranks_aim.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_recruit:0:back=0:turn=35:aim,soldier_trooper:2:back=0:turn=35:aim,soldier_marksman:3:back=0:turn=35:aim,soldier_ironclad:4:back=0:turn=35:aim,soldier_officer:6:back=0:turn=35:aim,soldier_crew:6:back=0:turn=35:aim
"$BIN" --snapshot snaps/soldier_actions.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_recruit:0:back=4:turn=55:aim,soldier_recruit:0:back=4:turn=55:fire,soldier_recruit:0:back=4:turn=55:reload=0.3,soldier_recruit:0:back=4:turn=55:reload=0.55,soldier_recruit:0:back=4:turn=55:throw=0.5,soldier_recruit:0:back=4:turn=55:march,soldier_recruit:0:back=4:turn=55:run,soldier_recruit:0:back=4:turn=55:rest
"$BIN" --snapshot snaps/soldier_actions_heavy.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_trooper:2:back=0:turn=55:aim,soldier_trooper:2:back=0:turn=55:reload=0.4,soldier_marksman:3:back=0:turn=55:aim,soldier_ironclad:4:back=0:turn=55:aim,soldier_ironclad:5:back=0:turn=55:fire,soldier_officer:6:back=0:turn=55:aim,soldier_officer:6:back=0:turn=55:point
"$BIN" --snapshot snaps/soldier_stations.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_crew:6:back=0:turn=60:seated,soldier_recruit:0:back=0:turn=60:passenger,soldier_crew:1:back=0:turn=60:gunner,soldier_crew:6:back=0:turn=60:console,soldier_recruit:0:back=0:turn=60:parade
"$BIN" --snapshot snaps/soldier_closeup.png --seed 12345 --find plains --yaw 30 --pitch -2 --time 0.3 --up 1 --rd 4 --facecam --stage --spawn soldier_officer:6:side=-0.7:back=-3.4:turn=-15,soldier_recruit:0:side=0.7:back=-3.4:turn=15
"$BIN" --snapshot snaps/soldier_squad.png --seed 12345 --structure military_base --yaw 0 --pitch -4 --up 1 --time 0.3 --rd 6 --facecam --spawnlevel --spawn soldier_officer:6:side=0:back=-1,soldier_recruit:0:side=-3.3:back=1.0,soldier_recruit:0:side=-1.1:back=1.0,soldier_recruit:0:side=1.1:back=1.0,soldier_recruit:0:side=3.3:back=1.0,soldier_trooper:2:side=-3.3:back=2.6,soldier_marksman:3:side=-1.1:back=2.6,soldier_trooper:2:side=1.1:back=2.6,soldier_marksman:3:side=3.3:back=2.6,soldier_ironclad:4:side=-5.6:back=1.8,soldier_crew:6:side=5.6:back=1.8:console
"$BIN" --snapshot snaps/soldier_squad_night.png --seed 12345 --structure military_base --yaw 0 --pitch -4 --up 1 --time 0.78 --rd 6 --facecam --torches --spawnlevel --spawn soldier_officer:6:side=0:back=-1,soldier_recruit:0:side=-3.3:back=1.0,soldier_recruit:0:side=-1.1:back=1.0,soldier_recruit:0:side=1.1:back=1.0,soldier_recruit:0:side=3.3:back=1.0,soldier_trooper:2:side=-3.3:back=2.6,soldier_marksman:3:side=-1.1:back=2.6,soldier_trooper:2:side=1.1:back=2.6,soldier_marksman:3:side=3.3:back=2.6,soldier_ironclad:4:side=-5.6:back=1.8,soldier_crew:6:side=5.6:back=1.8:console
"$BIN" --snapshot snaps/captains.png --seed 12345 --find plains --yaw 30 --pitch -15 --time 0.3 --up 1 --facecam --spawn pillager:captain,vindicator:captain,pillager --stage
"$BIN" --snapshot snaps/firefight.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --survival 20 --hold gun_smg --facecam --spawn soldier_trooper:aggro:0,soldier_recruit:aggro:1,soldier_ironclad:aggro:5 --fire 1.4 --stage
"$BIN" --snapshot snaps/deck_gun.png --seed 12345 --find plains --yaw 30 --pitch -32 --time 0.3 --up 5 --spawn deck_gun:aggro --stage
"$BIN" --snapshot snaps/spear_hold.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --survival 20 --hold copper_spear
"$BIN" --snapshot snaps/gun_hip.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --survival 20 --hold gun_rifle
"$BIN" --snapshot snaps/gun_aim.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --survival 20 --hold gun_shotgun:aim
"$BIN" --snapshot snaps/gun_scope.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --survival 20 --hold gun_sniper:aim
"$BIN" --snapshot snaps/steelhold.png --seed 12345 --structure military_base --frame 1 --time 0.3
"$BIN" --snapshot snaps/steelhold_gate.png --seed 12345 --structure military_base --yaw 0 --pitch 5 --time 0.3 --up 1
"$BIN" --snapshot snaps/steelhold_armory.png --seed 12345 --structure military_base --offset 14,0,-60 --yaw 0 --pitch 0 --time 0.3 --listframes
"$BIN" --snapshot snaps/steelhold_armory_swords.png --seed 12345 --structure military_base --offset 14,0,-60 --yaw 0 --pitch 0 --time 0.3 --listframes --framesword
# Frame bisection (armory items draw nowhere, the decor scene's do): Fast graphics, and 3 blocks closer.
"$BIN" --snapshot snaps/steelhold_armory_fast.png --seed 12345 --structure military_base --offset 14,0,-60 --yaw 0 --pitch 0 --time 0.3 --listframes --fast || true
"$BIN" --snapshot snaps/steelhold_armory_close.png --seed 12345 --structure military_base --offset 14,0,-63 --yaw 0 --pitch 0 --time 0.3 --listframes || true
"$BIN" --snapshot snaps/steelhold_fight.png --seed 12345 --structure military_base --offset 14,4,-60 --yaw 0 --pitch 0 --time 0.3 --fortresstest 20
"$BIN" --snapshot snaps/steelhold_command.png --seed 12345 --structure military_base --offset 0,6,-33 --yaw 0 --pitch -15 --time 0.3
"$BIN" --snapshot snaps/mobtests.png --seed 12345 --find plains --yaw 0 --pitch -30 --time 0.3 --up 3 --mobtests --posecheck
"$BIN" --snapshot snaps/pathtest.png --seed 12345 --find plains --yaw 0 --pitch -40 --time 0.75 --up 14 --pathtest
"$BIN" --snapshot snaps/ashen_grove.png --seed 12345 --find pale_garden --yaw 210 --pitch -20 --time 0.3 --up 4 --treecheck
"$BIN" --snapshot snaps/ashen_inside.png --seed 12345 --find pale_garden --yaw 120 --pitch 8 --time 0.3 --ground
"$BIN" --snapshot snaps/ashen_night.png --seed 12345 --find pale_garden --yaw 30 --pitch -10 --time 0.7 --up 2 --ticks 4 --place pale_oak_log,creaking_heart:1,pale_oak_planks,pale_moss_block,pale_moss_carpet,open_eyeblossom,closed_eyeblossom,pale_hanging_moss
"$BIN" --snapshot snaps/lush_caves.png --seed 12345 --find lush_caves --yaw 30 --pitch -10 --time 0.3
"$BIN" --snapshot snaps/dripstone_caves.png --seed 12345 --find dripstone_caves --yaw 30 --pitch -10 --time 0.3 --torches
"$BIN" --snapshot snaps/mineshaft_torches.png --seed 12345 --structure mineshaft --frame 0.4 --time 0.3 --torches --ambient
"$BIN" --snapshot snaps/deep_dark.png --seed 12345 --find deep_dark --yaw 30 --pitch -10 --time 0.3 --nightvision
"$BIN" --snapshot snaps/dark_forest.png --seed 12345 --find dark_forest --yaw 30 --pitch -15 --time 0.3 --up 4 --treecheck --unblock
"$BIN" --snapshot snaps/seabed_warm.png --seed 12345 --find warm_ocean --seabed 5 --pitch -20 --time 0.3
"$BIN" --snapshot snaps/seabed_deep.png --seed 12345 --find deep_ocean --seabed 5 --pitch -20 --time 0.3
"$BIN" --snapshot snaps/seabed_deep_far.png --seed 12345 --find deep_ocean --seabed 14 --pitch -30 --time 0.3
"$BIN" --snapshot snaps/cave_torches.png --seed 12345 --find dripstone_caves --yaw 60 --pitch -25 --time 0.3 --openview --torches
"$BIN" --snapshot snaps/in_lava.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --inlava
"$BIN" --snapshot snaps/spawn_portal_check.png --seed 12345 --rd 16 --up 2 --yaw 45 --pitch 20
"$BIN" --snapshot snaps/gallery_stone.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery stone,cobblestone,mossy_cobblestone,stone_bricks,mossy_stone_bricks,cracked_stone_bricks,smooth_stone,bricks,andesite,polished_andesite,diorite,polished_diorite,granite,polished_granite,tuff,calcite,deepslate,cobbled_deepslate,deepslate_bricks,deepslate_tiles,polished_deepslate,blackstone,basalt,obsidian
"$BIN" --snapshot snaps/gallery_wood.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery oak_planks,spruce_planks,birch_planks,jungle_planks,acacia_planks,dark_oak_planks,mangrove_planks,cherry_planks,oak_log,spruce_log,birch_log,jungle_log,acacia_log,dark_oak_log,mangrove_log,cherry_log,crimson_planks,warped_planks,bamboo_planks,pale_oak_planks,crimson_stem,warped_stem,bamboo_block,pale_oak_log
"$BIN" --snapshot snaps/gallery_ores.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery coal_ore,iron_ore,copper_ore,gold_ore,redstone_ore,emerald_ore,lapis_ore,diamond_ore,deepslate_coal_ore,deepslate_iron_ore,deepslate_copper_ore,deepslate_gold_ore,deepslate_redstone_ore,deepslate_emerald_ore,deepslate_lapis_ore,deepslate_diamond_ore,iron_block,gold_block,copper_block,diamond_block,emerald_block,lapis_block,redstone_block,netherite_block
"$BIN" --snapshot snaps/gallery_earth.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery grass_block,dirt,coarse_dirt,podzol,mycelium,rooted_dirt,mud,clay,sand,red_sand,gravel,snow_block,ice,packed_ice,blue_ice,terracotta,sandstone,red_sandstone,moss_block,pale_moss_block,netherrack,soul_sand,end_stone,glowstone
"$BIN" --snapshot snaps/gallery_color.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery white_wool,orange_wool,magenta_wool,light_blue_wool,yellow_wool,lime_wool,pink_wool,gray_wool,white_concrete,orange_concrete,magenta_concrete,light_blue_concrete,yellow_concrete,lime_concrete,pink_concrete,gray_concrete,white_terracotta,orange_terracotta,red_terracotta,blue_terracotta,glass,white_stained_glass,red_stained_glass,blue_stained_glass
"$BIN" --snapshot snaps/gallery_build.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery oak_door,spruce_door,iron_door,oak_trapdoor,glass,glass_pane,lantern,soul_lantern,bookshelf,crafting_table,furnace,chest,barrel,smoker,blast_furnace,cartography_table,stone_brick_stairs,oak_stairs,cobblestone_wall,oak_fence,iron_bars,ladder,hay_block,jack_o_lantern
"$BIN" --snapshot snaps/gallery_build_night.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.78 --up 6 --gallery oak_door,spruce_door,iron_door,oak_trapdoor,glass,glass_pane,lantern,soul_lantern,bookshelf,crafting_table,furnace,chest,barrel,smoker,blast_furnace,cartography_table,stone_brick_stairs,oak_stairs,cobblestone_wall,oak_fence,iron_bars,ladder,hay_block,jack_o_lantern
"$BIN" --snapshot snaps/gallery_ember.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery netherrack,nether_bricks,red_nether_bricks,cracked_nether_bricks,chiseled_nether_bricks,nether_quartz_ore,nether_gold_ore,ancient_debris,soul_sand,soul_soil,basalt,polished_basalt,blackstone,polished_blackstone,polished_blackstone_bricks,gilded_blackstone,crimson_nylium,warped_nylium,nether_wart_block,warped_wart_block,shroomlight,glowstone,magma_block,quartz_block
"$BIN" --snapshot snaps/gallery_plants.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery short_dry_grass,tall_dry_grass,bush,firefly_bush,leaf_litter,wildflowers,cactus_flower,short_grass,fern,dead_bush,tall_grass,large_fern,sweet_berry_bush,pink_petals,sugar_cane,azalea,flowering_azalea,moss_carpet,pale_moss_carpet,resin_clump,closed_eyeblossom,open_eyeblossom,torchflower,seagrass
"$BIN" --snapshot snaps/gallery_copper.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery copper_chest,exposed_copper_chest,weathered_copper_chest,oxidized_copper_chest,copper_lantern,oxidized_copper_lantern,copper_torch,copper_golem_statue,copper_bars,weathered_copper_bars,copper_chain,oxidized_copper_chain,copper_door,exposed_copper_door,oxidized_copper_door,copper_trapdoor,oak_shelf,cherry_shelf,crimson_shelf,pale_oak_shelf,dried_ghast,dried_ghast:3,weathered_copper_golem_statue,oxidized_copper_golem_statue
"$BIN" --snapshot snaps/gallery_copper_night.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.78 --up 6 --gallery copper_chest,exposed_copper_chest,weathered_copper_chest,oxidized_copper_chest,copper_lantern,oxidized_copper_lantern,copper_torch,copper_golem_statue,copper_bars,weathered_copper_bars,copper_chain,oxidized_copper_chain,copper_door,exposed_copper_door,oxidized_copper_door,copper_trapdoor,oak_shelf,cherry_shelf,crimson_shelf,pale_oak_shelf,dried_ghast,dried_ghast:3,weathered_copper_golem_statue,oxidized_copper_golem_statue
"$BIN" --snapshot snaps/farm_variants.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --facecam --spawn cow:1,cow:2,cow:3,pig:1,pig:2,pig:3,chicken:1,chicken:2,chicken:3 --stage
"$BIN" --snapshot snaps/copper_golems.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --facecam --spawn copper_golem:0,copper_golem:1:carry,copper_golem:2,copper_golem:3,zombie:copper --stage
"$BIN" --snapshot snaps/gallery_hollow.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --gallery end_stone,end_stone_bricks,purpur_block,purpur_pillar,obsidian,crying_obsidian,amethyst_block,budding_amethyst,sculk,sculk_catalyst,copper_block,exposed_copper,weathered_copper,oxidized_copper,cut_copper,copper_grate,prismarine,prismarine_bricks,dark_prismarine,sea_lantern,sponge,wet_sponge,honey_block,slime_block
"$BIN" --snapshot snaps/leak_12345.png --seed 12345 --x 36 --z 56 --up 6 --yaw 200 --pitch -35 --time 0.25
"$BIN" --snapshot snaps/agent_door_777.png --seed 777 --x 959.5 --z 272.5 --up 4 --yaw 180 --pitch -20 --time 0.25
"$BIN" --snapshot snaps/selftest.png --seed 12345 --find plains --yaw 30 --pitch 10 --time 0.3 --up 1 --selftest
# Z-fighting probes: each view rendered twice with the camera nudged 1/1000 block (ImageCheck.swift).
"$BIN" --snapshot snaps/flicker_village.png --seed 12345 --structure village --frame 0.8 --time 0.3 --flicker
"$BIN" --snapshot snaps/flicker_forest.png --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22 --flicker
"$BIN" --snapshot snaps/flicker_build.png --seed 12345 --find plains --yaw 0 --pitch 0 --time 0.28 --up 6 --flicker --gallery oak_door,oak_trapdoor,glass_pane,lantern,oak_stairs,oak_slab,cobblestone_wall,oak_fence,iron_bars,ladder,rail,white_carpet,snow_block,chest,red_bed,lectern
fi
# Visual oracles over every frame of this run (missing textures, black / blank / duplicate frames, z-fighting).
[ -f snaps/imagecheck.log ] && python3 tools/imagecheck.py snaps/imagecheck.log
trap - ERR
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "snap.sh: ${#FAILED[@]} failing line(s): ${FAILED[*]}"
  exit 1
fi
