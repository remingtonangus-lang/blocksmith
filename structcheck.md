# Structure check

Seeds 12345, 777, 424242, up to 3 per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.

| kind | checked | doors | POIs | mobs | issues |
|---|---|---|---|---|---|
| bastion | 9 | 0 | 18 | 63 | mob_in_block 4, mob_no_floor 5 |
| boreal_station | 2 | 30 | 44 | 54 | - |
| capital_city | 9 | 0 | 1502 | 583 | poi_unreachable 5 |
| desert_well | 1 | 0 | 0 | 0 | - |
| end_centre | 3 | 0 | 0 | 30 | - |
| end_city | 9 | 0 | 33 | 46 | - |
| fortress | 9 | 0 | 81 | 90 | - |
| fossil | 1 | 0 | 0 | 0 | - |
| frontier_site | 9 | 0 | 55 | 48 | - |
| greywall_base | 9 | 61 | 106 | 140 | - |
| greywall_depot | 7 | 14 | 32 | 42 | poi_unreachable 12 |
| hell_works | 9 | 0 | 135 | 72 | floating 6, poi_unreachable 12 |
| mansion | 5 | 0 | 50 | 42 | mob_no_floor 2, poi_unreachable 5 |
| military_base | 7 | 41 | 523 | 433 | - |
| monument | 9 | 0 | 0 | 117 | - |
| ocean_ruin | 9 | 0 | 0 | 9 | - |
| pillager_outpost | 8 | 0 | 29 | 54 | mob_trapped 6, poi_unreachable 3 |
| shipwreck | 9 | 0 | 0 | 3 | - |
| sky_isle | 9 | 0 | 9 | 0 | - |
| stronghold | 9 | 0 | 98 | 0 | - |
| temple | 9 | 0 | 24 | 1 | - |
| trail_ruins | 9 | 0 | 0 | 1 | - |
| trial_chambers | 9 | 45 | 368 | 0 | - |
| village | 9 | 77 | 322 | 140 | door_needs_jump 2, mob_trapped 7, poi_unreachable 14 |
| wild_camp | 9 | 0 | 29 | 7 | - |

## Issues (first 6 per kind and class)
- **door_needs_jump** village seed 12345 at 1337 173 92: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -0.1 -0.1 -0.1 -0.1 -0.1 -0.1 -0.1  | -0.1 -0.1 +0.9 +0.9 +0.9 +0.9 -0.1  |  0  0 +0.9  0 +0.9 +0.9 +0.9  |  #  #  #  0  #  #  #  |  0  0  0  0  0  0  0  | +0.6  0  0  0  0  0 +0.6   `--snapshot snaps/issue.png --seed 12345 --x 1337 --z 92 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1315 165 70: chest: no reachable cell next to it; closest reached 1315 165 67, next toward it 1315 68 from y-1 up: oak_planks/chest[east]/air/air  `--snapshot snaps/issue.png --seed 12345 --x 1315 --z 70 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1315.5 --z 67.5 --feet 165 --yaw -180 --pitch -15`
- **poi_unreachable** village seed 12345 at 1317 165 73: red_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1317 --z 73 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1305 168 109: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1305 --z 109 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1307 168 112: red_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1307 --z 112 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1418 173 77: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1418 --z 77 --up 3 --pitch -30`
- **poi_unreachable** village seed 12345 at 1415 173 79: red_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1415 --z 79 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1316 165 72: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1316 --z 72 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1416 173 78: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1416 --z 78 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 1306 168 111: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 1306 --z 111 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 862 89 -2150: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 862 --z -2150 --up 3 --pitch -30`
- **mob_trapped** village seed 12345 at 882 95 -2127: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 882 --z -2127 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 12345 at 643 199 338: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 643 --z 338 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 12345 at 659 133 -990: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 12345 --x 659 --z -990 --up 3 --pitch -30`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 203 566: barrel: no reachable cell next to it; closest reached 1414 203 564, next toward it 1414 565 from y-1 up: dark_oak_planks/mossy_cobblestone/cobblestone/birch_planks  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 566 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1414.5 --z 564.5 --feet 203 --yaw -180 --pitch -15`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 203 570: fletching_table: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 570 --up 3 --pitch -30`
- **poi_unreachable** pillager_outpost seed 12345 at 1414 223 566: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1414 --z 566 --up 3 --pitch -30`
- **poi_unreachable** camp_traders seed 12345 at -202 70 137: barrel: no reachable cell next to it; closest reached -204 70 137, next toward it -203 137 from y-1 up: spruce_planks/hay_block/air/white_wool  `--snapshot snaps/issue.png --seed 12345 --x -202 --z 137 --up 3 --pitch -30`
  - view: `--seed 12345 --x -203.5 --z 137.5 --feet 70 --yaw -90 --pitch -15`
