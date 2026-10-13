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
- Material blending: every smooth vertex carries its own ground (the commonest of its 8 blocks; turf where the ground
  faces up, snow under a snow layer) and the Quest chunk shader blends a quad's corners (chunk.vert slots by vertex index
  mod 4, chunk_solid.frag: one texture read where a quad is one material). Grass fades into dirt, stone and sand; ores,
  magma, geodes and sculk stay crisp. The Mac shows each quad's first corner (no blend).
- Snow layers on smooth ground are no longer drawn as slabs (they made a white sawtooth on every snowy slope); the
  ground under them shows snow. They still exist as blocks.
- Cost (optimized questcheck, x86, 5x5 chunks): 2.0 ms a section with geometry (round 2 1.5, blocks 0.7), all on the
  mesh workers.
- `BLOCKSMITH_FIELD=0` meshes the round-2 way (side by side). Headless views: `questcheck --view OUT.png --smooth
  --find BIOME --up N --cave --dig N --dig-eye DX,DY,DZ --meshbench`.

## Round 4: view height and trees
- The eye follows the drawn ground under the feet (ViewStep: World.smoothGroundOffset springs viewDY toward the field's
  crossing round the feet, +-0.6), so walking a smooth slope no longer bobs up a block step at a time.
- Tree canopies (T17): in field worlds leaf blocks mesh as rounded blobs (a second smoothQuads pass over the leaves,
  round-2 rounding, no pins, cutout buffer) instead of leaf cubes. Each quad is drawn twice, the outer shell and a darker
  one 0.45 block inside, so the leaf texture's holes show leaves behind, not sky. The ground pass treats leaves as open,
  so the ground under a bush shows; logs and built blocks keep their faces against a blob. Trunks stay square (look
  work on trees is the Mac lane's). Leaves are still blocks: breaking, decay, shears and collision unchanged.
  `BLOCKSMITH_LEAFBLOB=0` keeps leaf cubes. Cost: a forest's meshing about 14% more than field without blobs (debug).
- Water (T17): a still-water surface that steps down a level (a river's terraces) ramps down to the lower surface
  instead of standing as a box with a flat side (Mesher.stepDown: a top corner shared with an open column over still
  water drops to the block bottom, the lower surface's own corner height). Water blocks are unchanged.
- Mobs within 48 blocks stand on the drawn ground too (Mob.easeStep springs viewDY toward World.smoothGroundOffset,
  the 4 column heights cached per mob by cell), so they no longer float or sink up to half a block on smooth slopes.

## Next
Smooth water shorelines if needed, mesh cost on the device, then Smooth as the Quest default once Remington likes it.
