# Area 2 Review: VR Controls, Locomotion, HUD & Menus

Scope: `quest/src/app/`, `Sources/Menu*.swift`, `Sources/PauseMenu.swift`, `Sources/CombatHUD.swift`, `Sources/WorldMap.swift`, `Sources/VRMelee.swift` on `origin/claude/quest-port` (`89369b4`).
Excludes findings already covered in `docs/status/neon-review-2.md` (#4 Teleport, #5 laser text input, #8 `HudPanel`, #9 roomscale ship walls, #10 PauseMenu/WorldStore polish) and `docs/status/neon-reviews/playtest-2026-11-20.md` (#6 VR hand visuals). Findings ranked by value.

---

### 1. Advertised `"Controls: One Hand"` accessibility preset is unplayable (missing Use/Place/Eat, Inventory, Pause, Reload, and Bow)
- **Evidence:**
  - `quest/src/app/QuestOptions.swift:128,233,358,365,380` exposes `"Controls: One Hand"` (`QuestSettings.controlPreset == 2`) in First-Launch Setup and Options.
  - `quest/src/app/QuestHands.swift:79-85` is the **only** place in the entire codebase that implements `controlPreset == 2`, and it remaps **only** forward/back walking onto the dominant stick.
  - Every other core interaction stays stranded on the absent off-hand controller:
    - **Use / Place / Eat / Open Chest / Talk (`L.trigger` → `trigBtn[0]`, `QuestControls.swift:344`):** No mapping on the dominant hand. A one-handed player cannot place a block, eat, open a chest/crafting table, or board a vehicle.
    - **Inventory (`Y`, `L.button2`, `:754-771`) & Pick/Reload (`X`, `L.button1`, `:739-752`):** Unreachable on the dominant hand.
    - **Pause / Recenter (`Menu`, `QuestHands.swift:66`):** Bound strictly to physical left controller `src[0].menu` — unreachable for a right-handed one-hand player.
    - **Bow (`QuestControls.swift:476-477,1586-1631`):** Requires `L.aimValid` + `L.trigger` to nock and draw; completely non-functional one-handed.
- **Recommended fix:** When `controlPreset == 2`, map full single-controller chords on the dominant controller (e.g., `B` tap = Use/Place, `B` hold = sneak/drop, `A` hold or grip+stick click = Inventory/Pause, auto-enable `VRReload.buttonMode` with a dominant-hand reload, and allow single-trigger bow draw when `lost[0]`). Until those mappings exist, remove `"One Hand"` from First-Launch Setup so accessibility buyers aren't stranded.
- **Expected effect:** Turns a broken advertised accessibility preset into a working control scheme and protects Meta Horizon Store accessibility expectations.
- **Risk:** Low (gated behind `QuestSettings.controlPreset == 2`).

---

### 2. VR Bow draw collapses to `0.0` when the drawing hand leaves Quest 3 tracking cameras beside the cheek
- **Evidence:** `quest/src/app/QuestControls.swift:1586-1630`:
  - Natural VR archery draws the off-hand back to the cheek/jaw, which routinely leaves Quest 3's forward-facing tracking cameras for 0.1–0.5 s (`L.aimValid == false`).
  - Line `1600`: `let pose = VRBow.pose(grip: grip, handRot: rot, drawHand: bowNocked && L.aimValid ? L.aimPos : nil)`.
  - On any single frame where `L.aimValid` drops while `bowNocked == true`, `drawHand` becomes `nil`: `pose.draw` snaps instantly to `0.0` and `pose.dir` snaps to straight-ahead. Releasing the trigger during that blink either aborts the shot or drops a zero-power arrow at the player's feet (`game.vrBow.draw == 0`), and regaining tracking re-triggers `bowCreak` / `bowTick` haptics.
- **Recommended fix:** While `bowNocked`, store the last valid `L.aimPos` relative to `rig.trackingHead` (`lastDrawHeadRel`). When `L.aimValid` is briefly `false` (up to ~1.0 s while `trig` remains held), supply `rig.trackingHead + lastDrawHeadRel` to `VRBow.pose` so cheek-anchored full draw holds steady and looses cleanly.
- **Expected effect:** Eliminates misfired/dropped arrows during natural cheek-draw archery on Quest 3.
- **Risk:** Very low.

---

### 3. Standing auto-sit (`rig.sitAt`) fires while physically ducking in tunnels or behind cover, shoving the player's head into the ceiling
- **Evidence:**
  - `quest/src/app/QuestControls.swift:1282-1297` & `quest/src/app/QuestRig.swift:161-167`: In Standing play, if the player's head stays `> 0.45 m` below eye height and moves `< 0.15 m/s` for 3 seconds (`lowStill > 3`), `rig.sitAt(head.y)` raises `heightOffset = QuestRig.eyeHeight - head.y`.
  - There is **no ceiling-clearance check** (`!player.collides` at standing height) and no check against active combat/cover. If a standing player physically crouches inside a 1.5-block tunnel or under an overhang and pauses for 3 s (to mine, aim, or take cover behind a low wall), `sitAt` abruptly snaps their eye height straight up into the solid ceiling — triggering black `wallFade` (`:1024`) and clearing `game.player.ducking = false` (`:1297`), popping their hitbox up into enemy fire.
- **Recommended fix:** Before calling `rig.sitAt(head.y)` (`:1290`), require headroom above the player (`!game.world.collides(at: standingBox)`) and increase the stillness threshold (e.g., 5–6 s with no trigger/combat activity), or show a quick `"Seated height set"` toast so the player knows why their camera shifted.
- **Expected effect:** Stops players from getting black-screened (`wallFade`) when physically crouching under low roofs or taking cover in firefights.
- **Risk:** Very low.

---

### 4. `MapCache` address-aliasing bug shows the previous world's map after a world switch + sudden full-map wipe at 400k cells
- **Evidence:**
  - `Sources/WorldMap.swift:32-43`: `MapCache.use(_ g: TerrainGenerator)` checks `guard ObjectIdentifier(g) != genID else { return }`. On a world switch or dimension reload, if the previous `WorldGen` is deallocated and the new `WorldGen` allocates at the same heap address (the exact bug `MapCache.railGen` already had to fix with `gen.planSerial` at `:113`!), `use()` returns early without clearing `cells` — rendering the **previous world's biome map** on the new world's minimap and world map!
  - `Sources/WorldMap.swift:104`: `if cells.count > 400_000 { cells.removeAll() }` wipes the entire cache in one shot once explored area crosses 400k 4-block cells (~2.5×2.5 km), causing the minimap/world map to suddenly blank out grey until re-sampled.
- **Recommended fix:** Key `MapCache.use` on `(g.seed, type(of: g))` / `planSerial` (or store a weak ref + monotonic `genSerial` on `TerrainGenerator`) instead of `ObjectIdentifier(g)`. Replace `cells.removeAll()` with partial eviction (drop cells farthest from the player or keep the most recent half).
- **Expected effect:** Eliminates wrong-world minimap corruption after world switches and removes sudden mid-exploration map blanking.
- **Risk:** Very low.

---

### 5. Chase-view vehicle aiming (`aimGame`) stops at loaded chunks, making long-range frigate/crawler aiming drift off-target
- **Evidence:** `quest/src/app/QuestControls.swift:1369-1388`:
  - When piloting a capital ship or tank in chase view (`simd_length(app.rig.chase) > 0.5`), `aimGame()` casts a ray from `aimOrigin` out to `TankSight.shipReach` against `w.raycast` (loaded chunks only) and `w.ships.list`.
  - When aiming a Meridian Frigate's Tidebreaker at a fortress or terrain **beyond loaded chunks** (e.g. 200–400 m out at view 8–12, as in the Nov 20 playtest `06:55:10`), `w.raycast` hits nothing, leaving `t = TankSight.shipReach` in mid-air; `aimGame` then computes `d = simd_normalize(p - game.player.eye)` from the helm to that arbitrary far point, introducing parallax error relative to the laser's true terrain/target intersection.
- **Recommended fix:** When `w.raycast` misses in chase view, march/intersect the ray against `FarCitadel.solid` and the coarse heightfield (`world.gen.column`) so `chaseAimPoint` lands on the actual distant base/ground the player is pointing at.
- **Expected effect:** Makes long-range Tidebreaker and crawler turret aiming match the VR laser past loaded chunk distance.
- **Risk:** Low.

---

### 6. Left-handed mode spatial & haptic mismatches + dead `hotbarPointer` code & framerate-dependent `hoverRest`
- **Evidence:**
  - `quest/src/app/QuestControls.swift:532-536`: Chest-pocket journal grab hardcodes `- right * 0.11` (left breast) for `R` (`aimHand`). In Left-Handed mode (`QuestSettings.leftHanded == true`), `R` is the physical left hand, forcing a cramped same-side reach instead of mirroring to `+ right * 0.11`.
  - `quest/src/app/QuestControls.swift:809` + `quest/src/app/QuestHands.swift:66`: Holding physical-left `Menu` to recenter sends the confirmation buzz to `moveHand` (`hands[0]`) — which in Left-Handed mode is the **physical right controller**, not the hand holding `Menu`.
  - `quest/src/app/QuestControls.swift:1726`: `hoverRest += 1.0 / 72` hardcodes 72 Hz instead of `dt` (shortening the R5 anti-accidental-craft guard by 25% at 90 Hz / 40% at 120 Hz).
  - `quest/src/app/QuestControls.swift:1728`: Leaving the panel edge while dragging a stack across inventory slots (`MenuInput.swift:147-159`) sets `input.leftDown = false`, prematurely aborting/committing the drag mid-gesture.
  - `quest/src/app/QuestControls.swift:1654-1675`: `hotbarPointer(_ R: XRHand)` is completely uncalled dead code (`hotbarHover` is always reset to `nil` on `:841`).
- **Recommended fix:** Mirror chest pocket by `QuestSettings.leftHanded ? 1 : -1`; send Menu-recenter haptic to physical left (`QuestSettings.leftHanded ? aimHand : moveHand`); pass `dt` into `menuPointer` for `hoverRest`; keep `input.leftDown = trig` while `!game.menuDrag.isEmpty` even if the laser momentarily leaves the panel edge; remove dead `hotbarPointer` (or wire it behind an explicit option if desired).
- **Expected effect:** Cleaner left-handed ergonomics, consistent 90/120 Hz menu safety timing, and smoother inventory stack dragging.
- **Risk:** Very low.
