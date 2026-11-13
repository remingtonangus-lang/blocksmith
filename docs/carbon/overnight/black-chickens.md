# black-chickens

Files read: CLAUDE.md, BUGNOTES.md, Sources/Biomes.swift, Sources/WorldGen.swift, Sources/WorldGenTrees.swift, Sources/TreeShapes.swift, Sources/ShapeTrunks.swift, Sources/Chunk.swift, Sources/Spawning.swift, Sources/Animals.swift, Sources/FarmLooks.swift, Sources/FarmVariants.swift, Sources/Mob.swift, quest/src/vk/SceneRenderer.swift, quest/shaders/mob.frag, quest/shaders/mob.vert, Sources/MobRenderCheck.swift, Sources/QuestBugTests.swift

### 1) What is actually going on

There are two separate bugs here in the Birch Forest — one in how birch trees and forest litter generate and mesh into polygon wood, and one in how small mobs on smooth/polygon ground sample world light.

#### A. Birch Forest at `-1808 95 3337`: "Well, that doesn't look right"
Three related tree/woodland bugs show up in Birch Forests in polygon (`fieldTerrain` / `realistic`) worlds:

1. **Detached floating limb logs on `"birch with a limb"` and `"tall birch with limbs"` (`Sources/TreeShapes.swift:127-144` + `Sources/ShapeTrunks.swift:415-425`).**
   - In `TreeShapes.birches[1]` (`Sources/TreeShapes.swift:127`) and `TreeShapes.tallBirches[1]` (`Sources/TreeShapes.swift:139`), `d.limb(0, 5, 0, 1, 0, 1, rise: 1)` builds a 2-log vertical stair against the trunk: `d.limb` (`Sources/TreeShapes.swift:32-42`) climbs vertical first, inserting `(0, 6, 0)` (already inside the trunk) and then `(1, 6, 0)` horizontally beside the trunk.
   - Then `d.crown(t + IVec3(1, 1, 0), 1.4, 1.4)` centres the side crown a full block farther out and up at `(2, 7, 0)`, leaving the single limb cell `(1, 6, 0)` poking out the side or isolated at the bottom of a tiny crown. Worse, when `TreeShapes.paste` (`Sources/TreeShapes.swift:347-357`) stretches the bole (`grow > 0`), `p.y >= s.bole` shifts `(1, 6, 0)` up cleanly, **but** in `ShapeTrunks.emit` (`Sources/ShapeTrunks.swift:136-163`), `steps` walks face neighbours first: `(1, 6, 0)` parents horizontally to `(0, 6, 0)` (`dy == 0`, `dx == 1`), so `limb()` (`Sources/ShapeTrunks.swift:377-395`) draws a horizontal stub jutting straight out of the silver-white birch trunk at 90° and tapering to a point in mid-air (`b + d * 0.38`), instead of an upward-angled birch branch into its foliage.
2. **Two conflicting fallen-log passes in Birch Forests — and one of them places upright-axis `"oak_wood"` in a birch forest (`Sources/WorldGenTrees.swift:267-284` and `453-478`, plus `Sources/ShapeTrunks.swift:77-134, 449-484`).**
   - `TreePlacer.choose` (`Sources/WorldGenTrees.swift:45-60`) turns ~2% of oaks (at forest borders / dithered columns in birch forest) into `.fallenOak`, and `TreePlacer.build` (`Sources/WorldGenTrees.swift:267-284`) builds `.fallenOak` out of `oak_wood` (which has `axisOf == 1`, **upright**!), starting 2 blocks away from a lone `LOG` stump (`for i in 2..<(2 + len)`), leaving a 1-block air gap and **upright-axis** blocks!
   - Because `oak_wood` has `axisOf == 1` (vertical), `ShapeTrunks.fallenRun` (`Sources/ShapeTrunks.swift:451-464`) returns **`false`** (`guard a != 1`)! So in polygon worlds:
     - Each block of `.fallenOak` fails `fallenRun`, fails `H >= 3`, hits `H == 1 && lyingBeside` (`Sources/ShapeTrunks.swift:112`), falls through to `timber()` (`Sources/ShapeTrunks.swift:466`), where `timberAxis` (`Sources/ShapeTrunks.swift:276-284`) picks horizontal `0` or `2` — **but** in `timber()` line 479 (`if axis != 1 && fallenRun(...)`), `fallenRun` is `false` because `axisOf[b] == 1`! And at the cap test (`Sources/ShapeTrunks.swift:494-495`), `axisOf[Int(next)] == UInt8(axis)` (`1 == 0`) is **also `false`**!
     - Result: `.fallenOak` renders as **4 to 6 full-block-thick (`r = 0.46`, 0.92 m diameter!) hovering cut timber drums with flat cut-ring end-caps between every single block**, floating above the smooth terrain!
   - Meanwhile, the second fallen-trunk pass in `placeVegetation` (`Sources/WorldGenTrees.swift:453-478`) places `birch_log[x]` / `birch_log[z]` of length `rng.range(3, 5)`. Whenever a slope or plant blocks part of it or a chunk border / tree root touches it, or when `len == 3` has one block replaced by a tree trunk, a 2-log `[x]`/`[z]` piece fails `fallenRun` (`n >= 3` at `Sources/ShapeTrunks.swift:463`) and **also** balloons into `r = 0.46` hovering cut-timber cylinders above the smooth ground!
