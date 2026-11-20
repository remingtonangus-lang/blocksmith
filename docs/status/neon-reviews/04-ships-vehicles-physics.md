# Area 4: Ships, Capital Vessels, Vehicles, Trains & Physics

Reviewed against `origin/claude/quest-port` (`cb7295fb`, Ledger 385).
Files audited: `Sources/Ships.swift`, `Sources/ShipPhysics.swift`, `Sources/ShipPlay.swift`, `Sources/ShipCombat.swift`, `Sources/ShipMelt.swift`, `Sources/MainGun.swift`, `Sources/CapitalShips.swift`, `Sources/Aircraft.swift`, `Sources/FlightModel.swift`, `Sources/Submarines.swift`, `Sources/SkySkiff.swift`, `Sources/Boats.swift`, `Sources/VehicleControls.swift`, `Sources/VehicleDamage.swift`, `Sources/VehicleGunners.swift`, `Sources/VehicleRiding.swift`, `Sources/Trains.swift`, `Sources/TrainHulls.swift`, `Sources/Felling.swift`.

Skipped (already covered in prior reviews or fixed in `bug-ledger.md`): roomscale ship-wall clipping (`neon-review-2.md` #9), third-person chase aiming (`02-vr-controls-ui-menus.md` #5), carriage belly sweep (`cb7295fb` / Ledger 308), non-finite train-hull carry (`TrainHulls.swift:229`, Ledger 138), train curve speed (`Trains.swift:212`, Ledger 173), ridden train despawn (`Trains.swift:503`, Ledger 290), and `ShipMelt` frame-budgeting (`ShipMelt.swift:39`, Ledger 299).

---

## Ranked Findings

### 1. [Critical] `ShipManager.save` actively deletes `ships.json` if any single ship/felled-tree contains a non-finite float — wiping every player-built vehicle

- **Location:** `Sources/Ships.swift:1335-1360`, `1382-1407`, `1451-1496`
- **Problem:**
  1. `ShipManager.encode(_ snaps:)` (`Ships.swift:1382-1407`) returns `Data?` and collapses **two completely different outcomes into `nil`**:
     ```swift
     if out.isEmpty { return nil }
     return try? JSONEncoder().encode(out)
     ```
     Plain `JSONEncoder()` throws `EncodingError.invalidValue` on any `NaN` or `±infinity` float in *any* ship's `pos`, `rot`, `vel`, `angVel`, `liftLevel`, `hoverY`, `turretYaw`, `mount`, `pivot`, `home`, or any `BlockEntity` aboard any ship (including felled trees and toppled collapse pieces, which are also non-kinematic `Ship` instances saved in `ships.json`).
  2. `ShipManager.save` (`Ships.swift:1353-1356`) treats `nil` as "zero ships" and **deletes `ships.json` from disk**:
     ```swift
     guard let d = ShipManager.encode(snaps) else {
         if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
         return
     }
     ```
     One physics hiccup producing a single `NaN` in one felled tree or boat causes the next autosave to permanently wipe every player-built boat, airship, submarine, Sky Skiff, and salvaged aircraft in the dimension, with no log or toast.
  3. All four ship save files (`ships.json`, `takencaps.json`, `shipregions.json`, `navyparties.json`) use raw `JSONEncoder()` + `try? d.write(..., options: .atomic)` (`Ships.swift:1337-1358`) instead of `SaveIO.storeJSON` / `SaveIO.encoder()` — no `fsync`, no `.bak` backup, no disk-full error surfacing (`SaveIO.report`), and `load()`/`decode()` (`Ships.swift:1410-1418,1452`) silently drop all ships without `SaveIO.quarantine` or backup recovery.
- **Concrete suggested change:**
  - Separate empty-list handling from encoding failure in `ShipManager.save`: only delete `ships.json` when `snaps.isEmpty` (before encoding).
  - Sanitize non-finite floats per ship (`pos`/`rot`/`vel`/`angVel` fallback to finite defaults, skip corrupt entries with a warning) and encode/write all four files through `SaveIO.storeJSON` (or `SaveIO.encoder()` + `SaveIO.writeBytes` with `.bak` backup and `SaveIO.report`).
  - Route `load()` through `SaveIO.loadJSON` / `.bak` fallback + `SaveIO.quarantine` on decode failure.
- **Why it matters (players / store):** Permanent, silent loss of hours of player-built vehicles (and all chest inventories aboard them) from a single stray `NaN` is a severe data-loss bug and a direct risk to Meta Horizon Store retention/stability review.
- **Risk:** Low. Strictly safer error handling and persistence; preserves existing JSON schema.

---

### 2. [High] `dismountSpot` crashes (`Float -> Int` trap on `NaN`) when bailing out of a vertically pitched or 90°-rolled aircraft or flipped vehicle

- **Location:** `Sources/ShipPlay.swift:662-672`
- **Problem:**
  When leaving a Salvaged Fighter (`ShipPlay.swift:545`) or sidecar/motorcycle (`ShipPlay.swift:525`), `dismountSpot` projects the craft's `right` and `back` axes onto the XZ plane without checking for zero length:
  ```swift
  let right = s.dirToWorld(V3(1, 0, 0)), back = s.dirToWorld(V3(0, 0, 1))
  let r = simd_normalize(V3(right.x, 0, right.z)), bk = simd_normalize(V3(back.x, 0, back.z))
  ```
  - If an aircraft is pitched straight up or down (`back.x == 0 && back.z == 0`), or rolled 90° onto a wingtip (`right.x == 0 && right.z == 0`), `simd_normalize` returns `(NaN, NaN, NaN)`.
  - Even at moderate pitch + roll, `bk` and `r` can align horizontally (`bk == ±r`), making `simd_normalize(bk - r)` or `simd_normalize(-bk - r)` on line `669` return `NaN`.
  - Line `671` executes `let x = Int(floor(p.x)), z = Int(floor(p.z))` directly on `NaN`, triggering a Swift fatal trap (`Fatal error: Float value cannot be converted to Int because it is either infinite or NaN`) and instantly killing the Quest app.
- **Concrete suggested change:**
  - Build an orthonormal horizontal basis safely: fall back to `V3(cosf(s.yaw), 0, -sinf(s.yaw))` / `V3(sinf(s.yaw), 0, cosf(s.yaw))` (or `(1, 0, 0)` / `(0, 0, 1)`) whenever `simd_length_squared(V2(v.x, v.z)) < 1e-4`, derive `bk = V3(-r.z, 0, r.x)` so `r` and `bk` are guaranteed perpendicular (`bk ± r` always has length $\sqrt{2}$), and guard `p.x.isFinite && p.z.isFinite && mid.y.isFinite` before `Int(floor(...))`.
- **Why it matters (players / store):** Bailing out of a diving fighter or rolled sidecar is one of the most likely moments a player hits exit — a guaranteed hard crash in VR violates Meta Horizon Store VRC stability requirements (VRC.Quest.Functional.1).
- **Risk:** Very low. Purely defensive math fix on an exit helper.

---

### 3. [High] `restoreTaken` computes `engines0`, `wheels`, `engineCells`, `thrustCells`, and `reactorCells` from the *damaged* saved grid — permanently breaking repairs on reloaded captured capitals

- **Location:** `Sources/CapitalShips.swift:1182-1244`, `1346-1396`
- **Problem:**
  In `spawnCapital` (`CapitalShips.swift:1178-1244`), `asBuilt` is captured before overlaying `takenSave`, **but every damage/repair reference table is computed *after* `s.grid` has already been replaced with the battle-damaged saved grid**:
  - Lines `1183-1186`: `s.grid = ShipGrid(..., blocks: blocks); s.rebuild()` replaces the grid with the saved damaged hull.
  - Line `1210`: `st.engines0 = s.engines` sets the "100% engine baseline" to the *surviving* count instead of the as-built count.
  - Lines `1216-1232`: `st.thrustCells` and `st.reactorCells` only record thrusters/reactor blocks that were still intact at save time; destroyed ones vanish from the denominator forever.
  - Line `1237`: `st.wheels = Capital.vehicleWheels(s)` snapshots `w.orig` and `w.n0` from the **damaged** crawler grid. Any wheel that had blocks blown out before saving records `AIR` in `w.orig` and a shrunken `w.n0`, so `repairVehicle` (`CapitalShips.swift:1350-1369`) can **never** restore those blown-out wheel blocks with steel ingots after a reload.
  - Lines `1239-1243`: `st.engineCells` omits every engine block destroyed before saving, so `repairVehicle` (`:1380-1385`) cannot rebuild missing engine blocks directly (and `flyCommandeered` engine-socket smoke never appears at those sockets).
- **Concrete suggested change:**
  - Compute `st.engines0`, `st.thrustCells`, `st.reactorCells`, `st.wheels`, `st.engineCells`, and `st.groundOffset` from the fresh as-built `s` **before** applying `takenSave` to `s.grid`.
  - After overlaying `takenSave` onto `s.grid` and calling `s.rebuild()`, recount `st.thrustLive`, `st.reactorLive`, and each wheel's current block count `st.wheels[k].n` (and `wheelParts` blocks) against the restored damaged `s.grid`.
- **Why it matters (players / store):** Capturing a Meridian Frigate, Stormwarden Frigate, or Ironback Crawler almost always happens after crippling its wheels or engines. Reloading the world before finishing repairs permanently bricks wheel/engine repair on the player's prized endgame capital vessel.
- **Risk:** Low. Only reorders initialization inside `spawnCapital` for `takenSave != nil`.

---

### 4. [High] Capital Heron (`capplane`) has a sealed cockpit with no door and is omitted from `leaveHelm()` plane ejection; blast helm destruction also bypasses `leaveHelm()`

- **Location:** `Sources/Aircraft.swift:53-80`; `Sources/ShipPlay.swift:426,434,538-563`; `Sources/ShipCombat.swift:596-610`
- **Problem:**
  1. `Aircraft.heron()` (`Aircraft.swift:59-64`) builds a completely sealed 1-block-wide fuselage cabin (`x = -1...1`, floor `y = 1`, walls `y = 2...3`, roof `y = 4`, glass at `x = ±1, y = 3` and `x = 0, y = 4`) with **no doorway gap** (unlike `kestrel()` at `Aircraft.swift:26-28`).
  2. `commandeerable()` (`ShipPlay.swift:426,434`) lets the player board a Capital Heron from up to 8 blocks away (or 2.5 blocks from its hull), placing them inside the sealed cockpit.
  3. `leaveHelm()` (`ShipPlay.swift:543`) only runs cockpit-dismount and mid-air parachute bailout for:
     ```swift
     if s.name == AshWrecks.fighterName && s.parent == nil
     ```
     A commandeered Capital Heron (`role == "capplane"`, name `"Capital Heron"`) is completely missed. Exiting on the ground traps the player inside the sealed airframe (forcing them to mine out); exiting in mid-air leaves them trapped inside a falling plane with no parachute bailout.
  4. Separately, in `ShipCombat.swift:609`, when an explosion destroys the helm block of a ship the player is piloting:
     ```swift
     if pilot === s, let h = s.helm, destroyed.contains(h) { pilot = nil; s.piloted = false }
     ```
     - For **non-kinematic** ships (Salvaged Fighter, Capital Heron, sidecars, player builds), this clears `pilot` directly instead of calling `game?.leaveHelm()`, skipping plane/sidecar dismount/bailout and leaving `s.throttle`/`steer`/`climb`/`faceYaw` un-reset.
     - For **kinematic** ships, line `598` (`if s.helm == cell { s.helm = nil }`) already cleared `s.helm` *before* line `609`, making line `609` dead code on capitals.
- **Concrete suggested change:**
  - Broaden `ShipPlay.swift:543` to `(s.name == AshWrecks.fighterName || s.role == "capplane") && s.parent == nil` (or check a helper `isClosedCockpit(s)`), and optionally add a side entry door to `Aircraft.heron()` matching `kestrel()`.
  - In `ShipCombat.swift:596-610`, record `let lostHelm = pilot === s && s.helm.map { destroyed.contains($0) } ?? false` *before* mutating `s.helm = nil`, and call `game?.leaveHelm()` (falling back to clearing `pilot = nil; s.piloted = false; s.throttle = 0; s.steer = 0; s.climb = 0` only when `game == nil`).
- **Why it matters (players / store):** Getting permanently trapped in a sealed cockpit after commandeering a Capital plane is a jarring softlock in VR and repeats the exact Salvaged Fighter playtest failure (Nov 13) on a second aircraft.
- **Risk:** Low. Reuses the already-tested fighter bailout path.

---

### 5. [High] `ShipManager.setBlock` forgets to shift child turret `mountLocal`, own `pivot`, `damage`, `melt`, and gunner seats when `grid.grow` expands a ship

- **Location:** `Sources/Ships.swift:1240-1254`
- **Problem:**
  When a player places a block outside the current grid bounds of a non-kinematic ship or turret (any block on the `-X`, `-Y`, or `-Z` side), `s.grid.grow(toInclude: c)` shifts every block in `s.grid` by `shift` (`>= 0`). `setBlock` adjusts `s.com += sv`, `s.blockEntities`, and `target`, **but fails to shift**:
  - `t.mountLocal += sv` for every child turret `t` in `turrets(of: s)` — every mounted turret immediately teleports off its bearing ring by `-shift` blocks (often clipping into the hull or floating beside it).
  - `s.pivot += sv` when `s` itself is a turret (`s.parent != nil`) — the turret immediately jumps off its ring and rotates eccentrically around the wrong axis.
  - `s.damage` and `s.melt` dictionary keys (`k + shift`) — existing cracks/lava heat jump to unrelated blocks.
  - `VehicleGunners.seats` `local` coordinates for companions riding or manning `s`.
- **Concrete suggested change:**
  Inside the `if !s.grid.inside(c.x, c.y, c.z)` block (`Ships.swift:1242-1250`), when `shift != IVec3(0, 0, 0)`:
  - For each `t` in `turrets(of: s)`: `t.mountLocal += sv`.
  - If `s.parent != nil`: `s.pivot += sv`.
  - Remap `s.damage` and `s.melt` keys by `k + shift`.
  - Shift any `VehicleGunners.seats` entry whose `turret === s` (when `!rider && !station`) or `vehicle === s` (when `rider || station`) by `sv`.
- **Why it matters (players / store):** Customizing player-built ships and gun trucks with turrets is a core sandbox feature; adding a single block to the front, left, or underside of a ship with turrets visibly breaks every turret on the vessel.
- **Risk:** Low. Local coordinate bookkeeping only runs when `shift != .zero`.

---

### 6. [Medium] `Trains.through` and `Trains.leaveCab` run O(period / 0.1 s) brute-force scans (15,000–40,000 iterations) on the main thread, plus cross-world `tracks`/`throughOut` cache leak

- **Location:** `Sources/Trains.swift:363-392`, `455-465`, `641-649`, `985-1009`
- **Problem:**
  1. **Main-thread hitch on splice and cab dismount:** Both `Trains.through` (`:641-648`) and `Trains.leaveCab` (`:990-1001`) invert the timetable (`Track.at`) by brute-force stepping `u += 0.1` across the entire `t.period`:
     ```swift
     while u < t.period {
         let a = t.at(u - t.phase)
         ...
         u += 0.1
     }
     ```
     A spliced through-train spans 2–3 lines (~4,000–6,000 cells, round-trip ~10,000 cells at 7 b/s → `period` $\approx 1{,}500\text{–}2{,}200$ s). That runs **15,000–22,000 iterations** on the main thread in one frame — and `leaveCab` runs a **second** full scan (`:997-1001`, up to **40,000+ iterations**) if no leg runs in direction `d`. Every iteration calls `t.at()`, which does a linear scan of `legs` plus a binary search over `arc` (`sAt`), causing a noticeable VR frame drop right as the player crosses a link or steps off the locomotive.
  2. **Cross-world static cache leak:** `Trains.load(_ w: World)` (`Trains.swift:455-457`) resets `saved`, `trains`, `carOf`, and `TroopWrecks` when opening an overworld, **but never clears `tracks`, `trackMade`, `trackMaking`, or `throughOut`** (`:351-359,566`). Because `Railways.Line.id` is derived from `(row, stretch)` coordinates rather than world seed, cached `Track` instances (or in-flight worker results from `readyTrack` at `:378-389`) from a previous world can leak into a newly loaded world.
- **Concrete suggested change:**
  - Add a `Track.timeFor(s: Float, dir: Float, atStop: Int?) -> Double?` helper that iterates directly over `legs` (typically 4–20 entries): match dwell legs directly when `atStop != nil`, and on travel legs whose `[a, b]` range brackets `s` and matches `dir`, binary-search `f ∈ [0, 1]` for 16 steps (monotonic eased curve). This cuts 20,000–40,000 `at()` calls to ~20–60.
  - Clear `tracks`, `throughOut`, and (under `trackLock`) `trackMade`/`trackMaking` in `Trains.load` on overworld load, and tag async `readyTrack` work with a generation counter so stale results from a previous world are discarded.
- **Why it matters (players / store):** Eliminates a multi-millisecond VR hitch when driving through-trains or exiting the cab (important for Quest 3 72 Hz comfort / VRC frame-rate stability) and prevents ghost tracks after switching worlds.
- **Risk:** Low. Monotonic per-leg binary search is exact and easy to verify against the existing railway checks.

---

### 7. [Medium] Submarines lose `ballastLevel` and `depthY` on save/reload, and non-kinematic vessels/turrets drop `faction`, weapon stats, and `chip`

- **Location:** `Sources/Ships.swift:275-276`, `1265-1287`, `1363-1404`, `1451-1496`
- **Problem:**
  `ShipManager.Saved` (`Ships.swift:1265-1287`) persists `liftLevel` and `hoverY` for airships, **but omits `ballastLevel` and `depthY` for submarines** (`Ships.swift:275-276`). When a world is saved while a submarine is submerged and holding depth, reloading resets `ballastLevel = 0` and `depthY = nil`: the sub loses its buoyancy trim and either floats toward the surface or sinks until the player re-boards and re-trims it.
  In addition, `Saved` omits `faction`, `chip`, and custom turret weapon properties (`gunSpeed`, `gunGravity`, `gunPower`, `reloadTime`, `pitchMin`, `pitchMax`, `gunScatter`). Non-kinematic faction aircraft (e.g., Capital Kestrel / Capital Heron, spawned with `s.faction = Faction.steelhold.rawValue` in `Aircraft.swift:94`) reload with `faction = 0` (`.none`), and any non-default turret ballistics reset to baseline values on reload.
- **Concrete suggested change:**
  - Add optional fields (`ballastLevel: Float?`, `depthY: Float?`, `faction: Int?`, `chip: Float?`, and optional weapon overrides when non-default) to `ShipManager.Snap` and `ShipManager.Saved`, preserving backward compatibility with existing `ships.json` saves via `Optional` defaults.
- **Why it matters (players / store):** Submarines holding depth underwater stay parked where the player left them across sessions, and faction aircraft / turret vehicles preserve identity and tuning across save/reload.
- **Risk:** Very low. Additive optional fields in `Codable` `Saved` struct; fully backward-compatible with older saves.
