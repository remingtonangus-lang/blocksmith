# P384: sub-pixel far copies for everything that isn't ground

Host numbers come from `questcheck` built with the headset's compiler settings (`QUEST_OPT=-Ounchecked`), Remington's
seed 13480747113613945685, Polygons world, Quest settings (`--field --questlod`). "Before" and "after" use the same
binary: `BS_FARCOPY=0` meshes without the far copies, and the default meshes with them. `BS_FARCOPY=0` matches
P383's "after" numbers (782,387 vs 782,312 quads at Stone Gulch view 24; mobs move between runs). There is no GPU here: GPU cost is
read from quads and from lavapipe (a CPU rasterizer, not an Adreno). The timings in the tables were taken on a quiet
machine, with no build running.

Shots (too big for the repo): `/mnt/project-files/p384-shots/`. They are headset resolution (one eye 2064 x 2208,
104 degrees, both eyes side by side), taken from P381's spot over Stone Gulch (6080, 190, 700 raw, facing 123
degrees, 15 down):
- `gulch-view{16,24}-{full,far}.jpg`: the two renders.
- `gulch-view{16,24}-diff-over8.png`: white where the two differ by more than 8 of 255.
- `gulch-view{16,24}-crop{0..3}-full-left-far-right.png`: 1:1 crops of the four 256 px windows that differ most.

## Step 1: what view 24 draws (Stone Gulch, standing, before)

