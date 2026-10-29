# Structure check

Seeds 12345, 777, 424242, up to 3 per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.

| kind | checked | doors | POIs | mobs | issues |
|---|---|---|---|---|---|
| bastion | 9 | 0 | 18 | 63 | mob_in_block 4, mob_no_floor 5 |
| boreal_station | 2 | 30 | 44 | 54 | - |
| capital_city | 9 | 0 | 665 | 316 | - |
| desert_well | 1 | 0 | 0 | 0 | - |
| end_centre | 3 | 0 | 0 | 30 | - |
| end_city | 9 | 0 | 33 | 46 | - |
| fortress | 9 | 0 | 81 | 90 | - |
| fossil | 1 | 0 | 0 | 0 | - |
| frontier_site | 9 | 0 | 55 | 48 | - |
| greywall_base | 9 | 61 | 100 | 140 | door_blocked 5, door_unreachable 5, poi_unreachable 10 |
| greywall_depot | 7 | 20 | 32 | 45 | - |
| mansion | 5 | 0 | 50 | 42 | mob_no_floor 2, poi_unreachable 5 |
| military_base | 7 | 41 | 229 | 405 | - |
| monument | 9 | 0 | 0 | 117 | - |
| ocean_ruin | 9 | 0 | 0 | 9 | - |
| pillager_outpost | 8 | 0 | 29 | 54 | mob_trapped 6, poi_unreachable 3 |
| shipwreck | 9 | 0 | 0 | 3 | - |
| sky_isle | 9 | 0 | 9 | 0 | - |
| stronghold | 9 | 0 | 98 | 0 | - |
| temple | 9 | 0 | 24 | 1 | - |
| trail_ruins | 9 | 0 | 0 | 0 | - |
| trial_chambers | 9 | 45 | 368 | 0 | - |
| village | 9 | 84 | 315 | 145 | door_needs_jump 5, mob_trapped 6, poi_unreachable 12 |
| wild_camp | 9 | 0 | 29 | 7 | - |

