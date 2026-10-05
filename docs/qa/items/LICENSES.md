# Item art: sources and licences

Every item icon, held-item model and dropped-item model is generated procedurally by Blocksmith's own code at
startup; no external images, models or fonts are used.

| Asset | Source | Licence |
|---|---|---|
| Tool and armour icons (7 tiers x sword, pickaxe, axe, shovel, hoe, spear; 7 sets x 4 pieces) | `Sources/ItemHD.swift` vector designs (signed-distance shapes, procedural materials) | original, part of Blocksmith |
| Common item icons (food, ingots, gems, dusts, bow, buckets, compass, clock, ...) | `Sources/ItemHD.swift` (`common`) | original, part of Blocksmith |
| Every other item icon | Blocksmith's own 16 px pixel art (`ItemArt.swift`, `ItemShapes.swift`) scaled with Scale2x (EPX, a public-domain algorithm) and relit | original, part of Blocksmith |
| 3D item models | extruded from the icons at runtime (`Sources/ItemModels.swift`) | original, part of Blocksmith |

No CC0 or third-party assets were imported for items, so there is nothing to attribute.