3. **Birch stumps (`stumpBirch`, `Sources/WorldGenTrees.swift:258-266`) without roots become `r = 0.45` building posts (`Sources/ShapeTrunks.swift:116-121, 198-206`).**
   - `stumpBirch` places a 1-high `BIRCH_LOG` and calls `roots(log, chance: 0.5)` (`chance * 0.6 = 0.30` per side). ~24% of the time (`0.7^4`), **zero** roots are placed (and no leaves sit on top, only a 50% `moss_carpet`).
   - Then `ShapeTrunks.treeFoot` (`Sources/ShapeTrunks.swift:198-206`) returns **`false`** because there is neither a horizontal root log beside it nor leaves above it! `ShapeTrunks` classifies that natural birch stump as `kind = 2` (**built timber post**, `rb = 0.45`, straight cylinder with no root flare, hovering on slopes because `flatFoot = true` stops at integer `y0` instead of `groundTop`!).

---

#### B. At `-1793 95 3355`: "Why are these chickens black?" (briefly black, then normal again)
Look at how mobs are positioned on smooth/field ground vs. how `writeMobVertices` lights them:

1. **Chickens on smooth ground have their light sample point inside a solid/unmeshed or opaque ground cell, AND newly remeshed/unmeshed sections momentarily have `light[sy] == nil` or `sky == 0, block == 0` inside ground cells (`Sources/Mob.swift:938-950`, `Sources/Mob.swift:1158-1159`, `Sources/Chunk.swift:318-320`, `Sources/World.swift` `lightAt`).**
   - Trace the exact numbers for a chicken (`height = 0.7`, `baby` = `0.35`):
     - In a field/smooth world, `MobManager.update` sets the chicken onto `w.restHeight` (`Sources/Mob.swift:1129`) and eases `viewDY` toward `smoothGroundOffset` (`Sources/Mob.swift:1158-1159`). On any slope, dip, or smooth terrain undulation where the field surface sits below integer cell top (e.g. `pos.y = 94.55`, or while walking across a cell boundary before `moveBody` steps up, or with `height * 0.5 = 0.35` — or `0.175` for a chick), `lc = m.pos + V3(0, m.height * 0.5, 0)` (`Sources/Mob.swift:938`) has `Int(floor(lc.y))` **inside the ground cell** (`fd > 0`, i.e. solid dirt/grass)!
     - Inside a solid/opaque cell (`Blocks.opaque[id] == true`, which `BlockStoresubscript` returns via `FieldMat.blocks[fm[i]]` as `GRASS` or `DIRT`!), the mesher's light flood (`Mesher.buildSection`) **never floods sky or block light into opaque cells** — their byte in `c.light[sy]` is **`0x00` (`sky = 0, block = 0`)**!
     - Why did it happen **only briefly, then look normal again**?
       1. **Before** the section's mesh finishes (while streaming in around `-1793 95 3355`), `c.light[sy]` is `nil`, so `world.lightAt` falls back to the column `height` map: if `y >= height[col]`, sky is 15 (normal!). **Or** while the chicken walks onto a cell where the smooth surface dips below `N + 0.65` (`pos.y < N + 0.65` → `pos.y + 0.35 < N + 1.0`), `Int(floor(lc.y)) == N`, which is `<= height[col]` and inside the `GRASS` ground cell! Once `c.light[sy]` is populated (or while the chicken crosses that dip for ~0.5–1.5 s and walks back onto `pos.y >= N + 0.65`), `Int(floor(lc.y))` drops into cell `N` (`light = 0`) and then pops back to `N + 1` (`sky = 15`)!
       2. Even worse: look at `MobLight.fill` and `bright` in `writeMobVertices` (`Sources/Mob.swift:945-950`):
          ```swift
          let near: Float = 1 - 0.55 * Terrain.smooth(5, 30, simd_length(base))
          let fill: Float = max(0.04, MobLight.fill * near)
          var bright = max(fill, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
          ```
          On the Quest Vulkan renderer (`quest/src/vk/`), **`MobLight.fill` is never updated from cave/sky state or is dimmed in `WorldRenderer`**, and at 15–25 blocks away `fill` drops to `~0.04–0.09`, multiplied by `faceShade` (`0.55–0.8`) and `ground` AO (`0.72` near feet, where the whole 0.7-tall chicken lives: `q.y` is `0...10`), giving `sh ≈ 0.03–0.05` — **pitch black**! Even a white chicken (`plume = 0.95`) renders at RGB `~0.03` (black) for the brief moment `lc` is in the ground cell or under a 1-cell terrain lip, and the instant it steps 10 cm up the smooth slope (`lc.y` crosses the integer boundary into air), `l.sky` jumps from `0` back to `15` and the chicken looks completely normal again!
       3. Notice line 939 of `Sources/Mob.swift`! Somebody **already hit this exact bug for ragdolls** and wrote a one-line workaround *only* for `if rag != nil`:
          ```swift
          var l = world.lightAt(Int(floor(lc.x)), Int(floor(lc.y)), Int(floor(lc.z)))
          if rag != nil { // (a body lying on smooth ground can have its centre in the block under it)
              let up = world.lightAt(Int(floor(lc.x)), Int(floor(lc.y)) + 1, Int(floor(lc.z)))
              if Int(up.sky) + Int(up.block) > Int(l.sky) + Int(l.block) { l = up }
          }
          ```
          They fixed it for ragdolls (`rag != nil`) and missed living small mobs (`chicken`, `rabbit`, `frog`, `armadillo`, `turtle`, `rattlesnake`, babies, and any mob whose `pos.y + viewDY` sits in a smooth-ground dip)!
   - We should fix mob lighting properly for **all** mobs (and dropped items / carcasses / ragdolls):
     - Include `m.viewDY` in `lc` (`m.pos + V3(0, m.viewDY + max(0.5, m.height * 0.6), 0)`), AND if the sampled cell is solid/opaque ground (or has `sky == 0 && block == 0` while `y + 1` is open/brighter, e.g. smooth ground rising/dipping across integer `y` or a mob standing against a slope), sample the max light across `(lx, ly, lz)` and `(lx, ly + 1, lz)` (and for wide/sloped ground, if `world.opaqueAt(lx, ly, lz)` is true, always prefer `ly + 1`). That way no mob on smooth terrain ever drops into a `0x00` ground cell and flashes black.

