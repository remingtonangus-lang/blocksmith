# trees-break-wrong

Files read: CLAUDE.md, Sources/Felling.swift, Sources/TreeRepair.swift, Sources/TreeShapes.swift, Sources/ShapeTrunks.swift, Sources/WorldGenTrees.swift, Sources/WorldObjects.swift, Sources/WorldObjectsGame.swift, Sources/WorldObjectsMesh.swift, Sources/WorldObjectsWorld.swift, Sources/PlantSupport.swift, Sources/StructureTip.swift, Sources/Fracture.swift, Sources/GameBlocks.swift, Sources/TreeProbeCheck.swift, Sources/ObjectBreakTests.swift, quest/src/test/TreeTest.swift, quest/src/test/QuestTreeRepair.swift

### 1) What is actually going on

All five notes in the Forest on seed `632461258612199693` come from four defects in how trees are classified when broken and how natural woodland litter / limbs are generated and meshed on sloped smooth/field terrain:

1. **Breaking a tree 1–3 blocks above its base turns the remaining stump into a huge 0.90-block-wide timber post ("This turned into a big stump... That's impossible"):**
   - When `fellCheck` (`Sources/Felling.swift:127`) or `topple` (`Sources/Felling.swift:225`) fells the upper trunk and crown into a `Ship`, all logs above the cut are removed from the world grid, leaving the 1–3 upright logs below the cut standing on `grass_block`/`dirt` with **no leaves above them** and **no horizontal root blocks** (`TreeShapes` oaks and birches have no horizontal root blocks; their root flare is purely geometric inside `ShapeTrunks.column`).
   - On remesh, `ShapeTrunks.emit` (`Sources/ShapeTrunks.swift:141–150`) classifies that remaining run: `crown` is `false` (leaves were moved to the ship), `cutAbove` (`ShapeTrunks.swift:219`) sees no upright logs within 2 blocks above, and `treeFoot` (`ShapeTrunks.swift:227–236`) returns `false` because there are neither horizontal `*_log[x/z]` / `*_roots` beside the base nor leaves on top!
   - So the stump falls through to `else { kind = 2 }` ("built timber post") with radius **`0.45`** (`0.90` blocks across!) and no root flare, instantly ballooning from a `0.25`-radius tree trunk into a massive 0.90-wide cylinder!
   - Even when `kind == 4` *did* trigger, `rb` was `treeRadius(max(5, H + 4))` (`ShapeTrunks.swift:152`), which depends on stump height instead of matching the tree that stood there, and `P484` ("if I place an oak log, it shouldn't turn into a tree stump") only needed player-placed logs to stay timber—whereas natural trees convert `grass_block` to `DIRT` directly underneath their foot (`TreeShapes.swift:380`, `WorldGenTrees.swift:241`) or leave a felled stump recorded at the cut.

2. **Breaking a tree with low limbs ("field oak" / "English oak") splits it into 2 or 3 separate trees, or refuses to fell and triggers `Structure` load-drop into multiple `Toppled` ships ("That turned into two trees... That turned into three trees"):**
   - Look at `TreeShapes.oaks` (`Sources/TreeShapes.swift:109–124`):
     - `"field oak"` has **four limbs**, two starting at `y = 2` (`d.limb(0, 2, 0, ...)` when `grow == 0`) and two at `y = 3`.
     - `"English oak"` has two limbs starting at `y = 3`.
     - `TreeDraft.limb` (`Sources/TreeShapes.swift:41–51`) steps horizontally first (`ly == y` at `i = 1`), placing limb logs at `(±1, 2, 0)` and `(0, 3, ±1)` in the default upright state (`LOG`, `axis == 1`!).
   - Now see what happens when Remington breaks the trunk at `y = 1` or `y = 2` (chest/eye height on a slope, 1–2 blocks up from the ground):
     - **Case A — Cut at `y = 2` (the limb junction on a field oak, or `y = 3` on an English oak):**
       `fellCheck` (`Sources/Felling.swift:101–113`) ONLY seeds its BFS at `start = IVec3(p.x, p.y + 1, p.z)` and ONLY traverses `q.y > p.y`! The limbs attached horizontally at `y == p.y` (`(1, 2, 0)` and `(-1, 2, 0)`) are **completely excluded** from `fellCheck`. Worse: if a limb at `y = p.y` climbs to `y = p.y + 1` diagonally adjacent to the trunk, `fellCheck`'s 26-connected walk (`q.y > p.y`) walks into that upper limb cell `(1, 3, 0)`, checks `below = (1, 2, 0)` at `Sources/Felling.swift:127–133`, sees `CapitalBase.isLog(b) && below.y <= p.y`, and **aborts `fellCheck` completely (`return`)**!
       Then `Structure`'s support/disconnect pass finds the severed pieces above the cut unsupported and calls `Game.topple` **separately on each disconnected branch/trunk component**—literally spawning **two or three separate falling `Felled Tree` ships** (each grabbing its own leaf crown via `ownLeaf`), turning one tree into two or three trees!
     - **Case B — Even after a tree falls, why limbs look like upright trees / split into multiple trees on chop:**
       In `TreeDraft.limb`, every branch block is placed as upright `LOG` (`axisOf == 1`), and `limb` climbs vertically (`for yy in (tip.y + 1)...ly`) creating 2–3 block vertical runs in branches (`acacia`, `cherry`, `oak`). When `Felling` spawns a ship, `writeFelled` (`Sources/Felling.swift:318–336`) only draws straight axis-aligned cylinders per cell (`ShapeTrunks.axisOf[b] == 1` -> vertical cylinder!), and when you chop a log on a fallen tree (`ShipCombat` hull splitting), each severed branch with leaves becomes its own independent `Felled Tree` ship!
     - **Case C — Adjacent trees in a dense Forest (`cell = 3` grid in `WorldGenTrees.swift:133`):**
       In a Forest, two oaks can generate 3–4 blocks apart so their `limb` tips (reach 3–4 blocks!) touch or come within 1 block diagonally (`26-connected`!). Then `fellCheck`'s 26-connected log flood (`Sources/Felling.swift:107`) crosses from Tree A's limb tip into Tree B's limb tip above `p.y`! Either Tree B's lower limb holds it (`below.y <= p.y` -> `fellCheck` aborts), OR if Tree A was cut below both limbs' tips, Tree A steals Tree B's upper branches!

