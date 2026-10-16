# Plant density per biome, before / after (playtest Oct 9 PM #3)

"Too much vegetation. Grass: try about 1/8 of the current amount. Cactus far too common. Review all plants for density."

Seed 12345 (the questbugs world). For each biome the check finds the middle of the biome (a spiral search where the
centre and 8 points 40 blocks out all match), then counts 5 x 5 chunks on two generators with the same seed:
`WorldGen.plantsBeforePM9 = true` (the v78 densities, i.e. this morning's) and the new one. The numbers are plants per
256 columns of that biome (one chunk). Stalks (cactus, sugar cane, kelp, bamboo) and two-block plants count once.
"flowers" = small flowers, "mushrooms" = red + brown. Plants not listed for a biome had zero before and after.

Command: `Blocksmith --snapshot snaps/pm9b.png --seed 12345 --find plains --time 0.3 --rd 4 --questbugs --only pm9b`
(the `pm9b-table:` lines).

| biome | plant | before /chunk | after /chunk |
|---|---|---|---|
| plains | short_grass | 24.92 | 2.56 |
| plains | flowers | 1.28 | 1.28 |
| plains | leaf_litter | 0.08 | 0.04 |
| plains | pumpkin | 0.12 | 0.12 |
| plains | bush | 1.64 | 1.64 |
| forest | short_grass | 4.68 | 0.20 |
| forest | flowers | 0.32 | 0.32 |
| forest | mushrooms | 0.12 | 0.12 |
| forest | leaf_litter | 5.04 | 1.44 |
| forest | pumpkin | 0.04 | 0.04 |
| desert | dead_bush | 1.96 | 1.44 |
| desert | cactus | 1.24 | 0.40 |
| desert | short_dry_grass | 3.52 | 1.24 |
| desert | tall_dry_grass | 1.04 | 0.28 |
| savanna | short_grass | 20.20 | 2.32 |
| savanna | flowers | 0.48 | 0.48 |
| savanna | pumpkin | 0.04 | 0.04 |
| savanna | short_dry_grass | 5.60 | 1.60 |
| jungle | short_grass | 3.38 | 0.58 |
| jungle | fern | 1.36 | 0.25 |
| jungle | large_fern | 0.45 | 0.08 |
| jungle | flowers | 0.12 | 0.12 |
| jungle | mushrooms | 0.12 | 0.12 |
| jungle | melon | 0.08 | 0.08 |
| jungle | bush | 2.22 | 0.91 |
| taiga | short_grass | 1.36 | 0.20 |
| taiga | fern | 3.80 | 1.32 |
| taiga | large_fern | 1.92 | 0.64 |
| taiga | flowers | 0.40 | 0.40 |
| taiga | sweet_berry_bush | 0.28 | 0.28 |
| taiga | mushrooms | 0.04 | 0.04 |
| taiga | leaf_litter | 0.04 | 0.04 |
| taiga | pumpkin | 0.04 | 0.04 |
| swamp | short_grass | 4.15 | 0.56 |
| swamp | fern | 0.21 | 0.04 |
| swamp | large_fern | 0.17 | 0.00 |
| swamp | flowers | 0.21 | 0.21 |
| swamp | sugar_cane | 4.49 | 2.18 |
| swamp | sweet_berry_bush | 0.04 | 0.04 |
| swamp | lily_pad | 5.99 | 3.51 |
| swamp | firefly_bush | 2.78 | 1.07 |
| dark_forest | short_grass | 1.63 | 0.05 |
| dark_forest | fern | 0.05 | 0.00 |
| dark_forest | large_fern | 0.05 | 0.00 |
| dark_forest | flowers | 0.05 | 0.05 |
| dark_forest | sugar_cane | 0.05 | 0.00 |
| dark_forest | mushrooms | 0.59 | 0.25 |
| dark_forest | leaf_litter | 1.68 | 0.44 |
| birch_forest | short_grass | 5.81 | 0.52 |
| birch_forest | flowers | 0.52 | 0.52 |
| birch_forest | mushrooms | 0.09 | 0.09 |
| birch_forest | leaf_litter | 6.47 | 2.46 |
| birch_forest | wildflowers | 1.98 | 1.09 |

Short grass over all nine biomes: 66.1 -> 7.0 per chunk (x0.106; the check wants <= 1/8).

## Per-plant review (multipliers on the v78 chances, `calm(...)` in WorldGenTrees.placeVegetation)

| plant | change | why |
|---|---|---|
| short grass (all biomes, also grass in deserts/badlands) | x0.11 | "about 1/8" (measured x0.10-0.17 per biome, x0.106 overall) |
| tall grass | none (0 since v78) | |
| fern / large fern | x0.35 | ground cover; taiga keeps the most (1.3 + 0.6 a chunk) |
| small flowers | unchanged; flower forest, meadow, cherry grove x0.7 | already 1-2 a chunk in plains (classic feel) |
| cactus | x0.35 | desert 1.24 -> 0.40 a chunk: about one every 25 blocks instead of every 14 |
| dead bush | x0.75 | desert 1.4 a chunk (classic ~2) |
| short / tall dry grass (desert, badlands, savanna) | x0.3 | dry ground cover, same cut as grass-like cover |
| sugar cane | x0.4 of shore columns | swamp 4.5 -> 2.2 stalks a chunk; was 12% of every water-side column |
| lily pad | x0.6 | swamp 6.0 -> 3.5 a chunk |
| leaf litter | x0.35 | forests 5-6.5 -> 1.4-2.5 a chunk |
| wildflowers (birch forests) | x0.6 | 2.0 -> 1.1 a chunk |
| bush (jungle) | x0.4 | 2.2 -> 0.9 a chunk; plains bushes already cut in v78 (1.6) |
| firefly bush (swamps) | x0.4 | 2.8 -> 1.1 a chunk |
| mushrooms (dark forest, old spruce taiga) | x0.5; mushroom fields x0.75 | 0.6 -> 0.25 a chunk |
| sweet berry bush, melon, pumpkin, sunflower, bamboo, kelp, seagrass, coral | unchanged | already rare / patchy, or the biome's point (bamboo jungle, kelp forests) |
