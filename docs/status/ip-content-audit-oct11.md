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

## Replaced with original designs (G20, OriginalSites.swift)
Each keeps its old structure key (saves, explorer maps and the locate list still find it) and is built only on ground
no save generated with the old design (the P44 guard on the surface, G20Guard in the Emberdeep and the Deep), so no
half-built old structure is left at the edge of explored land. The old builders stay for that ground only.
| Copy of | Was | Now |
|---|---|---|
| Trial chambers | Proving Halls | **Sealed Armoury**: a pre-war Capital armoury sealed underground, its dead garrison still walking it: a cast-concrete gallery with bulkhead doors to a firing range, a magazine, a barracks and a caged vault of arms. |
| Woodland mansion | Forest Manor | **Brigand Roost**: a gang's palisade fort in the dark forest: a log hall with a loft and the strongbox, a lookout tower, a corral of horses, a fire pit; Brigands and Marauders on guard. |
| Ocean monument and elder guardian | Sea Temple, Elder Spikefish | **Sunken Dreadnought**: a Capital battleship broken in two on the deep sea floor, turrets, funnels and bridge on deck, its magazine (gold, a strongroom of arms) in the stern, drowned crewmen. No elder guardians. |
| Nether fortress | Cinder Fortress | **Ash Foundry**: the Ashguard's works in hell on the same cell network: steel gantries on girder legs, brick furnace halls with smelters, cinderwisps penned in barred furnace cages, ember-wart tanks. |
| Bastion remnant (its four layouts) | Boarling Keep | **Boarling Mound**: the boarlings' stepped onyxstone mound over their hoard: domed huts round the foot, a tusker pen, a pillared hall and the hoard vault inside the terraces, braziers on the summit. |
| The End, end city, ender dragon | The Hollow, Hollow Spire, Void Dragon | **Out of new worlds**: a stronghold's portal room on new ground holds a reliquary (a sealed coffer and two chests) instead of the gate frames, so the Hollow can't be reached. Saves that already have a gate keep it. |

## Kept
| Copy of | Here called | Note |
|---|---|---|
| Lush and dripstone cave biomes | Lush / Driprock caves | Generic enough (moss, stalactites) to keep with original plants. |

Original game content the audit found that stays: towns and their law, capitals, citadels and military bases, the
frigate navy, Boreal Station, the Ash Vault war, the Deep, horses' bonding, guns and armour.