## Issues (first 6 per kind and class)
- **door_needs_jump** village seed 12345 at 1212 125 -877: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): -0.1 -0.1 -1.1 +1.6  #  # +1  | -0.1 -0.1 -1.1 +1.6  #  # +1  | -0.1 -0.1 -1.1 -1.1  #  0  0  | -0.1 -0.1 -1.1  0  0  0  0  | -0.1 -0.1 -1.1 -1.1  #  0  0  | -0.1 -0.1 -1.1 -1.1  #  0  0  | -0.1 -0.1 -1.1 +1.6  # +1 +1   `--snapshot snaps/issue.png --seed 12345 --x 1212 --z -877 --up 3 --pitch -30`
- **door_needs_jump** village seed 12345 at 1212 129 -835: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3):  0 -1.1 -1.1 -1.1  #  0  0  | -0.5 -0.5 -0.5 -0.5  #  #  0  | -0.1 -0.1 -1.1 -1.1  #  0  0  | -0.1 -0.1 -1.1  0  0  0  0  | -0.1 -0.1 -1.1 -1.1  #  0  0  | -0.1 -0.1  # -1.1  # +2  0  | -0.1 -0.1 -0.1 -1.1  #  0  0   `--snapshot snaps/issue.png --seed 12345 --x 1212 --z -835 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1217 127 -905: brown_bed: no reachable cell next to it; closest reached 1215 127 -905, next toward it 1216 -905 from y-1 up: spruce_planks/spruce_planks/spruce_planks/spruce_planks  `--snapshot snaps/issue.png --seed 12345 --x 1217 --z -905 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1215.5 --z -904.5 --feet 127 --yaw -90 --pitch -15`
- **poi_unreachable** village seed 12345 at 1219 127 -902: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1219 --z -902 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1218 127 -904: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1218 --z -904 --up 3 --pitch -30`
- **door_needs_jump** village seed 12345 at 1337 173 92: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -0.1 -0.1 +0.9 +0.9 +0.9 +0.9 -0.1  |  0  0 +0.9  0 +0.9 +0.9 +0.9  |  #  #  #  0  #  #  #  |  0  0  0  0  0  0  0  | +0.6  0  0  0  0  0 +0.6   `--snapshot snaps/issue.png --seed 12345 --x 1337 --z 92 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1315 165 70: chest: no reachable cell next to it; closest reached 1316 165 68, next toward it 1315 69 from y-1 up: oak_planks/oak_planks/oak_planks/oak_planks  `--snapshot snaps/issue.png --seed 12345 --x 1315 --z 70 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1316.5 --z 68.5 --feet 165 --yaw 153 --pitch -15`
- **poi_unreachable** village seed 12345 at 1317 165 73: red_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1317 --z 73 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1305 168 109: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1305 --z 109 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1307 168 112: red_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1307 --z 112 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1316 165 72: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1316 --z 72 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1416 173 78: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1416 --z 78 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1306 168 111: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1306 --z 111 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 12345 at 643 199 338: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 643 --z 338 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 12345 at 659 133 -990: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 659 --z -990 --up 3 --pitch -30`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 203 566: barrel: no reachable cell next to it; closest reached 1414 203 564, next toward it 1414 565 from y-1 up: dark_oak_planks/mossy_cobblestone/cobblestone/birch_planks  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 566 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1414.5 --z 564.5 --feet 203 --yaw -180 --pitch -15`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 203 570: fletching_table: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 570 --up 3 --pitch -30`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 223 566: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 566 --up 3 --pitch -30`
- **poi_unreachable** camp_traders seed 12345 at -202 70 137: barrel: no reachable cell next to it; closest reached -204 70 137, next toward it -203 137 from y-1 up: spruce_planks/hay_block/air/white_wool  `--snapshot snaps/issue.png --seed 12345 --x -202 --z 137 --up 3 --pitch -30`
  - view: `--seed 12345 --x -203.5 --z 137.5 --feet 70 --yaw -90 --pitch -15`
- **poi_unreachable** camp_traders seed 12345 at -200 70 137: white_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x -200 --z 137 --up 3 --pitch -30`
- **door_blocked** greywall_base seed 12345 at -907 67 -3704: no room to stand on the -z side (bunker_concrete / bunker_concrete_stairs[west])  `--snapshot snaps/issue.png --seed 12345 --x -907 --z -3704 --up 3 --pitch -30`
- **door_unreachable** greywall_base seed 12345 at -907 67 -3704: no walking route from outside  `--snapshot snaps/issue.png --seed 12345 --x -907 --z -3704 --up 3 --pitch -30`
- **poi_unreachable** greywall_base seed 12345 at -910 67 -3703: chest: no reachable cell next to it; closest reached -912 67 -3703, next toward it -911 -3703 from y-1 up: bunker_concrete/bunker_concrete_dark/armored_glass/armored_glass  `--snapshot snaps/issue.png --seed 12345 --x -910 --z -3703 --up 3 --pitch -30`
  - view: `--seed 12345 --x -911.5 --z -3702.5 --feet 67 --yaw -90 --pitch -15`
- **poi_unreachable** greywall_base seed 12345 at -910 67 -3700: barrel: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x -910 --z -3700 --up 3 --pitch -30`
- **door_blocked** greywall_base seed 12345 at -5035 75 2792: no room to stand on the -z side (bunker_concrete / bunker_concrete_stairs[west])  `--snapshot snaps/issue.png --seed 12345 --x -5035 --z 2792 --up 3 --pitch -30`
- **door_unreachable** greywall_base seed 12345 at -5035 75 2792: no walking route from outside  `--snapshot snaps/issue.png --seed 12345 --x -5035 --z 2792 --up 3 --pitch -30`
- **poi_unreachable** greywall_base seed 12345 at -5038 75 2793: chest: no reachable cell next to it; closest reached -5040 75 2793, next toward it -5039 2793 from y-1 up: bunker_concrete/bunker_concrete_dark/armored_glass/armored_glass  `--snapshot snaps/issue.png --seed 12345 --x -5038 --z 2793 --up 3 --pitch -30`
  - view: `--seed 12345 --x -5039.5 --z 2793.5 --feet 75 --yaw -90 --pitch -15`