`questcheck --perfscenes --rd 24 --only gulch` with `BS_FARCOPY=0 BS_BLOCKTALLY=1`: 2,128 sections, 782,387 quads
drawn. The meshed quads by kind (`MeshKind`, tallied as each quad is emitted) of the visible sections, within and past
GroundMerge.farDistance (182 blocks: a section's nearest point at least that far from the eye):

| kind | within 182 (502 sections) | past 182 (1,626 sections) | past 182, in sections under the lowest surface (1,035) |
|---|---|---|---|
| ground (field surface) | 64,657 | 267,321 (drawn as P381's far copy: 224,493) | 207,641 |
| built blocks: cubes | 3,104 | 1,345 | 236 |
| built blocks: bevelled faces | 5,543 | 2,927 | 110 |
| props (models: carpets, stairs, fences, azalea...) | 12,635 | 169,329 | 168,657 |
| plants (crosses) | 23,352 | 122,176 | 80,048 |
| leaf blobs (2 cutout shells) | 23,790 | 56,320 | 0 |
| trunks and logs | 15,750 | 28,275 | 0 |
| round shapes (boulders, mushrooms...) | 5,236 | 12,495 | 49 |
| fluids | 18 | 4,753 | 4,753 |
| translucent | 2,391 | 1,473 | - |

Top meshed blocks (all loaded sections): moss_carpet 568k, short_grass 296k, cave_vines 193k, azalea 162k,
wildflowers 57k, hanging_roots 45k, big_dripleaf 40k, acacia_stairs 36k, acacia_planks 42k.

**The finding.** 1,035 of the 1,626 sections past 182 blocks lie wholly under their chunk's lowest surface
column. Those are caves, mostly lush caves: moss carpets, cave vines, azalea, dripleaf. They hold 168,657 of the
169,329 far props, 80,048 of the 122,176 far plants and 207,641 of the 267,321 far ground quads. The cull walks into
them through cave mouths and ravines, and the horizon and occlusion culls don't remove them. From a surface eye almost
none of their pixels can show. Removing them is a culling job, not a far copy, and it sits with P385 (cull is 7.5 ms
of the 11 ms record at view 24).

## Step 2: the error bound

A Quest 3 pixel is about 1/25 degree (P375), 0.000698 radians. At distance d it spans d x 0.000698 blocks:

| distance | one pixel | bound used |
|---|---|---|
| 182 (far switch) | 0.127 block | 1/8 = 0.125 |
| 270 | 0.188 | 1/8 |
| 360 | 0.251 | 1/8 |
| 384 (view 24's edge) | 0.268 | 1/8 |

A second, coarser copy at 1/4 block would be valid only from 358 blocks. At view 24 that covers the outer 26 blocks
of the view: (384² - 358²) / (384² - 182²) = 17% of the far ring's area. It would also cost a third copy of those
meshes in memory, which already grew 32 MB (below). So there is one far copy at 1/8 for everything past 182 blocks,
and it is under a pixel everywhere it is drawn. The same maths is in `Sources/FarCopy.swift`.

Light steps (step 5): one skylight level is 4-11% brightness (10-27 of 255 on a white texel) and one occlusion step is
19-31%. No step is under one level of 255 at any distance, because there is no fog in clear air. So built faces never
merge across a light step; they merge only where their corners' light, occlusion, material and tint all match.

## Steps 3-6: what was built

All of it is meshed on the workers with the section, never on the main thread. The renderer's far switch (P375,
generalised) picks per frame from the exact distance, so nothing remeshes as the player moves. Past 182 blocks:

- **Trunks, logs, boulders, round shapes, spikes, rails, struck cubes, free pieces** (the detail stream, step 3) get a
  far copy of the section's detail quads. It goes through AdaptiveGround's collapse, now generic
  (`AdaptiveGround.collapse<G: CollapseGuard>`), with a `DetailGuard`:
  - One material per join: the layer, tint and cutout must match.
  - Light within 1 level of 15 and occlusion within half a step.
  - Normals within 0.15, which keeps creases: a trunk's corner or a boulder's ridge has normals far apart and is never
    collapsed across.
  - Texture position within 0.1 block.
  - First, the vertices a shape's generator draws at one place with near-equal normals are joined (a trunk drawn
    block by block). The copy is kept when it saves at least 10%.
- **Leaf blobs** (step 4): one solid far shell in place of the two cutout shells. It is the outer shell (the one that
  makes the canopy's outline), drawn per position like the ground and simplified to the bound against that shell's
  exact surface. It is built per section, so a canopy that spans two sections has two pieces that meet at the
  section face; the outline is kept within the bound either way.
- **Built blocks** (step 5): the bevelled faces are drawn plain (their 1/16 chamfers are half a pixel there), and
  plain faces merge into runs where all four corners match (light, occlusion, material, tint), never across a
  material or colour edge.
- **Things laid on the ground** (P382 drapes: carpets, leaf litter, flower beds): the pieces that bend with the ground
  every 1/4 block are replaced by as few quads as stay within 1/8 of them. A rectangle becomes one quad on its corners,
  raised to stay on or over the ground, when the ground is within 1/16 of that plane. Otherwise it is halved, down to
  the pieces.
- **Plants (crosses), fluids, translucent**: unchanged. A cross is two quads with nothing to merge.

Stream layout: the opaque buffer is `[ground][bevelled near][rest solid][blob cut shells][draped near][other cut]
[draped far-only tail]` followed by the far copy `[ground far][bevel plain merged][blob far shell]`. The detail buffer
is the detail quads followed by their far copy. Section counts: `farSkip/farExtra` (P375), `farCut` (cutout quads
skipped far), `farTail` (cutout quads drawn far only), `detailFarSkip/detailFarExtra`.

Disk mesh cache (step 6): `MeshCache.format` 3 -> 4, and 15 counts a section (adds farCut, farTail, detailFarSkip and
detailFarExtra). The far copies are inside the stored opaque and detail buffers. This was checked by reading
`MeshCache.write`, `read` and `installShell`; there is no harness that reloads a save's mesh cache, so nothing ran
it.

### The bound, both ways (`questcheck --farcheck`)

Every section of the 5 x 5 chunks round the eye is meshed as the game does. Each far copy is measured against what it
stands for: every near point within 1/8 of the far copy, and every far point (corners, edge middles, centre) within
1/8 of the near quads.

| spot | sections | bevelled faces | leaf blobs | laid on the ground | detail |
|---|---|---|---|---|---|
| Stone Gulch: quads near -> far | 242 | 7,171 -> 3,462 | 4,410 -> 1,842 | 64 -> 4 | 10,319 -> 6,604 |
| worst near->far / far->near (block) | | 0.0625 / 0.0722 | 0.1224 / 0.1242 | 0.0625 / 0.0606 | 0.0714 / 0.0830 |
| forest camp: quads near -> far | 308 | 0 -> 0 | 16,708 -> 6,658 | 37,952 -> 12,985 | 7,690 -> 5,461 |
| worst near->far / far->near (block) | | - | 0.1250 / 0.1245 | 0.0931 / 0.0960 | 0.0777 / 0.1052 |

No point is over 1/8 at either spot. Leaf blobs are measured against the exact outer shell. Drawn, the 1/16 vertex
grid adds up to 0.054 either way, as for the ground.

Mesh cost on the workers (the 5 x 5 chunks, one thread): Stone Gulch 1,964 -> 2,050 ms (+4%), camp 2,874 -> 3,070 ms
(+7%). Mesh slabs at view 24: 416 -> 448 MB.

## Step 7: shots

Pixels differing between full and far copies (both eyes, 9,114,624 pixels):

| view | any difference | by more than 8 of 255 | by more than 32 of 255 |
|---|---|---|---|
| 16 | 21,986 (0.24%) | 5,270 (0.06%) | 2,671 (0.029%) |
| 24 | 47,392 (0.52%) | 11,085 (0.12%) | 5,634 (0.062%) |

Checked at 1:1 (the crops) and with the differing pixels marked over the whole left eye. The differences are
pixels on the far trees' canopies (tops and edges), where one solid far shell replaces two alpha-cut shells and the
canopy's edge pixels flip. The trees,
the town's roofs, the steel tower and the far hills keep their silhouettes, and I can't tell the pairs apart.

## Step 8: before and after

Stone Gulch perfscene, standing (`--perfscenes --rd 8,16,24 --only gulch --flyframes 0`):

| view | quads before | quads after | record before | record after | record stages after (cull / terrain) |
|---|---|---|---|---|---|
| 8 | 95,056 | 94,345 | 2.40 ms | 2.53 ms | 0.85 / 0.15 |
| 16 | 312,178 | 280,681 (-10.1%) | 5.67 ms | 5.57 ms | 3.35 / 0.65 |
| 24 | 782,387 | 655,481 (-16.2%) | 10.85 ms | 11.17 ms | 7.61 / 1.74 |

The forest camp gets the same treatment (its far side is forest): 177,444 -> 159,683 at view 16 and 222,919 ->
193,099 at view 24 (-13.4%).

Past 182 blocks at Stone Gulch view 24, by kind (drawn quads):

| kind | before | after |
|---|---|---|
| ground (P381's far copy, unchanged) | 224,493 | 224,493 |
| leaf blobs + built blocks | 61,255 | about 20,400 |
| things laid on the ground | 120,912 | 44,699 |
| detail (trunks, round shapes...) | 38,580 | 28,109 |
| plants (crosses), other props, fluids | unchanged | unchanged |
| total drawn (whole view) | 782,387 | 655,481 |

Headset shot over Stone Gulch (both eyes), lavapipe frame, two back-to-back runs:

| view | quads before | quads after | lavapipe before (run 1 / 2) | after (run 1 / 2) |
|---|---|---|---|---|
| 16 | 481,836 | 421,236 (-12.6%) | 627 / 667 ms | 619 / 613 ms |
| 24 | 1,363,493 | 1,135,175 (-16.7%) | 1,644 / 1,444 ms | 1,156 / 1,149 ms |

Record time doesn't move: the far copies change what each draw draws, not how many draws there are. Cull is about
70% of record at view 24, which is P385's work.

## Still over

P375's target is 72 fps on the Quest 3 at view 24 in Stone Gulch, which needs about 13.9 ms of GPU. P376's numbers
put that at about 330k quads for the Stone Gulch perfscene; it now draws 655k, about 2x. P375's headset log had
1.6-2.7 million quads at 54-72 ms of GPU. The headset shot here still draws 1.14 million quads both eyes; scaled,
that is roughly 30-38 ms of GPU, still 2-3x the budget. This can't be confirmed without the headset. What's left
past 182 blocks is mostly in caves under the surface (step 1's last column) and in crosses (grass and flowers, which
have nothing to merge). The options, for Remington:

1. **Cull sections under the surface from a surface eye** (P385's cull work). A section wholly under every column of
   its chunk and its neighbours can only show through a cave mouth. At Stone Gulch view 24 that is roughly 330k of
   the 655k quads. The risk is a far cave mouth drawn empty: it would show the cave fog colour, not the cave inside.
2. **Grass and flowers (crosses) stay as they are.** A cross is already two quads, and putting cards in place of
   them would be billboards standing in for shapes, which POLYGON STRICT rules out. Their count only falls with
   option 1 (80k of the 122k far crosses are in caves) or with fewer plants.
3. **A second, coarser copy past 358 blocks** (step 2): at most a few percent more, for one more copy in memory.
