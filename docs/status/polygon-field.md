# Polygon worlds: the ground is a density field (PG1, PG2, PG6 rewrite)

Remington, Oct 14: "forget blocks, polygon shouldn't use them even as a base". This is how a Polygons world works now
(PRs #253-#259 and step 8), what each backlog condition rests on, and what is still rounded.

## How a field world is made and kept
- **New worlds.** Create New World > Terrain: Polygons (the default) makes a field world (World.makeFieldWorld, marker
  `terrain-field.txt` in the save). Every dimension of that world is a field world too. Worlds saved before the field,
  and worlds created with block terrain, have no marker and stay block worlds for life. `--blockworlds` makes new
  Polygons worlds the old way (smoothed blocks) for comparison.
- **Storage.** Per chunk: `fd` (Int8 density per cell centre, 1/32 block, positive inside the ground), `fm` (ground
  material per sample: grass, dirt, stone, ores, sand...), and the built layer (`BlockStore.data`: plants, trees, fluids,
  structures, player blocks). Natural ground is never in the built layer. Saved as `t.X.Z.lz` beside the chunk and loaded
  as the field; a lost field file comes back from the seed.
- **Generation.** `TerrainGenerator.generateField`: the generator lays out the chunk, its structures are built into it
  (StructWriter marks what a piece builds), and `FieldTerrain.split` takes the ground out into the field. The density
  of every surface cell comes from the generator's own continuous fields, not from the cells:
  - Overworld: WorldGen's terrain density lattice and the three cave fields (SmoothField), plus the carvers' signed
    distances (ravines, sinkholes, lava pockets, floor lava) and ponds and pools from one continuous surface.
  - Emberdeep: the band's lattice density, its floor and roof caps as continuous noise surfaces (`fieldBlocks`
    lays the bedrock from the same surfaces), open distances just outside the band.
  - Deep: the Ash Vault's floor and roof noise, the pillars' and pockets' own distances, the core, the seal and the
    crust rows, and the hell band's lattice.
  - Hollow: each island column's continuous top, underside and rim distance (also out over the void), and the end
    stone laid from exactly that field.
- **Meshing.** Dual contouring of the stored densities: crossings and gradient normals from the field, each vertex's
  material from the ground just under the surface (blended between corners), shading from the field. Far chunks
  draw the field's smooth silhouette. No natural ground is ever drawn as block faces.

## Play on the field
- **Digging, blasts, rounds** subtract from the field (World.fieldCarve: a ball for digging, a bowl for a blast, a mark
  for a round); broken pieces are rigid-body debris meeting the field's surface. Bedrock is never carved.
- **Collision** for the player, mobs, animals, items and debris boxes: World.fieldBoxes, quarter-block columns from the
  trilinear field as the mesh draws it. Vehicles: hull spheres against the density, wheels on the field's surface.
  Items buried in the ground are pushed out along its normal; downed horses, dragged mobs and fishing bobbers rest on
  the field's surface (World.restHeight).
- **Rays** (mining, rounds, placing) meet the ground where the field crosses zero.

## Checks (questcheck)
- `--view OUT.png --field [--find BIOME | --at x,y,z | --near KIND] [--dim nether|end|deep] --fieldstats`: where each
  surface cell's distance came from, and the causes of the rest.
- `--fieldwalk`, `--fieldbodies`, `--fieldblast`, `--fielddump`, `--fieldsave` (field world and block world saved,
  reopened and compared cell for cell), `--playthrough --field`.

## Measured (seed 12345, step 8)
Share of surface cells whose distance comes from the generator's own continuous fields (`--fieldstats`, rd 3-6):
- Overworld: plains 99.4%, swamp 99.1%, windswept hills 99.6%; a village 98.8%, a Steelhold base 95.9%, the Capital
  city 93.3% (the rest is ground a structure cut back or banked up round its buildings).
- Emberdeep 100.0% (was 60% before step 8). Deep (Ash Vault and hell band) 98.3% (was 80%). Hollow: outer islands
  99.9% (was 85%), central island 95.8% (the rest is where the obsidian spikes stand in the island).
