# Open-source harvest, Nov 15 2026 (for Fable)

Remington's ask: find games and tools other developers built and gave away, mostly ones shown off on X, and take every piece Sunderfall can legally use.
Only permissive licences are listed: MIT, Apache, BSD, WTFPL, Unlicense or CC0. Each licence was checked in the repo's own LICENSE file.
None of this code is Swift except heckj/Voxels, so the rest is **algorithms and designs to port**, not files to drop in.
For MIT and Apache code, keep the copyright line in the game's licences screen if code is copied close to verbatim.
Clone any of these on demand with `git clone --depth 1 https://github.com/<repo>`. They are also on the Mac under `~/Documents/Blocksmith/asset-intake/code/`.

Assets (sounds, models, textures) are on the Mac only: `~/Documents/Blocksmith/asset-intake/`. That folder's LICENSES.md has the source and licence of every pack.
**Do not commit the Sonniss sounds raw into this public repo.** Their licence allows them inside the shipped game but bans redistributing the raw files. The CC0 packs are fine to commit.

## Mapped to open problems

### View distance 24 is triangle-bound (P375, P384, P392, P403, "can't render the citadel I'm shooting at")
- **voxelize/voxelize** (MIT) has a far-terrain layer:
  - `server/world/far_terrain.rs` samples surface height and material per low-res tile without generating chunks, on a worker with a bounded cache.
  - `packages/core/src/core/world/far-terrain-lod.ts` is a quadtree. Tiles split by angle subtended. Tiles with high relief split further, so mountains keep their shape. A parent keeps drawing until all its children are built, so there are never holes.
  - `far-terrain-seam.ts` handles the seam where the far layer meets loaded chunks.
  - `far-terrain-materials.ts` paints the far layer from the same block textures and biome tint, so the join doesn't show.
  - `crates/gen/src/flora.rs` has a "canopy" summary per tree species, which lets far tiles show forest.
