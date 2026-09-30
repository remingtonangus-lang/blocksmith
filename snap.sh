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
"$BIN" --snapshot snaps/aerial16.png --seed 12345 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/aerial16_777.png --seed 777 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/aerial16_424242.png --seed 424242 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 16
"$BIN" --snapshot snaps/aerial24.png --seed 424242 --yaw 200 --pitch -10 --time 0.25 --up 30 --rd 24
"$BIN" --snapshot snaps/sunset.png  --seed 12345 --yaw 270 --pitch 0   --time 0.47 --up 10
"$BIN" --snapshot snaps/sunset_fast.png --seed 12345 --yaw 270 --pitch 0 --time 0.47 --up 10 --fast
"$BIN" --snapshot snaps/sunset_sun.png --seed 12345 --yaw 90 --pitch 4 --time 0.49 --up 10
"$BIN" --snapshot snaps/night.png   --seed 12345 --yaw 90  --pitch -10 --time 0.75 --up 5
"$BIN" --snapshot snaps/lake.png --seed 12345 --find ocean --yaw 30 --pitch -6 --time 0.25 --up 2
"$BIN" --snapshot snaps/lake_glint.png --seed 12345 --find ocean --yaw 90 --pitch -5 --time 0.48 --up 2
"$BIN" --snapshot snaps/underwater.png --seed 12345 --find ocean --yaw 30 --pitch -10 --time 0.25 --underwater
"$BIN" --snapshot snaps/down.png    --seed 12345 --yaw 0   --pitch -80 --time 0.25 --up 3
"$BIN" --snapshot snaps/forest.png  --seed 12345 --find forest --yaw 30 --pitch -28 --time 0.22 --up 22
"$BIN" --snapshot snaps/forest_in.png --seed 12345 --find forest --yaw 120 --pitch -5 --time 0.22 --up 1
"$BIN" --snapshot snaps/crack.png --seed 12345 --find forest --yaw 120 --pitch -5 --time 0.22 --up 1 --crack 0.7
"$BIN" --snapshot snaps/snowy.png   --seed 12345 --find snowy_taiga --yaw 60 --pitch -25 --time 0.22 --up 20
for b in desert jungle badlands dark_forest cherry_grove jagged_peaks savanna swamp taiga warm_ocean birch_forest mangrove_swamp; do
  "$BIN" --snapshot snaps/biome_$b.png --seed 12345 --find $b --yaw 45 --pitch -22 --time 0.22 --up 18 || true
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
"$BIN" --snapshot snaps/furnace.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu furnace
"$BIN" --snapshot snaps/drops.png --seed 12345 --yaw 30 --pitch -30 --time 0.22 --up 1 --drops
"$BIN" --snapshot snaps/survival.png --seed 12345 --yaw 30 --pitch -12 --time 0.2 --survival 13 --slot 8 --debug
"$BIN" --snapshot snaps/sim.png --seed 12345 --sim 12 --yaw 30 --pitch -10 --time 0.25
"$BIN" --sounds snaps/sounds
"$BIN" --atlas snaps/atlas
"$BIN" --snapshot snaps/mobs.png --seed 12345 --yaw 30 --pitch -14 --time 0.22 --up 1 --mobs
"$BIN" --snapshot snaps/hostile.png --seed 12345 --yaw 30 --pitch -12 --time 0.22 --up 1 --mobs --hostile
"$BIN" --snapshot snaps/nether.png --seed 12345 --dim nether --yaw 30 --pitch -10 --up 2 --ambient
"$BIN" --snapshot snaps/ember_crimson.png --seed 12345 --dim nether --find crimson_forest --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/ember_warped.png --seed 12345 --dim nether --find warped_forest --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/ember_soul.png --seed 12345 --dim nether --find soul_sand_valley --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/ember_basalt.png --seed 12345 --dim nether --find basalt_deltas --yaw 30 --pitch -5 --up 2 --ambient
"$BIN" --snapshot snaps/nether_wide.png --seed 12345 --dim nether --x 300 --z -200 --yaw 200 --pitch -5 --up 6 --ambient
"$BIN" --snapshot snaps/fortress.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -8 --up 1 --rd 6
"$BIN" --snapshot snaps/fortress_far.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -35 --up 9 --rd 8
"$BIN" --snapshot snaps/nether_mobs.png --seed 12345 --dim nether --structure fortress --yaw -45 --pitch -2 --up 1 --rd 6 --mobs --nethermobs
"$BIN" --snapshot snaps/bastion.png --seed 12345 --dim nether --structure bastion --yaw 150 --pitch -10 --up 1 --rd 6
"$BIN" --snapshot snaps/bastion_far.png --seed 12345 --dim nether --structure bastion --yaw 150 --pitch -35 --up 14 --rd 8
"$BIN" --snapshot snaps/village.png --seed 12345 --structure village --yaw 45 --pitch -28 --up 14 --time 0.25
"$BIN" --snapshot snaps/village_top.png --seed 12345 --structure village --yaw 0 --pitch -89 --up 70 --time 0.25
"$BIN" --snapshot snaps/village2.png --seed 12345 --structure village --x 1500 --z -900 --yaw 45 --pitch -30 --up 16 --time 0.25
"$BIN" --snapshot snaps/village3.png --seed 12345 --structure village --x -1200 --z 600 --yaw 45 --pitch -30 --up 16 --time 0.25
"$BIN" --snapshot snaps/village_street.png --seed 12345 --structure village --yaw 135 --pitch -8 --up 1 --time 0.25 --rd 6
"$BIN" --snapshot snaps/temple.png --seed 12345 --structure temple --frame 1 --time 0.25
"$BIN" --snapshot snaps/temple2.png --seed 12345 --structure temple --x 3000 --z 3000 --frame 1 --time 0.25
"$BIN" --snapshot snaps/outpost.png --seed 12345 --structure pillager_outpost --frame 1.2 --time 0.25
"$BIN" --snapshot snaps/outpost_close.png --seed 12345 --structure pillager_outpost --frame 0.5 --time 0.25
"$BIN" --snapshot snaps/snowslope.png --seed 12345 --find snowy_slopes --yaw 45 --pitch -35 --time 0.25 --up 6
"$BIN" --snapshot snaps/ruined_portal.png --seed 12345 --structure ruined_portal --frame 1 --time 0.25
"$BIN" --snapshot snaps/shipwreck.png --seed 12345 --structure shipwreck --frame 1 --time 0.25
"$BIN" --snapshot snaps/mineshaft.png --seed 12345 --structure mineshaft --frame 0.4 --time 0.25
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
"$BIN" --snapshot snaps/mobs_g.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn wither,ravager,evoker,vex,snow_golem,zombie_villager,witch
"$BIN" --snapshot snaps/villager_jobs.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn villager:farmer,villager:librarian,villager:cleric,villager:armorer,villager:butcher,villager:fisherman,villager:nitwit
"$BIN" --snapshot snaps/heads.png --seed 12345 --find plains --yaw 30 --pitch -25 --time 0.3 --up 1 --place skeleton_skull,wither_skeleton_skull:1,zombie_head,creeper_head:1,piglin_head,dragon_head:1,carved_pumpkin,jack_o_lantern:1
"$BIN" --snapshot snaps/beacon.png --seed 12345 --find plains --yaw 30 --pitch 10 --time 0.55 --up 3 --beacon
"$BIN" --snapshot snaps/rain.png --seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --weather rain
"$BIN" --snapshot snaps/thunder.png --seed 12345 --find plains --yaw 30 --pitch 5 --time 0.3 --up 1 --weather thunder
"$BIN" --snapshot snaps/snowfall.png --seed 12345 --find snowy_plains --yaw 30 --pitch -5 --time 0.3 --up 1 --weather rain
"$BIN" --snapshot snaps/animals1.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --spawn rabbit,fox,wolf,cat,horse,donkey,llama,goat,panda
"$BIN" --snapshot snaps/animals2.png --seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --spawn polar_bear,turtle,frog,armadillo,sniffer,mooshroom,camel,wandering_trader
"$BIN" --snapshot snaps/animals3.png --seed 12345 --find plains --yaw 30 --pitch 0 --time 0.3 --up 1 --spawn bee,parrot,bat,allay,phantom,endermite,breeze,bogged,zoglin,warden
"$BIN" --snapshot snaps/aquatic.png --seed 12345 --find warm_ocean --yaw 30 --pitch -30 --time 0.3 --up 1 --spawn squid,glow_squid,dolphin,cod,salmon,tropical_fish,pufferfish,axolotl,guardian,elder_guardian
"$BIN" --snapshot snaps/boats.png --seed 12345 --find ocean --yaw 30 --pitch -25 --time 0.3 --up 1 --ticks 3 --spawn boat:0,boat:1:c,boat:2,boat:3,boat:4:c,boat:5,boat:6,boat:7,boat:8:c
"$BIN" --snapshot snaps/armor.png --seed 12345 --find plains --yaw 30 --pitch -8 --time 0.3 --up 1 --spawn armor_stand:leather,armor_stand:golden,zombie:chainmail,skeleton:iron,armor_stand:diamond,husk:netherite,armor_stand
"$BIN" --snapshot snaps/banners.png --seed 12345 --find plains --yaw 30 --pitch -22 --time 0.3 --up 3 --banners
"$BIN" --snapshot snaps/loom.png --seed 12345 --menu loom
"$BIN" --snapshot snaps/book.png --seed 12345 --menu book
"$BIN" --snapshot snaps/advancements.png --seed 12345 --menu advancements
"$BIN" --snapshot snaps/pause.png --seed 12345 --menu pause
"$BIN" --snapshot snaps/options.png --seed 12345 --menu options
"$BIN" --snapshot snaps/death.png --seed 12345 --menu death
"$BIN" --snapshot snaps/title.png --seed 12345 --menu title
"$BIN" --snapshot snaps/create.png --seed 12345 --menu create
"$BIN" --snapshot snaps/recipes.png --seed 12345 --menu recipes
"$BIN" --snapshot snaps/commands.png --seed 12345 --menu commands
"$BIN" --snapshot snaps/fireworks.png --seed 12345 --find plains --yaw 30 --pitch 20 --time 0.8 --up 1 --fireworks
"$BIN" --snapshot snaps/monument.png --seed 12345 --structure monument --frame 1 --time 0.25
"$BIN" --snapshot snaps/mansion.png --seed 12345 --structure mansion --frame 1.7 --time 0.25
"$BIN" --snapshot snaps/ancient_city.png --seed 12345 --structure ancient_city --yaw 30 --pitch -20 --up 12 --rd 5
"$BIN" --snapshot snaps/trial_chambers.png --seed 12345 --structure trial_chambers --yaw 45 --pitch -25 --up 6 --rd 5
"$BIN" --snapshot snaps/copper.png --seed 12345 --find plains --yaw 30 --pitch -25 --time 0.3 --up 1 --place copper_block,exposed_copper,weathered_copper,oxidized_copper,cut_copper,copper_grate,copper_bulb:1,campfire,bee_nest:5,scaffolding --ambient
"$BIN" --snapshot snaps/decor.png --seed 12345 --find plains --yaw 30 --pitch -10 --time 0.3 --up 1 --decor
"$BIN" --snapshot snaps/map.png --seed 12345 --yaw 30 --pitch -10 --time 0.3 --up 20 --map
"$BIN" --snapshot snaps/third_back.png --seed 12345 --find plains --yaw 30 --pitch -15 --time 0.3 --up 1 --camera 1
"$BIN" --snapshot snaps/third_swim.png --seed 12345 --find ocean --yaw 30 --pitch -20 --time 0.3 --camera 1 --swim
"$BIN" --snapshot snaps/third_front.png --seed 12345 --find plains --yaw 30 --pitch 5 --time 0.3 --up 1 --camera 2
"$BIN" --snapshot snaps/pathtest.png --seed 12345 --find plains --yaw 0 --pitch -40 --time 0.75 --up 14 --pathtest
"$BIN" --snapshot snaps/ashen_grove.png --seed 12345 --find pale_garden --yaw 210 --pitch -20 --time 0.3 --up 4 --treecheck
"$BIN" --snapshot snaps/ashen_night.png --seed 12345 --find pale_garden --yaw 30 --pitch -10 --time 0.7 --up 2 --ticks 4 --place pale_oak_log,creaking_heart:1,pale_oak_planks,pale_moss_block,pale_moss_carpet,open_eyeblossom,closed_eyeblossom,pale_hanging_moss
"$BIN" --snapshot snaps/lush_caves.png --seed 12345 --find lush_caves --yaw 30 --pitch -10 --time 0.3
"$BIN" --snapshot snaps/dripstone_caves.png --seed 12345 --find dripstone_caves --yaw 30 --pitch -10 --time 0.3
"$BIN" --snapshot snaps/deep_dark.png --seed 12345 --find deep_dark --yaw 30 --pitch -10 --time 0.3 --nightvision
"$BIN" --snapshot snaps/dark_forest.png --seed 12345 --find dark_forest --yaw 30 --pitch -15 --time 0.3 --up 4 --treecheck
"$BIN" --snapshot snaps/selftest.png --seed 12345 --find plains --yaw 30 --pitch 10 --time 0.3 --up 1 --selftest
