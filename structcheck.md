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
| mansion | 4 | 0 | 371 | 44 | - |
| military_base | 9 | 0 | 522 | 324 | - |
| mineshaft | 9 | 0 | 28 | 0 | - |
| monument | 9 | 0 | 0 | 81 | - |
| ocean_ruin | 9 | 0 | 0 | 9 | - |
| pillager_outpost | 7 | 0 | 26 | 48 | - |
| ruined_portal | 9 | 0 | 9 | 0 | - |
| shipwreck | 9 | 0 | 0 | 0 | - |
| stronghold | 9 | 0 | 80 | 0 | - |
| temple | 9 | 0 | 29 | 1 | - |
| trail_ruins | 9 | 0 | 0 | 0 | - |
| trial_chambers | 9 | 0 | 19 | 0 | - |
| village | 9 | 125 | 333 | 207 | - |

## Issues (first 6 per kind and class)
- **poi_unreachable** igloo seed 12345 at 1770 161 -1464: crafting_table: no reachable cell next to it; closest reached 1773 161 -1464, next toward it 1772 -1464 from y-1 up: powder_snow/air/air/air  `--snapshot snaps/issue.png --seed 12345 --x 1770 --z -1464 --up 3 --pitch -30`
  - view: `--seed 12345 --x 1773.5 --z -1463.5 --feet 161 --yaw 90 --pitch -15`
- **poi_unreachable** igloo seed 12345 at 1767 161 -1463: white_bed: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1767 --z -1463 --up 3 --pitch -30`
- **poi_unreachable** igloo seed 12345 at 1769 161 -1463: furnace: no reachable cell next to it  `--snapshot snaps/issue.png --seed 12345 --x 1769 --z -1463 --up 3 --pitch -30`