- **poi_unreachable** greywall_base seed 12345 at -5038 75 2796: barrel: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x -5038 --z 2796 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 12345 at 198 81 -331: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 12345 --x 198 --z -331 --up 3 --pitch -30`
- **mob_in_block** bastion seed 12345 at 518 81 101: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 12345 --x 518 --z 101 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 12345 at -90 81 725: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 12345 --x -90 --z 725 --up 3 --pitch -30`
- **door_needs_jump** village seed 777 at 707 99 -1428: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -1.1 -1.1 -1.1 -1.1 -1.1 -1.1 -1.1  | -1.1 -1.1 -1.1  0 -1.1 -1.1 -1.1  |  #  #  #  0  #  #  #  |  0  0  0  0  0 +1 +1  |  0  0  0  0  0  0  0   `--snapshot snaps/issue.png --seed 777 --x 707 --z -1428 --up 3 --pitch -30`
- **mob_trapped** village seed 777 at 264 79 -1748: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 777 --x 264 --z -1748 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 777 at 1395 74 -2462: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 777 --x 1395 --z -2462 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 777 at 1747 74 -2430: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 777 --x 1747 --z -2430 --up 3 --pitch -30`
- **poi_unreachable** mansion seed 777 at 3022 79 1944: chest: no reachable cell next to it; closest reached 3022 74 1944, next toward it 3022 1944 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 777 --x 3022 --z 1944 --up 3 --pitch -30`
  - view: `--seed 777 --x 3022.5 --z 1944.5 --feet 74 --yaw -180 --pitch -15`
- **poi_unreachable** mansion seed 777 at 2094 89 -3880: chest: no reachable cell next to it; closest reached 2094 84 -3880, next toward it 2094 -3880 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 777 --x 2094 --z -3880 --up 3 --pitch -30`
  - view: `--seed 777 --x 2094.5 --z -3879.5 --feet 84 --yaw -180 --pitch -15`
- **poi_unreachable** mansion seed 777 at -5106 117 1608: chest: no reachable cell next to it; closest reached -5106 112 1608, next toward it -5106 1608 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 777 --x -5106 --z 1608 --up 3 --pitch -30`
  - view: `--seed 777 --x -5105.5 --z 1608.5 --feet 112 --yaw -180 --pitch -15`
- **mob_no_floor** mansion seed 777 at -5131 115 1608: pillager has nothing to stand on  `--snapshot snaps/issue.png --seed 777 --x -5131 --z 1608 --up 3 --pitch -30`
- **door_blocked** greywall_base seed 777 at 1541 71 -776: no room to stand on the -z side (bunker_concrete / bunker_concrete_stairs[west])  `--snapshot snaps/issue.png --seed 777 --x 1541 --z -776 --up 3 --pitch -30`
- **door_unreachable** greywall_base seed 777 at 1541 71 -776: no walking route from outside  `--snapshot snaps/issue.png --seed 777 --x 1541 --z -776 --up 3 --pitch -30`
- **poi_unreachable** greywall_base seed 777 at 1538 71 -775: chest: no reachable cell next to it; closest reached 1536 71 -775, next toward it 1537 -775 from y-1 up: bunker_concrete/bunker_concrete_dark/armored_glass/armored_glass  `--snapshot snaps/issue.png --seed 777 --x 1538 --z -775 --up 3 --pitch -30`
  - view: `--seed 777 --x 1536.5 --z -774.5 --feet 71 --yaw -90 --pitch -15`
