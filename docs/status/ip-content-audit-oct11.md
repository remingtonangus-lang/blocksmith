# Content lookalike audit (Oct 11 Quest playtest P19)

Remington, 12:45-12:48: a deep-dark-style cave with a warden-like mob appeared, which he never asked for. The ask:
audit content copied from the reference game (warden, deep dark, end city and similar) and replace it with original
designs or remove it. Names were already scrubbed (docs/status/ip-renames.md); this is about *designs* that copy one
reference feature whole.

## Removed now (lane A, PlaytestOct11Tests.noMurkDepths checks it)
| Copy of | Here called | What changed |
|---|---|---|
| Deep dark cave biome (sculk floors, sensors, shriekers, catalysts under low-erosion country) | Murk Depths | Not generated any more (WorldGen.decorateCaves, Spawning.biome). Murk blocks stay registered for old saves and the creative menu. |
| Ancient city | Buried Citadel | No longer placed (BigStructures.types). |
| Warden summoned by the 4th shriek | Deep Stalker | Shriekers (placed or old-save) no longer call it (GameBlocks.stalkerCalls). The Deep expansion's own keep guardians are original designs and stay. |
| A loud eerie "cave noise" sting | Cave noises | Dropped from the random cave stings (it was also the unidentified sound of P14). |

## Still close copies (queued as backlog G20: replace each with an original design)
| Copy of | Here called | Note |
|---|---|---|
| The End dimension, end city and ender dragon | The Hollow, Hollow Spire, Void Dragon | Whole dimension; the spine (hell, the Reich below) never uses it. Candidate to remove from progression. |
| Nether fortress and bastion | Cinder Fortress, Boarling Keep | Hell is in the spine; its structures should become the Reich's own architecture. |
| Ocean monument and elder guardian | Sea Temple, Elder Spikefish | |
| Woodland mansion | Forest Manor | |
| Trial chambers | Proving Halls | |
| Lush and dripstone cave biomes | Lush / Driprock caves | Generic enough (moss, stalactites) to keep with original plants. |

Original game content the audit found that stays: towns and their law, capitals, citadels and military bases, the
frigate navy, Boreal Station, the Ash Vault war, the Deep, horses' bonding, guns and armour.