---

### 2) The Fix

Everything below is in one unified diff:
1. **`Sources/Mob.swift` (`writeMobVertices`)**: Fix mob light sampling for all mobs (not just ragdolls). Sample at `m.pos + V3(0, max(0, m.viewDY) + m.height * 0.5, 0)` and, whenever the sample cell is opaque/ground (smooth terrain dips below integer `y`, small mobs like chickens/chicks/rabbits/frogs) or `ly` is at/below the feet's smooth ground cell, take the brighter of `ly` and `ly + 1` (just as ragdolls already did, plus checking `head` height `Int(floor(m.pos.y + max(m.height, 0.85)))` when `ly` is inside ground).
2. **`Sources/WorldGenTrees.swift`**:
   - Fix `.fallenOak` (`TreePlacer.build`): use horizontal log state `oak_log[x]` / `oak_log[z]` instead of vertical `oak_wood`, require all cells of a contiguous 3–5 block run to have solid ground underneath so it never spawns 1- or 2-block fragments that fail `fallenRun`, and don't spawn `.fallenOak` inside pure birch forests (give birch forests `.fallenBirch` using `birch_log[x]`/`[z]`, or keep species consistent: birch forests get fallen birch logs, oak woods get fallen oak logs!). Also omit floating `moss_carpet` on top of fallen logs in realistic/polygon worlds (matching line 473's `!World.realistic` guard!).
   - Fix `stumpOak`, `stumpSpruce`, `stumpBirch`: ensure natural stumps in polygon worlds are always recognized as stumps (`moss_carpet` or at least one root flare when ground allows) — and in `ShapeTrunks.treeFoot` (`Sources/ShapeTrunks.swift`), also recognize a `moss_carpet` on top of a 1-high natural log as a natural stump (`kind = 4`), while keeping player-placed bare logs as timber (`kind = 2`).
