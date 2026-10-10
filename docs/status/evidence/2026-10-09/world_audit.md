# World-gen audit (Blocksmith --worldaudit 50)

Seeds 1000 + i*7919, i < 50; 2048-block square around each spawn origin; 30 s of survival ticks per time of day.

## Summary

- Unsafe spawns: 0/50
- Structure overlaps (different starts whose footprints intersect): 138 total
  - mineshaft + trial_chambers: 32
  - military_base + ruined_portal: 26
  - mineshaft + mineshaft: 18
  - ocean_ruin + shipwreck: 14
  - military_base + village: 8
  - capital_city + ruined_portal: 5
  - mineshaft + shipwreck: 3
  - capital_city + mineshaft: 3
  - military_base + mineshaft: 3
  - monument + ocean_ruin: 3
  - fossil + military_base: 3
  - ancient_city + mineshaft: 2
  - monument + shipwreck: 2
  - mineshaft + monument: 2
  - desert_well + military_base: 1
  - desert_well + village: 1
  - great_ruin + mineshaft: 1
  - mineshaft + ocean_ruin: 1
  - capital_city + trail_ruins: 1
  - buried_treasure + capital_city: 1
  - capital_city + fossil: 1
  - capital_city + pillager_outpost: 1
  - shipwreck + village: 1
  - ruined_portal + village: 1
  - ruined_portal + shipwreck: 1
  - capital_city + desert_well: 1
  - desert_pyramid + fossil: 1
  - trail_ruins + village: 1
- Distance from spawn to the nearest (blocks):
  - capital_city: min 15 median 752 max 1978; over 2000: 0
  - military_base: min 65 median 428 max 1544; over 2000: 0
  - village: min 69 median 479 max 2043; over 2000: 1
- Structure starts per 2048^2 square (mean): ancient_city 0.8, buried_treasure 2.5, capital_city 1.3, desert_pyramid 0.2, desert_well 0.9, fossil 1.0, great_ruin 0.2, igloo 1.0, jungle_temple 0.4, military_base 4.7, mineshaft 64.9, monument 0.9, ocean_ruin 14.3, pillager_outpost 0.3, ruined_portal 9.5, shipwreck 12.3, swamp_hut 0.1, trail_ruins 1.0, trial_chambers 6.2, village 3.1

## Spawn density (mobs alive after 30 s, per seed)

| time + group | per-seed counts |
|---|---|
| midnight hostile cave | min 0 median 6 max 30; zero on 7 seeds |
| midnight hostile surface | min 7 median 10 max 13; zero on 0 seeds |
| midnight passive cave | min 0 median 2 max 6; zero on 11 seeds |
| midnight passive surface | min 1 median 10 max 23; zero on 0 seeds |
| noon hostile cave | min 0 median 8 max 25; zero on 3 seeds |
| noon hostile surface | min 0 median 5 max 25; zero on 7 seeds |
| noon passive cave | min 0 median 2 max 6; zero on 11 seeds |
| noon passive surface | min 1 median 10 max 24; zero on 0 seeds |

### By biome (all seeds)

| time biome group | mobs |
|---|---|
| noon plains passive | 95 |
| midnight plains passive | 92 |
| midnight plains hostile | 67 |
| midnight beach hostile | 67 |
| noon beach passive | 64 |
| midnight snowyPlains hostile | 64 |
| midnight beach passive | 64 |
| noon forest passive | 61 |
| midnight forest hostile | 60 |
| noon plains hostile cave | 57 |
| midnight forest passive | 55 |
| noon beach hostile cave | 50 |
| noon forest hostile | 50 |
| noon snowyPlains hostile cave | 50 |
| noon snowyPlains passive | 49 |
| midnight snowyPlains passive | 47 |
| midnight beach hostile cave | 45 |
| noon forest hostile cave | 44 |
| midnight plains hostile cave | 40 |
| midnight taiga passive | 38 |
| midnight taiga hostile | 38 |
| noon plains hostile | 36 |
| midnight snowyPlains hostile cave | 35 |
| noon taiga hostile | 35 |
| midnight taiga hostile cave | 34 |
| midnight snowyTaiga hostile | 33 |
| noon snowyTaiga passive | 32 |
| midnight forest hostile cave | 32 |
| noon taiga passive | 32 |
| midnight snowyTaiga passive | 31 |
| midnight savanna passive | 27 |
| noon taiga hostile cave | 27 |
| midnight sparseJungle passive | 26 |
| midnight desert hostile | 26 |
| noon savanna passive | 26 |
| noon sparseJungle passive | 25 |
| noon sparseJungle hostile cave | 24 |
| noon ocean hostile cave | 23 |
| midnight meadow hostile | 23 |
| midnight sparseJungle hostile cave | 22 |

