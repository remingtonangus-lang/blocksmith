# Polygon terrain from the ground up (P142) — status

Objectives: docs/objectives/polygon-ground-up.md. Branch claude/polygon-ground-up-0ah37u.

## How to try it (Quest)
Same switch as before: Create New World > **Terrain: Polygons (Smooth)**, or Options > Video > **Polygon Terrain (This
World)** in an open world (saved with the world; block worlds load as blocks). Overworld smooth sections now mesh the
generator's own fields; other dimensions keep the round-2 smoothing.

## What changed (round 3: the field port)
- `Sources/SmoothField.swift`: evaluates WorldGen's terrain density lattice and the three cave fields (cheese, spaghetti,
  noodles) at any block, with the same node values and interpolation order as the generator, lazily (only round the
  surface), on the mesh workers.
- `Mesher.smoothQuads` (SmoothTerrain.swift): a sample is "on field" when its block is what the fields alone make there.
  Edges between two on-field samples cross at the field's own zero crossing (sub-block precision); edges touching an
  off-field sample (dug, placed, built-over ground, banks, ponds, ravines, a block being chipped) fall back to the block
  face. Only off-field vertices relax, one gentle pass, so a dug pit stays a block-sized rounded dent.
- Normals come from the gradient of whichever field made the surface there; ambient occlusion from the 4x4x4 blocks
  round a vertex (the 8 blocks round it drew a dark contour line at every hillside step: the terraced/checkered look).
- Dirt facing up under a neighbour's turf shows the turf (hillsides no longer stripe grass/dirt per block row).
- Rock mixed block by block (deeprock/stone, emberslate/blackstone/basalt, tuff, granite...) shows as the commonest rock
  round each face, so cave walls read as patches instead of a grid of single blocks; ores keep their own look.
- `BLOCKSMITH_FIELD=0` meshes the round-2 way (side by side). Headless views: `questcheck --view OUT.png --smooth
  --find BIOME --up N --cave --dig N --dig-eye DX,DY,DZ --meshbench`.

## Next
Material blending in the shader (soft borders between grass, dirt, stone, sand), smooth trees and water (T17), a
slope-following foot height, mesh cost on the device, then Smooth as the Quest default once Remington likes it.
