# P383: adaptive ground, what P381 didn't finish

Host numbers: `questcheck` built with the headset's compiler settings (`QUEST_OPT=-Ounchecked`), Remington's seed
13480747113613945685, Polygons world, Quest settings (`--field --questlod`). "Before" is origin/claude/quest-port at
b1c982ae (P381 + P382), "after" is this change. The cloud box (4 cores) was building the lane's and this item's
binaries during most runs, so record and lavapipe milliseconds swing by 10-30% run to run; quad counts are exact.
There is no GPU here: GPU cost is read from quads and from lavapipe (a CPU rasterizer, not an Adreno).

Shots (too big for the repo): `/mnt/project-files/p383-shots/` (headset resolution, one eye 2064 x 2208, 104 degrees,
both eyes side by side; eye at 6080, 190, 700 raw, facing 123 degrees, 15 down, over Stone Gulch):
`gulch-view{8,16,24}-{full,adaptive}.jpg`, and 1:1 crops of the windows that differ most (`crop-c8-*`, `crop-c24-*`:
full left, adaptive right).

## What changed

- One vertex per ground position (step 2). Field ground vertices no longer carry the quad's texture facing: the normal
  is an absolute octahedral code (22 x 22 cells in 9 bits: the shade bits, the overlay bit and v; u = 30 marks the
  vertex), the texture is picked by the vertex's own normal, and `chunk_solid.frag` textures it triplanar from the
  world position (one texture read on most ground, two on steep slopes). Each quad still blends the materials of its
  4 corners (P142's blend), so a quad shows up to 4 materials by per-vertex weights. Ground positions drawn with two or
  more different vertices: 35% (P381) -> 4.1% at Stone Gulch, 3.1% at the camp; what is left is a real per-face
  material (an ore's face among rock, ground the blend leaves out) or a vertex with no field normal.
- The collapse joins across material, light and occlusion seams (step 3); the 0.05 shape bound holds as before. A
  join must stay true to every vertex it stands for: interpolated light within 1 level of 15, occlusion within half a
  step, and the vertex's own material at least 60% of the blend where it lies. Without those guards (shape only) the
  ground goes to 58.5% instead of 64.5%, but pixels differing by more than 8 of 255 double (3.10% vs 1.58% at view 8)
  and by more than 32 grow 4.6x (0.345% vs 0.075%): borders between grounds and torch-lit patches move.
- The bound is measured against the field's exact surface (step 4): the surface nets' unsnapped positions
  (`MeshScratch.groundExact`), with a vertex identified by its exact position, so two field vertices the 1/16 grid
  draws at one place are no longer merged. A collapse also refuses a triangle that would turn over on the 1/16 grid.

## The table (steps 1 and 8)

`questcheck --perfscenes --rd 8,16,24 --only gulch,camp --flyframes 0` (standing 5 s), before and after run back to
back. Quads drawn (ground: the near copies' ground quads of the visible sections), CPU record mean:

| scene, view | quads before | quads after | ground before | ground after | record before | record after |
|---|---|---|---|---|---|---|
| Stone Gulch 8 | 100,818 | 94,192 | 40,102 | 33,445 (-16.6%) | 3.02 ms | 2.73 ms |
| Stone Gulch 16 | 335,669 | 314,050 | 164,208 | 137,603 (-16.2%) | 5.53 ms | 5.85 ms |
| Stone Gulch 24 | 831,130 | 782,312 | 385,555 | 331,408 (-14.0%) | 11.83 ms | 11.56 ms |
| camp 8 | 87,225 | 82,059 | 32,351 | 27,185 (-16.0%) | 2.75 ms | 1.78 ms |
| camp 16 | 185,860 | 177,444 | 69,806 | 59,640 (-14.6%) | 4.19 ms | 3.55 ms |
| camp 24 | 233,594 | 222,919 | 90,208 | 75,818 (-16.0%) | 5.97 ms | 6.91 ms |

Lavapipe frame for the headset shot over Stone Gulch (both eyes), two back-to-back runs:

| view | quads before | quads after | lavapipe before (run 1 / 2) | after (run 1 / 2) |
|---|---|---|---|---|
| 8 | 115,833 | 108,790 | 795 / 557 ms | 704 / 562 ms |
| 16 | 513,815 | 481,835 | 810 / 832 ms | 875 / 811 ms |
| 24 | 1,441,064 | 1,363,492 | 1,366 / 1,598 ms | 1,450 / 1,414 ms |

The triplanar texture costs nothing measurable: the same binary with `BS_TRIGROUND=0` (per-quad facing) draws the view
8 shot in 559 / 561 ms against 543 / 544 ms with it.

## Bound and borders (steps 5 and 6)

`questcheck --adaptivecheck` (every ground section of the 5 x 5 chunks round the eye, full vs adaptive, both against
the exact surface):

| spot | sections | ground quads full -> P381 -> now | near copy worst (points over 0.05) | far copy worst (over 1/8) | border edges differing |
|---|---|---|---|---|---|
| Stone Gulch | 235 | 74,090 -> 53,329 (72.0%) -> 47,776 (64.5%) | 0.0500 / 0.0500 (0 of 444,540 / 0 of 646,926) | 0.1249 / 0.1250 (0 / 0) | 0 |
| camp | 324 | 106,899 -> 81,079 (75.8%) -> 71,391 (66.8%) | 0.0500 / 0.0500 (0 of 641,394 / 0 of 967,764) | 0.1249 / 0.1250 (0 / 0) | 0 |
| in a cave under Stone Gulch (6094, 93, 688) | 235 | as Stone Gulch | 0.0500 / 0.0500 (0 over) | 0.1249 / 0.1250 (0 over) | 0 |

(The check covers every section of those columns, the caves under them included, so the cave run repeats the
Stone Gulch numbers.) The far copy goes 47,615 -> 39,537 quads at Stone Gulch, 71,032 -> 60,609 at the camp.

As drawn, every vertex sits on the 1/16 grid (the vertex format), which adds up to 0.054 block at a vertex for the
full and the adaptive ground alike: drawn full ground to the exact surface, worst 0.0504 at a triangle's points (3 of
1,028,797); drawn adaptive ground worst 0.0795 (1,304 of 644,098 over 0.05). A few hundred exact vertices of slivers
the grid flattens to nothing (both grounds) have no drawn triangle within 0.25.

Mesh cost on the workers (the 5 x 5 chunks, one thread): full 585 ms, P381 adaptive 1,380 ms, now 1,826 ms.

## Shots (step 7)

Pixels differing between the full and the adaptive ground (both eyes, 9,114,624 pixels):

| view | by more than 8 of 255 | by more than 32 of 255 |
|---|---|---|
| 8 | 144,337 (1.58%) | 6,857 (0.075%) |
| 16 | 173,743 (1.91%) | 6,673 (0.073%) |
| 24 | 187,439 (2.06%) | 7,673 (0.084%) |

(P381 had 0.89/1.08/1.20% over 8 and 0.08/0.09/0.11% over 32.) Looked at 1:1 across every window that differs most:
the grass/dirt edges of the town's paths, the sand by the river, the sand patches in the savanna and the red and sand
mesas on the horizon read the same in both; no smeared or bleeding material. What differs is shading: a cliff's dark
occlusion streaks are smoother on the bigger triangles (`crop-c8-0`), and slopes come out a level or two of 255
brighter or darker in patches.

## Still over (step 9)

View 24 at Stone Gulch draws 782k quads, about 2.4x the ~330k P376's numbers allow at 72 fps. With every seam joined
and no attribute guard the ground would be 58.5% of full (Stone Gulch) instead of 64.5%; at a 0.1-block bound 56.1%.
The ground is no longer the largest part: other opaque (built blocks and structures) is 345k of the 782k (P384).