- **poi_unreachable** greywall_base seed 777 at 1538 71 -772: barrel: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 1538 --z -772 --up 3 --pitch -30`
- **door_blocked** greywall_base seed 777 at 1605 85 -2824: no room to stand on the -z side (bunker_concrete / bunker_concrete_stairs[west])  `--snapshot snaps/issue.png --seed 777 --x 1605 --z -2824 --up 3 --pitch -30`
- **door_unreachable** greywall_base seed 777 at 1605 85 -2824: no walking route from outside  `--snapshot snaps/issue.png --seed 777 --x 1605 --z -2824 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 777 at 182 81 165: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 777 --x 182 --z 165 --up 3 --pitch -30`
- **mob_in_block** bastion seed 777 at -426 81 -315: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 777 --x -426 --z -315 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 777 at 230 81 -331: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 777 --x 230 --z -331 --up 3 --pitch -30`
- **door_needs_jump** village seed 424242 at 165 82 172: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): -0.1 -0.1 -0.1 -0.1 -0.1 -0.5 -1.1  | -0.1 -0.1 -0.1 -0.1  0 -0.5 -1.1  | -0.1 -0.1 -1.1 -1.1 -1.1 -0.5 -1.1  | -0.1 -1.1 -1.1  0 -1.1 -0.5 -1.1  |  #  #  #  0  #  #  #  |  0  0  0  0  0  0  0  |  #  0  0  0 +1 +1.6  0   `--snapshot snaps/issue.png --seed 424242 --x 165 --z 172 --up 3 --pitch -30`
- **mob_trapped** village seed 424242 at 188 81 193: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 424242 --x 188 --z 193 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 424242 at -781 82 114: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 424242 --x -781 --z 114 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 424242 at -2141 106 1362: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 424242 --x -2141 --z 1362 --up 3 --pitch -30`
- **poi_unreachable** ghost_town seed 424242 at -412 91 285: bell: no reachable cell next to it; closest reached -412 84 285, next toward it -412 285 from y-1 up: dark_oak_planks/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -412 --z 285 --up 3 --pitch -30`
  - view: `--seed 424242 --x -411.5 --z 285.5 --feet 84 --yaw -180 --pitch -15`
- **poi_unreachable** mansion seed 424242 at -610 82 -3912: chest: no reachable cell next to it; closest reached -610 77 -3912, next toward it -610 -3912 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -610 --z -3912 --up 3 --pitch -30`
  - view: `--seed 424242 --x -609.5 --z -3911.5 --feet 77 --yaw -180 --pitch -15`
- **mob_no_floor** mansion seed 424242 at -635 80 -3912: pillager has nothing to stand on  `--snapshot snaps/issue.png --seed 424242 --x -635 --z -3912 --up 3 --pitch -30`
- **poi_unreachable** mansion seed 424242 at -3394 93 -6520: chest: no reachable cell next to it; closest reached -3394 88 -6520, next toward it -3394 -6520 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -3394 --z -6520 --up 3 --pitch -30`
  - view: `--seed 424242 --x -3393.5 --z -6519.5 --feet 88 --yaw -180 --pitch -15`
- **door_blocked** greywall_base seed 424242 at 2389 136 1752: no room to stand on the -z side (bunker_concrete / bunker_concrete_stairs[west])  `--snapshot snaps/issue.png --seed 424242 --x 2389 --z 1752 --up 3 --pitch -30`
- **door_unreachable** greywall_base seed 424242 at 2389 136 1752: no walking route from outside  `--snapshot snaps/issue.png --seed 424242 --x 2389 --z 1752 --up 3 --pitch -30`
- **mob_in_block** bastion seed 424242 at 70 81 309: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 424242 --x 70 --z 309 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 424242 at -122 81 -75: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 424242 --x -122 --z -75 --up 3 --pitch -30`
- **mob_in_block** bastion seed 424242 at 358 81 -411: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 424242 --x 358 --z -411 --up 3 --pitch -30`