- **poi_unreachable** camp_traders seed 12345 at -200 70 137: white_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x -200 --z 137 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 12345 at 198 81 -331: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 12345 --x 198 --z -331 --up 3 --pitch -30`
- **mob_in_block** bastion seed 12345 at 518 81 101: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 12345 --x 518 --z 101 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 12345 at -90 81 725: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 12345 --x -90 --z 725 --up 3 --pitch -30`
- **poi_unreachable** hell_works seed 12345 at 90 43 211: chest: no reachable cell next to it; closest reached 90 43 213, next toward it 90 212 from y-1 up: polished_blackstone_bricks/iron_bars/iron_bars/iron_bars  `--snapshot snaps/issue.png --seed 12345 --x 90 --z 211 --up 3 --pitch -30`
  - view: `--seed 12345 --dim nether --x 90.5 --z 213.5 --feet 43 --yaw -0 --pitch -15`
- **poi_unreachable** hell_works seed 12345 at 67 43 234: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 67 --z 234 --up 3 --pitch -30`
- **poi_unreachable** hell_works seed 12345 at 109 43 234: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 109 --z 234 --up 3 --pitch -30`
- **poi_unreachable** hell_works seed 12345 at 90 43 253: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 90 --z 253 --up 3 --pitch -30`
- **floating** hell_works seed 12345 at 86 40 208: 14 wall/foundation columns over air (first shown; column: 42 polished_blackstone_bricks (was air), 41 polished_blackstone_bricks (was air), 40 polished_blackstone_bricks (was air), 39 air, 38 air, 37 air, 36 blackstone, 35 netherrack)  `--snapshot snaps/issue.png --seed 12345 --x 86 --z 208 --up 3 --pitch -30`
  - view: `--seed 12345 --dim nether --x 92.5 --z 208.5 --feet 37 --yaw 90 --pitch 15`
- **floating** hell_works seed 12345 at 179 43 -191: 1491 wall/foundation columns over air (first shown; column: 45 basalt (was air), 44 basalt (was air), 43 basalt (was air), 42 air, 41 air, 40 air, 39 air, 38 air)  `--snapshot snaps/issue.png --seed 12345 --x 179 --z -191 --up 3 --pitch -30`
  - view: `--seed 12345 --dim nether --x 185.5 --z -190.5 --feet 40 --yaw 90 --pitch 15`
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
- **poi_unreachable** capital_city seed 777 at -2246 98 -4121: barrel: no reachable cell next to it; closest reached -2246 94 -4121, next toward it -2246 -4121 from y-1 up: barrel/air/air/air  `--snapshot snaps/issue.png --seed 777 --x -2246 --z -4121 --up 3 --pitch -30`
  - view: `--seed 777 --x -2245.5 --z -4120.5 --feet 94 --yaw -180 --pitch -15`
- **poi_unreachable** capital_city seed 777 at -2278 100 -4027: barrel: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x -2278 --z -4027 --up 3 --pitch -30`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2569: chest: no reachable cell next to it; closest reached 4656 73 2569, next toward it 4655 2569 from y-1 up: coarse_dirt/chain_link_fence/chain_link_fence/chain_link_fence  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2569 --up 3 --pitch -30`
  - view: `--seed 777 --x 4656.5 --z 2569.5 --feet 73 --yaw 90 --pitch -15`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2571: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2571 --up 3 --pitch -30`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2583: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2583 --up 3 --pitch -30`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2585: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2585 --up 3 --pitch -30`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2597: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2597 --up 3 --pitch -30`
- **poi_unreachable** greywall_depot seed 777 at 4652 73 2599: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 4652 --z 2599 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 777 at 182 81 165: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 777 --x 182 --z 165 --up 3 --pitch -30`
- **mob_in_block** bastion seed 777 at -426 81 -315: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 777 --x -426 --z -315 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 777 at 230 81 -331: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 777 --x 230 --z -331 --up 3 --pitch -30`
- **poi_unreachable** hell_works seed 777 at 410 44 -109: chest: no reachable cell next to it; closest reached 408 44 -109, next toward it 409 -109 from y-1 up: polished_blackstone_bricks/iron_bars/iron_bars/iron_bars  `--snapshot snaps/issue.png --seed 777 --x 410 --z -109 --up 3 --pitch -30`
  - view: `--seed 777 --dim nether --x 408.5 --z -108.5 --feet 44 --yaw -90 --pitch -15`
- **poi_unreachable** hell_works seed 777 at 387 44 -86: chest: no reachable cell next to it  `--snapshot snaps/issue.png --seed 777 --x 387 --z -86 --up 3 --pitch -30`
- **floating** hell_works seed 777 at 406 41 -112: 155 wall/foundation columns over air (first shown; column: 43 polished_blackstone_bricks (was air), 42 polished_blackstone_bricks (was air), 41 polished_blackstone_bricks (was air), 40 air, 39 air, 38 air, 37 air, 36 air)  `--snapshot snaps/issue.png --seed 777 --x 406 --z -112 --up 3 --pitch -30`
  - view: `--seed 777 --dim nether --x 412.5 --z -111.5 --feet 38 --yaw 90 --pitch 15`
- **door_needs_jump** village seed 424242 at -1788 99 767: reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): +0.6 +1  0  0  # -0.1 -0.1  |  0 +1  0  0  # -0.1 -0.1  |  0 +1.6  0  0  # -1.1 -0.1  |  0 +1  0  0  0  0 -1.1  |  0 +1  0  0  # -1.1 -1.1  |  0 +1  0 +1  # +1.6 -1.1  |  0  0  0 +1  # -0.5 -0.5   `--snapshot snaps/issue.png --seed 424242 --x -1788 --z 767 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 424242 at -781 82 114: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 424242 --x -781 --z 114 --up 3 --pitch -30`
- **mob_trapped** pillager_outpost seed 424242 at -2141 106 1362: villager spawn not connected to the village  `--snapshot snaps/issue.png --seed 424242 --x -2141 --z 1362 --up 3 --pitch -30`
- **poi_unreachable** ghost_town seed 424242 at -412 91 285: bell: no reachable cell next to it; closest reached -412 84 285, next toward it -412 285 from y-1 up: dark_oak_planks/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -412 --z 285 --up 3 --pitch -30`
  - view: `--seed 424242 --x -411.5 --z 285.5 --feet 84 --yaw -180 --pitch -15`