### By kind (all seeds)

midnight creeper 261, midnight skeleton 221, midnight zombie 185, noon zombie 184, noon creeper 175, noon skeleton 137, midnight bat 112, noon spider 111, midnight spider 109, noon bat 103, noon rabbit 101, midnight rabbit 97, noon chicken 72, midnight chicken 72, noon sheep 71, midnight sheep 67, noon turtle 59, midnight turtle 58, noon cow 40, midnight cow 39, midnight pig 38, noon pig 38, noon villager 36, midnight villager 35, midnight stray 31, midnight wolf 27, noon wolf 27, midnight fox 25, noon fox 25, noon soldierRecruit 17, midnight enderman 13, noon soldierMarksman 12, midnight zombieVillager 12, noon witch 11, noon enderman 10, noon zombieVillager 10, midnight bogged 9, noon tropicalFish 8, noon soldierTrooper 7, noon pillager 6, midnight pillager 6, noon cod 6, midnight tropicalFish 6, midnight squid 5, noon goat 5, noon parrot 5, midnight salmon 4, midnight goat 4, midnight husk 4, noon armadillo 4, noon salmon 4, midnight armadillo 4, midnight witch 4, midnight parrot 4, midnight cod 4, midnight ironGolem 3, noon ironGolem 3, midnight horse 3, noon horse 3, noon squid 2, midnight ocelot 2, noon ocelot 2, midnight cat 2, noon cat 1, noon deckGun 1, noon slime 1, midnight polarBear 1, midnight slime 1, noon polarBear 1, noon frog 1, midnight donkey 1, noon drowned 1, noon donkey 1, midnight frog 1

## Per seed