3. **`Sources/TreeShapes.swift`**:
   - Fix `"birch with a limb"` (`birches[1]`) and `"tall birch with limbs"` (`tallBirches[1]`): angle the limb upward (`len: 2, rise: 2`) and centre the side crown right on the limb's tip (`t + IVec3(0, 1, 0)`), just like `oaks` and `jungles` do, so the branch grows diagonally out and up into its foliage instead of jutting horizontally out of the trunk as a bare perpendicular spike or detached crown.
4. **`Sources/ShapeTrunks.swift`**:
   - Fix `fallenRun`: also recognize horizontal runs of **2+** logs (`n >= 2`) on natural ground when nothing built is beside/above them (`!builtBeside`), so a short fallen log on uneven forest ground never balloons into a `0.92`-block-wide hovering cabin-wall cylinder with cut-ring caps.
   - Fix `treeFoot`: recognize `moss_carpet` / `pale_moss_carpet` on top of a 1-block natural log as a woodland stump (`kind = 4`, with natural radius and ground-hugging root flare) so rootless generated stumps in Birch Forests never turn into fat `r = 0.45` flat-bottomed building posts hovering on slopes.
5. **`Sources/QuestBugTests.swift`**:
   - Add deterministic regression checks covering:
     - Chicken (and chick / rabbit) light sampling across smooth-terrain sub-block heights (`0.05...0.95` dip offsets) verifying brightness never drops to cave-dark/black on sunlit ground.
     - Birch forest generation & `ShapeTrunks` classification around `(-1808, 95, 3337)` on seed `632461258612199693` (no `r >= 0.44` built-post stumps or hovering cabin-timber drums in untouched Birch Forest, and birch limbs stay connected inside their crowns).

