# Structure check

Seeds 12345, 777, 424242, up to 3 per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.

| kind | checked | doors | POIs | mobs | issues |
|---|---|---|---|---|---|
| ancient_city | 9 | 0 | 69 | 0 | - |
| bastion | 9 | 0 | 16 | 34 | - |
| capital_city | 9 | 0 | 213 | 146 | floating 1 |
| desert_well | 4 | 0 | 0 | 0 | - |
| end_centre | 3 | 0 | 0 | 30 | - |
| end_city | 9 | 0 | 33 | 46 | - |
| fortress | 9 | 0 | 16 | 0 | - |
| fossil | 2 | 0 | 0 | 0 | - |
| great_ruin | 9 | 1 | 19 | 0 | - |
| mansion | 3 | 0 | 251 | 33 | - |
| military_base | 9 | 0 | 99 | 333 | - |
| mineshaft | 9 | 0 | 28 | 0 | - |
| monument | 9 | 0 | 0 | 82 | - |
| ocean_ruin | 9 | 0 | 0 | 9 | - |
| pillager_outpost | 9 | 0 | 36 | 63 | - |
| ruined_portal | 9 | 0 | 9 | 0 | - |
| shipwreck | 9 | 0 | 0 | 0 | - |
| stronghold | 9 | 0 | 80 | 0 | - |
| temple | 9 | 1 | 28 | 5 | - |
| trail_ruins | 9 | 0 | 0 | 0 | - |
| trial_chambers | 9 | 0 | 19 | 0 | - |
| village | 9 | 125 | 333 | 207 | - |

## Issues (first 6 per kind and class)
- **floating** jungle_temple seed 424242 at 249 65 1178: 4 wall/foundation columns over air (first shown; column: 67 cobblestone (was dirt), 66 cobblestone (was stone), 65 cobblestone (was air), 64 air, 63 air, 62 air, 61 air, 60 stone)  `--snapshot snaps/issue.png --seed 424242 --x 249 --z 1178 --up 3 --pitch -30`
  - view: `--seed 424242 --x 255.5 --z 1178.5 --feet 62 --yaw 90 --pitch 15`
- **floating** capital_city seed 424242 at -768 40 1054: 9 wall/foundation columns over air (first shown; column: 42 capital_stone_trim (was air), 41 capital_stone_trim (was air), 40 capital_stone_trim (was air), 39 air, 38 air, 37 air, 36 air, 35 air)  `--snapshot snaps/issue.png --seed 424242 --x -768 --z 1054 --up 3 --pitch -30`
  - view: `--seed 424242 --x -761.5 --z 1054.5 --feet 37 --yaw 90 --pitch 15`
