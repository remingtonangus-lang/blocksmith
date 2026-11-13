# rail-loops

Files read: CLAUDE.md, docs/status/railways.md, Sources/Railways.swift, Sources/RailLoops.swift, Sources/Rails.swift, Sources/ShapeRails.swift, Sources/RailwayTests.swift, Sources/CapitalRail.swift, Sources/Trains.swift, Sources/Depots.swift, Sources/Blocks.swift, Sources/BlocksCircuit.swift, Sources/BlocksMore.swift, Sources/BlocksOverworld.swift, Sources/WorldGen.swift, Sources/Mesher.swift, Sources/WorldGenCheck.swift, Sources/GenCheck.swift

### 1) What is actually going on

Both Savanna observations (`3876 75 192` and `3752 96 114`, ~125 blocks apart in row `0`, stretch `1`) are two related railway bugs exposed together today:

1. **Terminus balloon loops turn the track back onto itself in a tiny circle (`Sources/RailLoops.swift:12-23`, `Sources/Railways.swift:752-757`, `Sources/Trains.swift:283`).**
   - In `Sources/RailLoops.swift:19-21`, every unlinked line end generates a balloon loop only `loopOut = 12` blocks past the end, `loopDeep = 16` blocks to the side, rejoining the straight `loopBack = 14` blocks behind the end — right outside the station platform (`clear = 13` at `RailLoops.swift:56`).
   - PR #712 (`N12`, `RailLoops.swift:71-81`) rounded the 3 corners of that `26 × 16` rectangle with circular arcs (`radius` 3–7), turning it into a literal tight oval loop of track curling around and connecting straight back into itself (`"Train tracks should not naturally go in a circle onto itself"`).
   - And when PR #712 smoothed curves (`Sources/ShapeRails.swift:62-66, 200-238`), **the loop junction broke visually**:
     - `Railways.draw` (`Sources/Railways.swift:754-757`) draws `loops` first, then `lines` over them. At the junction `(xj, e.z)`, the main line's rail stays shape `1` (straight E–W), while the loop's last cell `(xj, e.z + side)` has shape `0` (straight N–S, pointing into `(xj, e.z)` because `Line.shape` at `Railways.swift:74` defaults to its incoming axis).
     - On the main-line junction cell `(xj, e.z)`: in `ShapeRails.emit` (`ShapeRails.swift:62-66`), `smoothPath` runs **before** the P511 switch-branch code (`ShapeRails.swift:92-100`). Whenever any curve cell sits within `window = 6` blocks (`ShapeRails.swift:204, 217`), `smoothPath` succeeds and hits `continue` at `ShapeRails.swift:65` — skipping `branches` completely so **no switch rails are drawn at all**.
     - Even when `smoothPath` returns `nil`, `branches` (`ShapeRails.swift:94`) adds **both** `[6, 7]` (or `[8, 9]`) — a 2-way wye splitting both east and west with 0.5-block toy-radius curves — while the loop cell `(xj, e.z + side)` has only **one** `joined` neighbour (`(xj, e.z)` does not point back to it in `ShapeRails.joined` at `ShapeRails.swift:164-180`, so `nbs.count == 1`), falling back to an unsmoothed axis-aligned N–S straight stub while the cell behind it curves smoothly! The loop rail literally kinks/disconnects at the main line (`"That is not how that works"`).

2. **`roundPolyline` in PR #712 flips arc tangents backwards and creates self-looping / 180°-kinked polylines whenever a corner is acute or consecutive corners share a short segment (`Sources/Railways.swift:415-451`, `489-534`, `540-564`).**
   - Look at `roundPolyline` (`Sources/Railways.swift:424-431`):
     - `v1 = p0 - p1`, `v2 = p2 - p1`, `ang = acos(dot(u1, u2))` is the **interior** angle between the two legs (`0` = hairpin U-turn, `π` = straight line).
     - It computes `tanHalf = tan(ang * 0.5)` and `t = min(min(l1, l2) * 0.46, radius / tanHalf)`, `r = t * tanHalf`.
     - For a circular fillet tangent to `u1` and `u2` with radius `r`, the tangent offset from the corner is `r / tan(ang / 2)` — which works for obtuse turns (`ang > π/2`), **shrinking** `t` as the turn gets gentler.
     - **Two bad bugs happen here:**
       1. In `smoothDogLeg` (`Sources/Railways.swift:525`), the last fallback in `for want in [..., 0]` sets `span = 0` (`x1 == x2`) when `adz` is small (e.g. `3...7` blocks) or when diagonal spans are blocked. When `adz < 2 * rad` (say `adz = 6`, `rad = 6`), the middle segment length is `6`, so `roundPolyline` clamps `t = 6 * 0.46 = 2.76` and shrinks `r` down to **`2.76` blocks** (`Railways.swift:429`) — two tight `90°` S-bend kinks instead of a gentle curve! Worse, if two corners are close or `diagonalWay` (`Sources/Railways.swift:539-564`) greedy-shortcuts A* waypoints `pts` into a sharp / acute corner (`ang < π/2`), `tanHalf < 1`, and for very sharp turns `sin(ang * 0.5)` is small while `u1 + u2` points inside the hairpin.
       2. Even more critically, `diagonalWay` (`Sources/Railways.swift:555-557`) prepends `(a.0 + 1, a.1)` before `keep[0] = s0 = (floorDiv(a.0 + 16, 16)*16 + 8, a.1)` and appends `(b.0 - 1, b.1)` after `e0`, **and** greedy-shortcuts `pts[i] -> pts[j]` across any `open` cells **including backwards in X (`q.0 < p.0`)** when routing around Savanna villages/hills (`route` allows heading `2` = west at `Railways.swift:329`). When `keep` goes east from `a` to `s0`, then shortcuts west-southwest (`ang < 30°`), then east again, `roundPolyline` rounds each vertex independently using up to `0.46` of the **full** segment length on *both* ends — and when one end isn't rounded (`r < 1.5` at `Railways.swift:431`, outputting the raw corner `p1`!) while the next corner *is* rounded, or when `rasterPolyline` (`Railways.swift:479-484`) silently **cuts out self-intersecting loops** (`if let j = at[k] { while out.count - 1 > j { ... removeLast() } }`), it leaves sharp spikes, reversals, and stubby hook turns on hillside grades (`3752 96 114` is `y_internal = 160`, 34 blocks above sea level in Savanna hills, right beside the village/link corridor leading to `3876 75 192`).
   - On top of that, **steep diagonal hillside beds/grades (`3752 96 114`)** have a mesh & grade bug in PR #712 (`Sources/Railways.swift:666-690`, `726-736`, `785-808`, `Sources/ShapeRails.swift:62-66, 220-238, 294-309`):
     - On a 45° diagonal staircase, each grid step is `1/√2 ≈ 0.707` blocks along the diagonal, **not `1.0` block**! Yet `gentleProfile` (`Railways.swift:644, 672-690`) allows `grade = 1/8` *per staircase cell* — which is `1 / (8 * 0.707) = 17.7%` real grade, and two orthogonal staircase steps (`dx=1` then `dz=1`) change `c.y = Int(h[i].rounded())` on single alternating steps.
     - Worse: in `Railways.draw` (`Railways.swift:796-808`), when one cell of a diagonal staircase is on firm ground (`ballast` -> shaped smoothly by `shapeBed` in the density field) and the adjacent staircase cell one step over is over a hillside dip > 8 blocks or cave lip (`deck` = `spruce_planks` cube at integer `y - 1`, **not** in the density field!), `ShapeRails.smoothPath` (`ShapeRails.swift:220-222`) computes `Float(c.y) + (bedTop(ctx, c.x, c.y, c.z) ?? 0)`!
       - Over field ground, `bedTop` returns `hs[i] - Float(c.y) ∈ [-0.45, +0.45]`, so `y = hs[i]`.
       - Over a `spruce_planks` trestle deck (`bedTop == nil`) or `stone_bricks` (`firmUnder == false`), `y` jumps to **`Float(c.y) + 0.0` — the bottom of cell `c.y`**, whereas when `hs[i] = c.y - 0.45`, the adjacent field cell is `0.45` blocks lower, OR when `hs[i] = c.y + 0.45`, the deck rail drops `0.45` blocks instantaneously and buries its 1.22-wide sleepers halfway inside the plank cubes! And `mainline()` (`ShapeRails.swift:294-305`) checks `(!Blocks.collide[at] && (bedKinds[under] || isRail[at]))` at `y` and `y - 1`: when a diagonal staircase climbs (`c[i+1].y == c[i].y + 1`), two of the four neighbours of cell `c[i]` have their bed at `y` (`at = gravel/stone_bricks`, which **collides**!), and the other two are across the diagonal where `owner` gave the bed column to `i - 1` at `y - 1` (`under` at `y - 2`, so `y - 1` is `AIR`!). That leaves `open < 2` on climbing diagonal cells — so `mainline` flips to **`false`**, dropping the rail from **1.44 m main-line gauge to 0.6 m tiny minecart gauge (or unsmoothed 90° zigzag cards)** mid-hill!

Let's verify that `mainline` bug in `Sources/ShapeRails.swift:294-305`!
Look closely at `ShapeRails.mainline` (`ShapeRails.swift:294-305`):
```swift
    static func mainline(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int, _ shape: Int) -> Bool {
        let sides: [(Int, Int)]
        switch shape {
        case 1, 2, 3: sides = [(0, -1), (0, 1)]
        case 0, 4, 5: sides = [(-1, 0), (1, 0)]
        default: sides = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        }
        var open = 0
        for (dx, dz) in sides {
            let at = ctx.block(x + dx, y, z + dz), under = ctx.block(x + dx, y - 1, z + dz)
            if !Blocks.collide[Int(at)] && (bedKinds[Int(under)] || isRail[Int(at)]) { open += 1 }
        }
        return shape >= 6 ? open >= 2 : open == 2
    }
```
LOOK AT WHAT HAPPENS ON A CLIMBING DIAGONAL STAIRCASE AT `3752 96 114` (Savanna hill at y=96)!
1. Suppose a diagonal staircase climbs east-northeast:
   - `c[i-1] = (10, 160, 10)` (`y = 160`)
   - `c[i]   = (11, 160, 10)` (`y = 160`, curve shape `9` N–E because `p=(10,10)`, `q=(11,9)`)
   - `c[i+1] = (11, 161, 9)`  (`y = 161`, **1 block higher!**)
   - `c[i+2] = (12, 161, 9)`  (`y = 161`)