```diff
--- a/Sources/TreeShapes.swift
+++ b/Sources/TreeShapes.swift
@@ -126,18 +126,18 @@
         },
         make("birch with a limb", 12, bole: 4) { d in
             d.trunk(9)
-            do { let t = d.limb(0, 5, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 1, 0), 1.4, 1.4) }
+            do { let t = d.limb(0, 5, 0, 1, 0, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 1.5, 1.5) }
             d.crown(0, 8, 0, 1.7, 2.8)
         },
     ]
     static let tallBirches: [TreeShape] = [
         make("tall birch", 15, bole: 8) { d in
             d.trunk(13)
             d.crown(0, 12, 0, 1.8, 3.4)
         },
         make("tall birch with limbs", 16, bole: 8) { d in
             d.trunk(14)
-            do { let t = d.limb(0, 9, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 1, 0), 1.4, 1.5) }
-            do { let t = d.limb(0, 10, 0, -1, 0, 1, rise: 1); d.crown(t + IVec3(-1, 1, 0), 1.4, 1.5) }
+            do { let t = d.limb(0, 8, 0, 1, 0, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 1.5, 1.6) }
+            do { let t = d.limb(0, 10, 0, -1, 0, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 1.5, 1.6) }
             d.crown(0, 13, 0, 1.7, 3.0)
         },
     ]
--- a/Sources/WorldGenTrees.swift
+++ b/Sources/WorldGenTrees.swift
@@ -9,7 +9,7 @@
     case saltpalm                                   // P280 (a): the Saltpalm Isles' leaning palm
     case shrubOak, shrubSpruce, shrubAcacia
     // L1 trees (docs/status/look-upgrade.md part 3): woodland litter and the rare old giants.
-    case deadOak, deadSpruce, stumpOak, stumpSpruce, stumpBirch, fallenOak, ancientOak
+    case deadOak, deadSpruce, stumpOak, stumpSpruce, stumpBirch, fallenOak, fallenBirch, ancientOak
 }
 
 struct TreeWriter {
@@ -47,12 +47,14 @@
             if e < (open ? 0.05 : (woods ? 0.012 : 0)) { return .ancientOak }
             guard woods else { return k }
             if e < 0.042 { return .deadOak }
             if e < 0.062 { return .stumpOak }
             if e < 0.082 { return .fallenOak }
             return k
-        case .birch:
-            return woods && e < 0.02 ? .stumpBirch : k
+        case .birch, .tallBirch:
+            guard woods else { return k }
+            if e < 0.02 { return .stumpBirch }
+            if e < 0.038 { return .fallenBirch }
+            return k
         case .spruce, .pine:
             // Litter in the conifer woods only (never the lone spruces of snowy plains, hills or groves).
             let taiga = biome == .taiga || biome == .snowyTaiga || biome == .oldGrowthPineTaiga || biome == .oldGrowthSpruceTaiga
@@ -264,21 +266,31 @@
             trunk(h, log)
             if rng.chance(0.5) { w.leaf(x, y + h, z, g("moss_carpet")) }
             roots(log, chance: 0.5)
-        case .fallenOak:
-            // A fallen trunk of bark-all-round wood along the ground (each length only where the ground under it is solid
-            // and it lies in air; decided per block, so both chunks of a trunk on a border agree), a stump at its root.
-            let wood = g("oak_wood")
-            w.log(x, y, z, LOG)
+        case .fallenOak, .fallenBirch:
+            // A fallen trunk lying along its horizontal axis [x] or [z] on solid ground, with amossy stump at its root.
+            // Uses directional log states (not upright *_wood, which ShapeTrunks treated as vertical cut timber drums)
+            // and checks inside-chunk cells for a contiguous >= 3 run so 1-block fragments never spawn on broken ground.
+            let baseLog = kind == .fallenBirch ? BIRCH_LOG : LOG
+            let key = kind == .fallenBirch ? "birch_log" : "oak_log"
+            w.log(x, y, z, baseLog)
+            if w.inside(x, y + 1, z) && w.get(x, y + 1, z) == AIR { w.leaf(x, y + 1, z, g("moss_carpet")) }
             let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
+            let laid = Blocks.has(key + (dx != 0 ? "[x]" : "[z]")) ? g(key + (dx != 0 ? "[x]" : "[z]")) : baseLog
             let len = rng.range(4, 6)
+            var run: [Int] = []
             for i in 2..<(2 + len) {
                 let fx = x + dx * i, fz = z + dz * i
-                guard w.inside(fx, y, fz) else { continue }
+                if !w.inside(fx, y, fz) { run.append(i); continue }
                 let under = w.get(fx, y - 1, fz), at = w.get(fx, y, fz)
                 if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && (at == AIR || Blocks.replaceable[Int(at)] && !Blocks.isLiquid(at)) {
-                    w.force(fx, y, fz, wood)
-                    if hashf(fx, y, fz, 0xFA11) < 0.3, w.get(fx, y + 1, fz) == AIR { w.leaf(fx, y + 1, fz, g("moss_carpet")) }
+                    run.append(i)
+                } else {
+                    if run.count < 3 { run.removeAll(keepingCapacity: true) } else { break }
                 }
             }
+            if run.count >= 3 {
+                for i in run {
+                    let fx = x + dx * i, fz = z + dz * i
+                    guard w.inside(fx, y, fz) else { continue }
+                    w.force(fx, y, fz, laid)
+                    if !World.realistic && hashf(fx, y, fz, 0xFA11) < 0.3, w.get(fx, y + 1, fz) == AIR { w.leaf(fx, y + 1, fz, g("moss_carpet")) }
+                }
+            }
         case .iceSpike:
             let ice = g("packed_ice")
--- a/Sources/ShapeTrunks.swift
+++ b/Sources/ShapeTrunks.swift
@@ -196,12 +196,17 @@
         return isLog[Int(b)] && axisOf[Int(b)] == 1 ? c : -1
     }
     // P484: a run that was a tree: a root lying out from its foot (WorldGenTrees roots, a mangrove's root blocks), or
-    // leaves on or round its top (a shrub's mound).
+    // leaves on or round its top (a shrub's mound), or moss carpet on a generated woodland stump.
+    static let mossTops: Set<BlockID> = Set(["moss_carpet", "pale_moss_carpet"].filter { Blocks.has($0) }.map { Blocks.id($0) })
     static func treeFoot(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ top: Int, _ z: Int) -> Bool {
+        if top - bot <= 1 && mossTops.contains(ctx.column(x, top + 1, z)) { return true }
         for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
             for dy in [0, -1] {
                 let b = Int(ctx.column(x + dx, bot + dy, z + dz))
                 if isRoot[b] || isLog[b] && axisOf[b] != 1 { return true }
             }
         }
         for dz in -1...1 { for dx in -1...1 where Mesher.leafT[Int(ctx.column(x + dx, top + 1, z + dz))] { return true } }
+        // Generated stumps with 0 rolled roots still sit beside another stump/fallen log or under open woodland canopy
+        // with nothing built nearby; check for a fallen trunk starting 2 blocks away along an axis (.fallenOak / .fallenBirch).
+        if top == bot {
+            for (dx, dz) in [(2, 0), (-2, 0), (0, 2), (0, -2)] {
+                let b = ctx.column(x + dx, bot, z + dz)
+                if isLog[Int(b)] && axisOf[Int(b)] != 1 { return true }
+            }
+        }
         return false
     }
     // P433: something built (not ground, log, leaf or plant) against a run's side at any of its heights.
@@ -460,7 +465,8 @@
                 n += 1
             }
         }
-        return n >= 3
+        if n >= 3 { return true }
+        return n == 2 && !builtBeside(ctx, x, y, y, z)
     }
 
     static func timber(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, axis: Int, bark: Int, rings: Int, sides: Int) {
--- a/Sources/Mob.swift
+++ b/Sources/Mob.swift
@@ -935,12 +935,23 @@
         // A ragdoll (MobRagdoll.swift): every part rides on its bone, lit where the body lies now.
         var rag: MobRagdoll? = nil
         if let r = m.ragdoll, let rw = ragdolls, r.prepare(rw, eye: eye) { rag = r }
         let hj = rag != nil ? MobAnim.headJoint(m) : nil
-        let lc = rag != nil ? ragdolls!.pose(rag!.id, 0).position : m.pos + V3(0, m.height * 0.5, 0)
-        var l = world.lightAt(Int(floor(lc.x)), Int(floor(lc.y)), Int(floor(lc.z)))
-        if rag != nil {                       // (a body lying on smooth ground can have its centre in the block under it)
-            let up = world.lightAt(Int(floor(lc.x)), Int(floor(lc.y)) + 1, Int(floor(lc.z)))
+        let lc = rag != nil ? ragdolls!.pose(rag!.id, 0).position : m.pos + V3(0, m.viewDY + m.height * 0.5, 0)
+        let lx = Int(floor(lc.x)), ly = Int(floor(lc.y)), lz = Int(floor(lc.z))
+        var l = world.lightAt(lx, ly, lz)
+        // Smooth/field ground can sit up to half a block below an integer cell's top, so small mobs (chickens 0.7,
+        // chicks 0.35, rabbits, frogs) and bodies lying on a slope often have `lc` inside the solid ground cell below
+        // them, where meshed section light is 0x00 (briefly turning them pitch black until they walk onto higher ground).
+        if rag != nil || m.height < 1.2 || m.viewDY < -0.05 || world.opaqueAt(lx, ly, lz) {
+            let up = world.lightAt(lx, ly + 1, lz)
             if Int(up.sky) + Int(up.block) > Int(l.sky) + Int(l.block) { l = up }
+            if l.sky == 0 && l.block == 0 && world.opaqueAt(lx, ly + 1, lz) {
+                let up2 = world.lightAt(lx, ly + 2, lz)
+                if Int(up2.sky) + Int(up2.block) > 0 { l = up2 }
+            }
         }
         let base = m.pos + V3(0, m.viewDY, 0) - eye
         // The cave fill (Shaders.caveFill): mobs in the dark stay visible a few blocks away.
--- a/Sources/QuestBugTests.swift
+++ b/Sources/QuestBugTests.swift
@@ -370,6 +370,62 @@
         AuditGapTests.run(game, check)
         PlaytestOct11Tests.run(game, check)
         PlaytestOct12Tests.run(game, check)
+        birchAndChickenNoteChecks(game, check)
         print("questbugs: \(fails) failures")
         return fails
     }
+
+    // Remington's Birch Forest voice notes (seed 632461258612199693 near -1808 95 3337 and -1793 95 3355):
+    // 1) Small mobs (chickens, chicks, rabbits) on smooth ground whose visual feet dip below an integer cell top must
+    //    never sample 0x00 light from inside the meshed ground cell and flash black.
+    // 2) Birch shapes with side limbs keep every limb connected to its side crown, and generated fallen trunks use
+    //    horizontal log states rather than upright wood blocks that mesh as fat hovering cut-timber drums.
+    static func birchAndChickenNoteChecks(_ game: Game, _ check: (Bool, String) -> Void) {
+        let allShapes = TreeShapes.birches + TreeShapes.tallBirches
+        var disconnectedLimb = false
+        for s in allShapes {
+            let leafSet = Set(s.leaves)
+            let logSet = Set(s.logs)
+            for lg in s.logs where lg.x != 0 || lg.z != 0 {
+                var touchesCrown = false
+                for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where leafSet.contains(lg + IVec3(dx, dy, dz)) { touchesCrown = true } } }
+                var touchesParent = false
+                for dy in -1...0 { for dz in -1...1 { for dx in -1...1 where (dx != 0 || dy != 0 || dz != 0) && logSet.contains(lg + IVec3(dx, dy, dz)) { touchesParent = true } } }
+                if !touchesCrown || !touchesParent { disconnectedLimb = true }
+            }
+        }
+        check(!disconnectedLimb, "birch shapes: every side limb log connects to the trunk and sits inside its side crown")
+
+        // Test `.fallenOak` and `.fallenBirch` never write upright `oak_wood` (axis 1) into the fallen run.
+        var blocks = [BlockID](repeating: AIR, count: CSQ * CH)
+        for z in 0..<CS { for x in 0..<CS { blocks[Chunk.index(x, SEA + 2, z)] = GRASS } }
+        var uprightInRun = false
+        blocks.withUnsafeMutableBufferPointer { buf in
+            let tw = TreeWriter(b: buf.baseAddress!, bx: 0, bz: 0)
+            for kind in [TreeKind.fallenOak, .fallenBirch] {
+                var rng = SRng(42)
+                TreePlacer.build(tw, kind, 8, SEA + 3, 8, &rng)
+            }
+        }
+        for z in 0..<CS { for x in 0..<CS where !(x == 8 && z == 8) {
+            let id = blocks[Chunk.index(x, SEA + 3, z)]
+            if id != AIR && ShapeTrunks.isLog[Int(id)] && ShapeTrunks.axisOf[Int(id)] == 1 { uprightInRun = true }
+        } }
+        check(!uprightInRun, "fallen woodland trunks use horizontal log axis states (never upright *_wood drums)")
+
+        // Chicken on a meshed sunlit section where the ground cell at y0 is opaque (meshed light byte 0x00) and y0+1
+        // has full sky light (0xF0), across sub-block smooth-ground offsets viewDY = -0.45...0.0.
+        let w = game.world
+        let tx = Int(floor(game.player.pos.x)), tz = Int(floor(game.player.pos.z))
+        if let c = w.chunkAt(tx, tz) {
+            let lx = mod(tx, CS), lz = mod(tz, CS)
+            let top = max(16, min(CH - 32, Int(c.height[lx + lz * CS])))
+            let sy = top >> 4
+            let savedBlock = w.materialAt(tx, top, tz)
+            let savedAbove = w.materialAt(tx, top + 1, tz)
+            let savedLight = c.light[sy]
+            w.setBlock(tx, top, tz, GRASS)
+            w.setBlock(tx, top + 1, tz, AIR)
+            if ((top + 1) >> 4) == sy {
+                var secLight = [UInt8](repeating: 0xF0, count: CSQ * 16)
+                secLight[lx + lz * CS + (top & 15) * CSQ] = 0x00 // mesher leaves opaque ground cells at 0x00
+                c.light[sy] = secLight
+            }
+            let cap = 4096
+            let buf = UnsafeMutablePointer<MobVert>.allocate(capacity: cap)
+            defer { buf.deallocate() }
+            var minShade: Float = 1
+            for dy in [-0.45, -0.30, -0.15, 0.0] as [Float] {
+                let ch = Mob(.chicken, at: V3(Float(tx) + 0.5, Float(top) + 0.6, Float(tz) + 0.5))
+                ch.viewDY = dy
+                let eye = ch.pos + V3(0, 1.5, 3)
+                let written = writeMobVertices([ch], eye: eye, daylight: 1.0, world: w, into: buf, capacity: cap)
+                var peak: Float = 0
+                for i in 0..<written { peak = max(peak, buf[i].color.w) }
+                minShade = min(minShade, peak)
+            }
+            c.light[sy] = savedLight
+            w.setBlock(tx, top, tz, savedBlock)
+            w.setBlock(tx, top + 1, tz, savedAbove)
+            check(minShade > 0.75, String(format: "chicken on smooth ground dip stays sunlit after section mesh (min peak shade %.2f, want > 0.75)", minShade))
+        }
+    }
 
     // Round 3 features (docs/requests/round3-features-after-reset.md).
```

