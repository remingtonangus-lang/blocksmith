# Polygon terrain from the ground up (P142, with the polygon notes in P106, P107, P141, T17)

Remington's brief (Oct 13 12:28): convert the Quest game to smooth polygon terrain by porting, not rebuilding. Mesh the
world generator's continuous fields before they are quantized into blocks; keep the block grid as the source of truth
for everything else; ship it as the "Smooth" world option first.

## Expanded objectives (written before building)
1. **Field, not blocks.** Smooth sections mesh the generator's own continuous values: the terrain density (the 4x8x4
   trilinear lattice the stone fill thresholds, which already carries heights, rivers, cliffs and overhangs) and the
   three cave fields (cheese caverns, spaghetti tunnels, noodles). The same field values decide the blocks, so the
   surface sits exactly where the blocks are, at sub-block precision: no stair-steps to blur, no wavy relaxation, no
   checkered hillsides.
2. **Same world.** No generator change: same seeds, same layout, caves, towns, bases and structures in the same places.
   A world can flip between Blocks and Smooth at any time (Video > Smooth Terrain), and existing block worlds load
   unchanged.
3. **Blocks stay the truth.** Physics, collision, digging, saves, mobs, items, fluids and circuits keep reading blocks.
   The mesher compares every block with the field: where they agree it uses the field's zero crossing, where they do
   not (dug, placed, structure ground, banks, ponds, ravines) it falls back to the block face and relaxes those
   vertices only, so every edit shows and nothing pops back into a cube.
4. **Digging dents.** A dug block leaves a block-sized rounded dent in the smooth surface; chipping in progress dents
   the surface as before (P106).
5. **Structures crisp.** Built blocks (planks, bricks, cobble, rails, paths, logs...) stay cubes; ground vertices that
   touch them pin to their corners, so foundations meet the ground with no gaps.
6. **Materials.** Grass covers slopes that face up even where the exposed block is the dirt under a neighbour's turf
   (the old per-block choice striped every hillside grass/dirt/grass: the checkered look of P141); steep faces show dirt,
   rock shows its own stone. Blending between materials at their borders comes after the terrain works.
7. **Normals from the field.** Vertex normals come from the gradient of whichever field made the surface there, so hills
   shade as continuous slopes.
8. **Quest budget.** Field values are computed lazily per section (only the cells next to the surface), on the mesh
   workers, never on the frame thread; target 72 fps at render distance 12+.
9. **Other dimensions** (and any section without a generator field, e.g. ships) keep the round-2 smoothing.
10. Later rounds: material blending, smooth trees and water (T17), a slope-following foot height, then Smooth as the
    Quest default once Remington likes it on the headset.