- **poi_unreachable** mansion seed 424242 at -610 82 -3912: chest: no reachable cell next to it; closest reached -610 77 -3912, next toward it -610 -3912 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -610 --z -3912 --up 3 --pitch -30`
  - view: `--seed 424242 --x -609.5 --z -3911.5 --feet 77 --yaw -180 --pitch -15`
- **mob_no_floor** mansion seed 424242 at -635 80 -3912: pillager has nothing to stand on  `--snapshot snaps/issue.png --seed 424242 --x -635 --z -3912 --up 3 --pitch -30`
- **poi_unreachable** mansion seed 424242 at -3394 93 -6520: chest: no reachable cell next to it; closest reached -3394 88 -6520, next toward it -3394 -6520 from y-1 up: chest[east]/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -3394 --z -6520 --up 3 --pitch -30`
  - view: `--seed 424242 --x -3393.5 --z -6519.5 --feet 88 --yaw -180 --pitch -15`
- **poi_unreachable** capital_city seed 424242 at 459 102 871: barrel: no reachable cell next to it; closest reached 459 98 871, next toward it 459 871 from y-1 up: barrel/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x 459 --z 871 --up 3 --pitch -30`
  - view: `--seed 424242 --x 459.5 --z 871.5 --feet 98 --yaw -180 --pitch -15`
- **poi_unreachable** capital_city seed 424242 at 1914 120 535: barrel: no reachable cell next to it; closest reached 1914 116 535, next toward it 1914 535 from y-1 up: barrel/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x 1914 --z 535 --up 3 --pitch -30`
  - view: `--seed 424242 --x 1914.5 --z 535.5 --feet 116 --yaw -180 --pitch -15`
