# World gen, Oct 10 playtest follow-up (capitals, volcanoes, ruined gates, wild camps)

Source: Remington's Quest playtest of Oct 10 (seed 2943808052895834412), docs/playtests/2026-10-10/voice-notes.md:
09:22:48 "capital buildings are supposed to be more rare, why did I just find one", 09:23:06 "the volcano just looks
weird in the background, that shouldn't be there", 09:23:19/26 "volcanoes don't mesh very well into the environment",
09:25:29/35 "these broken portals, not really any point". Plus a new feature: small wild camps to stumble on.

Code: `Sources/WorldRules.swift` (placement rules), `Sources/WildCamps.swift` (camps), `Sources/Landmarks.swift`
(volcano siting and foothills), `Sources/WorldGenCheck.swift` (`--worldgencheck`, `--volcanosites`), small hooks in
CapitalCity.swift / MilitaryBase.swift (one line each), OverworldStructures.swift (type list), WorldGen.swift (surface,
snow), Structures.swift (guard set, camp loot fallback), World.swift (one line: loads the guard), Game.swift
(findSpawn split into a terrain-only static), WorldAudit.swift (new summary lines), Commands.swift (/locate wild_camp).

## Old saves

Nothing already explored changes. On its first load with this build a world writes `structure-guard-oct10.txt` (the
chunks it had generated, never grows; a new world's is empty). A Capital city or citadel that the new rules would
drop stays wherever any of its chunks is in that set, so no explored city is cut in half; the rules only remove
placements (they never move one), so nothing new appears on explored ground (FactionTests: "none on explored ground"
on all 4 saved worlds on this Mac). Ruined gates fit in one chunk, so dropping them can't cut one in half; the key,
loot table and blocks stay registered. Volcano and foothill shapes are terrain: a save that had generated part of a
cone that is now gone (cold country) keeps its generated chunks, so a cut-off cone edge is possible there.

## 1. Capital cities (and citadels) near spawn

Rules (WorldRules): no Capital city within 1,200 blocks of the world spawn (+40 margin), and each 56-chunk region keeps
its city with probability 0.7. No Capital citadel within 320 blocks of the spawn (soldiers on top of a new player);
citadels otherwise unchanged (Remington wanted them findable, playtest 2). The spawn is the game's own terrain-only
spawn search (Game.findSpawn, now static), cached per seed.

| measure (20 seeds, `--worldaudit 20 --secs 0`, real spawn) | before | after |
|---|---|---|
| nearest Capital city from spawn | min 224, median 1064, max 1978 | min 1248, median 1592, max 2448 |
| seeds with a Capital city within 1,200 | 14/20 | 0/20 |
| seeds with a Capital citadel within 320 | 7/20 | 0/20 |
| Capital cities per 2048^2 square | 0.9 | 0.65 (`--worldgencheck`: 2.60 per 4096^2) |
| nearest Capital citadel from spawn | min 65, median 467, max 1458 | min 335, median 587, max 1458 |
| citadels per 2048^2 square | 4.0 | 3.8 |

Remington's seed: the seed's spawn is at 5432,1928 and its nearest Capital city is now 2,076 blocks from it (25
seeds incl. his: min 1,248, median 1,631). The city he met (09:22:48, at -1155,-26) is about 6,700 blocks from that
spawn, so his Quest world's play area is near an older or a respawn origin, not the seed spawn; it is explored, so
it stays in that save either way. New worlds get the rule.

## 2. Volcanoes

Seen: a snow-capped cone over snowy taiga next to a beach, a hard rock edge on flat ground
(worldgen-oct10/volcano_beach_before.jpg, volcano_taiga_before.jpg).
Changes (Landmarks.swift, WorldGen.swift):
- Siting: besides the old rules (land, away from coast and ranges), the surface temperature with altitude must be
  above -0.1 at the centre and at 24 points round the foot (no snow country), dry land (no sea, bay or lake, continent
  value > 0.02, height > sea + 2) at 1.0 and 1.3 foot radii all round, and the foot within 55 blocks of the base.
- Foothills: a lobed apron of grassed, wooded low hills (up to 13 % of the cone's height) from the foot out to 1.45
  radii; river valleys keep their floor. The cone rises out of a swell of land instead of standing on a flat plain.
- Surface: the rock edge is ragged (surface noise sets where basalt starts), coarse dirt and tuff thin out over the
  foot; no snow anywhere on the cone (volcanic heat).

| measure (25 seeds, 1,377 cells of 1280^2) | before | after |
|---|---|---|
| cells with a volcano | 110 (8.0 %) | 31 (2.3 %) |
| turned down by the new rules | - | cold 50, water round the foot 23, uneven foot 6 |
| volcanoes with snow-biome or wet ground round the foot (checked at 12 points, 1.2 radii) | not checked | 0 |
| Remington's seed, cones near his notes (cells -1,-1 and 1,-1) | 2 | 0 (both "cold") |

Shots: volcano_beach_after.jpg (his 09:23:06 view: the cone is gone), volcano_foothills_135623.jpg (foot and apron),
volcano_mid_135623.jpg (rd 24 from 360 blocks), volcano_far_135623.jpg (650 blocks at rd 16). Far away the cone
still reads pale: that is the renderer's distance haze over unloaded terrain (render-distance work, not changed here).

## 3. Ruined gates

Removed from overworld generation (OverworldStructures.types); `ruinedPortal` and the "ruined_portal" loot table
stay for reference and old saves; /locate lists Wild Camp instead. Before: 9.8 starts per 2048^2 square; after: 0.

## 4. Wild camps (new)

Structure type `wild_camp` (start kinds `camp_*`), 20 x 20-chunk regions, 85 % roll, then: dry, fairly level ground
(within 3 blocks at 9-11 blocks out), not on a volcano or in a canyon, clear of villages (96), watchtowers (80),
temples (48), citadels (170), Capital cities (240), Boreal Stations (80), manors (96), trail ruins (48), spires
(120), desert wells (32). Variant by country, weights: the country's camp 3, abandoned 1, outlaws 1 (outlaws only
400+ blocks from spawn). Ground levelled to the centre, eased back to the natural ground over the last 2 blocks,
filled down to solid ground; trees keep out of the footprint (a clearing). Each has a loot chest.

| kind | where | what |
|---|---|---|
| camp_hunters | forests, taigas, groves, cherry groves | hide tent (brown or green wool, ridge pole), campfire with log seats, drying rack hung with hides, barrels and hay, chopping block |
| camp_prospectors | windswept hills, savanna plateau, badlands, meadow, high open ground | timber headframe over a test pit with a hanging lantern, rail track to an ore cart (barrel + raw iron), gravel and ore spoil heaps, canvas lean-to over a crafting table, grindstone |
| camp_traders | plains, savanna, meadow, snowy plains, desert | covered wagon on log wheels (canvas on fence hoops, goods inside, a step at the tail), hitching post with a donkey, wandering trader (70 %), barrels, hay, fire |
| camp_abandoned | any of the above | collapsed tent, cold fire, cobwebs, a barrel, a bone pile, sparse chest |
| camp_outlaws | forests, taigas, savanna, badlands, plains, 400+ from spawn | two dark tents, lookout platform with ladder, target, a Brigand and a Marauder |

Counts (`--worldgencheck 24`, 25 seeds): 4.9 camps per 2048^2 square (hunters 40, traders 30, abandoned 27,
prospectors 14, outlaws 12). `--worldaudit 20`: 4.4 per 2048^2. `--structcheck --kinds wild_camp` over 6 seeds,
36 camps: 0 issues (2 floating and 3 unreachable-barrel issues found and fixed on the way: fill to solid ground, a
step onto the wagon). Shots: worldgen-oct10/camp_*.jpg (seed 12345 and Remington's seed).

## Checks

- `Blocksmith --worldgencheck 24` (about 10 s, gating in snap.sh): no Capital city within 1,200 of spawn and one
  within 4,000; no citadel within 320 and one within 1,500; 0 ruined gates; camps 2...14 per 2048^2 with every kind
  present, each on dry land off volcanoes, outlaws away from spawn, no overlap with villages/citadels/cities/
  outposts/temples/manors; every camp loot item exists; every volcano with dry, non-snowy ground round its foot.
- `Blocksmith --volcanosites SEED X Z`: the volcano cells round a point with their verdicts and foot biomes.
- `--worldaudit` summary adds: cities within 1,200 / citadels within 320 of spawn, ruined gates, camps by kind.
- Unchanged checks re-run: `--questbugs --only factions` all ok; `--structscan 8` ok; `--gencheck` identical to
  the baseline build; `--structcheck --seeds 12345,777,424242 --per 3 --strict` 2 issues (jungle_temple and
  capital_city floating on seed 424242), the same 2 on the baseline build (pre-existing).