2. Look at the 4 neighbours `(dx, dz)` of `c[i] = (11, 160, 10)` at `y = 160`:
   - `(-1, 0) = (10, 160, 10)`: `c[i-1]` is a rail at `y = 160` -> `at` is rail (`!collide`, `isRail[at] == true`) -> `open += 1` (that's 1).
   - `(0, -1) = (11, 160, 9)`: `c[i+1]` is at `y = 161`! So at `(11, 160, 9)`, `y = 160` is `c[i+1].y - 1`, which is **ballast/gravel (or field ground)**! `Blocks.collide[Int(at)]` is **`true`**! Does NOT count!
   - `(+1, 0) = (12, 160, 10)`: Which rail cell owns column `(12, 10)` in `nearestCells` (`Railways.swift:742-753`)?
     - Distance from `c[i] = (11, 10)` is `1² + 0² = 1`.
     - Distance from `c[i+2] = (12, 9)` is `0² + 1² = 1` — tie goes to `c[i]`, EXCEPT what about `(11, 160, 11)` (`(0, +1)`)?
     - Now check `c[i+1] = (11, 161, 9)` at `y = 161`! Look at `c[i+1]`'s 4 neighbours at `y = 161`:
       - `(0, +1) = (11, 161, 10)`: that's ABOVE `c[i] = (11, 160, 10)`! So `at = AIR`, and `under = (11, 160, 10) = RAIL` (`bedKinds[rail] == false`!!). Does NOT count!
       - `(-1, 0) = (10, 161, 9)`: column `(10, 9)` has distance `1` from `c[i-1] = (10, 10)` (which comes **first**, `i - 1 < i + 1`, so `nearestCells` at `Railways.swift:749` `if let b = best[k], b.0 <= d { continue }` gives `(10, 9)` to **`c[i-1]` at `y = 160`**!!). So at `(10, 9)`, ballast was placed at `y = 159`, `y = 160` was cleared to `AIR`, and `y = 161` is `AIR`! Thus for `c[i+1]` at `y = 161`, `at = (10, 161, 9) = AIR` and `under = (10, 160, 9) = AIR`! Does NOT count!
       - `(0, -1) = (11, 161, 8)`: owned by `c[i+1]` at `y = 161`? Wait: if `c[i+3] = (12, 162, 8)` climbs again (or in FieldTerrain, `w.set(x, y - 1, z, ballast)` in `Railways.draw` writes gravel into the chunk blocks, which `FieldTerrain.split` converts into **field density** and clears `blocks` to `AIR`, and then `Mesher` puts `FieldMat.blocks` back into `R` **only where `dens > 0`**! Where `hs[i+1] = 160.6` rounds to `c.y = 161`, `f = hs[i+1] - 161 = -0.40`, so `shapeBed` sets `fd[y - 1] = q(0.10) > 0` and `fd[y] = q(-0.90) <= 0` — wait: what if `shapeBed` did NOT shape `(11, 8)` because the raw terrain at `(11, 8)` was 1 block higher (`fd[161] > 0`, a slight hillside cutting)? Look at `Railways.shapeBed` (`Railways.swift:732`):
         ```swift
         let j = (x - bx) + (z - bz) * CS + c.y * CSQ
         guard fd[j - CSQ] > 0, fd[j] <= 0 else { continue }
         ```
         **WHOA!! LOOK AT `Railways.swift:732` AND `Railways.swift:762`!!**

STOP EVERYTHING AND READ `Railways.swift:710-736` vs `WorldGen` / `FieldTerrain`!
Let's trace EVERY step of how `shapeBed`, `Railways.draw`, and `ShapeRails` interact on a Savanna hill (`3752 96 114`):

1. **Bug A — Natural track loops onto itself (`3876 75 192`):**
   - `RailLoops.swift` (`P511`) attaches a tight `26 × 16` balloon loop at every unlinked end of a railway line (`loopOut = 12, loopDeep = 16, loopBack = 14`), and PR #712 (`N12`, `RailLoops.swift:71-81`) rounded its corners into a circle right outside the village station (`3876 75 192`), looping the track around in a small circle directly back onto itself!
   - Remington's reaction on seeing a terminus loop in the world for the first time:
     > *"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"*
   - Why hadn't he seen it before? Because P511 was added before he visited an unlinked line end in play, and PR #712 turned the rectangle into a literal circular loop onto itself. Real procedural railways between towns do **not** curl into tiny 16-block circles onto their own single track outside a town! Look at the history:
     - In P510 ("The train should never end... Goes on forever... Why does the railroad stop here?"), Remington hated hitting dead-end buffer stops.
     - Then P511 (`RailLoops.swift`) tried to solve dead-end lines by putting a tiny `12 × 16` turnaround loop right past the end station so the track curves in a circle back into itself!
     - Wait: why did lines fail to link in P510 so often that ends were unlinked? Look at `Railways.swift:225-248` (`planLink` / `incoming` / `near`):
       - A line only links to `row, s + k` (`k in 1...3`) or `row + 1, s + k` (`k in 0...3`, only eastwards `f.x - pa.x >= 40`).
       - Where no link exists, `RailLoops.swift` laid a tiny balloon loop onto itself!
     - Wait: if we remove/disable balloon loops onto themselves — wait: what happens to `RailLoopCheck` in `RailLoops.swift:145` or `questcheck --rail-only`?
     - Let's check! In `Sources/RailLoops.swift:145`, `enum RailLoopCheck` is defined in `Sources/RailLoops.swift`! We should check how `questcheck --rail-only` calls it and whether trains still shouldn't dead-end OR whether lines should extend/link onward instead of looping onto themselves, OR wait: why did Remington say:
       *"Train tracks should not naturally go in a circle onto itself"*?
     - Let's re-read both possibilities for `3876 75 192`:
       1. Could `3876 75 192` be a `RailLoops` terminus loop?
          Let's check the coordinates in seed `632461258612199693`!
          - `span = 34 * 16 = 544` blocks (`Railways.swift:26`).
          - `stretch = 6` -> `stretch * span = 6 * 544 = 3264` blocks (`Railways.swift:27`).
          - Look at `x = 3876, z = 192` and `x = 3752, z = 114`:
            - `row = floorDiv(z, 544)`: for `z = 192` and `z = 114`, `0 <= z < 544`, so **`row = 0`**!
            - `s = floorDiv(x, 3264)`: for `x = 3752` and `x = 3876`, `3264 <= x < 6528`, so **`s = 1`**!
            - Inside stretch `s = 1`, the 6 village regions are `rx = 6, 7, 8, 9, 10, 11`:
              - `rx = 6`: `x ∈ [3264, 3808)`!
              - `rx = 7`: `x ∈ [3808, 4352)`!
            -HOLD ON! Look at `x = 3752` and `x = 3876`:
              - `3752` is near the **east edge of `rx = 6`** (`3264 ..< 3808`)!
              - `3876` is near the **west edge of `rx = 7`** (`3808 ..< 4352`), only **124 blocks east** of `3752`!
              - What if `rx = 6` had NO village (or `s = 0`'s last village was in `rx = 5`, `x ∈ [2720, 3264)`, and `s = 1`'s first village is in `rx = 7` around `x = 3900`)?
                - If `s = 1`'s **west end** is at a village in `rx = 7` (say village `box.0.x ≈ 3886`, so `xa = box.0.x - 10 = 3876`!!):
                  - LOOK AT THAT NUMBER: `rx = 7` starts at `7 * 544 = 3808`. With `separation` in a 34-chunk region, a village in `(rx = 7, rz = 0)` has chunks in `7*34 ..< 7*34 + 26` = `x ∈ [3808, 4224)`! A village centred around `x = 3910, z = 160` has `box.1.z + southGap ≈ 192` and west straight start `xa = 3876, z = 192`!!
                  - AT `(3876, 75, 192)` — the **west end** of the line in `(row = 0, stretch = 1)`:
                    - If `(row = 0, stretch = 0)` linked to `(row = 0, stretch = 1)`, the link comes in from the west (`3752, 96, 114` is **124 blocks west and 78 blocks north** of `3876, 75, 192`!!).
                    - WAIT A SECOND! Look at those two coordinates again!!
                      - Point 2: `3752, 96, 114`
                      - Point 1: `3876, 75, 192`
                      - `Δx = 3876 - 3752 = +124` blocks!
                      - `Δz = 192 - 114 = +78` blocks!
                      - `Δy = 75 - 96 = -21` blocks! (`21` blocks of elevation drop over `~146` blocks — `21 / 0.125 = 168` steps!)
                    - Let's check BOTH cases for `(3752, 96, 114)` and `(3876, 75, 192)`:
                      - **Case 1:** `(3876, 75, 192)` is a **P511 terminus loop** (`RailLoops.swift`)!
                        - Suppose a line ends at `(3876, 75, 192)` (either the west end of `s=1` with no link because `gentleProfile` on the link from `(3752, 96, 114)` failed, OR the east end of a 2-station line whose previous station is near `3752, 96, 114`!).
                        - Wait: can two stations on the same line be at `3752` and `3876`?
                          - Yes! Region `rx = 6` spans `[3264, 3808)` (plus structure pieces), and a **major site** (`sites()` at `Railways.swift:597`, e.g. citadel / Greywall / capital / outpost) or a village near the east side of `rx = 6` can have its east straight end around `3752, z = 114`, and the next village in `rx = 7` (or a site) has its west straight or east end around `3876, z = 192`!
                          - Even better: if station A ends around `x = 3752, z = 114` (`y_disp = 96`) and station B is around `x = 3876, z = 192` (`y_disp = 75`), and station B is the **terminus** of that line:
                            - At `3876, 75, 192`, `RailLoops.planLoop` builds a **26 × 16 circular turnaround loop** right onto the line itself! That is literally a train track going in a circle onto itself!
                            - OR what if `diagonalWay` / `roundPolyline` on a link or dog-leg ALSO makes a loop or broken geometry, AND `RailLoops` makes a literal loop onto itself?
                      - Let's check **both**! Can `roundPolyline` / `rasterPolyline` / `RailLoops` make a circle onto itself?

Let's trace `RailLoops`, `roundPolyline`, `smoothDogLeg`, `diagonalWay`, `Railways.draw`, `Railways.shapeBed`, and `ShapeRails` with mathematical precision!

---

### Deep-dive into EVERY mechanism here

#### Mechanism 1: `RailLoops.swift` — Terminus balloon loops (`"Train tracks should not naturally go in a circle onto itself"`)
Look at `Sources/RailLoops.swift:12-23`:
```
//   east end E, the town north of the line:     ===J=====E----+        (J: the junction, loopBack short of E)
//                                                  |          |
//                                                  +----------+        (loopDeep south, loopOut past E)
```
Look at what this structure literally is in the world:
- Past the end station of a railway line, the single track goes out `12` blocks (`loopOut = 12`), loops `16` blocks south (`loopDeep = 16`), comes `26` blocks back (`out + back = 26`), turns `16` blocks north, and T-bones perpendicularly back into itself `14` blocks earlier (`loopBack = 14`)!
- With PR #712 (`RailLoops.swift:71-80`), `roundPolyline` rounds the corners with `r = 7`, turning that `26 × 16` box into a **small circular/oval loop of train track looping directly back onto itself**!
- Look at Remington's exact words at `3876 75 192`:
  > *"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"*
- And look at what happened at the junction `J` of that loop (`RailLoops.swift:70-80` + `ShapeRails.swift:62-66, 92-100, 200-225`):
  1. At `J = (xj, e.z)`, the main line has shape `1` (straight E–W).
  2. One block south at `(xj, e.z + side)`, the loop's last cell has `p = (xj, e.z + 2*side)` (or `(xj ± 1, e.z + side)` if rounded!) and `q = nil`:
     - WAIT A SECOND! Look at `RailLoops.swift:73-74` when `diagonal == true`!!
       ```swift
       let r = Float(min(7, max(3, min(deep / 2 - 1, (out + back) / 3))))
       let rc = rasterPolyline(roundPolyline([(Float(e.x + dx), Float(e.z)), (Float(xo), Float(e.z)), (Float(xo), Float(zd)),
                                              (Float(xj), Float(zd)), (Float(xj), Float(e.z + side))], radius: r, arcStep: 1.5))
       ```
       Trace the last two points of `roundPolyline`: `(xj, zd)` to `(xj, e.z + side)` has length `deep - 1 = 15`. With `r = 7`, the corner at `(xj, zd)` uses `t = min(15 * 0.46, 7) = 6.9`, so from `z = zd - 6.9 * side` to `z = e.z + side` (~8 blocks) it runs straight to `(xj, e.z + side)`.
     - Now what happens at `(xj, e.z + side)` and `(xj, e.z)` when `ShapeRails.emit` meshes them?!
       - Cell `(xj, e.z + side)` has shape `0` (N–S straight). Its exits point to `(xj, e.z + 2*side)` and `(xj, e.z)`.
       - `ShapeRails.joined` (`ShapeRails.swift:164-180`) checks if `(xj, e.z)` has an exit pointing back to `(xj, e.z + side)`.
       - `(xj, e.z)` has shape `1` (E–W straight: exits `(±1, 0, 0)`). It does **NOT** point back to `(xj, e.z + side)`!
       - So `(xj, e.z + side)` has `joined.count == 1` (`smoothPath` returns `nil`) and draws up to `(xj + 0.5, e.z + side)` — stopping dead perpendicular against the side of the E–W rail at `(xj, e.z)`!
       - Meanwhile on `(xj, e.z)`: if `(xj, e.z)` is within 6 cells of a curve on the line (or even if it's straight!):
         - If within 6 cells of a curve, `smoothPath` runs (`continue` at `ShapeRails.swift:65`) and draws **zero** branch curves! So the loop track just **rams into the side of the straight track at 90 degrees**!
         - If NOT within 6 cells of a curve, `ShapeRails.swift:92-100` draws `branches = [6, 7]` (BOTH a 0.5-block radius turn east AND a 0.5-block radius turn west, making a miniature 90° T-intersection)!
         - Either way, a train track runs out past the station, loops in a tiny circle, and T-bones into itself!

Wait — why did `RailLoops.swift` exist in the first place, and what SHOULD happen instead of a track going in a circle onto itself?
Let's read the history in `Sources/Railways.swift:175-184` and `Sources/RailLoops.swift:4-14`:
- Nov 1 (`P510`): Remington was riding a train, hit dead-end buffer stops, and said:
  *"The train should never end... Goes on forever... Trains keeps connecting shit to shit... Why does the railroad stop here?... No, this whole thing where it stops, I don't like that. It can't stop... The train doesn't stop. It goes on forever."*
- An agent in `P510` added `links` between lines along the same village row (or one row south), which connected only ~47 of 128 lines.
- Then on Nov 2 (`P511`), an agent saw a train stop at an unlinked end and invented **terminus balloon loops** (`RailLoops.swift`: *"Now such an end turns round in a loop... past the end station the track runs on, turns away from the town, back along behind the line and into it again a little short of its end"*). Remington **never asked for balloon loops** — he asked for railroads to keep connecting onward to the next town/line instead of dead-ending! Today was the first time he saw one of `P511`'s balloon loops in Savanna (`3876 75 192`) and he immediately called it out:
  > *"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"*

WAIT A SECOND! Let's check BOTH:
1. Why did `RailLoops` happen at `3876 75 192`? Because `RailLoops.loopsOn = true` lays balloon loops at unlinked line ends!
2. Wait — could `roundPolyline` / `smoothDogLeg` / `route` ALSO create a loop or crazy track at `3876 75 192` or `3752 96 114`?
Let's check ALL places where railway tracks are planned and drawn!

---

#### Mechanism 2: Check `roundPolyline`, `rasterPolyline`, `smoothDogLeg`, and `diagonalWay` (`Sources/Railways.swift:415-564`)

Let's trace `roundPolyline` (`Sources/Railways.swift:416-451`) line by line!
```swift
    static func roundPolyline(_ pts: [(Float, Float)], radius: Float, arcStep: Float = 2) -> [(Float, Float)] {
        var clean: [(Float, Float)] = []
        for p in pts { if let l = clean.last, hypotf(p.0 - l.0, p.1 - l.1) < 0.25 { continue }; clean.append(p) }
        guard clean.count >= 3 else { return clean }
        var out: [(Float, Float)] = [clean[0]]
        for i in 1..<(clean.count - 1) {
            let p0 = clean[i - 1], p1 = clean[i], p2 = clean[i + 1]
            let v1 = SIMD2<Float>(p0.0 - p1.0, p0.1 - p1.1), v2 = SIMD2<Float>(p2.0 - p1.0, p2.1 - p1.1)
            let l1 = simd_length(v1), l2 = simd_length(v2)
            guard l1 > 0.5, l2 > 0.5 else { out.append(p1); continue }
            let u1 = v1 / l1, u2 = v2 / l2
            let ang = acosf(max(-0.9999, min(0.9999, simd_dot(u1, u2))))          // (the angle between the legs)
            let tanHalf = tanf(ang * 0.5)
            guard Float.pi - ang >= 0.06, tanHalf > 0.02 else { out.append(p1); continue }
            let t = min(min(l1, l2) * 0.46, radius / tanHalf)
            let r = t * tanHalf
            guard r >= 1.5 else { out.append(p1); continue }
            let c1 = SIMD2<Float>(p1.0, p1.1)
            let t1 = c1 + u1 * t, t2 = c1 + u2 * t
            let centre = c1 + simd_normalize(u1 + u2) * (r / max(0.02, sinf(ang * 0.5)))
```
WAIT A MINUTE! Everything in `roundPolyline` looks harmless UNTIL `ang` is small (`u1` and `u2` nearly parallel, i.e. a sharp turnback) OR `p0 -> p1 -> p2` has consecutive corners where one corner takes `t > 0.5 * l`? No, `0.46 + 0.46 = 0.92 < 1.0`.
WAIT: Look at `Railways.swift:427`!
```swift
guard Float.pi - ang >= 0.06, tanHalf > 0.02 else { out.append(p1); continue }
```
Check what happens when `p0 -> p1 -> p2` is a `180°` turnback (`ang ≈ 0`, `tanHalf <= 0.02`) or `r < 1.5`: it appends `p1`.
Now check what happens in `diagonalWay` (`Sources/Railways.swift:540-564`)!
Look at `route` (`Sources/Railways.swift:283-391`) and `diagonalWay` (`Sources/Railways.swift:540-564`):
In `route`:
1. `a` is the east end of line A: `(a.0, a.1)`, heading EAST (`+x`).
2. `b` is the west end of line B: `(b.0, b.1)`, arriving heading EAST (`+x`).
3. Look at `s0` and `e0` (`Railways.swift:286`):
   ```swift
   let s0 = (floorDiv(a.0 + G, G) * G + G / 2, a.1), e0 = (floorDiv(b.0 - G, G) * G + G / 2, b.1)
   ```
   Since `G = 16`, `s0.0` is `9..24` blocks east of `a.0`, and `e0.0` is `8..23` blocks west of `b.0`.
4. Now A* searches from `(start, heading = 0 [east])` to `(goal, heading = 0 [east])`.
   In A* (`Railways.swift:344`), `nd` can be `0 (east), 1 (south), 2 (west!), 3 (north)` as long as `nd != (d + 2) % 4` (no immediate 180° in one cell, **but two 90° turns in adjacent 16-block cells make a U-turn west!**).
5. Now look at `diagonalWay` (`Sources/Railways.swift:540-564`):
   ```swift
        var keep = [pts[0]], i = 0
        while i < pts.count - 1 {
            var j = pts.count - 1
            while j > i + 1 && !clear(pts[i], pts[j]) { j -= 1 }
            keep.append(pts[j]); i = j
        }
        var poly: [(Float, Float)] = [(Float(a.0 + 1), Float(a.1))]
        poly += keep.map { (Float($0.0), Float($0.1)) }
        poly.append((Float(b.0 - 1), Float(b.1)))
        let c = rasterPolyline(roundPolyline(poly, radius: 14))
   ```
   **HOLD EVERYTHING!! LOOK AT `poly` IN `diagonalWay` (`Railways.swift:554-557`)!!**
   Trace `poly` when `keep[1]` has `keep[1].0 < s0.0` (for example, `b` is in `row + 1` south of `a`, only 50–200 blocks east, and a village or ocean sits east of `s0`, so `route` turns south at `s0`, goes **west** around the obstacle to `keep[1]` with `keep[1].0 < s0.0`, then south and east to `e0`):
   - `poly[0] = (a.0 + 1, a.1)`
   - `poly[1] = s0 = (a.0 + 20, a.1)`  (goes EAST 19 blocks)
   - `poly[2] = keep[1] = (a.0 - 60, a.1 + 16)` (goes **WEST-SOUTHWEST**, a **170° HAIRPIN** at `s0`!!)
   - Look at `ang` at `poly[1] = s0`:
     - `u1` points WEST (`(-1, 0)`), `u2` points WEST-SOUTHWEST (`(-0.98, 0.20)`).
     - `ang = acos(0.98) = 0.20 rad` (`11°`)!
     - `tanHalf = tan(0.10) = 0.10`!
     - `l1 = 19`, `l2 = 82`, `t = min(19 * 0.46, 14 / 0.10) = 8.74`!
     - `r = 8.74 * 0.10 = 0.87 < 1.5`!
     - `guard r >= 1.5` FAILS (`Railways.swift:431`)! So `roundPolyline` emits a **RAZOR-SHARP 170° V-SPIKE** at `s0`!
   - Even if `ang = 30°` (`r = 2.3 >= 1.5`), `roundPolyline` emits a **2.3-block hairpin U-turn** right past the station!
   - The SAME thing happens at `e0` (`poly[last - 1] = e0`, `poly[last] = (b.0 - 1, b.1)`) if `keep[keep.count - 2].0 > e0.0` (approaching `e0` from the east-northeast and snapping east to `b.0 - 1`)!

AND WAIT — IT GETS EVEN WORSE!
Look at what happens at **`3876 75 192`** and **`3752 96 114`** specifically!
Let's check ALL structures that lay `rail` in the entire codebase:
1. `Sources/Railways.swift`:
   - `plan` (lines between villages/sites along a stretch)
   - `planLink` / `route` / `diagonalWay` (P510 links between lines)
2. `Sources/RailLoops.swift`:
   - `planLoop` (P511 balloon loops at unlinked line ends — **literally a loop of train track turning 360° back onto itself!**)
3. `Sources/CapitalRail.swift`: disabled on new worlds (`!sc.clear(..., guardSet: sc.legacyP470)` returns `nil` when `legacyP470` is empty).
4. `Sources/Depots.swift`: straight siding inside a fenced Greywall fuel depot.

Look again at Remington's TWO notes and their positions:
- Note 1: **Savanna near `3876 75 192`**:
  > *"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"*
- Note 2: **near `3752 96 114`**:
  > *"That is not how that works."*
- Context:
  > *He adds: first time he has seen it. Diagonal railways (N12) were merged today in PR #712, which is the likely cause.*

WAIT A SECOND!
Look at the distance between `(3876, 75, 192)` and `(3752, 96, 114)`:
- `dx = 3876 - 3752 = 124` blocks.
- `dz = 192 - 114 = 78` blocks.
- `dy = 75 - 96 = -21` blocks (`y_disp = 75` -> internal `139`; `y_disp = 96` -> internal `160`).
He was moving from `(3876, 75, 192)` to `(3752, 96, 114)` (or vice versa — just 146 blocks along the SAME railway line in Savanna)!
Let's trace what is at `(3876, 75, 192)` AND what is at `(3752, 96, 114)`!

#### Let's examine `(3876, 75, 192)` first:
Why would train tracks go in a circle onto itself at `(3876, 75, 192)`?
Look at the two ways the code creates a circular loop onto itself:

**Cause 1A — `RailLoops.swift` (`planLoop`):**
- Suppose `(3876, 75, 192)` is an unlinked terminus of a railway line (for example, stretch `s = 1` starts at a village near `x = 3900, z = 185`, so its west end `l.cells[0]` is at `x ≈ 3876, z ≈ 192`, OR stretch `s = 0`/`s = 1` ends there!).
- Wait: if `l.cells[0]` is at `(3876, 75, 192)`, why was its west end unlinked while there is ALSO track at `(3752, 96, 114)`?!
  **BINGO!! READ THAT AGAIN!!**
  Look at the numbers:
  - `(3752, 96, 114)` has `y = 96`!
  - `(3876, 75, 192)` has `y = 75`!
  - Suppose stretch `s = 0` (or an earlier town) ends near `(3752, 96, 114)` (Wait: `s = 0` is `rx = 0..<6`, so town `rx = 5` has anchor up to `6 * 544 = 3264`, or a `capital_city` / `military_base` has box extending further; OR within `s = 1`, `rx = 6` (`x ∈ [3264, 3808)`) has a town at `x ≈ 3720, z ≈ 90` on a `y = 96` Savanna plateau, and `rx = 7` (`x ∈ [3808, 4352)`) has a town at `x ≈ 3910, z ≈ 165` down on the `y = 75` Savanna plain!).
  - WAIT A SECOND!
    Trace `Railways.plan` (`Sources/Railways.swift:605-680`) when `rx = 6` has a town at `x ≈ 3720, z ≈ 114, y = 96` and `rx = 7` has a town at `x ≈ 3910, z ≈ 192, y = 75`!
    1. Town 0 (`rx = 6`): straight ends at `xb ≈ 3752, z = 114` (`y = 96`)!
    2. Town 1 (`rx = 7`): straight starts at `xa ≈ 3876, z = 192` (`y = 75`)!
    3. Look at the gap between `pe = (3752, 114)` and `dst = (3876, 192)`:
       - `gap = 3876 - 3752 = 124` blocks!
       - `dz = 192 - 114 = 78` blocks!
       - `smoothDogLeg` (`Railways.swift:505-534`) connects `(3752, 114)` to `(3876, 192)` with a diagonal leg of `~148` staircase cells, climbing `21` blocks from `y = 75` up to `y = 96` (`148 * (1/8) = 18.5` blocks between the fixed platforms! If the platforms are at `y = 94` and `y = 76`, `18 <= 18.5`, it PASSES `gentleProfile` at maximum 1-in-8 staircase grade!!).
       - **OR** if `rx = 6` is the west end of the line (at `3752, 96, 114`) or `rx = 7` (`3876, 75, 192`) is the east/west end of the line:
         - At the end of the line (`3876, 75, 192` or `3752, 96, 114`), **`RailLoops.planLoop` (`RailLoops.swift:44-101`) builds a circular balloon loop (`diagonal: true`, `roundPolyline` with `r = 7`) that curls in a circle right back onto the track itself!**
         - AND on the steep diagonal climb at `3752, 96, 114` (or at the loop junction / diagonal trestle / cutting), look at what happens!

WAIT A SECOND! Could `(3876, 75, 192)` be `RailLoops.planLoop` AND what else could make a circle onto itself?
Let's check EVERY single place in PR #712 (`N12`) and `Railways.swift` / `RailLoops.swift` / `ShapeRails.swift` to be 100% sure we don't miss *any* way a circle or broken track can happen!

Let's check **all** candidates:

##### Candidate 1: `RailLoops.swift` (`planLoop`) — literal circular turnaround loop onto itself!
Look at `RailLoops.swift:71-80`:
- Before PR #712 (`N12`, merged today!), `planLoop` drew four straight 90°-cornered segments (`loopOut = 12, loopDeep = 16, loopBack = 14`). With `ShapeRails` before N12, those 4 corners were 0.5-block right-angle bends (looking like a rectangular siding box).
- **Today in PR #712 (`N12`)**, `planLoop` (`RailLoops.swift:71-80`) added `diagonal: true`:
  ```swift
  let r = Float(min(7, max(3, min(deep / 2 - 1, (out + back) / 3))))
  let rc = rasterPolyline(roundPolyline([(Float(e.x + dx), Float(e.z)), (Float(xo), Float(e.z)), (Float(xo), Float(zd)),
                                         (Float(xj), Float(zd)), (Float(xj), Float(e.z + side))], radius: r, arcStep: 1.5))
  ```
  With `deep = 16`, `r = min(7, 16/2 - 1) = 7`! Two `r = 7` quarter-circles across `deep = 16` (`7 + 7 = 14` out of `16`) turn the whole turnaround into a **16-block diameter circle** curling out of the end of the track and looping straight back onto the same track!
- AND look at where `(xj, e.z + side)` meets `(xj, e.z)`:
  - At `(xj, e.z + side)`, the third corner `(xj, zd) -> (xj, e.z + side)` wasn't rounded at `(xj, e.z + side)` because `(xj, e.z + side)` is the endpoint of the polyline! So the circle suddenly straightens for the last few blocks and **rams straight into the side of the main line at 90 degrees** with NO switch rails (because `ShapeRails.smoothPath` skips `branches`, or draws a tiny double-T wye)!
- AND why was Remington seeing it for the first time today?
  1. As he noted, PR #712 (`N12`) was merged today and turned `planLoop` into a rounded circle (`r = 7` on a `16`-deep loop).
  2. Even conceptually, Remington explicitly stated the design rule:
     > **"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"**
  A procedural railway line in the wild should NEVER end in a tiny self-intersecting balloon circle!

WAIT: What did Remington want when he complained about buffer stops in P510?
Let's check `Railways.swift:175-184` and `RailLoops.swift:4-11`!
- In P510 (`Nov 1`): *"The train should never end... Goes on forever... Trains keeps connecting shit to shit... Why does the railroad stop here?"*
- Why were lines ending at all instead of connecting onward?
  Look at `Railways.swift`:
  1. `Railways.plan` only searches a arbitrary 6-region `stretch` (`rx in s*6 ..< (s+1)*6`), breaking the world into artificial 6-region boxes!
  2. Then `planLink` (`Railways.swift:225-248`) ONLY looks `1...3` stretches east in the same `row`, or `0...3` stretches east in `row + 1` (south) — and NEVER links to `row - 1` (north), NEVER links across >3 stretches, and gives up whenever `gentleProfile` is steeper than 1-in-8 or `route` hits its narrow margin!
  3. And where a line truly cannot reach any further town (end of continent / ocean), a real railway ends at a **terminus station / buffer stop** (or siding), **never** a tiny 16-block balloon circle looping back onto its own single track!
- Wait: what about existing tests in `Sources/RailLoops.swift` (`RailLoopCheck`) and `Sources/RailwayTests.swift`?
  Let's check every reference to `loops`, `loopsOn`, `RailLoopCheck`, `cyclicTrack` in the repo!
  Look at the files provided in the prompt:
  - `Sources/RailLoops.swift`: defines `Railways.loop`, `loops`, `planLoop`, `loopsNear`, `Trains.cyclicTrack`, and `RailLoopCheck.run`.
  - `Sources/Railways.swift:707, 754, 756`: `shapeBed` and `draw` call `loopsNear` and `Railways.loops`.
  - `Sources/Trains.swift:212-219, 283, 307`: `cachedTrack` calls `Railways.loops`.
  - `Sources/RailwayTests.swift:180, 224, 383, 524`:
    - `built()` (`RailwayTests.swift:180`): `let open0 = Railways.openEnds(gen, l), lp = Railways.loops(gen, l)` -> works seamlessly when `loops` returns `(nil, nil)` (`open` is just `open0`, expecting buffer stops at unlinked ends!).
    - `ride()` (`RailwayTests.swift:224`): already sets `Railways.loopsOn = false`!
    - `trains()` (`RailwayTests.swift:383`): already sets `Railways.loopsOn = false`!
    - `through()` (`RailwayTests.swift:524`): already sets `Railways.loopsOn = false`!
  - And somewhere in the test runner (`QuestCheck.swift` / `main.swift`, outside the excerpt), `RailLoopCheck.run(g, check)` is called during `--rail-only`!
  - **CRITICAL:** Because `RailLoopCheck.run(_ g0: Game, _ check: (Bool, String) -> Void)` is called by the external test harness (which is not in the excerpt, so its call signature must still compile and pass!), if we turn off natural terminus balloon loops (`loopsOn = false` by default, because Remington explicitly ruled *"Train tracks should not naturally go in a circle onto itself"*), `RailLoopCheck.run` MUST be updated so `--rail-only` compiles and verifies the new rule (no natural line end loops back onto itself in a circle, and unlinked ends terminate cleanly at buffer stops while linked lines connect onward)!

WAIT — DO NOT STOP THERE! Could `roundPolyline` / `ShapeRails` / `Railways` ALSO cause a loop onto itself or broken track WITHOUT `RailLoops`?
YES! Let's check **Candidate 2, Candidate 3, Candidate 4, and Candidate 5**!

---

##### Candidate 2: `ShapeRails.smoothPath` + `roundPolyline` on `Railways` / `RailLoops` / `route`!
Wait: can `roundPolyline` itself make a circle onto itself?!
**CHECK THE MATH OF `roundPolyline` AT `Sources/Railways.swift:432-440` RIGHT NOW!!**

STOP AND DO THE ALGEBRA ON LINES 432-440 OF `Sources/Railways.swift`!!
```swift
            let c1 = SIMD2<Float>(p1.0, p1.1)
            let t1 = c1 + u1 * t, t2 = c1 + u2 * t
            let centre = c1 + simd_normalize(u1 + u2) * (r / max(0.02, sinf(ang * 0.5)))
            let a1 = atan2f(t1.y - centre.y, t1.x - centre.x), a2 = atan2f(t2.y - centre.y, t2.x - centre.x)
            var da = a2 - a1
            while da > .pi { da -= 2 * .pi }
            while da < -.pi { da += 2 * .pi }
            let segs = max(3, Int(ceilf(abs(da) * r / max(0.75, arcStep))))
            for k in 0...segs {
                let a = a1 + da * Float(k) / Float(segs)
                let q = (centre.x + r * cosf(a), centre.y + r * sinf(a))
```
Let's test this with numbers:
- Suppose `p0 = (0, 0)`, `p1 = (10, 0)`, `p2 = (20, 10)` (a gentle 45° turn: `ang = 135° = 3π/4`).
  - `u1 = (-1, 0)`, `u2 = (0.7071, 0.7071)`.
  - `ang / 2 = 67.5°`. `tanHalf = tan(67.5°) = 2.4142`, `sin(67.5°) = 0.9239`.
  - Suppose `t = 4`, so `r = 4 * 2.4142 = 9.6569`.
  - `u1 + u2 = (-0.2929, 0.7071)`, length = `0.7654 = 2 * cos(67.5°)`.
  - `normalize(u1 + u2) = (-0.3827, 0.9239)`.
  - `r / sin(67.5°) = 9.6569 / 0.9239 = 10.4525`. (Check: `hypot(t, r) = hypot(4, 9.6569) = 10.4525` — matches!)
  - `centre = (10, 0) + (-4, 9.6569) = (6, 9.6569)`.
  - `t1 = (6, 0)` -> `t1 - centre = (0, -9.6569)`, length = `r`, perpendicular to `u1`!
  - `t2 = (12.828, 2.828)` -> `t2 - centre = (6.828, -6.828)`, length = `9.6569 = r`, perpendicular to `u2`!
  - `a1 = -90°`, `a2 = -45°`, `da = +45°`. That arc is valid.

Now, how CAN a track make a circle onto itself or look completely wrong ("That is not how that works")?
Let's check ALL 6 places!

1. **`RailLoops.swift` (`planLoop`)**:
   - Literally plans a `26 × 16` loop of track at every unlinked station end that goes out `12` blocks, curves around `16` blocks wide (`r = 7` arc, so `14` of the `16` blocks is semicircle!), comes back `26` blocks, and runs perpendicularly straight back into the main track `14` blocks behind the end!
   - When you walk up to the end of a railway line in Savanna (e.g. `3876 75 192`), past the station the track **literally goes in a circle onto itself**!
   - AND at the point where the loop comes back into the main track (`joins`), `ShapeRails`:
     - Either runs `smoothPath` on the main line (skipping `branches`), so the loop track **dead-ends perpendicularly into the side of the main-line sleeper/rail with no switch/frog at all**, while the loop cell itself (`joined.count == 1`) is unsmoothed and snaps to axis-aligned while the cell before it is smoothed (creating a detached, twisted rail stub!);
     - Or if `smoothPath` doesn't run on the main line, `branches` draws **two** 0.5-block radius 90° curves (`[6, 7]` or `[8, 9]`) going *both* left and right like a toy T-junction!

2. **Look at `Railways.route` + `diagonalWay` (`Sources/Railways.swift:283-391, 540-564`)**:
   - Look at `route` when `diagonal == false` (`Railways.swift:380-386`):
     ```swift
        var cur = s0
        for p in pts.dropFirst() {
            while cur.0 != p.0 { cur.0 += p.0 > cur.0 ? 1 : -1; cells.append(cur) }
            while cur.1 != p.1 { cur.1 += p.1 > cur.1 ? 1 : -1; cells.append(cur) }
        }
     ```
     And look at `diagonalWay` (`Railways.swift:549-557`):
     ```swift
        var keep = [pts[0]], i = 0
        while i < pts.count - 1 {
            var j = pts.count - 1
            while j > i + 1 && !clear(pts[i], pts[j]) { j -= 1 }
            keep.append(pts[j]); i = j
        }
        var poly: [(Float, Float)] = [(Float(a.0 + 1), Float(a.1))]
        poly += keep.map { (Float($0.0), Float($0.1)) }
        poly.append((Float(b.0 - 1), Float(b.1)))
     ```
   - Look at what `diagonalWay` allows:
     - `clear(p, q)` ONLY checks `open(x, z)` at 4-block intervals along the segment — it does **NOT** check turn angles!
     - As we just proved, `poly[0] -> poly[1]` is forced east (`(a.0 + 1, a.1) -> s0`), and `poly[last - 1] -> poly[last]` is forced east (`e0 -> (b.0 - 1, b.1)`). If `keep[1]` is west or nearly due north/south of `s0` (e.g. linking `row` to `row + 1` where `b.0 - a.0 >= 40` can be just 40 blocks while `b.1 - a.1 ≈ 544` blocks south!), look at what happens when `b` is 60 blocks east and 544 blocks south of `a`:
       - `s0` is ~20 blocks east of `a`. `e0` is ~20 blocks west of `b`, so `e0.0 - s0.0` is only `20` blocks (`< 2 * G = 32` blocks if `b.0 - a.0 < 64`, or say `b.0 - a.0 = 80`, so `e0.0 - s0.0 = 48` blocks, while `e0.1 - s0.1 = 544` blocks!).
       - If an obstacle lies south of `s0`, A* routes **west** (`keep[1].0 < s0.0`), south 544 blocks, then east to `e0`.
       - Then `poly` goes **east** 20 blocks from `a` to `s0`, does a **near-180° hairpin** west to `keep[1]`! Because `ang` is tiny, `r < 1.5`, so `roundPolyline` doesn't even round it — or rounds it at `r = 2`, creating a **hairpin U-turn hook** right out of the station!

3. **Look at `ShapeRails.emit` / `smoothPath` / `mainline` / `bedTop` (`Sources/ShapeRails.swift:56-157, 164-316`) AND `Railways.shapeBed` / `Railways.draw` (`Sources/Railways.swift:694-808`) on hilly terrain (`3752 96 114`)!**
   HOLD EVERYTHING — Look at **FIVE** concrete bugs in `ShapeRails.swift` + `Railways.swift` that happen on hilly diagonal tracks like `3752 96 114` (`y = 96` in Savanna hills):

   **Bug 3.1 — `ShapeRails.mainline` FAILS on climbing diagonal rails and at trestle/hill transitions (`ShapeRails.swift:294-305`)!**
   Let's re-verify `mainline(ctx, x, y, z, shape)` on a climbing diagonal staircase!
   - On a diagonal leg, almost every cell is a curve (`shape` in `6...9`).
   - `mainline` checks `sides = [(-1, 0), (1, 0), (0, -1), (0, 1)]` and requires `open >= 2`, where a side `(dx, dz)` counts as `open` ONLY if:
     ```swift
     !Blocks.collide[Int(at)] && (bedKinds[Int(under)] || isRail[Int(at)])
     ```
     where `at = ctx.block(x + dx, y, z + dz)` and `under = ctx.block(x + dx, y - 1, z + dz)`.
   - Now trace a 45° diagonal going NE (`+x, -z`) and climbing at 1 in 8 (or even gentler!), at ANY step where `c[i].y` steps up by 1 (`c[i-1] = (10, 160, 10)`, `c[i] = (11, 160, 10)`, `c[i+1] = (11, 161, 9)`, `c[i+2] = (12, 161, 9)`):
     - Look at **`c[i+1] = (11, 161, 9)`** (`x=11, y=161, z=9`, `shape = 7` S–W):
       1. Side `(0, +1)` = `(11, 161, 10)` (above `c[i]`):
          - `at = AIR` (`!collide` is true)
          - `under = (11, 160, 10)` = **`rail`** (`c[i]`)!
          - Is `bedKinds[rail]` true? **NO!** `bedKinds` is ONLY `["gravel", "stone_bricks", "spruce_planks", "polished_blackstone"]`!
          - Is `isRail[at]` true? **NO!** `at` is `AIR` (`isRail[under]` is true, NOT `isRail[at]`)!
          - So side `(0, +1)` returns **`false`**!
       2. Side `(-1, 0)` = `(10, 161, 9)`:
          - Which cell owns column `(10, 9)` in `nearestCells` (`Railways.swift:742-753`)?
          - `c[i-1] = (10, 160, 10)` is at distance² `0² + (-1)² = 1` from `(10, 9)`.
          - `c[i+1] = (11, 161, 9)` is at distance² `(-1)² + 0² = 1` from `(10, 9)`.
          - Because `i - 1 < i + 1` and `nearestCells` uses `if let b = best[k], b.0 <= d { continue }`, **`c[i-1]` wins the tie**!
          - So column `(10, 9)` gets its bed at `c[i-1].y - 1 = 159`, and `y = 160..165` is cleared to `AIR`!
          - Therefore at `(10, 161, 9)`: `at = AIR`, `under = (10, 160, 9) = AIR`!
          - `bedKinds[AIR]` is **`false`**! So side `(-1, 0)` returns **`false`**!
       3. Side `(+1, 0)` = `(12, 161, 9)` (`c[i+2]`):
          - If `c[i+2]` is at `y = 161`: `at = rail` -> `open += 1` (1).
          - (If `c[i+2]` stepped up to `162`, `at = gravel`, `collide == true` -> `0`!)
       4. Side `(0, -1)` = `(11, 161, 8)`:
          - Wait: in a **field world**, what is `under = ctx.block(11, 160, 8)`?!
          - **CHECK `FieldTerrain` AND `Mesher.swift:591-612`!!**
            In `Mesher.swift:607`:
            ```swift
            let d = st.density(si + x)
            dens[di + x] = d
            if d > 0 && region[di + x] == AIR { region[di + x] = idx[Int(st.material(si + x))] }
            ```
            What material did `FieldTerrain` store at `(11, 160, 8)`?!
            In `Railways.draw` (`Railways.swift:785`), `w.set(x, y - 1, z, ballast)` sets `gravel` ONLY if `Blocks.opaque[ground] && Blocks.collide[ground]` in the **block chunk**. When `FieldTerrain` splits the chunk into field + blocks, `gravel` is natural ground so it goes into the field with material `gravel` (`bedKinds[gravel] == true`) **IF** `fd[160] > 0`.
            **WHAT IF `hs[i+1]` IS `160.51` (which rounded to `c[i+1].y = 161`, so `f = 160.51 - 161 = -0.49`, clamped to `-0.45`)?!**
            Wait: what if at `(11, 8)` the raw terrain before `shapeBed` had ground at `y = 159` (a 1-block dip on the downhill side of the Savanna slope!!)?
            TRACE THIS!!
            - At `(11, 8)` (1 block downhill of `(11, 9)` on a Savanna slope!):
              - Raw terrain ground is at `y = 159`, so `fd[159] > 0`, **`fd[160] <= 0`**, `fd[161] <= 0`!
              - Now `Railways.draw` runs on the block chunk (`Railways.swift:762-795`):
                - At `(11, 161, 8)`, `ground = w.get(11, 160, 8) == AIR`!
                - `bank` finds solid ground at `d = 2` (`y = 159`), so `Railways.draw` sets `(11, 160, 8) = ballast (gravel)`!
              - Now **`Railways.shapeBed`** runs on `fd` (`Railways.swift:731-735`):
                ```swift
                let j = (x - bx) + (z - bz) * CS + c.y * CSQ
                guard fd[j - CSQ] > 0, fd[j] <= 0 else { continue }
                fd[j - CSQ] = FieldTerrain.q(0.5 + f)
                fd[j] = FieldTerrain.q(-(0.5 - f))
                ```
                **LOOK AT LINE 732 OF `Sources/Railways.swift`:**
                `j` is at `y = c.y = 161`, so `j - CSQ` is at `y = 160`!
                When `shapeBed` runs on `fd`, what is `fd[j - CSQ]` (`fd` at `y = 160`) when the hillside had a 1–8 block dip that `Railways.draw` banked up with dirt + gravel, OR when the hillside had a 1–5 block rise that `Railways.draw` cut away (`w.set(x, yy, z, AIR)` for `yy in y...(y+5)`)?!
                - Wait: `FieldTerrain` converts the post-structure block array into `fd` FIRST, and *then* calls `Railways.shapeBed`!
                - In `FieldTerrain`, if `(11, 159, 8)` was dirt, `(11, 160, 8)` was gravel, and `(11, 161, 8)` was air, then `fd[160] > 0` and `fd[161] <= 0` — UNLESS `(11, 160, 8)` was placed as **`plat` (`stone_bricks`)** (`w.firmUnder` was false over a cave, `Railways.swift:785`) OR **`deck` (`spruce_planks`)** (`bank < 0`, dip > 8 blocks)!
                - Wait: what if `(11, 8)` is beside `(12, 9)` or what if `c[i+2]` ALSO stepped up, OR what if `(11, 8)` is in the NEXT CHUNK? `inChunk(pad: 2)` handles `+2`.
                - NOW CHECK WHAT HAPPENS WHEN `c[i]` AND `c[i+1]` STEP UP EVEN WITHOUT ANY DIP:
                  Suppose `c[i-1] = (10, 159, 11)`, `c[i] = (10, 160, 10)`, `c[i+1] = (11, 160, 10)`, `c[i+2] = (11, 161, 9)`:
                  Look at `c[i] = (10, 160, 10)`:
                  - `(0, +1) = (10, 160, 11)`: above `c[i-1]` at `159` -> `at = AIR`, `under = rail` -> **`false`**!
                  - `(+1, 0) = (11, 160, 10)`: `c[i+1]` at `160` -> `at = rail` -> **`true`** (1).
                  - `(-1, 0) = (9, 160, 10)`: distance² to `c[i-1]=(10,11)` is `2`, distance² to `c[i]=(10,10)` is `1` -> owned by `c[i]` at `160` -> **`true`** (2).
                  Now what if the diagonal is **steeper than 45°** (`smoothDogLeg` tries `want = adz * 3 / 4` and `max(8, adz / 2)` at `Railways.swift:525`!), so there are two Z steps then one X step:
                  `c[i-1] = (10, 160, 11)` (straight Z, shape `4` ascending north!)
                  `c[i]   = (10, 160, 10)` (curve shape `6` S–E)
                  `c[i+1] = (11, 161, 10)` (curve shape `8` N–W, stepped up to `161`!)
                  `c[i+2] = (11, 161, 9)`  (straight Z, shape **`0` or `4`**!)
                  **WAIT A SECOND!! STOP AND LOOK AT `c[i+2]` RIGHT THERE!!**

   **OH!! MY!! GOD!!**
   **LOOK AT `Line.shape(_ i: Int)` AT `Sources/Railways.swift:55-76` AND `ShapeRails.emit` AT `Sources/ShapeRails.swift:62-66, 164-180`!!**

   READ THIS CAREFULLY — THIS IS HUGE!!
   Trace `Line.shape(i)` (`Sources/Railways.swift:55-76`) on **ANY** diagonal railway that isn't a pure 1:1 45° staircase (i.e. EVERY eased turn arc in `roundPolyline`, EVERY shallower/steeper diagonal in `smoothDogLeg`, EVERY routed link in `diagonalWay`)!!
   Suppose a curved turn or non-45° diagonal has TWO steps in the same direction (e.g. `x` advances twice before `z` steps once: `(10, 10) -> (11, 10) -> (12, 10) -> (12, 11)`), AND `y` steps up by `1` betweentwo of those cells (`gentleProfile` allows `y` to step up anywhere because `diagonal == true` disabled `isCurve` at `Railways.swift:656`!!):

   Case I: `y` steps up between TWO CURVE CELLS:
   - `c[i]   = (11, 160, 10)` (`shape = 6`, curve S–E)
   - `c[i+1] = (11, 161, 11)` (`shape = 8`, curve N–W, **`y` is `161`, one block higher than `160`!**)
   - Look at `Rails.exits[shape]` (`Sources/Rails.swift:9-13`):
     - Curve shapes `6, 7, 8, 9` have `dy = 0` in `Rails.exits` (`[(0, 0, 1), (1, 0, 0)]`, etc.), which `ShapeRails.joined` (`ShapeRails.swift:171`) handles via `for dy in [e.1, 0, 1, -1]`.
     - **HOWEVER**, what happens when **`Railways.draw` places the rail blocks into the world** AND later a chunk loads or any neighbour block updates (e.g. grass settling, tree leaf brushing, fluid tick, sparkstone/block update)? No, `autoShape` only runs on placement.
     - Wait: what happens in `ShapeRails.mainline` (`ShapeRails.swift:294-305`) on **straight cells (`shape` 0..5) inside an eased curve or shallow diagonal**?!
       Look at `(10, 160, 10) -> (11, 160, 10) -> (12, 161, 10) -> (12, 161, 11)`:
       - At `c[i] = (11, 160, 10)`: `dIn = (1, 0, 0)`, `dOut = (1, 0, 0)`. Not a curve! `c[i+1].y == 161 == c[i].y + 1`, so **`shape = 2` (ascending east)**!
       - Look at `ShapeRails.mainline` (`ShapeRails.swift:296-305`) when `shape == 2`:
         ```swift
         switch shape {
         case 1, 2, 3: sides = [(0, -1), (0, 1)]
         case 0, 4, 5: sides = [(-1, 0), (1, 0)]
         default: sides = [(-1, 0), (1, 0), (0, -1), (0, 1)]
         }
         ...
         return shape >= 6 ? open >= 2 : open == 2
         ```
         **IT REQUIRES `open == 2` (BOTH `(0, -1)` AND `(0, +1)` OPEN WITH BED AT `y - 1`)!!**
         Now check `(0, +1) = (11, 160, 11)` beside `c[i] = (11, 160, 10)`!
         - `c[i+2]` is `(12, 161, 11)` at **`y = 161`**!
         - What is the distance from `(11, 11)` to `c[i] = (11, 10)`? `0² + 1² = 1`!
         - What is the distance from `(11, 11)` to `c[i+2] = (12, 11)`? `1² + 0² = 1`!
         - Now flip the direction (going west-to-east, curving **north**, `-z`):
           `c[i-1] = (10, 161, 9)` (curve at **`y = 161`**!)
           `c[i]   = (11, 160, 10)`? Wait: `(10, 161, 9) -> (10, 161, 10) -> (11, 160, 10) -> (12, 160, 10)`:
           Look at **`c[i+1] = (11, 160, 10)`**? That's a curve (`shape >= 6`). Look at **`c[i+2] = (12, 160, 10)`**? Wait: what if `(10, 161, 9) -> (11, 161, 9) -> (11, 160, 10) -> (12, 160, 10) -> (13, 160, 10)`:
           Look at **`c[i+2] = (12, 160, 10)`** (`shape == 1`, straight E–W at `y = 160`, so `mainline` requires **BOTH** `(12, 9)` and `(12, 11)` to have bed at `y - 1 = 159` and open at `y = 160`!):
           - Check column `(12, 9)` (`(0, -1)` from `(12, 10)`):
             - Distance² from `c[i] = (11, 161, 9)` (which is a curve cell, so its `bed` is `3×3` + `±2`, containing `(12, 9)`!) to `(12, 9)` is `1² + 0² = 1`!
             - Distance² from `c[i+2] = (12, 160, 10)` to `(12, 9)` is `0² + 1² = 1`!
             - **`i < i + 2`, SO `c[i]` AT `y = 161` WINS THE TIE IN `nearestCells` (`Railways.swift:749`)!!**
             - Column `(12, 9)` gets its ballast placed at `c[i].y - 1 = 160` (i.e. **`y = 160` IS SOLID GRAVEL!!**), NOT `159`!
             - Now `ShapeRails.mainline` runs on `c[i+2] = (12, 160, 10)` (`shape = 1`):
               - It checks `(dx, dz) = (0, -1)` -> `(12, 160, 9)`:
               - `at = ctx.block(12, 160, 9)` = **SOLID GRAVEL (`Blocks.collide[at] == true`)**!!
               - So `open` is **`1`, NOT `2`**!!
               - `mainline` returns **`false`**!!
               - Look at `ShapeRails.emit` (`ShapeRails.swift:62`):
                 ```swift
                 let big = mainline(ctx, x, y, z, shape)
                 if smooth && big && !powered, let path = smoothPath(ctx, x, y, z) {
                 ```
                 **BECAUSE `big` IS `false` ON `c[i+2]`:**
                 1. **`smoothPath` IS SKIPPED ON `c[i+2]`!!** While `c[i+1]` drew a smoothed diagonal Hermite rail offset away from the block centre at **1.44-block main-line gauge (`mainGauge = 0.72`, sleeper width `2.44`)**, `c[i+2]` suddenly draws an **UNSMOOTHED axis-aligned tiny 0.6-block minecart rail (`gauge = 0.3`, sleeper width `0.92`)** Down the middle of the cell, **completely disconnected in position, angle, AND width** from the main-line rails on both sides of it!!

   **BINGO!! JACKPOT!! READ THAT AGAIN!!**
   Let's double-check that exact trace because it is 100% deterministic and happens on EVERY climbing/descending eased turn in PR #712 (`N12`), including Savanna hills at `3752 96 114`!
   Let's verify every single step of that trace:
   1. Any eased curve (`roundPolyline`) or shallow diagonal (`smoothDogLeg`, `diagonalWay`) alternates curve steps with short 1-, 2-, or 3-cell straight steps (`shape` `0..5`), e.g.:
      - `c[i]   = (11, 161, 9)` (curve cell at `y = 161`)
      - `c[i+1] = (11, 160, 10)` (curve cell at `y = 160` — `y` dropped 1 block on the grade!)
      - `c[i+2] = (12, 160, 10)` (straight cell, `shape = 1`, at `y = 160`!)
   2. In `Railways.nearestCells` (`Railways.swift:742-753`):
      - `c[i] = (11, 161, 9)` is a curve cell, so `bed(l, i)` includes `(12, 9)` at squared distance `1`.
      - `c[i+2] = (12, 160, 10)` is a straight cell along X, so `bed(l, i+2)` includes `(12, 9)` at squared distance `1`.
      - Because `i < i + 2`, `if let b = best[k], b.0 <= d { continue }` keeps **`i`** as the owner of `(12, 9)`!
   3. In `Railways.draw` (`Railways.swift:762-785`) and `Railways.shapeBed` (`Railways.swift:729-735`):
      - Column `(12, 9)` is built for owner `i` at `y = 161`, so `y = 160` is **solid ballast/ground**!
   4. In `ShapeRails.mainline` (`ShapeRails.swift:294-305`):
      - For `c[i+2] = (12, 160, 10)` (`shape = 1`), `sides` has only 2 entries: `[(0, -1), (0, 1)]`, and line 304 demands `open == 2`!
      - At `(0, -1)` = `(12, 160, 9)`, `at` is **solid ballast** (`Blocks.collide[Int(at)] == true`)!
      - So `open` is `1` (`!= 2`), **`mainline` returns `false`**!
   5. What does `ShapeRails.emit` (`ShapeRails.swift:61-66`) do when `big == false`?
      - `if smooth && big && !powered, let path = smoothPath(...)` is **SKIPPED**!
      - Instead of continuing the smooth curved 1.44m-wide railway track from `c[i+1]` to `c[i+3]`, `c[i+2]` draws a **tiny 0.6m-wide straight minecart track** snapped to `(0, 0.5) -> (1, 0.5)` at a completely different lateral offset and angle!
      - Look at what the player sees on a hill at `3752 96 114`: the wide curved train track suddenly **chops off in mid-air**, a tiny narrow straight minecart rail sits crookedly beside a step of dirt/gravel encroaching over the track, and then the wide curved train track resumes a block later!
      - *"That is not how that works."* — **EXACTLY!!**

   AND LOOK EVEN CLOSER — THE SAME BUG ALSO HAPPENS ON PURE 45° CLIMBING CURVE CELLS!
   Check `c[i+1] = (11, 161, 9)` when `c[i-1] = (10, 160, 10)`, `c[i] = (11, 160, 10)`, `c[i+1] = (11, 161, 9)`, `c[i+2] = (12, 162, 9)` (wait: grade is 1/8 so `y` steps at most once every 8 cells, EXCEPT at `hs[i] ≈ N + 0.5` before the dip/hump fix, no, 1/8 rises 1.0 every 8 cells). Even at 1 step per 8 cells, look at `c[i+1] = (11, 161, 9)` when `c[i+2] = (11, 161, 8)` (turning north, `shape = 0` straight N–S!):
   - `c[i-1] = (10, 160, 10)` (`y = 160`, curve)
   - `c[i]   = (11, 160, 10)` (`y = 160`, curve)
   - `c[i+1] = (11, 161, 9)`  (`y = 161`, curve)
   - `c[i+2] = (11, 161, 8)`  (`y = 161`, **straight N–S, `shape = 0`**!)
   - Check `c[i+1] = (11, 161, 9)` (`shape = 6` or `7`? Wait: `p=(11,10)`, `c=(11,9)`, `q=(11,8)` -> **`c[i+1]` IS ALREADY STRAIGHT `shape = 4` (ascending north, `c[i]` is at `160`? No, `c[i]` is lower, so `shape = 0`)!!**):
     - On `c[i+1] = (11, 161, 9)` (`shape = 0`): `sides = [(-1, 0), (1, 0)]` = `[(10, 9), (12, 9)]`!
     - Who owns `(10, 9)`? `c[i-1] = (10, 160, 10)` is at distance² `1` and `i - 1 < i + 1`! So `(10, 9)` has its bed at `159`, and `(10, 160, 9)` is **`AIR`**!
     - On `c[i+1] = (11, 161, 9)`, side `(-1, 0)` checks `under = (10, 160, 9)` = **`AIR`**! `bedKinds[AIR] == false`!
     - So `open == 1 != 2` -> **`mainline` returns `false` going BOTH up AND down hills!!**
     - Going UP (`y` increases with `i`): the earlier lower curve cell steals the side bed column, leaving `AIR` under the straight cell's side (`under == AIR`) -> `mainline == false`!
     - Going DOWN (`y` decreases with `i`): the earlier higher curve cell steals the side bed column, putting solid `ballast` at `y` beside the lower straight cell (`Blocks.collide[at] == true`) -> `mainline == false`!
   - **BOTH UPGRADE AND DOWNGRADE BREAK `ShapeRails.mainline`!** Every time a curved turn in N12 climbs or descends across an integer block boundary into/out of a straight cell, `nearestCells` gives one side column to the earlier cell at the wrong `y`, `mainline` evaluates to `false`, `smoothPath` aborts, and the main-line railway turns into a crooked miniature minecart rail mid-turn!

---

#### Let's check Bug 3.2 — What else happens on `smoothPath` + trestle / stone_bricks transitions on hills (`ShapeRails.swift:220-222`, `Railways.swift:729-735, 785-800`)!

Look at `ShapeRails.smoothPath` (`Sources/ShapeRails.swift:220-222`):
```swift
        let raw: [SIMD3<Float>] = nodes.map { c in
            SIMD3(Float(c.x) + 0.5, Float(c.y) + (bedTop(ctx, c.x, c.y, c.z) ?? 0), Float(c.z) + 0.5)
        }
```
And look at `ShapeRails.emit` for non-`smoothPath` rails (`Sources/ShapeRails.swift:102-119`):
```swift
            if let hc = bedTop(ctx, x, y, z) {
                ...
```
NOW TRACE WHAT `bedTop(ctx, x, y, z)` RETURNS (`Sources/ShapeRails.swift:309-316`):
```swift
    static func bedTop(_ ctx: DetailContext, _ x: Int, _ y: Int, _ z: Int) -> Float? {
        guard let field = ctx.field else { return nil }
        let cx = (x + 16) >> 4, cz = (z + 16) >> 4, wy = ctx.sy * 16 + y
        guard cx >= 0 && cz >= 0 && cx < 3 && cz < 3, wy >= 1 && wy < CH else { return nil }
        let st = field[cx + cz * 3]
        let i = ((x + 16) & 15) + ((z + 16) & 15) * CS + wy * CSQ
        let a = FieldTerrain.f(st.density(i - CSQ)), b = FieldTerrain.f(st.density(i))
        guard a > 0, b <= 0, a - b > 1e-3 else { return nil }
        return max(-0.5, min(0.5, a / (a - b) - 0.5))
    }
```
LOOK AT WHAT HAPPENS IN TWO VERY COMMON CASES ON SAVANNA HILLS (`3752 96 114`):
1. **Over a cave / hollow (`!w.firmUnder` at `Railways.swift:785`) or a trestle (`deck` at `Railways.swift:796`)**:
   - `Railways.draw` places **`plat` (`stone_bricks`)** or **`deck` (`spruce_planks`)** at `y - 1`.
   - Neither `stone_bricks` nor `spruce_planks` is natural field ground (`SmoothTerrain.natural` is false for built blocks)!
   - So in `FieldTerrain.split`, `st.density(i - CSQ)` is **`<= 0` (outside)** — the built cube stays in `st.data` at `y - 1`, and its top face is at `Float(y)` (i.e. offset `0.0` relative to cell `y`).
   - Meanwhile, the very next rail cell `c[i+1]` IS on firm `ballast` (`gravel`), where `hs[i+1] = Float(c.y) - 0.44` (or `+ 0.44`)!
   - At `c[i]` (`stone_bricks` or `spruce_planks`), `bedTop` returns `nil` -> height is `Float(c.y) + 0.0`!
   - At `c[i+1]` (`gravel`), `bedTop` returns `-0.44` (or `+0.44`, or if `c.y` stepped up by 1 from `160` on deck to `161` with `bedTop = -0.44`, wait: `160 + 0.0` to `160 - 0.44` is a **0.44-block DROP backward** while going uphill, or `160 + 0.0` to `161 + 0.0` on a trestle)!
   - EVEN WORSE: Look at a **diagonal trestle** or **climbing trestle** (`hs` has a 1-in-8 slope, so `c.y = Int(hs[i].rounded())` steps by **1 full block** every 8 cells, while `spruce_planks` cubes at `c.y - 1` step up by **1 full block at once**!).
     - In `smoothPath` (`ShapeRails.swift:220-222`), `raw` only smooths `.x` and `.z` (`ShapeRails.smoothed` at `ShapeRails.swift:192-193`: *"heights as they are"*!), keeping `raw.y = Float(c.y) + 0`!
     - So over a trestle or `stone_bricks`, `raw.y` has a **1.0-block vertical cliff** in 1 cell (`45°` vertical kink in the steel rails, cutting straight through the 1-block plank step!), AND across the 3.5-block width of a diagonal curve, the smoothed rail shifts up to **0.75 blocks sideways** off cell `c` onto a neighbour cell whose plank deck is 1 block higher or lower — **burying one rail inside the wooden cubes and leaving the other rail floating in mid-air**!
   - Look at `Railways.gentleProfile` (`Sources/Railways.swift:648-654`):
     - Why were trestles over rivers/ravines allowed to slope in `gentleProfile` on diagonal lines? Because `gentleProfile` didn't level trestle spans, AND `Railways.draw` (`Railways.swift:776-783`) only banks up to `d = 9` (`8` blocks deep) when dry! On a steep Savanna hill/ravine > 8 blocks deep (or 2+ blocks of water), it switches from smooth banked earth to stepped `spruce_planks` cubes mid-curve and mid-grade!

2. **Look at `ShapeRails.smoothed` (`Sources/ShapeRails.swift:185-198`) on `y` AND at `bed` width on rounded arcs (`Railways.swift:695-705`)!**
   Wait: check what `ShapeRails.smoothed` does to `(x, y, z)`:
   ```swift
   next[i].x = (a.x + 2 * sm[i].x + c.x) * 0.25
   next[i].z = (a.z + 2 * sm[i].z + c.z) * 0.25
   ```
   After 4 passes of `(1, 2, 1)/4`, on a curved arc of radius `R = 14`, the curve pulls **inward** toward the centre of the arc by `~4 * (1 / (2 * R))` ≈ `0.15..0.5` blocks, AND on a 90° unrounded corner (old rail or fallback dog-leg when `smoothDogLeg` fails!) wait:
   **STOP AND CHECK WHAT HAPPENS WHEN `smoothDogLeg` FAILS AND `Railways.plan` FALLS BACK TO AN L-SHAPED 90° DOG-LEG IN A FIELD WORLD (`Sources/Railways.swift:622-645` + `ShapeRails.swift:56-66`)!!**

   WAIT A SECOND!! CHECK THIS!!
   In `Railways.plan` (`Sources/Railways.swift:622-645`):
   - `diagonal` is `true` (because it's a field world).
   - Suppose between two towns, `smoothDogLeg` returns `nil` (blocked by a village piece or tight gap), so `dogLeg` falls back to the classic **90-degree dog-leg** (`xm`), OR on ANY old-style 90° corner in a field world:
   - `ShapeRails.emit` (`ShapeRails.swift:56, 62`) checks:
     `let smooth = ctx.field != nil && !Railways.oldRails`
     It runs `smoothPath` on **ALL** main-line curves in a field world!
   - Wait: on a 90° corner, 4 passes of `(1, 2, 1)/4` pull the corner inward by **`~0.80` blocks** (the midpoint of `(0,0)` after 4 passes on `(-k, 0) .. (0, 0) .. (0, k)` moves to `(-0.55, 0.55)`, distance `0.78` blocks diagonally from `(0.5, 0.5)`, i.e. onto cell `(-1, +1)`!).
   - On a `smoothDogLeg` (`r >= 6`), `rasterPolyline` already rasterized the circular arc, so 4 passes only smooth out the 0.35-block staircase teeth onto the exact diagonal/arc, keeping the centre line within `0.35` blocks of `c` (`bed` reaches `±2` = `1.4..2.0` blocks out, which covers `0.72 + 0.35 = 1.07` blocks).
   - **HOWEVER**, look at `Railways.bed(l, i)` (`Sources/Railways.swift:694-706`) on the **short 2- or 3-cell straight runs inside a `roundPolyline` arc** (near 0° or 90° of the arc, where the arc runs nearly along X or Z, stepping in Z once every 3 or 4 X steps)!
     Trace `bed(l, i)` on `(10, 10) -> (11, 10) -> (12, 10) -> (13, 10) -> (13, 11)`:
     - `c[i]   = (11, 10)`: `p = (10, 10)`, `q = (12, 10)` -> **`curve == false`!!**
     - `c[i+1] = (12, 10)`: `p = (11, 10)`, `q = (13, 10)` -> **`curve == false`!!**
     - `c[i+2] = (13, 10)`: `p = (12, 10)`, `q = (13, 11)` -> `curve == true`!
     - Because `curve == false` on `(11, 10)` and `(12, 10)`, `bed(l, i)` ONLY spans `z ∈ 9...11` (`±1`), NOT `±2`!
     - Meanwhile `ShapeRails.smoothPath` looks `window = 6` cells ahead, sees `(13, 10) -> (13, 11)`, and shifts the track at `(12, 10)` toward `+z` by `~0.35` blocks! With sleeper half-width `1.22` (`ShapeRails.swift:141, 267`), the outer end of the sleeper reaches `0.5 + 0.35 + 1.22 = 2.07` — past `z = 11` (`2.0`) into the uncut hillside or air at `z = 12`!
     - AND if `(13, 11)` is 1 block higher (`y + 1`) than `(12, 10)`, as we proved in Bug 3.1, `(13, 10)` or `(13, 11)` steals `(12, 11)` in `nearestCells`, **causing `mainline` on `(12, 10)` to return `false`!**

---

#### Let's ALSO check: Could `smoothDogLeg`, `route`, `diagonalWay`, or `plan` ITSELF loop or fold back?!

Let's check EVERY path generator in `Sources/Railways.swift` and `Sources/RailLoops.swift`!

1. **`RailLoops.planLoop` (`Sources/RailLoops.swift:44-101`)**:
   - **YES — 100%!** At EVERY unlinked west or east end of a railway line (in `RailLoopCheck`, **192 out of 256** line ends across 12 seeds are unlinked and get a `planLoop`!! That's **75% of all railway ends in the game**!), `planLoop` generates a `26 × 16` loop (`r = 7` rounded corners in N12) right outside the end town that goes out 12 blocks, curves in a 16-block circle, and runs straight back into the track itself 14 blocks behind the end!
   - Think about how common that is: **3 out of every 4 railway line ends in the world have one!** The very first time Remington followed a railway line to an unlinked station in Savanna (`3876 75 192`) after N12 rounded it into a circle, he saw the track curl around in a 16-block circle onto itself and T-bone its own track (`ShapeRails.smoothPath` didn't even draw switch rails where it hit!).
   - Look at BOTH of his quotes again:
     - Near `3876 75 192`: *"That should never happen. What is this?... Train tracks should not naturally go in a circle onto itself"*
     - Near `3752 96 114` (146 blocks away along the same line, climbing the Savanna hill to `y = 96`): *"That is not how that works."*

2. **WAIT — What else could happen at `3876 75 192` or `3752 96 114`? Let's check if TWO lines/links can cross, overlap, or U-turn near `3876 75 192` and `3752 96 114`!**
   Let's check ALL ways two tracks or one link can behave badly:

   - **Check A: `planLink` + `route` + `diagonalWay` (`Sources/Railways.swift:225-408, 540-564`)**:
     Look at `planLink` (`Sources/Railways.swift:235-245`):
     ```swift
        if b == nil, let pa = a.cells.last {
            south: for k in 0...linkReach where hasLine(gen, row + 1, s + k) {
                guard let l = line(gen, row: row + 1, stretch: s + k), let f = l.cells.first, f.x - pa.x >= 40 else { continue }
                for j in 1...linkReach where hasLine(gen, row + 1, s + k - j) {
                    if line(gen, row: row + 1, stretch: s + k - j) != nil { continue south }
                }
                b = l; bKey = key(row + 1, s + k)
                break
            }
        }
     ```
     LOOK AT `k = 0` IN `for k in 0...linkReach` (`Railways.swift:236`)!!
     Suppose `a` is in `(row = -1, stretch = 1)` (`z ≈ -350`, `x` up to `~5000`), and `b` is in `(row = 0, stretch = 1)` (`z ≈ +150`, `x` starting at `3876`)!
     Wait: if `pa.x = 3752, pa.z = -350` and `pb = (3876, 192)`:
     `pb.x - pa.x = 3876 - 3752 = 124 >= 40`!!
     `pb.z - pa.z = 192 - (-350) = 542` blocks south!
     OR even in the SAME row (`row = 0`): `a` is `(row = 0, stretch = 0)` whose east end `pa` is around `(3200, 114)` and `b` is `(row = 0, stretch = 1)` whose west end `pb` is at `(3876, 192)`!
     NOW TRACE `route` + `diagonalWay` when `route` goes around a Savanna village or structure!
     1. In `route` (`Railways.swift:294-306`), `blocked` marks all structure pieces (`village`, etc.) — **NOT existing railway lines `a` or `b`!**
        **WAIT A SECOND!! STOP AND READ `Railways.route` LINES 294-306 RIGHT NOW!!**
        ```swift
        // Blocked squares: structure pieces (padded), filled in once from the starts round the box.
        var blocked = [Bool](repeating: false, count: nx * nz)
        ```
        **`route` DOES NOT MARK LINE `a`'S OWN CELLS OR LINE `b`'S OWN CELLS AS BLOCKED!!**
        HOLD EVERYTHING!! READ THAT TEN TIMES!!
        Look at `route(gen, sc, from: (pa.x, pa.z), to: (pb.x, pb.z))` (`Railways.swift:283-391`):
        - `pa` is `a.cells.last` (the east end of line `a`)! Line `a` lies immediately WEST of `pa` (`x <= pa.x`)!
        - `pb` is `b.cells.first` (the west end of line `b`)! Line `b` lies immediately EAST of `pb` (`x >= pb.x`)!
        - Look at the search grid bounds in `route` (`Railways.swift:289-290`):
          ```swift
          let gx0 = floorDiv(min(s0.0, e0.0) - 4 * G, G), gx1 = floorDiv(max(s0.0, e0.0) + 4 * G, G)
          let gz0 = floorDiv(min(s0.1, e0.1) - margin, G), gz1 = floorDiv(max(s0.1, e0.1) + margin, G)
          ```
          **`gx0` EXTENDS `4 * G = 64` BLOCKS WEST OF `s0` ( ~48 BLOCKS OVER LINE `a` ITSELF!), AND `gx1` EXTENDS `4 * G = 64` BLOCKS EAST OF `e0` (~48 BLOCKS OVER LINE `b` ITSELF!)!!**
        - NOW TRACE WHAT A* DOES WHEN SOMETHING (ocean, cliff, village, outpost, camp) BLOCKS THE DIRECT EASTWARD PATH FROM `s0` OR INTO `e0`!!
          - Suppose just west of `b` (`pb = (3876, 192)`), there is a structure/camp/ruin blocking the approach from the west, while `e0` (`x = 3864, z = 192`) is forced open (`blocked[goal] = false; looked[goal] = 1` at `Railways.swift:324`!!)!
          - Because `e0 - 1` (west of `e0`) is BLOCKED by that structure, how does A* reach `(goal, d = 0 [heading east!])`?!
          - Wait: to arrive at `goal` with `d = 0` (heading east), A* must enter `goal` from `goal - 1` (the square west of `goal`). What if `goal - 1` is open, or what if `start + 1` (east of `s0`) is blocked?
            1. `start` starts at `(s0, heading = 0 [east])`.
            2. At `start`, `nd` can be **`1` (south) or `3` (north)** immediately!
            3. One square north/south (`z ± 16`), `nd` can be **`2` (WEST)**!
            4. It goes **WEST** past `pa` (because `gx0` goes `64` blocks west of `s0`!), crosses **across line `a`**, loops around behind `pa`, or at `goal`:
            5. Suppose A* comes in from the east (`gx1` goes `64` blocks east of `e0`, right through `pb` and `b`'s station!): A* goes **past `e0` to the east (crossing `b`'s track!)**, turns south/north, goes **west** behind `e0` to `goal - 1`, turns north/south, and enters `goal` heading east (`d = 0`), then runs east to `pb` — **MAKING A GIANT LOOP RIGHT OVER `b`'S END (`3876 75 192`)!!**

   **WHOA!! STOP AND VERIFY THAT!!**
   Let's trace that step by step!
   Suppose `b` starts at `pb = (3876, 192)` (west end of `b`'s station straight for a town in Savanna!).
   - Where is `b`'s town? The station straight is `southGap = 5` blocks south of the town's bounding box (`z = box.1.z + 5 = 192`), from `xa = box.0.x - 10 = 3876` to `xb = box.1.x + 10`!
   - So the town's bounding box is `x ∈ [3886, ~3950], z ∈ [~120, 187]` — **NORTH of `z = 192`, starting at `x = 3886`!**
   - Where is `e0`? `e0 = (floorDiv(3876 - 16, 16) * 16 + 8, 192) = (3864, 192)`!
   - Now suppose the link is coming from **NORTH** of `z = 192` (for example from `(3752, 96, 114)` where `z = 114 < 192`!!)!
   - **LOOK AT THE Z COORDINATES IN REMINGTON'S NOTES:**
     - Note 2: `x = 3752, y = 96, z = 114`
     - Note 1: `x = 3876, y = 75, z = 192`
   - Suppose at `x ≈ 3848..3864, z ≈ 160..192`, a piece of a structure (or a wild camp / village house / ruined structure) blocks `(x = 3848, z = 192)` (`goal - 1`)? No, if `goal - 1` is blocked, `goal` with `d = 0` is unreachable. What if `(3848, 192)` (`goal - 1`) IS open, `(3848, 176)` (north of `goal - 1`) is **blocked** by a village piece extending west, while `(3880, 176)` is blocked by the village, and what if the link overshoots east of `s0` or loops around at `s0`/`e0`?
   - Even simpler: Suppose `s0` has an obstacle at `s0 + (16, 0)`:
     - From `pa`, the link goes **east** 16 blocks to `s0`, turns **north**, goes **west** 32 blocks (crossing or running alongside line `a`), turns **south** **CROSSING ITS OWN `(pa -> s0)` SEGMENT**?!
     - WAIT A SECOND!! **CAN `route` CROSS `(pa -> s0)` OR `(e0 -> pb)`?!**
       LOOK AT `Railways.swift:286, 378-389`!!
       1. `s0` is at `(pa.x + 9..24, pa.z)`.
       2. Line 379 adds cells `(pa.x + 1, pa.z) ... (s0.0, pa.z)` **AFTER** A* finishes! A* ONLY starts at `s0` and NEVER marks `(pa.x + 1 ... s0.0 - 1, pa.z)` (the square `start - 1`!) as blocked!!
       3. Look at what happens when `start + 1` (east of `s0`) is blocked, `start - nx` (north of `s0`) is open, and the destination is **south** of `pa.z` (just like `z = 114` -> `z = 192`, which is `78` blocks **SOUTH**!!), while `start + nx` (south of `s0`) is ALSO blocked (e.g. by the station house of `pa`'s own town!!)!
       **HOLD EVERYTHING!! STOP AND CHECK WHERE `pa`'S OWN STATION HOUSE IS!!**
       LOOK AT `Railways.draw` (`Sources/Railways.swift:835-843`):
       - The town is **NORTH** of the track (`z <= pa.z - 5`), and `pa` is only `stationRun = 10` blocks east of the town's box (`xb = t.box.1.x + 10`)!
       - In `route` (`Railways.swift:296-305`), the town's pieces have `pc.max.x + 4` up to `pa.x - 6`, and `s0.0` is `floorDiv(pa.x + 16, 16) * 16 + 8`.
       - What if east of `s0` is a structure / deep ocean, and north of `s0` is open?
         - From `s0`, A* goes **north** 1 square (`z - 16`), **west** 1 square (`s0.0 - 16`, which is `pa.x - 7..8` or `s0.0 - 16 = pa.x + 4`!), and then **SOUTH** 2 squares — **GOING STRAIGHT ACROSS `(pa.x + 1 ... s0.0, pa.z)`!!**
         - Now what happens in `route` (`Railways.swift:388`) vs **`diagonalWay` (`Railways.swift:540-564`)**?!
           - In `route` (BEFORE PR #712!): line 388 had:
             ```swift
             for c in cells where !seen.insert(...).inserted { tally?("link route: over itself"); return nil }
             ```
             So BEFORE PR #712 (`diagonal == false`), when A* looped back across `(pa -> s0)` or `(e0 -> pb)`, `seen.insert` caught the self-intersection and **rejected the link (`return nil`)**!
           - **NOW LOOK AT PR #712 (`N12`, MERGED TODAY!) IN `Railways.swift:371-377`, `479-484`, AND `540-564`!!**
             1. Line 371:
                ```swift
                if diagonal, let d = diagonalWay(gen, sc, pts, from: a, to: b, open: { ... }) { return d }
                ```
                It returns `d` **BEFORE** line 388's `over itself` check!
             2. Inside `diagonalWay` (`Railways.swift:558`):
                ```swift
                let c = rasterPolyline(roundPolyline(poly, radius: 14))
                ```
             3. **NOW LOOK AT `rasterPolyline` (`Sources/Railways.swift:479-484`)!!**
                ```swift
                var out: [(Int, Int)] = [], at: [Int64: Int] = [:]
                for c in raw {
                    let k = colKey(c.0, c.1)
                    if let j = at[k] { while out.count - 1 > j { at[colKey(out.last!.0, out.last!.1)] = nil; out.removeLast() } }
                    else { at[k] = out.count; out.append(c) }
                }
                ```
                AND what if `roundPolyline` looped around **WITHOUT** crossing `(pa -> s0)` — e.g. `s0` goes north, west, south to `pa.z + 16` (just south of `pa`), and east — OR in `RailLoops.planLoop` (`RailLoops.swift:71-80`), which **intentionally** builds a 360° loop around onto itself (`!bySide, !touchesItself(rc)`)!

   **LOOK AT BOTH:**
   1. **`RailLoops.planLoop` (`Sources/RailLoops.swift:44-101`)** literally builds a 360° circular track onto itself at 75% of line ends (`3876 75 192`), rounded into a circle today by PR #712 (`N12`), with a broken/missing junction into the main line!
   2. **`diagonalWay` + `route` (`Sources/Railways.swift:283-391, 540-564`)** ALSO allows A* to go west behind `pa` or east past `pb`, creating 270° loop-arounds and acute `< 90°` hairpin corners at `s0` and `e0`!

---

#### Let's check EVERY detail of `(3752, 96, 114)` ("That is not how that works.") too!

Let's list ALL the physical/visual defects on hillside diagonal tracks in PR #712 (`N12`) so we fix **every single one of them**, not just one!

Look at what happens on a hilly Savanna railway near `(3752, 96, 114)`:

1. **Gauge & smoothing drop-out mid-turn / mid-hill (`ShapeRails.mainline`, `Sources/ShapeRails.swift:294-305`)**:
   - As we proved mathematically above, whenever a curved/diagonal railway climbs or descends across a block boundary (`c.y` changes by `±1`), `Railways.nearestCells` assigns the shared bed shoulder column to the lower-index curve cell at the old `y`.
   - Adjacent straight cells (`shape` `0..5`, which appear every few blocks in eased arcs and non-45° diagonals) require `open == 2`, see solid gravel at `y` (downgrade) or `AIR` at `y - 1` (upgrade) on that stolen shoulder, and get **`mainline == false`**!
   - Even curve cells (`shape` `6..9`) on narrow trestles or climbing turns where two sides step in `y` can get `open < 2` -> **`mainline == false`**!
   - Result: `big` becomes `false` and `smoothPath` is skipped for those cells! Right in the middle of a wide 1.44m smooth diagonal railway, individual cells turn into **0.6m tiny unsmoothed 90° minecart rails** that don't line up with the rails on either side!

2. **Rail height / bed mismatch on hills, cave roofs, and trestles (`Railways.draw` `Sources/Railways.swift:785-800`, `Railways.shapeBed` `Sources/Railways.swift:729-735`, `ShapeRails.smoothPath` `Sources/ShapeRails.swift:220-222`, `ShapeRails.bedTop` `Sources/ShapeRails.swift:309-316`)**:
   - Look at `Railways.draw` line 785:
     ```swift
     if Blocks.opaque[Int(ground)] && Blocks.collide[Int(ground)] { w.set(x, y - 1, z, w.firmUnder(x, y - 1, z) ? ballast : plat) }
     ```
     In a **field world**, `plat` is `stone_bricks` (a **built** cube, NOT field material!). Whenever the track passes over a cave within a few blocks of the surface (`!w.firmUnder`), `Railways.draw` places `stone_bricks` cubes instead of `gravel`!
     - `stone_bricks` is NOT shaped by `shapeBed` (`FieldTerrain` keeps it as a 1×1×1 blocky cube at integer `y - 1`, sticking up up to `0.45` blocks through the sloped gravel bed as square stone brick blocks!).
     - And `bedTop` returns `nil` over `stone_bricks`, so the rail suddenly jumps up/down by up to `0.45` blocks onto the flat cube top!
     - Why did R22 use `plat` (`stone_bricks`) instead of `STONE`? Because gravel falls if unsupported, whereas `STONE` doesn't fall AND `STONE` **is** natural field ground (`SmoothTerrain.natural[STONE] == true`), OR even simpler, filling 1 block under `y - 1` with `STONE` makes `ballast` firm so `shapeBed` shapes it seamlessly!
   - Now look at **trestle decks (`spruce_planks`)** in field worlds (`Railways.swift:775-800`, `ShapeRails.swift:185-238`):
     - Over dips > 8 blocks deep or over rivers/lakes, `Railways.draw` places `spruce_planks` cubes at `c.y - 1`.
     - On a `diagonal` line, `gentleProfile` (`Railways.swift:656`) allowed the track to **climb/descend at 1 in 8 across trestles**, AND `ShapeRails.smoothed` (`ShapeRails.swift:185-198`) **did NOT smooth `.y`**, while `bedTop` returned `nil` (`0.0`) on every `spruce_planks` cell!
     - So on a sloped trestle (`3752 96 114` is at `y = 96` in Savanna hills/valleys!), for 7 cells `raw.y` stays flat at `160.0`, then at cell 8 `raw.y` jumps vertically to `161.0` in a single block (`1:1` 45° kink in the steel rails while the ground grade was supposed to be 1-in-8!), and on a diagonal trestle the smoothed `(x, z)` curve swings off cell `c` over a neighbour cell whose plank cube is 1 block higher/lower, **sticking the sleepers and steel rails straight through the side of a floating stair-stepped pile of plank cubes**!
     - Even worse: look at `Railways.draw` (`Railways.swift:797-798`) for diagonal trestle legs:
       ```swift
       let edge = l.diagonal ? abs(x - c.x) + abs(z - c.z) >= 2 : (alongX && z != c.z) || (!alongX && x != c.x)
       if edge && i % 4 == 0 { w.groundDown(x, y - 2, z, leg, minY: y - 48) }
       ```
       Look at what `i % 4 == 0` does on a diagonal line with `owner[colKey(x, z)] == i`!
       On a 45° staircase `(0,0), (1,0), (1,1), (2,1), (2,2)...`:
       For `i = 0` (`c = (0,0)`), which `edge` cells (`|dx| + |dz| >= 2`) actually have `owner == 0`?!
       - `(1, 1)` is `c[2]` itself (`d = 0 < 2`) -> owned by `2`, NOT `0`!
       - `(2, 0)` has `d² = 4` to `c[0]=(0,0)`, `d² = 1` to `c[1]=(1,0)` -> owned by `1`, NOT `0`!
       - `(0, 2)` has `d² = 4` to `c[0]=(0,0)`, `d² = 2` to `c[2]=(1,1)` -> owned by `2`, NOT `0`!
       - `(+1, -1)` has `d² = 2` to `c[0]`, `d² = 1` to `c[1]=(1,0)` -> owned by `1`, NOT `0`!
       - `(-1, +1)` has `d² = 2` to `c[0]`, `d² = 2` to `c[2]=(1,1)` -> owned by `0` on one side ONLY, while the **entire `+x, -z` side of `c[0]` has ZERO owned cells with `|dx| + |dz| >= 2`** (because `c[1] = (1, 0)` is one step east, stealing `(1, -1)` and `(2, 0)` with `d² = 1`, and for `c[1]`, `i = 1`, `1 % 4 != 0` so `c[1]` NEVER PLACES LEGS)!!
       **STOP AND RE-READ THAT!!**
       Let's check that math right now!!
       Take a 45° NE staircase (`+x, -z`):
       - `c[0] = (0, 0)` (`i % 4 == 0` — tries to place legs!)
       - `c[1] = (1, 0)` (`i % 4 == 1` — NO legs!)
       - `c[2] = (1, -1)` (`i % 4 == 2` — NO legs!)
       - `c[3] = (2, -1)` (`i % 4 == 3` — NO legs!)
       - `c[4] = (2, -2)` (`i % 4 == 0` — tries to place legs!)
       Now check EVERY cell `(x, z)` in `bed(l, 0)` on the **south-east (`+x, +z`)** side of the diagonal (`x - c.x + z - c.z > 0`) AND on the **north-west (`-x, -z`)** side (`x - c.x + z - c.z < 0`) for `c[0] = (0, 0)`:
       The candidate `edge` cells in `bed(l, 0)` (`|x| + |z| >= 2`) are:
       1. `(-1, -1)` (NW side): distance² to `c[0]=(0,0)` is `2`; distance² to `c[2]=(1,-1)` is `4`; distance² to `c[-1]=(0,1)` is `5`. Owned by `0` -> gets a leg on NW side.
       2. `(+1, +1)` (SE side): distance² to `c[0]=(0,0)` is `2`; distance² to `c[-1]=(0,1)` is **`1`** (`(1-0)² + (1-1)² = 1`)!! **STOLEN BY `c[-1]` (`i = -1`, `i % 4 == 3` — NO LEG)!!**
       3. `(+2, 0)` (SE side): distance² to `c[0]=(0,0)` is `4`; distance² to `c[1]=(1,0)` is **`1`**!! **STOLEN BY `c[1]` (`i = 1` — NO LEG)!!**
       4. `(0, +2)` (SE side): distance² to `c[0]=(0,0)` is `4`; distance² to `c[-1]=(0,1)` is **`1`**!! **STOLEN BY `c[-1]` (`i = -1` — NO LEG)!!**
       5. `(-2, 0)` (NW side): owned by `c[-2] = (-1, 1)` (`d² = 2` vs `4`) -> stolen!
       6. `(0, -2)` (NW side): owned by `c[2] = (1, -1)` (`d² = 2` vs `4`) -> stolen!
       7. `(+1, -1)`: **IS `c[2]` ITSELF!**
       8. `(-1, +1)`: **IS `c[-2]` ITSELF!**
       **EVERY SINGLE SE-SIDE EDGE CELL OF `c[0]`, `c[4]`, `c[8]`, ... IS STOLEN BY AN ODD-INDEXED NEIGHBOUR (`c[k - 1]` AND `c[k + 1]`), WHICH HAS `i % 4 != 0`!!**
       **SO ONE ENTIRE SIDE OF EVERY DIAGONAL TRESTLE BRIDGE HAS ZERO SUPPORT LEGS FOR ITS ENTIRE LENGTH — FLOATING PLANKS HANGING IN MID-AIR WITH LEGS ONLY ON ONE EDGE!!**
       AND what if the staircase starts on the other parity (`c[1]` is the corner `(1, 0)` and `c[0]` is `(0, 0)`): for `c[0], c[4], c[8]`, **ZERO** SE-side legs ever generate! And if `y - minY > 48` on a high hill (`y = 96`), `groundDown(..., minY: y - 48)` stops in mid-air if the valley is deep, though 48 is deep — the missing legs on the entire SE side happen on **EVERY** diagonal trestle even 3 blocks above water or 9 blocks above a Savanna gully!
       *"That is not how that works."* — **A diagonal trestle bridge with floating planks, zero legs on one side, stair-stepped 1-block vertical kinks in the rails, and mid-span