- **poi_unreachable** capital_city seed 424242 at -2469 125 -713: barrel: no reachable cell next to it; closest reached -2469 121 -713, next toward it -2469 -713 from y-1 up: barrel/air/air/air  `--snapshot snaps/issue.png --seed 424242 --x -2469 --z -713 --up 3 --pitch -30`
  - view: `--seed 424242 --x -2468.5 --z -712.5 --feet 121 --yaw -180 --pitch -15`
- **mob_in_block** bastion seed 424242 at 70 81 309: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 424242 --x 70 --z 309 --up 3 --pitch -30`
- **mob_no_floor** bastion seed 424242 at -122 81 -75: searwing has nothing to stand on  `--snapshot snaps/issue.png --seed 424242 --x -122 --z -75 --up 3 --pitch -30`
- **mob_in_block** bastion seed 424242 at 358 81 -411: searwing spawns inside air / netherrack  `--snapshot snaps/issue.png --seed 424242 --x 358 --z -411 --up 3 --pitch -30`
- **floating** hell_works seed 424242 at 147 47 129: 1573 wall/foundation columns over air (first shown; column: 49 basalt (was air), 48 basalt (was air), 47 basalt (was air), 46 air, 45 air, 44 air, 43 air, 42 air)  `--snapshot snaps/issue.png --seed 424242 --x 147 --z 129 --up 3 --pitch -30`
  - view: `--seed 424242 --dim nether --x 153.5 --z 129.5 --feet 44 --yaw 90 --pitch 15`
- **floating** hell_works seed 424242 at -205 44 -239: 719 wall/foundation columns over air (first shown; column: 46 basalt (was air), 45 basalt (was air), 44 basalt (was air), 43 air, 42 air, 41 warped_nylium, 40 netherrack, 39 netherrack)  `--snapshot snaps/issue.png --seed 424242 --x -205 --z -239 --up 3 --pitch -30`
  - view: `--seed 424242 --dim nether --x -198.5 --z -238.5 --feet 41 --yaw 90 --pitch 15`
- **floating** hell_works seed 424242 at 198 42 -160: 96 wall/foundation columns over air (first shown; column: 44 polished_blackstone_bricks (was air), 43 polished_blackstone_bricks (was air), 42 polished_blackstone_bricks (was air), 41 air, 40 air, 39 air, 38 air, 37 air)  `--snapshot snaps/issue.png --seed 424242 --x 198 --z -160 --up 3 --pitch -30`
  - view: `--seed 424242 --dim nether --x 204.5 --z -159.5 --feet 39 --yaw 90 --pitch 15`
