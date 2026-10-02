# Structure check

Seeds 12345, 777, 424242, up to 3 per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.

| kind | checked | doors | POIs | mobs | issues |
|---|---|---|---|---|---|
| ancient_city | 9 | 0 | 74 | 0 | - |
| bastion | 9 | 0 | 16 | 34 | - |
| desert_well | 4 | 0 | 0 | 0 | - |
| end_centre | 3 | 0 | 0 | 30 | - |
| end_city | 9 | 0 | 33 | 46 | - |
| fortress | 9 | 0 | 16 | 0 | - |
| fossil | 2 | 0 | 0 | 0 | - |
| mansion | 4 | 0 | 36 | 44 | - |
| military_base | 9 | 0 | 523 | 324 | poi_unreachable 1 |
| mineshaft | 9 | 0 | 28 | 0 | - |
| monument | 9 | 0 | 0 | 81 | - |
| ocean_ruin | 9 | 0 | 0 | 9 | - |
| pillager_outpost | 7 | 0 | 7 | 42 | - |
| ruined_portal | 9 | 0 | 9 | 0 | - |
| shipwreck | 9 | 0 | 0 | 0 | - |
| stronghold | 9 | 0 | 80 | 0 | - |
| temple | 9 | 0 | 31 | 1 | - |
| trail_ruins | 9 | 0 | 0 | 0 | - |
| trial_chambers | 9 | 0 | 19 | 0 | - |
| village | 9 | 125 | 333 | 207 | floating 2 |

## Issues (first 6 per kind and class)
- **floating** village seed 777 at 957 67 261: 26 wall/foundation columns over air (first shown; column: 69 oak_planks (was air), 68 cobblestone (was air), 67 dirt (was air), 66 air, 65 air, 64 air, 63 air, 62 stone)  `--snapshot snaps/issue.png --seed 777 --x 957 --z 261 --up 3 --pitch -30`
  - view: `--seed 777 --x 963.5 --z 261.5 --feet 64 --yaw 90 --pitch 15`
- **floating** village seed 424242 at -291 75 341: 34 wall/foundation columns over air (first shown; column: 77 sandstone (was air), 76 dirt (was air), 75 dirt (was air), 74 air, 73 air, 72 air, 71 air, 70 air)  `--snapshot snaps/issue.png --seed 424242 --x -291 --z 341 --up 3 --pitch -30`
  - view: `--seed 424242 --x -284.5 --z 341.5 --feet 72 --yaw 90 --pitch 15`
- **poi_unreachable** military_base seed 424242 at 1380 83 1244: chest: no reachable cell next to it; closest reached 1386 82 1244, next toward it 1385 1244 from y-1 up: steel_plating/steel_plating/steel_plating/steel_plating  `--snapshot snaps/issue.png --seed 424242 --x 1380 --z 1244 --up 3 --pitch -30`
  - view: `--seed 424242 --x 1386.5 --z 1244.5 --feet 82 --yaw 90 --pitch -15`