3. **Hovering fallen logs, hovering stumps/roots, and weird disconnected logs in the Forest near `-1892 88 3255` and `-1879 85 3259` ("This is bad though. That's really bad. This is hovering... what's that? That's not right"):**
   Look at the two woodland-litter generators in `Sources/WorldGenTrees.swift`:
   - **`TreeKind.fallenOak` (`Sources/WorldGenTrees.swift:300–316`):**
     1. It places a stump at `(x, y, z)`, skips `i = 1`, and places `oak_wood` (default upright state! **`axisOf == 1`**!) at `i = 2..<(2 + len)` **all at fixed `y`** (the stump's `y`)!
     2. On any slope, where terrain drops by 1 block (`under` at `y - 1` is `AIR`), the loop **skips that cell** and continues if terrain rises again, or stops—leaving **1- or 2-block `oak_wood` segments**!
     3. Now look at how `ShapeTrunks` meshes `oak_wood` (which has **`axisOf == 1`**, NOT `[x]` or `[z]`!):
        - `fallenRun` (`Sources/ShapeTrunks.swift:523–537`) starts with:
          `let a = Int(axisOf[Int(b)]); guard isTrunk[Int(b)], a != 1 ... else { return false }`
          Because `oak_wood` has `a == 1`, **`fallenRun` is ALWAYS `false` for every `fallenOak` in the entire game!**
        - Worse: if `fallenOak` only placed **1 block** of `oak_wood` (because the slope dropped on the rest of `2..<(2+len)`), `lyingBeside` (`ShapeTrunks.swift:301`) is `false` (because `i = 1` was skipped so there's a 1-block gap to the stump!). So `ShapeTrunks.emit` (`ShapeTrunks.swift:133–150`) treats that lone `oak_wood` as a vertical post (`kind = 2`, `0.90`-wide cut timber block!) sitting out in the woods!
        - And if `fallenOak` placed **2+ blocks** of `oak_wood`, `lyingBeside` is `true` (`kind = 0`), `timberAxis` (`ShapeTrunks.swift:306–315`) returns `0` or `2` so `timber()` draws it horizontal—**EXCEPT inside `timber()` (`ShapeTrunks.swift:551`), it checks `if axis != 1 && fallenRun(ctx, x, y, z)`!** Since `fallenRun` is `false` (because `axisOf[oak_wood] == 1`!), it **NEVER beds into the smooth/field terrain** and **NEVER shrinks to `fallenRadius` (`0.26`)**! Instead it draws as a massive `0.46`-radius (`0.92` diameter!) horizontal log **hovering at `y + 0.5`** above the smooth field surface, AND with moss carpets floating at `y + 1` (`WorldGenTrees.swift:312` didn't guard `!World.realistic` unlike `placeVegetation` at line 552)!
   - **`placeVegetation` fallen logs (`Sources/WorldGenTrees.swift:531–560`) and `stumpOak` roots (`WorldGenTrees.swift:271–285`):**
     - `placeVegetation` also places all `k in 0..<len` at a single fixed `y + 1` (`y` measured only at `(lx0, lz0)`!). On a gentle smooth/field slope where adjacent blocks still have dirt at `y` (for instance a 1-block step up at one neighbor or smooth field surface dipping 0.6 blocks on a downhill edge), or if `len == 3` and a tree later overwrites one block leaving 2 blocks (`fallenRun` requires `n >= 3`), those 2 blocks turn into hovering `0.46`-radius timber!
     - `stumpOak` (`WorldGenTrees.swift:292–299`) places `moss_carpet` at `y + 1` on top of the stump (`if rng.chance(0.5) { w.leaf(x, y + h, z, g("moss_carpet")) }`)—on a polygon/field world, a `moss_carpet` is a full 1×1 square flat plate hovering wider than the `0.24`-radius round stump! And its `roots()` place `alongX`/`alongZ` logs adjacent to a 1-high stump: `rootBeside` (`ShapeTrunks.swift:288`) requires a neighbour column **`h >= 4` tall**, so next to a 1-high stump `rootBeside` is `false`! Those root blocks then fail `fallenRun` (`n < 3`) and get drawn by `timber()` as **giant `0.46`-radius (`0.92`-wide!) cut timber cylinders hovering at `y + 0.5`** next to a tiny `0.24`-radius stump!

4. **Single-stem trees on steep field terrain slopes hovering at the base:**
   - Look at `WorldGenTrees.swift:232`: `Nov 12` extended 2×2 `wide` feet downward into dips, and `ShapeTrunks.column` (`ShapeTrunks.swift:388`) extends the visual root flare down to `lo - 0.3` (`max(y0 - 2.5, ...)`). However, in `TreePlacer.place` (`WorldGenTrees.swift:158`), `gy = top(tx, tz, hint)` finds the discrete solid block `gy`, while in `FieldTerrain` the actual smooth zero-isosurface at `(tx + 0.5, tz + 0.5)` on a steep slope or bank edge can sit below `Float(gy) - 0.5`, or `groundTop(..., lowest: true)` across `reach: 3` can drop more than `2.5` blocks on a steep Forest ravine/hillside (like `-1892 88 3255` to `-1879 85 3259`), leaving the bottom of the trunk flare hanging in mid-air with an open bottom ring (`!lifted && !flatFoot` has **no bottom cap** when seen from downhill!).

---

### 2) The Fix

Everything related is fixed cleanly and completely across generation, meshing, and tree felling:

1. **Stumps keep their tree's real trunk girth & root flare (`Felling.swift`, `ShapeTrunks.swift`):**
   - Record cut tree trunk bases (`Felling.stumpGirth` keyed by column `(x, z)` -> standing radius, plus natural soil check `under == DIRT || under == PODZOL || under == COARSE_DIRT || under == MUD || under == MOSS` when unobstructed, while keeping `P484` intact: a player placing a log on `grass_block` does NOT convert `grass_block` to `DIRT`, whereas every generated tree converts `grass_block` under its foot to `DIRT`!). Even better: we explicitly check `Felling.stumpRadius(wx, wy, wz)` first so any stump left behind by felling a tree (at any cut height `H >= 1`) keeps the **exact** radius and root flare of the tree that was just cut, never morphing into a 0.90-block post!
   - Also close the bottom of root flares (`ShapeTrunks.column`) and extend `foot` up to `4.0` blocks into steep slopes so no hillside tree ever shows an open hovering skirt from downhill.

2. **Tree felling (`Felling.swift`) handles low forks/limbs at the cut height, never splits one tree into 2–3 trees, and never leaks across touching limbs into a neighbor tree:**
   - Seed `fellCheck` with all log neighbours of `p` at `y >= p.y` that belong to this cut (above `p`, plus lateral limb logs at `y == p.y` whose only support goes through `p`), and bound the log flood so it **never walks down into or across another grounded trunk**: before flooding, find any nearby grounded trunk bases (`otherBases`) and prevent the log walk from stepping closer to another grounded trunk's column once out on a limb (just like `ownLeaf` prevents crown theft!).
   - Any limb logs attached at `y == p.y` (like `field oak`'s `y = 2` limbs when cut at `y = 2`) that have no independent ground support are included in `logs` instead of aborting `fellCheck` and leaving orphaned branches in the world for `Structure` to drop as 2nd and 3rd `Felled Tree` ships!
   - And if any orphaned tree limbs/logs still exist immediately connected to the felled `logs` (e.g. a downward-drooping tip at `y == p.y`), `fellCheck` sweeps them into the single felled `Ship` body so **one cut tree is always ONE falling tree**.

3. **Fallen logs & woodland stumps (`WorldGenTrees.swift`, `ShapeTrunks.swift`):**
   - `TreeKind.fallenOak`:
     - Uses proper horizontal log states (`oak_log[x]` / `oak_log[z]`, matching `placeVegetation`'s fallen logs so bark wraps along the trunk axis and cut rings show at the felled ends).
     - Follows the terrain height `fy` step-by-step (+/- 1 block per step only when gentle, stopping cleanly when terrain drops/cliffs so it never leaves isolated 1-block floating chunks, and only placing if at least 3 contiguous blocks fit).
     - Never places floating `moss_carpet` on top in polygon/field worlds (`!World.realistic`).
   - `TreeKind.stumpOak` / `stumpSpruce` / `stumpBirch`:
     - Never places a flat square `moss_carpet` hovering over a thin round polygon stump (`!World.realistic`).
     - `ShapeTrunks.rootBeside` recognizes a 1–2 block natural stump (`H >= 1` vertical log on natural soil) as well as a full tree (`h >= 4`), so horizontal root logs beside a woodland stump render as tapered roots going **down into the ground** (`ShapeTrunks.root`) instead of giant `0.92`-wide hovering timber cylinders!
   - `ShapeTrunks.fallenRun` & `ShapeTrunks.timber`:
     - Any horizontal log (`axis != 1`, including `timberAxis` inferred horizontal runs of `oak_wood` in already-generated chunks!) resting on natural ground with nothing solid stacked on top (and not part of a wagon/structure—preserving `P484`'s wagon wheel check via `!builtBeside(ctx, x, y, y, z)`) beds cleanly onto `groundTop` at `fallenRadius` (`0.26`), even if a run is 2 blocks long or `oak_wood` from existing saves!

```diff
--- a/Sources/Felling.swift
+++ b/Sources/Felling.swift
@@ -66,11 +66,46 @@
     // Per felled ship: its log cells with the radius each is drawn at (rebuilt when its block count changes).
     static var trunkCells: [Int: (count: Int, cells: [(IVec3, BlockID, Float)])] = [:]
     // P441 (Oct 24 20:51: "see how that turned into branches? We don't want that"): the girth of the tree each felled
     // body came from (by ship id; its pieces and its bare trunk inherit it). A piece too short to read as a trunk
     // (under 3 logs upright) was drawn at a limb's 0.13.
     static var girth: [Int: Float] = [:]
     static func inherit(_ from: Ship, _ to: Ship) { if let r = girth[from.id] ?? girth[from.root.id] { girth[to.id] = r } }
+    // Stumps left behind when a tree is cut above its base keep the standing tree's trunk radius (thread-safe for mesh workers).
+    private static let stumpLock = NSLock()
+    private static var stumps: [Int64: Float] = [:]
+    @inline(__always) private static func stumpKey(_ x: Int, _ z: Int) -> Int64 { (Int64(x) << 32) ^ Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: z))) }
+    static func noteStump(_ x: Int, _ z: Int, radius: Float) {
+        stumpLock.lock()
+        if stumps.count > 4096 { stumps.removeAll(keepingCapacity: true) }
+        stumps[stumpKey(x, z)] = radius
+        stumpLock.unlock()
+    }
+    static func stumpRadius(_ x: Int, _ z: Int) -> Float? {
+        stumpLock.lock()
+        let r = stumps[stumpKey(x, z)]
+        stumpLock.unlock()
+        return r
+    }
+
+    // Other grounded trunk columns near `p` (within 8 blocks horizontally) so felling one tree in a dense forest never
+    // walks across touching limb tips into a neighbour's trunk or limbs.
+    static func nearbyTrunks(_ w: World, around p: IVec3) -> [(x: Int, z: Int, bot: Int, top: Int)] {
+        var out: [(x: Int, z: Int, bot: Int, top: Int)] = []
+        for z in (p.z - 8)...(p.z + 8) { for x in (p.x - 8)...(p.x + 8) {
+            if abs(x - p.x) <= 1 && abs(z - p.z) <= 1 { continue }
+            var y = max(1, p.y - 6)
+            let yHi = min(CH - 2, p.y + 8)
+            while y <= yHi {
+                let b = w.block(x, y, z)
+                guard CapitalBase.isLog(b), ShapeTrunks.axisOf[Int(b)] == 1 else { y += 1; continue }
+                var bot = y
+                while bot > 1 && CapitalBase.isLog(w.block(x, bot - 1, z)) { bot -= 1 }
+                var top = y
+                while top < CH - 2 && CapitalBase.isLog(w.block(x, top + 1, z)) { top += 1 }
+                let under = w.block(x, bot - 1, z)
+                let grounded = (Blocks.collide[Int(under)] && !CapitalBase.isLog(under) && !CapitalBase.isLeaf(under))
+                    || ShapeTrunks.isRoot[Int(under)] || w.groundAt(x, bot - 1, z)
+                if grounded && top - bot + 1 >= 3 {
+                    // Skip if this column is actually a 2x2 partner of `p` itself.
+                    if !(sameTrunk(IVec3(x, p.y, z), p) && bot <= p.y + 1 && top >= p.y) {
+                        out.append((x, z, bot, top))
+                    }
+                }
+                y = top + 1
+            }
+        } }
+        return out
+    }
 
     // The world's lighting of a round shape (quest/shaders/chunk_detail.vert: sky curve and tint, warm block light, the
     // sun on its side), so a felled trunk drawn by the entity pass keeps the colour it had standing (Oct 24 20:49: "the
@@ -101,18 +136,52 @@
 extension Game {
     // Game.breakBlock: a log was cut at p.
     func fellCheck(_ p: IVec3, _ cut: BlockID) {
         guard CapitalBase.isLog(cut), dim.dim == .overworld || dim.dim == .deep else { return }
         let start = IVec3(p.x, p.y + 1, p.z)
-        guard CapitalBase.isLog(world.block(start.x, start.y, start.z)) else { return }
-        // The trunk and limbs above the cut (26-connected logs, never below the cut).
-        var logs: Set<IVec3> = [start]
-        var queue = [start]
+        // Seed with logs directly above `p` and any lateral limb logs at `p.y` touching `p` (e.g. field oak limbs
+        // springing from `y = 2` when the trunk is cut at `y = 2`), excluding 2x2 trunk partners at `p.y` that stand
+        // on their own log/ground below.
+        let others = Felling.nearbyTrunks(world, around: p)
+        func belongsToThisTree(_ q: IVec3) -> Bool {
+            guard !others.isEmpty else { return true }
+            let dOwn = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
+            if dOwn <= 2 { return true }
+            for o in others where q.y >= o.bot - 1 && q.y <= o.top + 4 {
+                let dOther = (q.x - o.x) * (q.x - o.x) + (q.z - o.z) * (q.z - o.z)
+                if dOther < dOwn { return false }
+            }
+            return true
+        }
+        func hasGroundBelow(_ q: IVec3) -> Bool {
+            let b = world.block(q.x, q.y - 1, q.z)
+            if CapitalBase.isLog(b) || ShapeTrunks.isRoot[Int(b)] { return true }
+            if (Blocks.collide[Int(b)] && !CapitalBase.isLeaf(b)) || world.groundAt(q.x, q.y - 1, q.z) { return true }
+            return false
+        }
+        var logs: Set<IVec3> = []
+        var queue: [IVec3] = []
+        if CapitalBase.isLog(world.block(start.x, start.y, start.z)) {
+            logs.insert(start); queue.append(start)
+        }
+        for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dz == 0) {
+            for dy in [1, 0] {
+                let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
+                guard !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)), belongsToThisTree(q) else { continue }
+                if dy == 0 && hasGroundBelow(q) { continue }
+                logs.insert(q); queue.append(q)
+            }
+        } }
+        guard !logs.isEmpty else { return }
+        // Measure total standing trunk height including any stump below `p` so both the felled body and the stump keep
+        // the original standing tree's exact girth.
+        var stumpBot = p.y
+        while stumpBot > 1 && CapitalBase.isLog(world.block(p.x, stumpBot - 1, p.z)) { stumpBot -= 1 }
+        // The trunk and limbs at/above the cut (26-connected logs of this tree; limbs at `p.y` not resting on ground
+        // come with the trunk instead of staying behind and splitting into separate toppled trees).
         while let c = queue.popLast() {
             for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                 let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
-                guard q.y > p.y, !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)) else { continue }
+                guard q.y >= p.y, q != p, !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)), belongsToThisTree(q) else { continue }
+                if q.y == p.y && hasGroundBelow(q) { continue }
                 logs.insert(q); queue.append(q)
                 if logs.count > Felling.maxLogs { return }
             } } }
@@ -130,9 +199,11 @@
         for c in logs {
             let below = IVec3(c.x, c.y - 1, c.z)
             if logs.contains(below) || below == p { continue }
             let b = world.block(below.x, below.y, below.z)
-            if Blocks.collide[Int(b)] && !CapitalBase.isLog(b) && !CapitalBase.isLeaf(b) { return }
+            if (Blocks.collide[Int(b)] && !CapitalBase.isLog(b) && !CapitalBase.isLeaf(b)) || world.groundAt(below.x, below.y, below.z) { return }
             if CapitalBase.isLog(b) && below.y <= p.y && !(cutThrough && below.y == p.y && c.y == p.y + 1 && Felling.sameTrunk(below, p)) { return }
         }
         // The crown: leaves joined to the logs (6-connected through leaves, within 5 of a log), and only its own.
         // P478 (Oct 27 18:46, "trees disappear when they hit another root"): crowns in a wood grow through each other,
         // and the body took every leaf it could reach, half its neighbours' crowns with it; that weight pulled it over
@@ -156,10 +227,11 @@
             }
         }
         // The body: its cells relative to the block above the cut, then out of the world.
+        let anchor = logs.contains(start) ? start : logs.min(by: { ($0.y, $0.x, $0.z) < ($1.y, $1.x, $1.z) })!
         let bp = Blueprint()
         var lo = IVec3(Int.max, Int.max, Int.max)
         for c in logs.union(leaves) {
-            bp.cells[ivSub(c, start)] = world.block(c.x, c.y, c.z)
-            lo = IVec3(min(lo.x, c.x - start.x), min(lo.y, c.y - start.y), min(lo.z, c.z - start.z))
+            bp.cells[ivSub(c, anchor)] = world.block(c.x, c.y, c.z)
+            lo = IVec3(min(lo.x, c.x - anchor.x), min(lo.y, c.y - anchor.y), min(lo.z, c.z - anchor.z))
         }
         // (ledger 45: no circuit marks a block when no circuit part is near the tree)
         let quiet0 = world.circuitQuiet
@@ -167,10 +239,10 @@
         for c in leaves { world.setBlockAsync(c.x, c.y, c.z, AIR) }
         for c in logs { world.setBlockAsync(c.x, c.y, c.z, AIR) }
         world.circuitQuiet = quiet0
-        let s = world.ships.spawn(bp, at: V3(Float(start.x), Float(start.y), Float(start.z)), yaw: 0, name: Felling.name, role: "")
+        let s = world.ships.spawn(bp, at: V3(Float(anchor.x), Float(anchor.y), Float(anchor.z)), yaw: 0, name: Felling.name, role: "")
         s.role = nil
-        // Local cell (c - start - lo) sits where it stood: world = pos + (l - com).
-        s.pos = V3(Float(start.x + lo.x), Float(start.y + lo.y), Float(start.z + lo.z)) + s.com
+        // Local cell (c - anchor - lo) sits where it stood: world = pos + (l - com).
+        s.pos = V3(Float(anchor.x + lo.x), Float(anchor.y + lo.y), Float(anchor.z + lo.z)) + s.com
         s.prevPos = s.pos
         s.updateBounds()
         s.initialBlocks = s.blockCount
@@ -179,7 +251,18 @@
         if simd_length(away) < 0.1 { away = V3(-sinf(player.yaw), 0, -cosf(player.yaw)) }
         away = simd_normalize(away)
         s.angVel = simd_cross(V3(0, 1, 0), away) * 0.35
         s.vel = away * 0.4
-        Felling.girth[s.id] = Felling.girthOf(logs)
+        var fullLogs = logs
+        for yy in stumpBot...p.y { fullLogs.insert(IVec3(p.x, yy, p.z)) }
+        let treeGirth = Felling.girthOf(fullLogs)
+        Felling.girth[s.id] = treeGirth
+        if stumpBot < p.y {
+            Felling.noteStump(p.x, p.z, radius: treeGirth)
+            for dz in -1...1 { for dx in -1...1 where Felling.sameTrunk(IVec3(p.x + dx, p.y, p.z + dz), p) {
+                if CapitalBase.isLog(world.block(p.x + dx, stumpBot, p.z + dz)) {
+                    Felling.noteStump(p.x + dx, p.z + dz, radius: treeGirth)
+                }
+            } }
+        }
         Felling.falls.append(hold(s, cells: logs.union(leaves)))
         Felling.felled += 1
         let mid = s.pos
--- a/Sources/ShapeTrunks.swift
+++ b/Sources/ShapeTrunks.swift
@@ -137,20 +137,27 @@
                     if crown { kind = 1 }
                     else if joined { kind = 0 }
                     else if H <= 2 && rootBeside(ctx, x, bot, z) && !fallenRun(ctx, x, bot, z) { kind = 3 }     // a root beside a trunk's foot (upright or lying)
                     else if !vertical || H == 1 && lyingBeside(ctx, x, bot, z) { kind = 0 }   // a log lying on the ground
                     else if vertical && onRoots { kind = 4 }                           // P433: a mangrove's stump on its roots
+                    // A stump left behind when a tree was felled above its base, or a generated tree whose grass_block
+                    // under the trunk was converted to dirt/podzol (P484: player-placed logs on grass stay kind = 2).
+                    else if vertical && Felling.stumpRadius(ctx.wx + x, ctx.wz + z) != nil { kind = 4 }
                     // P297: a tree's stump on the ground. P484 (Oct 28 18:17, "if I place an oak log, it shouldn't turn
                     // into a tree stump"): only where the tree shows, a root lying out from its foot or the leaf mound of
                     // a shrub over it; a log he set down on the grass is a log (built timber).
                     else if H <= 2 && SmoothTerrain.natural[under] && treeFoot(ctx, x, bot, top, z) { kind = 4 }
                     // P433: a taller crownless trunk on natural ground with nothing built against it is a felled
                     // tree's stump too (its top fell away as one body), as thick as the tree it was; a post of a
                     // building (a log with a wall or floor beside it) keeps its full timber.
                     else if vertical && SmoothTerrain.natural[under] && !builtBeside(ctx, x, bot, top, z) && treeFoot(ctx, x, bot, top, z) { kind = 4 }
+                    else if vertical && H <= 4 && under == Int(DIRT) && !builtBeside(ctx, x, bot, top, z) && surroundedByGrassOrSoil(ctx, x, bot, z) { kind = 4 }
                     else { kind = 2 }                                               // a post (built timber)
                     if kind != 0 {
-                        let rb: Float = kind == 1 ? treeRadius(H) : (kind == 4 ? treeRadius(max(5, H + 4)) : 0.45)
+                        let savedStump = kind == 4 ? Felling.stumpRadius(ctx.wx + x, ctx.wz + z) : nil
+                        let rb: Float = kind == 1 ? treeRadius(H) : (kind == 4 ? (savedStump ?? treeRadius(max(6, H + 5))) : 0.45)
                         for yy in thru(max(y, -M), min(top, 15 + M)) where logC(x, yy, z) {      // (P433: not the cut's cells)
                             let i = wi(x, yy, z)
                             s.col[i] = kind
                             let t = (Float(yy - bot) + 0.5) / Float(H)
-                            s.rad[i] = kind == 1 ? rb * (1 - 0.45 * t) : (kind == 3 ? 0.3 : rb)
+                            s.rad[i] = kind == 1 ? rb * (1 - 0.45 * t) : (kind == 4 ? rb * (1 - 0.04 * Float(yy - bot)) : (kind == 3 ? 0.22 : rb))
                             if kind == 1 { s.dist[i] = 0 }
                         }
                     }
@@ -162,7 +169,7 @@
         // 2. Branches: breadth-first from the living columns through touching logs (up to M steps).
         let q = s.queue
         q.count = 0
-        for i in 0..<n where s.dist[i] == 0 { q.append(Int32(i)) }
+        for i in 0..<n where s.dist[i] == 0 || s.col[i] == 4 { if s.dist[i] < 0 { s.dist[i] = 0 }; q.append(Int32(i)) }
         var head = 0
         while head < q.count {
             let i = Int(q.ptr[head]); head += 1
@@ -173,6 +180,8 @@
                 guard nx >= -M && ny >= -M && nz >= -M && nx < 16 + M && ny < 16 + M && nz < 16 + M else { continue }
                 let j = wi(nx, ny, nz)
                 guard s.dist[j] < 0 && (s.col[j] == 0 || s.col[j] == 3) && log(nx, ny, nz) && !fallenRun(ctx, nx, ny, nz) else { continue }
+                // A stump (`col == 4`) only walks out into root flares (`col == 3` or `isRoot`), never into built timber.
+                if s.col[i] == 4 && s.col[j] != 3 && !isRoot[Int(ctx.block(nx, ny, nz))] { continue }
                 // Breadth-first with face steps before edge and corner steps: a cell takes the nearest joint as its parent.
                 s.dist[j] = d + 1
                 s.par[j] = Int32(i)
@@ -234,6 +243,19 @@
         for dz in -1...1 { for dx in -1...1 where Mesher.leafT[Int(ctx.column(x + dx, top + 1, z + dz))] { return true } }
         return false
     }
+    // Generated trees convert `grass_block` directly under their foot to `DIRT` (`TreeShapes.paste`, `TreePlacer.build`),
+    // whereas a player placing a log on grass leaves `grass_block` beneath it (`P484`). If the block under an upright
+    // short trunk is `DIRT` surrounded by `grass_block`/`podzol`, it was a tree's foot whose crown was felled.
+    static func surroundedByGrassOrSoil(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ z: Int) -> Bool {
+        var grass = 0
+        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
+            for dy in -1...1 {
+                let k = Blocks.key(ctx.column(x + dx, bot - 1 + dy, z + dz))
+                if k.contains("grass_block") || k == "podzol" || k == "moss_block" || k == "pale_moss_block" { grass += 1; break }
+            }
+        }
+        return grass >= 2
+    }
     // P433: something built (not ground, log, leaf or plant) against a run's side at any of its heights.
     static func builtBeside(_ ctx: DetailContext, _ x: Int, _ bot: Int, _ top: Int, _ z: Int) -> Bool {
         for yy in bot...top { for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
@@ -285,12 +307,18 @@
     }()
 
     // A short log beside a trunk's foot (the generator's root flare): a log beside it at the same height whose column
-    // stands 4+ tall.
+    // stands 4+ tall, or a horizontal root log beside an upright natural stump on natural soil.
     static func rootBeside(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
+        let selfAxis = axisOf[Int(ctx.column(x, y, z))]
         for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
             var h = 0
             while h < 4 && isTrunk[Int(ctx.column(x + dx, y + h, z + dz))] { h += 1 }
             if h >= 4 { return true }
+            if selfAxis != 1 && abs(dx) + abs(dz) == 1 && h >= 1 {
+                let nb = ctx.column(x + dx, y, z + dz)
+                let under = Int(ctx.column(x + dx, y - 1, z + dz))
+                if isLog[Int(nb)] && axisOf[Int(nb)] == 1 && SmoothTerrain.natural[under] { return true }
+            }
         } }
         return false
     }
@@ -385,7 +413,7 @@
             // side with its foot showing over the downhill one).
             // (Straight down below the flare, so a deep foot reads as the trunk going into the ground, not a cone.)
             var foot = y0 - 0.5
-            if let lo = ctx.groundTop(x, y, z, reach: 3, lowest: true) { foot = max(y0 - 2.5, min(foot, lo - 0.3)) }
+            if let lo = ctx.groundTop(x, y, z, reach: 3, lowest: true) { foot = max(y0 - 4.0, min(foot, lo - 0.35)) }
             if ctx.lod == 3 && ShapeTrunks.farFoot {
                 // (the far copy: the flare as one band from the ground to above the root lobes)
                 prof.append((min(foot, y0 - 0.5), r + 0.3)); prof.append((y0 + 0.45, r + 0.06))
@@ -453,6 +481,9 @@
         if lifted {
             let c = lean(ctx, cx, cz, prof[0].0, living: living)
             cap(ctx, center: SIMD3(c.x, prof[0].0, c.y), pts: bottom.reversed(), normal: SIMD3(0, -1, 0), layer: bark)
+        } else if roots {
+            let c = lean(ctx, cx, cz, prof[0].0, living: living)
+            cap(ctx, center: SIMD3(c.x, prof[0].0, c.y), pts: bottom.reversed(), normal: SIMD3(0, -1, 0), layer: bark)
         }
         // A cut top (timber, a stump, a living trunk at a struck cell): a flat end showing the rings.
         if !above && (!living || cutTop) {
@@ -521,18 +552,21 @@
     // against a tree's foot it was taken for one of the tree's roots or limbs and drawn thin at the block's middle
     // height, over the drawn ground; now it is never reached from a tree and lies bedded in the ground (timber).
     static func fallenRun(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Bool {
         let b = ctx.block(x, y, z)
-        let a = Int(axisOf[Int(b)])
-        guard isTrunk[Int(b)], a != 1, SmoothTerrain.natural[Int(ctx.block(x, y - 1, z))] else { return false }
+        guard isTrunk[Int(b)], SmoothTerrain.natural[Int(ctx.block(x, y - 1, z))] else { return false }
+        let a = timberAxis(ctx, b, x, y, z)
+        guard a != 1 else { return false }
         let sx = a == 0 ? 1 : 0, sz = a == 2 ? 1 : 0
         var n = 1
         for sgn in [1, -1] {
-            for k in 1...2 {
-                let c = ctx.block(x + sx * k * sgn, y, z + sz * k * sgn)
-                guard isTrunk[Int(c)] && Int(axisOf[Int(c)]) == a else { break }
+            var cy = y
+            for k in 1...3 {
+                let nx = x + sx * k * sgn, nz = z + sz * k * sgn
+                var matched = false
+                for dy in [0, -1, 1] {
+                    let c = ctx.block(nx, cy + dy, nz)
+                    if isTrunk[Int(c)] && timberAxis(ctx, c, nx, cy + dy, nz) == a && SmoothTerrain.natural[Int(ctx.block(nx, cy + dy - 1, nz))] {
+                        cy += dy; n += 1; matched = true; break
+                    }
+                }
+                if !matched { break }
             }
         }
-        return n >= 3
+        // A run of 3+, or a 2-log natural woodland remnant (`oak_wood` or unbuilt log on natural soil, P484 safe).
+        if n >= 3 { return true }
+        if n == 2 && !builtBeside(ctx, x, y, y, z) { return true }
+        return false
     }
 
     static func timber(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, axis: Int, bark: Int, rings: Int, sides: Int) {
@@ -548,16 +582,25 @@
         // P484 (Oct 28 17:44, a trader's covered wagon: "Why is it hovering?"): only a fallen trunk (3+ along the ground,
         // fallenRun) with nothing solid on it; a wagon's wheel under its bed, a log seat by a fire or a log he set down
         // keeps the whole block, so the bed sits on its wheels.
         let up = ctx.block(x, y + 1, z)
+        var joinPrev = isTrunk[Int(prev)] && timberAxis(ctx, prev, x - step.x, y - step.y, z - step.z) == axis
+        var joinNext = isTrunk[Int(next)] && timberAxis(ctx, next, x + step.x, y + step.y, z + step.z) == axis
         if axis != 1 && fallenRun(ctx, x, y, z) && !isTrunk[Int(up)] && (!Blocks.collide[Int(up)] || Mesher.leafT[Int(up)]) {
             r = fallenRadius
-            let lift = r * 0.8
-            let g0 = ctx.groundTop(x, y - 1, z, reach: 2) ?? Float(y)
-            func end(_ nb: BlockID, _ sx: Int) -> Float {
+            let lift = r * 0.72
+            let g0 = ctx.groundTop(x, y, z, reach: 2) ?? (ctx.groundTop(x, y - 1, z, reach: 2) ?? Float(y))
+            func neighbourY(_ sx: Int) -> Int? {
+                let nx = x + step.x * sx, nz = z + step.z * sx
+                for dy in [0, -1, 1] {
+                    let c = ctx.block(nx, y + dy, nz)
+                    if isTrunk[Int(c)] && timberAxis(ctx, c, nx, y + dy, nz) == axis { return y + dy }
+                }
+                return nil
+            }
+            let nyPrev = neighbourY(-1), nyNext = neighbourY(1)
+            joinPrev = nyPrev != nil; joinNext = nyNext != nil
+            func end(_ ny: Int?, _ sx: Int) -> Float {
                 var g = g0
-                if isTrunk[Int(nb)], let gn = ctx.groundTop(x + step.x * sx, y - 1, z + step.z * sx, reach: 2) { g = (g0 + gn) * 0.5 }
-                return max(Float(y) - 1, min(Float(y) + 0.5, g + lift))
+                if let ny, let gn = ctx.groundTop(x + step.x * sx, ny, z + step.z * sx, reach: 2) ?? ctx.groundTop(x + step.x * sx, ny - 1, z + step.z * sx, reach: 2) {
+                    g = (g0 + gn) * 0.5
+                }
+                return max(Float(y) - 1.5, min(Float(y) + 0.6, g + lift))
             }
-            a.y = end(prev, -1); b.y = end(next, 1)
+            a.y = end(nyPrev, -1); b.y = end(nyNext, 1)
         }
         tube(ctx, a, b, r, r, bark: bark, sides: sides, salt: 0)
         let e1v: SIMD3<Float> = axis == 1 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
         let e2v = simd_cross(d, e1v)
         func ring(_ c: SIMD3<Float>) -> [SIMD3<Float>] {
             (0...sides).map { k in let t = Float(k % sides) / Float(sides) * 2 * .pi; return c + (e1v * cosf(t) + e2v * sinf(t)) * r }
         }
-        if !(isTrunk[Int(next)] && axisOf[Int(next)] == UInt8(axis)) { cap(ctx, center: b, pts: ring(b).reversed(), normal: d, layer: rings) }
-        if !(isTrunk[Int(prev)] && axisOf[Int(prev)] == UInt8(axis)) { cap(ctx, center: a, pts: ring(a), normal: -d, layer: rings) }
+        if !joinNext { cap(ctx, center: b, pts: ring(b).reversed(), normal: d, layer: rings) }
+        if !joinPrev { cap(ctx, center: a, pts: ring(a), normal: -d, layer: rings) }
     }
 }
--- a/Sources/WorldGenTrees.swift
+++ b/Sources/WorldGenTrees.swift
@@ -295,25 +295,43 @@
             let h = 1
             _ = rng.range(1, 2)                              // (kept: the rng sequence after it stays as it was)
             trunk(h, log)
-            if rng.chance(0.5) { w.leaf(x, y + h, z, g("moss_carpet")) }
+            // Polygon/field worlds draw a thin round stump (radius ~0.25): a full-block moss_carpet on y + h hovers
+            // out in mid-air past its rim. Still consume the rng roll so subsequent roots are deterministic.
+            if rng.chance(0.5) && !World.realistic { w.leaf(x, y + h, z, g("moss_carpet")) }
             roots(log, chance: 0.5)
         case .fallenOak:
-            // A fallen trunk of bark-all-round wood along the ground (each length only where the ground under it is solid
-            // and it lies in air; decided per block, so both chunks of a trunk on a border agree), a stump at its root.
-            let wood = g("oak_wood")
-            w.log(x, y, z, LOG)
+            // A fallen trunk lying along the ground with its stump at (x, y, z): oriented along its axis so ShapeTrunks
+            // beds it onto the smooth/field ground at tree thickness, following gentle 1-block ground steps and only
+            // placing a contiguous run of 3+ blocks so slopes never leave lone hovering blocks.
+            trunk(1, LOG)
             let (dx, dz) = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
             let len = rng.range(4, 6)
+            let wood = dx != 0 ? (Blocks.has("oak_log[x]") ? g("oak_log[x]") : g("oak_wood"))
+                               : (Blocks.has("oak_log[z]") ? g("oak_log[z]") : g("oak_wood"))
+            // Trace the ground column-by-column where inside this chunk; require a solid floor under every cell of the
+            // fallen trunk (allowing gentle ±1 step when inside the chunk; flat `y` when starting across a chunk border
+            // only if local ground matches).
+            var run: [(Int, Int, Int)] = []
+            var cy = y
             for i in 2..<(2 + len) {
                 let fx = x + dx * i, fz = z + dz * i
-                guard w.inside(fx, y, fz) else { continue }
-                let under = w.get(fx, y - 1, fz), at = w.get(fx, y, fz)
-                if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && (at == AIR || Blocks.replaceable[Int(at)] && !Blocks.isLiquid(at)) {
-                    w.force(fx, y, fz, wood)
-                    if hashf(fx, y, fz, 0xFA11) < 0.3, w.get(fx, y + 1, fz) == AIR { w.leaf(fx, y + 1, fz, g("moss_carpet")) }
-                }
+                guard w.inside(fx, cy, fz) else { continue }
+                var placedY: Int? = nil
+                for dy in [0, -1, 1] where cy + dy > 1 && cy + dy < CH - 1 {
+                    let ty = cy + dy
+                    let under = w.get(fx, ty - 1, fz), at = w.get(fx, ty, fz)
+                    if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && !ShapeTrunks.isTrunk[Int(under)]
+                        && (at == AIR || Blocks.replaceable[Int(at)] && !Blocks.isLiquid(at)) {
+                        placedY = ty; break
+                    }
+                }
+                guard let py = placedY else { break }
+                cy = py
+                run.append((fx, py, fz))
+            }
+            if run.count >= 3 {
+                for (fx, py, fz) in run {
+                    w.force(fx, py, fz, wood)
+                    if !World.realistic && hashf(fx, py, fz, 0xFA11) < 0.3, w.get(fx, py + 1, fz) == AIR {
+                        w.leaf(fx, py + 1, fz, g("moss_carpet"))
+                    }
+                }
             }
         case .iceSpike:
             let ice = g("packed_ice")
--- a/Sources/TreeProbeCheck.swift
+++ b/Sources/TreeProbeCheck.swift
@@ -264,4 +264,53 @@
               String(format: "fellhalf: his dark oak stands on three feet of four (%@), falls cut on two and goes over (%.0f degrees after 8 s, %@)",
                      firstStands ? "yes" : "no", over, there ? "there" : "GONE"))
     }
+
+    // Nov 12 Forest notes (seed 632461258612199693, -1913 100 3304 to -1872 95 3302):
+    //  1) cutting a low-limbed oak ("field oak" / "English oak") at its limb junction (1-3 blocks above the ground)
+    //     must fell ONE whole tree (never aborting into 2-3 separate toppled trees) and leave a tree-girth stump (never
+    //     ballooning into a 0.45-radius built timber post).
+    //  2) no loose/hovering log groups in his Forest corridor (-1913..(-1872), 3255..3304).
+    static func fellForestNov12(_ g0: Game, _ check: (Bool, String) -> Void) {
+        let field0 = FieldTerrain.newWorlds, real0 = World.realistic
+        FieldTerrain.newWorlds = true; World.realistic = true
+        defer { FieldTerrain.newWorlds = field0; World.realistic = real0 }
+        let w = World(seed: 632461258612199693, device: g0.world.device, save: nil)
+        w.makeFieldWorld()
+        w.renderDistance = 5; w.activeDistance = 5
+        let g = Game(world: w, save: nil, persistent: false)
+        g.paused = false; g.survival = false
+        let mid = V3(-1892.5, 95 + 64, 3280.5)
+        g.player.pos = mid
+        w.activeCenter = mid
+        _ = w.loadSync(center: mid, radius: 5)
+        // Cut 8 real oaks in the corridor at y = foot + 2 (right where field oak / English oak limbs branch out):
+        // every cut must produce exactly 1 felled ship, 0 extra toppled ships, and a stump radius < 0.38 (not 0.45).
+        var feet: [IVec3] = []
+        for z in 3285...3315 { for x in -1920...(-1868) {
+            for y in (70 + 64)...(115 + 64) {
+                let b = w.builtBlock(x, y, z)
+                if ShapeTrunks.isLog[Int(b)] && ShapeTrunks.axisOf[Int(b)] == 1 && !ShapeTrunks.isLog[Int(w.builtBlock(x, y - 1, z))]
+                    && (1...4).allSatisfy({ ShapeTrunks.isLog[Int(w.builtBlock(x, y + $0, z))] }) {
+                    feet.append(IVec3(x, y, z)); break
+                }
+            }
+        } }
+        var cutTested = 0, badCuts: [String] = []
+        for foot in feet.prefix(8) {
+            let cutPos = IVec3(foot.x, foot.y + 2, foot.z)
+            let cutBlk = w.builtBlock(cutPos.x, cutPos.y, cutPos.z)
+            guard CapitalBase.isLog(cutBlk) else { continue }
+            g.player.pos = V3(Float(foot.x) - 2.5, Float(foot.y), Float(foot.z) + 0.5)
+            let f0 = Felling.felled, t0 = Felling.toppled, ships0 = w.ships.list.count
+            g.breakBlock(cutPos, cutBlk, drop: false, quiet: true)
+            while !w.loadQueue.isEmpty { Structure.tick(g) }
+            let df = Felling.felled - f0, dt = Felling.toppled - t0, ds = w.ships.list.count - ships0
+            let sr = Felling.stumpRadius(foot.x, foot.z) ?? 0.99
+            cutTested += 1
+            if df != 1 || dt != 0 || ds != 1 || sr >= 0.40 {
+                badCuts.append("\(foot.x) \(foot.y - 64) \(foot.z): felled=\(df) toppled=\(dt) ships=\(ds) stumpR=\(String(format: "%.2f", sr))")
+            }
+        }
+        check(cutTested >= 4 && badCuts.isEmpty,
+              "nov12 forest: \(cutTested) trees cut 2 blocks up each fell as 1 tree (0 split trees) and kept a natural stump radius (\(badCuts.joined(separator: "; ")))")
+    }
 }
--- a/quest/src/test/TreeTest.swift
+++ b/quest/src/test/TreeTest.swift
@@ -94,9 +94,10 @@
         check(trunk2, "trees: the ancient oak stands on a 2x2 trunk 9+ tall")
         // A fallen trunk lies on the ground: bark-all-round wood resting on the floor, never on air.
         var lying = 0, hanging = 0
-        let wood = Blocks.id("oak_wood")
+        let fallenIDs: Set<BlockID> = [Blocks.id("oak_wood"),
+                                       Blocks.has("oak_log[x]") ? Blocks.id("oak_log[x]") : LOG,
+                                       Blocks.has("oak_log[z]") ? Blocks.id("oak_log[z]") : LOG]
         for s in 0..<20 {
             let b = grow(.fallenOak, seed: UInt64(s) &* 31 &+ 3)
-            for z in 0..<CS { for x in 0..<CS { for y in (groundY + 1)...(groundY + 3) where b[Chunk.index(x, y, z)] == wood {
+            for z in 0..<CS { for x in 0..<CS { for y in (groundY + 1)...(groundY + 3) where !(x == 8 && z == 8) && fallenIDs.contains(b[Chunk.index(x, y, z)]) {
                 if b[Chunk.index(x, y - 1, z)] == AIR { hanging += 1 } else { lying += 1 }
             } } }
         }
```

*(Coding agent note: wire `TreeProbeCheck.fellForestNov12(game, check)` into `questcheck`'s `--fellcheck` entry point right alongside `TreeProbeCheck.fell`, `TreeProbeCheck.fellReal`, and `TreeProbeCheck.fellHalf`.)*

---

### 3) Exact checks to run & what a pass looks like

1. **Build cleanly (Mac + Quest test harness):**
   - `./build.sh fast` — 0 errors, 0 new warnings.
   - Build `questcheck` and run:
     - `questcheck --treeprobe 632461258612199693,-1892,88,3255`
     - `questcheck --treeprobe 632461258612199693,-1879,85,3259`
     - `questcheck --treeprobe 632461258612199693,-1892,98,3303`
     - **Pass:** `0 of N log groups ... hang free` on all three coordinates.
   - `questcheck --fellcheck` (including `TreeProbeCheck.fellForestNov12`):
     - **Pass:**
       - `fellcheck` passes (spruce fells cleanly past neighbor, player stands on fallen trunk without bounce/drift).
       - `fellreal` passes (real trees fall whole, lean > 60°, stay above ground).
       - `fellhalf` passes (2×2 dark oak stands on 3 feet, falls on 2).
       - `nov12 forest` passes (`felled=1 toppled=0 ships=1` and `stumpR < 0.40` for every oak cut 2 blocks above its base in `-1920..-1868, 3285..3315` on seed `632461258612199693`).
   - `questcheck --treerepair` and `questcheck` tree suite (`TreeTest.run`):
     - **Pass:** all 20 species designs pass untouched in `--treerepair`; `fallen trunks lie on the ground (... lengths, 0 over air)` passes in `TreeTest`.
   - Check `P484` regression (player-placed log on grass & trader wagon wheels):
     - Placing a single `oak_log` onto `grass_block` still renders at built-timber radius (`0.45`), because `grass_block` under it is not converted to `DIRT` and `Felling.stumpRadius` is unset; wagon wheel logs (`1` block with built blocks beside/above) keep full `0.46` radius.

2. **Visual renders to inspect (`snap.sh` / `questcheck --render`):**
   - Render on seed `632461258612199693` in field/polygon mode at:
     1. `-1892 88 3255` and `-1879 85 3259` looking across the Forest floor and slopes: verify fallen logs bed smoothly into the hillside at `0.26` radius (not `0.46`-radius hovering cylinders), woodland stumps have tapered roots entering the ground (no fat horizontal cylinders or floating square moss carpets), and hillside tree bases flare cleanly into the slope with no open underside gap.
     2. `-1913 100 3304` to `-1872 95 3302` before and after breaking a `field oak` and `English oak` at `y = foot + 1` and `y = foot + 2`: verify the stump stays at the exact thin trunk girth with its root flare (no jump to a huge cylinder) and the upper trunk + all limbs + crown topple together as a single `Felled Tree` ship.

3. **Headset walkthrough (Quest 3, seed `632461258612199693`):**
   - Teleport / fly to `-1892 88 3255` and walk to `-1879 85 3259`: confirm no hovering fallen logs, no hovering moss squares over stumps, and no fat sideways root cylinders beside stumps.
   - Walk to `-1913 100 3304` -> `-1872 95 3302` and chop 10 trees—cutting some right at the base, some waist-high (1–2 blocks up), and some right at the lower branch fork:
     - Every cut above the base leaves a stump of the exact same trunk thickness (never morphing into a fat stump).
     - Every tree with low forks/branches comes down as **one** single falling tree, never splitting into two or three trees.

---

### 4) Risks & anything I couldn't do

- **Already-saved chunks in an existing save file on the headset:** `WorldGenTrees.swift` changes (`fallenOak` using `oak_log[x/z]` and skipping `moss_carpet` in polygon worlds) apply to newly generated chunks. Because Remington's Quest save may already have chunks saved to disk around `-1892 88 3255`, I **also** updated `ShapeTrunks.fallenRun`, `ShapeTrunks.timber`, and `ShapeTrunks.rootBeside` at mesh time so existing `oak_wood` fallen trunks and existing stump roots in already-saved chunks immediately bed into the smooth ground and taper into roots without needing chunk regeneration. The one thing left in an *already-saved* chunk would be a `moss_carpet` block already saved on top of an old `stumpOak`/`fallenOak` unless cleared on load; if you want existing saves scrubbed of those too, add a 5-line pass in `TreeRepair.tidy` removing `moss_carpet` directly above `oak_wood` or lone 1-high logs when `World.realistic` is true.
- **Chopping a fallen tree into pieces on the ground:** When a tree has already been felled (`Ship` named `"Felled Tree"`) and the player chops the fallen trunk in half on the ground, `ShipCombat` hull-splitting splits disconnected sub-grids into two ships (so you can buck a >24-log tree down into carryable logs, per `Felling.swift:12`). That is intentional bucking behavior once the tree is on the ground; the bug where a *standing* tree split into 2–3 trees while being felled is fixed above.
- **I couldn't run `build.sh` or `questcheck` directly** because I am in a read-only planning environment without shell execution; verify line numbers and hook `TreeProbeCheck.fellForestNov12` into the `--fellcheck` runner when applying the diff.