- **stared/warsaw-vibe-voxel** (MIT code; the map data is ODbL, don't ship it):
  - `web/src/city.ts` and `stream.ts` give full detail nearest-first under a triangle budget. Where the budget runs out, an 8 m "clay" level stands in, and each city block turns real once all its tiles are in.
  - The README's blind A/B test: judges couldn't tell budgeted streaming from all-in-memory (p = 0.8).
- **Conflict to flag:** Remington ruled that everything out to view 24 must look exactly like the land near him (P339). Both projects above draw cheaper geometry far away. Warsaw's A/B result is evidence that this can be invisible. Ask him before relaxing the rule.
- **scallyw4g/bonsai** (WTFPL):
  - Octree world with GPU terrain generation: `shaders/terrain/shaping`, `decoration`, `TerrainFinalize`.
  - `src/engine/lod.cpp` extracts boundary voxels along chunk edges.
  - Worth a look for moving generation to the GPU, given the Quest CPU budget.

### Trees: 100 preset trees, no procedural logs, fell as one piece (Nov 15 notes 18–25, 20:50–21:12)
- Models:
  - Quaternius Stylized Nature MegaKit (CC0): trees, bushes, rocks, stumps in FBX/OBJ/glTF.
  - Kenney Nature Kit (CC0): 329 low-poly models, 61 of them trees, plus logs and stumps.
  - Use them as shape references or voxelise them into the preset list.
- Placement:
  - Voxelize `crates/gen/src/flora.rs` uses a deterministic two-level lattice. Grove clusters roll on jittered cells, gated by a low-frequency patch field (real clearings).
  - Placement re-derives per chunk, so a tree crossing a chunk border is identical from both sides. That fixes stumps added to log posts and trees cut at borders.
  - The same lattice also fixes "things spawn in clumps" (horses, 21:17).
  - Stamp the preset models through it instead of growing logs.

### Building feel, half blocks, the "two blocks placed at once" bug (Nov 15 08:41–08:46, "nearly unplayable")
- **Shoalstone/quietengine** (MIT):
  - `src/render/sculptbits.js`: a block shape is a 16x16x16 occupancy grid. A greedy box decomposition gives exact collision and selection boxes.
  - `src/world/cellrules.js`: one place decides which cell a body can collide with or target. Raycast and collision both ask it, so they cannot disagree. A mismatch between the two is a likely cause of the double-place bug.
  - `src/world/raycast.js` is the block-targeting raycast to compare against ours.
- **heckj/Voxels** (MIT, Swift):
  - `GreedyBlockMesh.swift`, `Renderers/SurfaceNetRenderer.swift`, `Renderers/MarchingCubes.swift`, plus `VoxelStorage/HeightmapConverter.swift`.
  - It's Swift, so it can be read directly for P338's real-polygon ground.

### Ice ("do better than Minecraft ice", flat panes, bullet holes; 21:08, 08:39)
- Quiet Engine `src/render/clearice.js` (and its `docs/clearice.md`):
  - Bulk clear ice you see into. Depth comes from the depth peel with no extra pass.
  - The mesher culls interior faces, and `gl_FrontFacing` tells entry from exit.
  - A frozen lake can show what's under the surface.
- No free CC0 ice texture set exists on Poly Haven.
- godotshaders "ice-covering" (MIT) is a 2D screen overlay only (cracks, frost). It could serve as a frost and crack overlay idea.

### Water and lava (P363)
- Quiet Engine `src/world/fluids.js`:
  - Scheduled-tick cellular fluid. A level is the distance from the feeding cell.
  - Flow spreads toward the nearest drop, using a drain field.
  - Depth, submersion and current all read the same corner-height sheet the mesher draws, so water can't look one way and behave another.
  - That covers "remove the source and it drains" and "settles onto the beach".
- `src/phys/pbfluid.js`: position-based fluids, for splashes or lava blobs if wanted.

### Roads, traffic, horses and carriages, trains that never end (21:12–21:13, 21:07–21:08)
- **warsaw-vibe-voxel** `web/src/sim/`:
  - `life.ts` runs cars on the Intelligent Driver Model per lane, with junction locks, signals, pedestrians at crossings, and density that follows the hour. Carriages on roads could follow the same pattern.
  - `trains.ts`: trains brake for stations and keep their distance behind the train ahead on the same track.
  - `crossings.ts`: level crossings.
- **amilich/isometric-city** (MIT; AI-built city sim):
  - `src/components/game/trainSystem.ts`: carriages follow the locomotive along bezier curves, with following-distance speed control.
  - `railSystem.ts`: level crossings with gates and signals, and `findPathOnRails`.
  - `trafficSystem.ts`, `pedestrianSystem.ts`, `bridgeSystem.ts`.
- Neither generates a world-spanning rail network. The "no turnarounds, never ends" planner is still ours.

### Held items, torch in hand, viewmodel (Nov 14 cave torch, Panzerfaust looks bad in hand)
- Quiet Engine `src/render/viewmodel.js`:
  - Hand and held-item rig with equip animation, and poses stated in camera space.
  - It's desktop first-person, but the pose table idea carries over to VR grip offsets.

### Physics, falling trees and unsupported blocks (P351, P380)
- Voxelize `server/world/physics/` (`sweep.rs`, `rigidbody.rs`, auto-step).
- Quiet Engine `src/world/simfeel.js` puts every "feel" number in one table: gravity, slip, shove, settling, how a held item hangs.

### Sounds (ElevenLabs ends Nov 17)
On the Mac, in `asset-intake/`:
- **Kenney** (CC0):
  - impact: footsteps on wood, metal and generic surfaces
  - RPG: chopping, swords, cloth, doors
  - interface
  - sci-fi: engines, lasers, explosions
- **Sonniss GDC 2026** (royalty-free, no credit needed; 5 parts, unzipping):
  - pro libraries including Historical Weapons, Extreme Winds, vehicles, explosions and ambiences
  - Build a short list of what the game still needs, then pick from these before generating anything.

### VR native samples (low value; we already have OpenXR, Vulkan, multiview and foveation)
- leetvr/hotham (MIT/Apache): `systems/grabbing.rs`, `components/stage.rs` (moving the stage for locomotion).
- danwillm/Quest-OpenXR-Vulkan (MIT) and cshenton/quest_xr (MIT): minimal Quest bring-up.
- None has a vehicle-comfort solution. The tank motion sickness (two controls turn it) stays a controls fix on our side.

## Other assets collected (CC0, Mac only)
- Quaternius:
  - Medieval Village MegaKit: 300+ modular house pieces, tables and chairs. Answers "add desks and tables", 21:17.
  - Universal Animation Library: humanoid animations.
- Kenney:
  - Castle Kit
  - Survival Kit
  - Voxel Pack: block textures and tool icons
  - Particle Pack: smoke, fire, sparks, muzzle flashes
- Poly Haven: 208 texture maps (bark, planks, brick, cobblestone, moss, forest floor), CC0.
- SkyWolf CC0Tree: low-poly weapons, props and vehicles, with new ones weekly.
