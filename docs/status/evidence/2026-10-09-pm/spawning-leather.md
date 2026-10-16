# Surface spawning (PM #4) and leather (PM #8)

Check: `Blocksmith --snapshot snaps/pm9b.png --seed 12345 --find plains --time 0.3 --rd 4 --questbugs --only pm9b`.

## Surface mob density: half

`MobManager.surfaceSpawnScale = 0.5` (Spawning.swift):
- Night monsters on the surface fill half the monster cap (rd 6: 11 of 21). With that share full, a surface spawn
  sample is taken as a cave sample instead, so caves get at least the attempts they had (v78 cave spawning kept).
- Animal packs: 3.5% -> 1.75% of new chunks; timed animal spawns every 40 s instead of 20 s.

The check runs the spawner's own rounds (`hostileAttempts`, 4 a 0.25 s, no mob AI) at midnight, render distance 6, with
the scale at 1 (old) and at 0.5 (new) on the same world: three 60 s nights on the surface at the spawn and three in a
cave near it (monsters 8+ blocks under the ground), then `populateChunks` over the 109 loaded chunks.

| run | surface monsters, old -> new | cave monsters, old -> new | animals around spawn, old -> new |
|---|---|---|---|
| 1 | 63 -> 33 (x0.52) | 84 -> 93 | 12 -> 8 |
| 2 | 63 -> 33 (x0.52) | 102 -> 104 | 12 -> 8 |
| 3 | 61 -> 33 (x0.54) | 69 -> 92 | 12 -> 8 |

Animal pack roll over 14400 chunks: 558 -> 279 (x0.50). Asserts: surface x0.35-0.65, caves >= 0.75x old and >= 6,
animals around spawn <= 0.75x, pack rolls x0.45-0.55. The v78 spawning checks (in the full `--questbugs`) still pass.

## Leather

Cow, mooshroom, horse, donkey, mule, llama, trader llama: leather 0-2 -> 1-3 (Looting still adds +1 a level to the
top); tusker (hoglin) 0-1 -> 0-2. 400 kills each through `Game.mobDied`: cow 2.03, mooshroom 2.01, horse 2.02, llama
2.00 leather a kill (was 1.0).