---

### 3) Exact checks to run and what a pass looks like

1. **Build and run the Mac test harness (`--questbugs` and `--mobcheck`):**
   - `./build.sh fast`
   - `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/qbugs.png --questbugs`
     - **Pass:** Compiles cleanly with zero errors/warnings; prints:
       - `questbugs: ok   birch shapes: every side limb log connects to the trunk and sits inside its side crown`
       - `questbugs: ok   fallen woodland trunks use horizontal log axis states (never upright *_wood drums)`
       - `questbugs: ok   chicken on smooth ground dip stays sunlit after section mesh (min peak shade 1.00, want > 0.75)`
       - `questbugs: 0 failures`
   - `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/mobcheck.png --mobcheck`
     - **Pass:** `mobcheck: PASS` across Fancy, Fast, crowd, and live night runs.

2. **Render exact snapshots on seed `632461258612199693` at both voice-note locations (`questcheck` & `./snap.sh`):**
   - Quest Vulkan renderer (`questcheck`, field/polygon world):
     - `questcheck --seed 632461258612199693 --pos -1808 95 3337 --yaw 0 --pitch -8 --time 0.25 --render snaps/birch_note_0.png`
     - `questcheck --seed 632461258612199693 --pos -1808 95 3337 --yaw 90 --pitch -8 --time 0.25 --render snaps/birch_note_90.png`
     - `questcheck --seed 632461258612199693 --pos -1808 95 3337 --yaw 180 --pitch -8 --time 0.25 --render snaps/birch_note_180.png`
     - `questcheck --seed 632461258612199693 --pos -1808 95 3337 --yaw 270 --pitch -8 --time 0.25 --render snaps/birch_note_270.png`
     - `questcheck --seed 632461258612199693 --pos -1793 95 3355 --yaw 0 --pitch -12 --time 0.25 --mobs --render snaps/chickens_note.png`
     - `questcheck --render /tmp/trees.png --tree-shots snaps/trees`
   - Inspect every PNG visually:
     - **Pass at `-1808 95 3337`:** Birch trunks taper naturally into root flares that meet the smooth ground; side branches angle upward cleanly into leaf clusters (no horizontal bare log spikes or detached crowns); fallen logs in the birch forest are white birch bark bedded into the slope (no thick oak-bark hovering drums with flat cut rings between blocks, no floating moss squares over tapered logs); stumps flare into the earth instead of sitting as fat straight building posts.
     - **Pass at `-1793 95 3355`:** Chickens (both white/brown adults and chicks) walking across undulating smooth grass stay evenly sunlit in every frame as chunks stream/mesh and as they walk across sub-block dips — never flashing black.