- Bodies dropped on open ground (`--fieldbodies`): mean gap to the drawn surface 0.015-0.023 block. Walking 8 headings
  on hills (`--fieldwalk`): mean |gap| 0.07-0.10 block. Cave bot: field caves are easier to move through than block caves.
- Saves (`--fieldsave`): a field world's density, material and built layer reopen with 0 of 196608 cells different; a
  block world reopens with 0 of 4.4 M cells different and no field written.
- Load cost (unoptimized build, plains, rd 6, 193 chunks, all cores): block world gen 7.6-8.4 s + mesh 20.3-23.8 s; field
  world gen 11.2 s + mesh 13.5-14.1 s. Generating the field costs about 40% more, meshing it about 40% less.
- Playthrough (`--playthrough --field`, seed 12345): spawn, tools, iron, diamonds, the Emberdeep fortress, the Hollow and
  its wyrm, the spire's jetpack, the Blight, then the Deep from the Wardstone floor to the Ash Chancellor's ending and the
  lift home: 124 checks passed, 0 failed.

## What is still rounded or still cells
- One density sample per block: shapes smaller than a block (a one-block hole, a thin ledge) round off.
- A few surface cells take their distance from the cells round them, smoothed (no block faces, but the shape is the
  generator's cells): structure cuts into the ground, stalactites and magma in the Deep, banks a structure lays.
- Water and lava are still cell fluids in the built layer; their surfaces meet the ground's smooth surface.
- AI pathing reads cells (a cell inside the ground reads as its material); collision does not.

## Where a field world still reads the block grid (P338 step 1, Oct 18)
Two kinds of reads. A **material read** asks what the ground is made of at a point (farming soil, bone meal, plant
support, ore drops, footstep sounds): it reads the cell's material through `BlockStore` (Chunk.swift `subscript`) and is
not a shape the player can see or feel. A **shape read** treats a ground cell as a full cube: those are the bugs. The
debug overlay's third line (PerfOverlay, field worlds) counts both kinds as "ground cell reads" per frame and the natural
ground meshed as cubes ("Ground as cubes"); the cube count must be 0 everywhere.

Shape reads, and what happens to each:
- Drawing: natural ground is never a cube in a field world (Mesher.swift: natural cells inside the field go to the dual
  contouring; one left in the built layer would be counted, `SectionMesh.naturalCubes`). Far chunks: the field on a
  2-block lattice (SmoothTerrain.coarseGround). Fixed.
- Collision of bodies, items, debris: World.collisionBoxes -> World.fieldBoxes (FieldTerrain.swift). Fixed.
- Pathing: PathFinder.solidTop read a ground cell as a full block (Pathfinding.swift solidTop, standCost, open). Now it
  reads the field's collision columns, and on the field a node may have the ground rising up to half a block into its
  feet cell. Fixed in this step (handoff step 9).
- Spawning and placing bodies: Spawning.swift (the stand checks at 332 and 395-398), Mob.swift 2703 and 2789 (dropping a
  body to the floor), MobAI.swift 248 pick a cell's floor. A new body is now set onto the field's surface once when it
  first updates (MobManager.update, `Mob.fieldSettled`), so the cell floor never shows. The searches themselves still
  step by cells: left as is (they only pick a column, the surface decides the height).
- Raycasts for mining and placing: World.raycast (World.swift 1473) steps cells and meets ground where the field crosses
  zero (Game.swift 1928-1969 finds the surface point). The hit is still a cell for what happens next (dig a ball there):
  step 8 (free building) moves placing off the grid.
- Digging, blasts and rounds: World.fieldCarve subtracts round shapes from the field. Ground placed by the player is a
  cell-sized lump (World.fieldShape): step 8.
- Fluids: water and lava are still cells of the built layer (World.fluidTick): step 5 / P363.
- Density samples: one per block (FieldData.fd): step 4.
- Riding: Riding.swift 482 asks whether a horse's head is in a solid cell (ground as a cube under an overhang): it reads
  the material, then World.collides decides; low-impact, left.
