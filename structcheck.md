# Structure check

Seeds 12345, 777, 424242, up to 3 per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.

| kind | checked | doors | POIs | mobs | issues |
|---|---|---|---|---|---|
| ancient_city | 9 | 0 | 69 | 0 | - |
| bastion | 9 | 0 | 16 | 34 | - |
| buried_treasure | 1 | 0 | 0 | 0 | - |
| capital_city | 9 | 0 | 213 | 146 | - |
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
| shipwreck | 9 | 0 | 0 | 0 | floating 1 |
| stronghold | 9 | 0 | 80 | 0 | - |
| temple | 9 | 1 | 28 | 5 | - |
| trail_ruins | 9 | 0 | 0 | 0 | - |
| trial_chambers | 9 | 0 | 19 | 0 | - |
| village | 9 | 125 | 333 | 207 | - |

## Issues (first 6 per kind and class)
- **floating** shipwreck seed 777 at -317 27 296: 7 wall/foundation columns over air (first shown; column: 29 water, 28 oak_planks (was air), 27 spruce_log[x] (was air), 26 air, 25 air, 24 amethyst_block, 23 amethyst_block, 22 calcite)  `--snapshot snaps/issue.png --seed 777 --x -317 --z 296 --up 3 --pitch -30`
  - view: `--seed 777 --x -310.5 --z 296.5 --feet 24 --yaw 90 --pitch 15`