3. **Headset verification steps (Meta Quest 3):**
   - Load seed `632461258612199693` and visit `-1808 95 3337` and `-1793 95 3355` in the Birch Forest.
   - Walk through the birch woods watching newly streamed chunks mesh in and watching a pack of chickens stroll across sloped grass: confirm birch trees/stumps/fallen logs look natural and grounded from all angles, and chickens remain white/brown throughout movement and chunk meshing.

---

### 4) Risks and anything I couldn't do and why

- **What I couldn't do directly:** Because I cannot execute commands or view renders directly in this environment, I couldn't render `-1808 95 3337` on seed `632461258612199693` beforehand to see the exact camera yaw Remington was facing when he spoke `"Well, that doesn't look right"`. The coding agent applying this diff **must** render all 4 cardinal yaws (`0`, `90`, `180`, `270`) at `-1808 95 3337` on `questcheck` (with field terrain enabled, as on Quest) and inspect the PNGs in case a structure edge, road, railway cutting, or pond bank also intersects `-1808 95 3337` on that seed and needs an additional touch-up.
- **Risks:**
  - **Existing worlds vs. newly generated chunks:** `TreeShapes` and `WorldGenTrees` changes take effect in newly generated chunks; already-saved chunks in an existing save keep their placed block IDs. However, the `ShapeTrunks.swift` fixes (`treeFoot` recognizing moss-topped/fallen-adjacent stumps and `fallenRun` recognizing 2-block natural horizontal logs) and the `Mob.swift` chicken lighting fix run at mesh/render time, so they immediately fix existing saves too without breaking save compatibility.
  - **Underground / overhang lighting:** In `writeMobVertices`, checking `ly + 1` (and `ly + 2` only when `ly` is `0x00` and `ly + 1` is also opaque) only triggers when the mob's midpoint is inside an opaque block, small (`height < 1.2`), or dipped (`viewDY < -0.05`). A chicken inside a genuinely dark cave has `0x00` in both `ly` and `ly + 1`, so cave mobs stay properly dark and never pull daylight through a cave roof.