- seed 1000: 127 starts, 5 overlaps | village 1438, military_base 1148, capital_city 1008 | spawn safe | noon passive 16+1 hostile 0+8 | midnight passive 16+2 hostile 9+9
- seed 8919: 113 starts, 4 overlaps | village 1860, military_base 971, capital_city 1159 | spawn safe | noon passive 8+4 hostile 8+6 | midnight passive 7+1 hostile 10+5
- seed 16838: 119 starts, 3 overlaps | village 449, military_base 361, capital_city 1325 | spawn safe | noon passive 3+2 hostile 0+12 | midnight passive 2+2 hostile 10+7
- seed 24757: 133 starts, 3 overlaps | village 1219, military_base 1205, capital_city 1075 | spawn safe | noon passive 4+4 hostile 3+25 | midnight passive 4+4 hostile 11+13
- seed 32676: 135 starts, 3 overlaps | village 432, military_base 433, capital_city 1267 | spawn safe | noon passive 2+1 hostile 7+8 | midnight passive 3+3 hostile 11+10
- seed 40595: 147 starts, 1 overlaps | village 2043, military_base 845, capital_city 1978 | spawn safe | noon passive 13+4 hostile 4+7 | midnight passive 13+4 hostile 12+2
- seed 48514: 137 starts, 2 overlaps | village 74, military_base 65, capital_city 288 | spawn safe | noon passive 18+4 hostile 12+15 | midnight passive 18+3 hostile 10+13
- seed 56433: 134 starts, 2 overlaps | village 276, military_base 467, capital_city 734 | spawn safe | noon passive 9+2 hostile 4+15 | midnight passive 8+4 hostile 12+13
- seed 64352: 133 starts, 1 overlaps | village 886, military_base 251, capital_city 401 | spawn safe | noon passive 14+1 hostile 5+13 | midnight passive 13+2 hostile 10+14
- seed 72271: 120 starts, 1 overlaps | village 516, military_base 202, capital_city 804 | spawn safe | noon passive 4+0 hostile 8+3 | midnight passive 4+0 hostile 10+3
- seed 80190: 147 starts, 1 overlaps | village 523, military_base 262, capital_city 1028 | spawn safe | noon passive 1+3 hostile 5+18 | midnight passive 1+3 hostile 10+15
- seed 88109: 114 starts, 2 overlaps | village 431, military_base 504, capital_city 1064 | spawn safe | noon passive 9+3 hostile 0+5 | midnight passive 9+1 hostile 10+4
- seed 96028: 113 starts, 2 overlaps | village 143, military_base 265, capital_city 224 | spawn safe | noon passive 13+0 hostile 11+2 | midnight passive 13+1 hostile 10+0
- seed 103947: 149 starts, 2 overlaps | village 528, military_base 746, capital_city 1881 | spawn safe | noon passive 4+4 hostile 4+13 | midnight passive 4+4 hostile 9+14
- seed 111866: 148 starts, 4 overlaps | village 374, military_base 515, capital_city 1872 | spawn safe | noon passive 5+2 hostile 6+14 | midnight passive 5+2 hostile 12+13
- seed 119785: 122 starts, 2 overlaps | village 167, military_base 223, capital_city 323 | spawn safe | noon passive 17+2 hostile 1+5 | midnight passive 17+2 hostile 10+0
- seed 127704: 148 starts, 6 overlaps | village 141, military_base 140, capital_city 338 | spawn safe | noon passive 3+2 hostile 10+7 | midnight passive 3+4 hostile 10+8
- seed 135623: 139 starts, 1 overlaps | village 1044, military_base 1458, capital_city 1550 | spawn safe | noon passive 15+4 hostile 2+17 | midnight passive 17+0 hostile 9+30
- seed 143542: 98 starts, 3 overlaps | village 609, military_base 405, capital_city 876 | spawn safe | noon passive 11+1 hostile 1+5 | midnight passive 10+2 hostile 8+5
- seed 151461: 156 starts, 4 overlaps | village 479, military_base 477, capital_city 1119 | spawn safe | noon passive 5+1 hostile 5+7 | midnight passive 5+4 hostile 10+2
- seed 159380: 105 starts, 3 overlaps | village 170, military_base 375, capital_city 908 | spawn safe | noon passive 8+1 hostile 3+10 | midnight passive 8+2 hostile 10+5
- seed 167299: 138 starts, 2 overlaps | village 165, military_base 232, capital_city 1202 | spawn safe | noon passive 2+4 hostile 7+7 | midnight passive 2+4 hostile 10+4
- seed 175218: 129 starts, 6 overlaps | village 792, military_base 149, capital_city 449 | spawn safe | noon passive 12+4 hostile 3+1 | midnight passive 12+4 hostile 10+4
- seed 183137: 108 starts, 6 overlaps | village 412, military_base 98, capital_city 215 | spawn safe | noon passive 18+4 hostile 0+6 | midnight passive 17+4 hostile 7+6
- seed 191056: 123 starts, 3 overlaps | village 74, military_base 111, capital_city 663 | spawn safe | noon passive 17+6 hostile 9+8 | midnight passive 17+6 hostile 10+8
- seed 198975: 137 starts, 0 overlaps | village 1325, military_base 966, capital_city 502 | spawn safe | noon passive 24+1 hostile 4+5 | midnight passive 23+3 hostile 9+8
- seed 206894: 115 starts, 1 overlaps | village 595, military_base 511, capital_city 1289 | spawn safe | noon passive 6+0 hostile 6+9 | midnight passive 6+0 hostile 12+16
- seed 214813: 142 starts, 2 overlaps | village 197, military_base 177, capital_city 505 | spawn safe | noon passive 6+0 hostile 6+5 | midnight passive 6+0 hostile 10+0
- seed 222732: 140 starts, 4 overlaps | village 346, military_base 137, capital_city 879 | spawn safe | noon passive 10+4 hostile 6+18 | midnight passive 10+4 hostile 10+19
- seed 230651: 126 starts, 5 overlaps | village 730, military_base 467, capital_city 523 | spawn safe | noon passive 12+2 hostile 7+8 | midnight passive 12+1 hostile 10+0
- seed 238570: 103 starts, 1 overlaps | village 519, military_base 428, capital_city 645 | spawn safe | noon passive 6+0 hostile 8+8 | midnight passive 6+0 hostile 12+4
- seed 246489: 123 starts, 3 overlaps | village 902, military_base 664, capital_city 593 | spawn safe | noon passive 23+2 hostile 9+0 | midnight passive 23+2 hostile 9+2
- seed 254408: 147 starts, 1 overlaps | village 1350, military_base 1212, capital_city 1739 | spawn safe | noon passive 13+4 hostile 0+17 | midnight passive 11+5 hostile 7+22
- seed 262327: 100 starts, 5 overlaps | village 839, military_base 148, capital_city 1443 | spawn safe | noon passive 6+0 hostile 11+3 | midnight passive 6+0 hostile 10+0
- seed 270246: 159 starts, 5 overlaps | village 881, military_base 353, capital_city 612 | spawn safe | noon passive 12+4 hostile 1+13 | midnight passive 12+4 hostile 7+11
- seed 278165: 119 starts, 2 overlaps | village 783, military_base 553, capital_city 1125 | spawn safe | noon passive 17+0 hostile 9+0 | midnight passive 17+0 hostile 10+1
- seed 286084: 126 starts, 2 overlaps | village 640, military_base 461, capital_city 697 | spawn safe | noon passive 8+1 hostile 0+14 | midnight passive 8+1 hostile 8+9
- seed 294003: 128 starts, 2 overlaps | village 1161, military_base 978, capital_city 701 | spawn safe | noon passive 5+4 hostile 3+6 | midnight passive 4+4 hostile 9+11
- seed 301922: 143 starts, 1 overlaps | village 342, military_base 698, capital_city 994 | spawn safe | noon passive 20+2 hostile 1+10 | midnight passive 18+3 hostile 10+2
- seed 309841: 100 starts, 2 overlaps | village 386, military_base 456, capital_city 334 | spawn safe | noon passive 11+0 hostile 5+2 | midnight passive 10+0 hostile 10+2
- seed 317760: 136 starts, 4 overlaps | village 432, military_base 359, capital_city 677 | spawn safe | noon passive 16+4 hostile 2+8 | midnight passive 16+4 hostile 10+1
- seed 325679: 109 starts, 4 overlaps | village 69, military_base 198, capital_city 404 | spawn safe | noon passive 23+2 hostile 7+13 | midnight passive 23+4 hostile 12+10
- seed 333598: 112 starts, 3 overlaps | village 272, military_base 425, capital_city 752 | spawn safe | noon passive 5+3 hostile 10+2 | midnight passive 5+4 hostile 10+5
- seed 341517: 138 starts, 3 overlaps | village 341, military_base 395, capital_city 651 | spawn safe | noon passive 13+1 hostile 7+4 | midnight passive 11+1 hostile 11+8
- seed 349436: 91 starts, 1 overlaps | village 554, military_base 883, capital_city 262 | spawn safe | noon passive 11+0 hostile 11+1 | midnight passive 11+0 hostile 10+0
- seed 357355: 104 starts, 2 overlaps | village 352, military_base 360, capital_city 311 | spawn safe | noon passive 8+1 hostile 7+3 | midnight passive 7+0 hostile 10+0
- seed 365274: 95 starts, 0 overlaps | village 455, military_base 242, capital_city 1447 | spawn safe | noon passive 5+0 hostile 4+6 | midnight passive 5+1 hostile 9+4
- seed 373193: 108 starts, 3 overlaps | village 254, military_base 317, capital_city 15 | spawn safe | noon passive 7+3 hostile 25+8 | midnight passive 7+2 hostile 13+6
- seed 381112: 111 starts, 6 overlaps | village 327, military_base 453, capital_city 702 | spawn safe | noon passive 3+0 hostile 0+0 | midnight passive 3+0 hostile 10+1
- seed 389031: 137 starts, 4 overlaps | village 1751, military_base 1544, capital_city 908 | spawn safe | noon passive 11+4 hostile 3+13 | midnight passive 11+4 hostile 8+11
