# Realistic world: shape, damage and physics layer (design)

Owner: the realistic-world thread (backlog P142, P175 and the polygon notes P106, P107, P141, T17). Started Oct 13.
World option: **Create New World > Terrain: Polygons (Smooth)** (and Options > Video > Polygon Terrain for an open world).
It becomes the Quest default only after Remington approves it on the headset.

## The principle (Remington, Oct 13)

Everything in the world should look like what it really is, and react physically when it is damaged. Pumpkins and trees
were only examples. No list of special cases: systems that apply to every block, plant, object and creature
automatically. Keep everything the game already has (generation, seeds, caves, towns, bases, structures, mobs, items,
saves, gameplay) and change how it looks and breaks: a new representation and physics layer under the same content.

So every rule below reads data the game already has (block definitions, the generator's own fields, mob models) and
never names a block. Where a rule needs a hint (a gourd is ribbed, a mushroom has a cap), it keys on a *family* derived
from the definition (render type, material, tool, axis states, textures), not on a block.

## Layers

| Layer | What it is | Where it lives |
|---|---|---|
| 0. Backbone (unchanged) | The block grid: saves, world generation, mining rules and times, drops, crafting, light, path finding, circuits | Chunk / World / Save (no format change) |
| 1. Form | Each block state gets a realistic form from its shape class; natural ground is one smooth surface | `ShapeClass.swift`, `DetailMesh.swift`, `ShapeTrunks.swift`, `ShapeOrganic.swift`, `ShapeBuilt.swift`, SmoothTerrain |
| 2. Damage | A hit removes exactly the volume it touched and fractures it into pieces made on the spot | `Damage.swift`, `Fracture.swift` |
| 3. Physics | Debris are rigid bodies; creatures die into ragdolls; things stand on the drawn surface | `RigidBodies.swift`, `Ragdoll.swift`, `SurfaceQuery.swift` |
| 4. Budgets | Quest 3 at 72 fps, render distance 12-16 | meshing and fracture on the mesh workers, physics budgets |

The block grid stays the truth for gameplay. The layers above it are a view of it (form), a memory of what was chipped
off it (damage, cosmetic until the block breaks) and short-lived bodies (physics). A save holds blocks only, so a
smooth world loads exactly as before; chips in progress are not saved (a half-mined block comes back whole, as today).

## 1. Shape system

### 1.1 Shape classes, derived for every block state

`ShapeClass.of[state]` is computed once at start-up from each `BlockDef`, in this order (first match wins):

| Class | Rule (from the definition, never a name list) | Form |
|---|---|---|
| none | air, `render == .none` | nothing |
| liquid | `render == .liquid` | continuous liquid surface |
| plant | `render == .cross` | the plant, standing on the drawn ground (P175) |
| foliage | leaves (`Mesher.leafT`) | leaf masses (blobs with a broken edge) |
| trunk | a 3-state axis pillar (`BlockRegistry.pillar`: base, `[x]`, `[z]`) cut with an axe and sounding of wood, whose side texture differs from its end texture (bark and rings) | round tapered trunks and limbs grown from the log graph |
| terrain | an opaque full cube that the world generator lays down and no recipe makes (ground, rock, ores, sand, snow, ice, clay...) | the smooth surface from the generator's own fields (the round-3 field port; caves stay exactly as they are) |
| organic | any other opaque full cube that is natural (no recipe makes it, or it sounds of plant/wool/slime/bone/wood without being planks) | a rounded organic primitive (family below) |
| built | an opaque full cube a recipe makes, or that only structures place (planks, bricks, concrete, metal, glass, wool...) | crisp cube with bevelled exposed edges and wear |
| model | `render == .model / .connect / .wire / .rail` and cubes that are not full | its boxes as today (later: bevels) |

"A recipe makes it" is read from `Recipes.all` and the smelting table (a block whose item is a result is man-made),
"the generator lays it down" from a census of generated chunks is not needed: a block no recipe makes and that is not
placed only by structures is natural. Counts per class are logged at start-up (`ShapeClass.census()`).

Organic families (each is a parameterised primitive, picked from the definition):
- **gourd**: a natural cube with a distinct top texture and the same texture on its four sides, cut with an axe and not a pillar
  (pumpkins, melons, their carved and lit forms): an oblate spheroid with ribs, a stem, its own top texture on the cap.
- **bale**: a natural axis pillar that is not wood (hay, bone, dried kelp, bamboo bundles): a rounded drum along its axis.
- **cap**: a natural cube sounding of wood with no axis and no recipe (mushroom blocks, stems): a domed cap or a stalk,
  chosen by whether the same block continues above it.
- **blob**: everything else natural (sponge, moss, coral blocks, honeycomb, slime, nether wart, shroomlight...): a
  superellipsoid with low-frequency noise, squashed by its hardness (soft things sag).
Every family is textured by projecting the block's own six face textures onto the shape by the surface direction, so a
carved pumpkin's face lands on its front and any block added later is covered with no work.

### 1.2 Detail meshes (a second vertex stream)

The section vertex (2 x UInt32) holds positions in 1/16 block, a 7x7-level normal code that only works with
position-projected textures, and no free bits. That is right for terrain, but a round trunk drawn with it is lumpy,
its bark cannot wrap round it, and its normals step. So round shapes go into a second per-section stream:

```
DetailVertex, 16 bytes (4 x UInt32), positions section-local:
  w0: x  Int16 (1/256 block) | y Int16 << 16
  w1: z  Int16               | nx snorm8 << 16 | ny snorm8 << 24
  w2: nz snorm8 | tint(2) << 8 | ao(2) << 10 | sky(4) << 12 | block(4) << 16 | layer(11) << 20 | cut(1) << 31
  w3: u  half float          | v half float << 16      (texture repeats; bark wraps round a trunk)
```

- Mesher writes it into `SectionMesh.detail` (quads, 4 vertices each, the shared quad index buffer; a triangle is a quad
  with its last vertex repeated). `World.apply` uploads it to `Section.detailBuf` from the same `MeshArena`.
- Quest: `chunk_detail.vert` decodes it and feeds `chunk_solid.frag` / `chunk_cut.frag` unchanged (same varyings, real
  normals into the same sun shading); drawn after the solid terrain pass, batched like it.
- Mac: compiles, does not draw detail meshes; `Mesher.detailMeshes` is off there, so the Mac keeps cubes (Mac polish is
  low priority, it must only build).
- 4 mm precision, so shapes are smooth and seams to the 1/16 terrain are welded by snapping shared edges to 1/16.

### 1.3 Natural terrain
The round-3 field port stays: overworld sections mesh the generator's terrain density and its three cave fields, so
caves stay exactly as they are. What changes: the natural set is the terrain class (every natural ground block, with no
hand list), and dug or chipped ground is drawn by the damage layer (section 2) instead of the sub-cube dents.

### 1.4 Trees and plants
- **Trunks** are rebuilt per section from the log graph in the 48-block mesh region round it (a tree never straddles
  more than that): every log knows its parent (the neighbour nearer the trunk's root), its height up the trunk and how
  many logs hang beyond it. Radius follows the pipe model (thick at the root, thin at the tips), trunks taper and lean a
  little with height (world-position noise, so neighbouring sections agree), flare into roots where they meet the
  ground (the flare sinks into the smooth ground) and close in a rounded cap at the top. 2x2 trunks are one fat trunk.
  Branches are round limbs from the parent's centre to the child's, so they leave the trunk at an angle and fork.
  Bark wraps round them (u around, v along), end rings show where a log is cut.
- **Leaves** keep the rounded canopy blobs (PR #85) with a broken, leafy edge.
- **Plants** stand on the drawn ground (P175, done) and keep their crossed sprites for now.
- Gameplay is unchanged: logs are still blocks (chopping, collision, saves).

### 1.5 Crops and objects
Organic families above. They keep their block collision for walking (a player on a pumpkin stands on its box); debris
and ragdolls collide with the drawn shape (section 3).

### 1.6 Liquids
Water's top is one continuous surface: every corner takes the height of the liquid columns round it, a step down a
level ramps (T17), the shore plane carries the water under natural ground (P175), so no block steps or water walls show.
Falling water stays a column with its curved top.

### 1.7 Man-made blocks
Crisp, believable: exposed convex edges of full built cubes get a 1/16-block chamfer (bevel strip with a 45-degree
normal, in the existing vertex format, so it costs nothing new), corners where three bevels meet get a corner patch,
and the bevel catches light like a real edge. Faces between two built blocks get no bevel (a wall stays flat).

## 2. Procedural damage

### 2.1 Contact
Every source makes a `Contact`: the point on the drawn surface it touched, the surface normal, the direction of the
blow, a radius and an energy, and what made it (hand, tool by tier and kind, bullet by calibre, explosion, main gun).
- **Tools and hands**: in polygon worlds the ray hits the drawn surface (the smooth surface, a trunk, a gourd), and the
  block mined is the one under that point: the pickaxe mines only what it touches.
- **Bullets**: the round's impact point and direction.
- **Explosions and the main gun**: the blast centre; blocks it removes break into big pieces flung outward.

### 2.2 Removing exactly that volume
Each damaged block keeps a few **bites**: (centre in block-local 1/64, radius, seed), at most 8. A bite removes a
rough sphere (radius jittered by noise per direction, so no two look alike) from the block. Gameplay is untouched: the
block breaks when its mining progress completes, as now (mining times, tools and drops unchanged); each hit's bite is
sized so the removed volume tracks the progress. When the block breaks, what was left of it fractures too.
- The mesher draws a bitten block's surface (smooth ground, cube faces, trunk, gourd) subdivided round the bites and
  pushed in to the bites' surface: a real crater where the tool struck, deeper with every blow.
- Bites live in `World.bites` (not saved, capped, cleared when the block changes).

### 2.3 Fracture on the spot
The removed volume (the bite clipped to the block) is split with a 3D Voronoi diagram: 3-8 random seeds (a new random
pattern every hit), each cell clipped by plane cuts from the bite's convex hull into a convex piece. Pieces carry the
block's own texture on the outer faces (projected from where they were in the world, so they match the wall) and a
darker inner face where they broke. They leave as debris bodies (section 3) with the blow's impulse. Fracture runs on
the mesh workers; the frame takes finished pieces.

## 3. Physics

### 3.1 The drawn surface as the collision world
`SurfaceQuery` answers "where is the surface near this point, and which way does it face" from what the mesher drew:
the smooth surface's dual vertices are kept per loaded section near the player (3 bytes each, the offset inside its
cell), and the quads between them are rebuilt from the block grid on demand. Built cubes and models answer with their
boxes; trunks and gourds with their primitive (capsule, spheroid). So nothing hovers over a dip or sinks into a bump.

### 3.2 Debris bodies
Rigid bodies with convex hulls (the fracture pieces): mass from volume and material, a box inertia, 60 Hz steps with
sub-steps, contacts from each hull vertex against `SurfaceQuery`, friction and bounce by material, sleep when still,
fade after a while. Budget: 160 live pieces on the Quest (oldest fade first), 24 new a frame, about 0.5 ms a frame.
Drawn through the entity pass (no new pipeline).

### 3.3 Ragdolls
On death a creature's model parts become a ragdoll: points at each part's joints and ends, held by distance
constraints (position-based dynamics, a few iterations a step), colliding with the drawn surface, started with the
creature's last motion plus the killing blow. Each part is drawn from its points. Every creature with a model gets one
automatically. They settle, then stay as the corpse (P57 rules).

### 3.4 Walking on the drawn surface
Mobs, townsfolk, animals, the player's view and dropped items sit on `SurfaceQuery`'s height under them (replacing the
terrain-field-only `World.smoothGroundOffset`), so everything stands on the polygons.

## 4. Performance (Quest 3, 72 fps, render distance 12-16)
- All shape generation, bites and fracture on the mesh workers; the frame thread only uploads results (1.5 ms budget).
- Detail meshes by distance: full rings near, fewer sides further out, plain cubes beyond the mid ring.
- Smooth terrain gets a geometric far level (a coarser surface for the far ring), the biggest win at distance 16.
- Physics budgets above; ragdolls sleep; debris fades.

## Slices (each merged to claude/quest-port so Remington can try it on the headset)
1. Shape system: classes, detail meshes on the Quest, round trunks and limbs, organic primitives, bevelled built blocks,
   continuous water.
2. Damage: contacts from tools, hands, bullets and blasts; bites drawn as craters; Voronoi fracture into pieces.
3. Physics: debris bodies, ragdolls, everything on the drawn surface.
4. Performance: far-ring terrain level, detail rings, budgets measured on the meshbench.

## Status (slice 1, Oct 13)
Shipped on the Quest (Polygons (Smooth) worlds; the Mac compiles and keeps cubes):
- Shape classes for all 5090 block states (1063 names), from the definitions plus a census of generated chunks
  (`ShapeClass`, cached as natural-census.txt beside the worlds): none 1, liquid 18, plant 87, foliage 9, trunk 139,
  terrain 84, organic 35, built 464, model 4253 (stairs, slabs, doors and other models keep their boxes for now).
- Detail mesh stream (16-byte vertices, `chunk_detail.vert`, batched with the terrain passes).
- Round trunks (`ShapeTrunks`): full-height columns read across the 3x3 chunks so taper and lean agree between sections;
  living trunks flare into lobed roots that sink into the smooth ground and close in a dome; branches and roots are
  tubes from the parent's centre; cut timber, posts and stumps are crisp round logs with end rings. 2x2 trunks are one.
- Rounded organic objects (`ShapeOrganic`): one soft-box primitive, rounded where exposed and flat where the same block
  continues or rests on the ground: ribbed gourds, hay drums, domed mushroom caps, lumpy blobs (wart, sponge, glow).
- Bevelled built blocks (1/16 chamfers on exposed convex edges, near ring only), lumpy leaf masses, water sheets that
  thin to the ground at their edges.
- Cost (optimized questcheck, x86, dark forest, 25 chunks): meshing +33% over smooth terrain without detail; far ring
  (beyond 5 chunks) draws cubes for trunks and objects, so render distance 12-16 pays only for the near rings.

## Status (slice 2, Oct 13)
- Bites (`World.bites`, `Craters.swift`): a pickaxe step (each eighth of mining progress), a round or a blast leaves a
  rough bowl where it struck: on smooth ground along the swing (so it lands on the drawn surface), on cube faces along
  the face. The mesher subdivides only the quads a bowl reaches, with grid lines clustered round each bite, into the
  detail stream; the bowl shows the struck block's own material, darker in the deep part. 8 bites a block, 4096 blocks.
- Chips (`Fracture.bite`) fly from where the tool touched; a mined-through block splits into 5 Voronoi pieces that
  slump into a pile; a blast splits its 16 nearest broken blocks into 4 pieces each and throws them, and kicks pieces
  already lying round.
- Debris (`DebrisWorld`, `DebrisField`): rigid bodies on the drawn ground (`WorldGround`: the field's crossing over
  natural ground, collision boxes elsewhere), sleeping when still, fading after 8 s at rest. 160 live pieces, 64 new a
  frame. Step cost (optimized host build, 27 pieces): 0.4 ms mean, 0.7 ms worst.
- Mining times, drops and collision are unchanged (a bitten block keeps its whole box until it breaks).

## Decisions taken (defaults, noted per Remington's autonomy rule)
- The block grid stays the save and gameplay truth; nothing new is saved.
- Detail meshes are Quest-only; the Mac keeps cubes for these shapes and must only compile.
- Chips in progress are not saved.
- Organic shapes keep block collision for walking; only debris and ragdolls use the drawn shapes.
- Verification is by building the Quest APK and looking at headless Quest renders of the same scenes, not by new test
  harnesses (backlog rule).
