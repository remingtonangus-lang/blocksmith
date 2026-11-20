# Area 6 Review — Worldgen, Biomes, Structures, Dimensions & Far Scenery

**Base reviewed:** `origin/claude/quest-port` at `cb7295fb` (Ledger 385).
**Files inspected:** `Sources/WorldGen.swift`, `Sources/WorldGenTrees.swift`, `Sources/Terrain.swift`, `Sources/Structures.swift`, `Sources/DeepGen.swift`, `Sources/DeepSeam.swift`, `Sources/EmberGen.swift`, `Sources/Hollow.swift`, `Sources/Portal.swift`, `Sources/HellGate.swift`, `Sources/HellDrop.swift`, `Sources/Stronghold.swift`, `Sources/CapitalBases.swift`, `Sources/CapitalAir.swift`, `Sources/Greywall.swift`, `Sources/GreywallAlarm.swift`, `Sources/BorealStation.swift`, `Sources/BorealAlarm.swift`, `Sources/BaseObjectives.swift`, `Sources/FarRing.swift`, `Sources/FarForest.swift`, `Sources/FarSprites.swift`, `Sources/FarCitadel.swift`, `Sources/LandmarkRender.swift`, `Sources/CampSmoke.swift`, `Sources/WorldMap.swift`, `quest/src/vk/WorldRenderer.swift`, `quest/src/vk/SceneRenderer.swift`, `quest/shaders/farcard.vert`.

Ranked by player impact and Meta Horizon Store VRC compliance. Skips issues already fixed in `docs/status/bug-ledger.md` or covered in prior reviews.

---

## 1. [Critical] `BaseRecord.init(from:)` drops `parked` and `kestrelTaken` on every load — duplicating Kestrel helicopters inside each other on every reload

- **Where:** `Sources/CapitalBases.swift:65-66, 88-119`; `Sources/CapitalAir.swift:67-96, 133-138`
- **What happens:**
  1. `BaseRecord` declares `var parked: Int? = nil` and `var kestrelTaken: Bool? = nil` (`CapitalBases.swift:65-66`). Because `BaseRecord` uses the synthesized `encode(to:)`, both fields are written to `world.json`. However, the custom backward-compatible `init(from dec: Decoder)` (`CapitalBases.swift:88-119`) **omits both `parked` and `kestrelTaken`**. Every world load silently resets both to `nil`.
  2. When the player reloads near any visited citadel whose parked Kestrel was already saved in `ships.json`, `baseParked(_:_:)` (`CapitalAir.swift:67-96`) sees `r.kestrelTaken == nil`, `r.parked == nil`, and `padProblem(r) == nil` (`padProblem` only checks `world.solidAt` blocks, not existing ships), and spawns a **brand-new Kestrel at `pad + V3(0, 3, 0)` directly inside the already-parked Kestrel**. Every save/reload stacks another interpenetrating Kestrel on top of the previous ones.
  3. If the player steals a citadel's parked Kestrel (`r.kestrelTaken = true` at `CapitalAir.swift:74`), saves, and reloads, `kestrelTaken` resets to `nil` and a fresh Kestrel spawns on the helipad — both an infinite aircraft duplication exploit and a violation of the "the player flew it off: the citadel has no aircraft left" rule (`CapitalBases.swift:66`).
  4. Independently, in `baseAir(_:_:_:)` (`CapitalAir.swift:133-138`), if the player steals a Kestrel during a sortie (`ships.pilot === k`), `done("taken by the player")` clears `r.air` and `r.airShip` without setting `r.kestrelTaken = true`, so `baseParked` spawns a replacement on the pad on the very next second.
- **Concrete suggested change:**
  1. In `BaseRecord.init(from:)` (`Sources/CapitalBases.swift:110`), decode both missing fields:
     ```swift
     parked = (try? c.decodeIfPresent(Int.self, forKey: .parked))
     kestrelTaken = (try? c.decodeIfPresent(Bool.self, forKey: .kestrelTaken))
     ```
  2. In `baseParked(_:_:)` (`Sources/CapitalAir.swift:85`), before spawning a new parked Kestrel, also check if any existing `"kestrel"` ship in `ships.list` is already resting within 8 blocks of `pad` (and adopt its `id` as `r.parked`), healing saves that were already corrupted by the missing decoder lines.
  3. In `baseAir(_:_:_:)` (`Sources/CapitalAir.swift:133-138`), set `r.kestrelTaken = true` when `ships.pilot === k`.
- **Why it matters:** Players reloading near a Capital citadel get violently colliding/stacked helicopters on the helipad, multiplying ship physics and Vulkan draw calls on Quest 3 (hurting frame rate / `VRC.Quest.Performance.1`), and stealing a citadel's helicopter fails to persist across saves.
- **Risk:** Low. Strictly additive decoding (`decodeIfPresent`) + adoption guard for existing saves.

---

## 2. [Critical] Cross-world cache poisoning: stale `game.clock` timestamps freeze 5 landmark/map caches across world switches, and `FarCitadel.models` leaves phantom collision walls in World B

- **Where:** `Sources/LandmarkRender.swift:20-37, 75-120`; `Sources/CampSmoke.swift:13-41, 113-147`; `Sources/WorldMap.swift:26, 33-43, 346-350`; `Sources/FarCitadel.swift:32-65, 246-278`
- **What happens:**
  1. Five process-wide static caches compare `game.clock` against a static timestamp without checking `game.clock >= lastAt` or keying on world identity/seed:
     - `Renderer.citadelCache` (`LandmarkRender.swift:36`: `if game.clock - Renderer.citadelAt < 2`)
     - `Renderer.spireCache` (`LandmarkRender.swift:112`: `if game.clock - Renderer.spireAt < 2`)
     - `Renderer.campCache` (`CampSmoke.swift:19`: `if game.clock - Renderer.campAt < 2`)
     - `Renderer.townCache` (`CampSmoke.swift:118`: `if game.clock - Renderer.townAt < 3`)
     - `MapCache.tick` (`WorldMap.swift:346`: `guard g.clock - scanTimer > 1`)
     *(Ledger 385's new `greywallCache` at `LandmarkRender.swift:79` added `&& game.clock >= Renderer.greywallAt`, confirming the hazard, but the other five caches still omit it — and even `greywallCache` still shows World A's bases if World B's clock starts near or above World A's within 2 s.)*
     If a player spends 30 minutes in World A (`game.clock == 1800`), exits to the menu, and starts/opens World B (`game.clock == 0`), `game.clock - lastAt == -1800`:
     - All far citadels, ancient spires, camp smoke columns, village/capital night glows, and far town/Greywall boxes stay **frozen on World A's coordinates for the entire first 30 minutes of World B**.
     - **`MapCache.tick` stops discovering every village, citadel, Greywall base, Boreal Station, Capital city, Sky Isle, and vessel patrol for the entire first 30 minutes of World B.**
  2. In `MapCache.use(_:)` (`WorldMap.swift:34-35`), the fast-path guard compares `ObjectIdentifier(g) != genID`. If World B's `WorldGen` is allocated at the freed address of World A's `WorldGen` (the exact pointer-reuse bug already documented in `CapitalBases.swift:171` and `WorldMap.swift:113`), `MapCache.use` returns early and renders World A's map tiles over World B.
  3. `FarCitadel.models` (`FarCitadel.swift:32, 47-62`) is a static dictionary keyed only by `"citadel:\(x),\(z)"` / `"greywall:\(x),\(z)"` with no world seed and no clear on world switch. `FarCitadel.solid(_:_:)` (`FarCitadel.swift:246-260`) tests Tidebreaker main-gun shells against **every entry in `models.values`**, so up to 6 citadels/Greywall bases from World A remain as invisible solid collision blocks in empty air in World B (and `FarCitadel.hits` at `:263-276` carries smoke plumes across worlds).
  4. All five planning booleans (`Renderer.citadelPlanning`, `spirePlanning`, `greywallPlanning`, `campPlanning`, `townPlanning`) are unsynchronized `static var Bool`s mutated on `DispatchQueue.global(qos: .utility)` and read/written on the main/render thread (Swift data race).
- **Concrete suggested change:**
  1. Key `Renderer` landmark caches and `FarCitadel.models`/`hits` on `(worldSeed: UInt64, planSerial: Int)` (or `ObjectIdentifier` paired with a `weak` `WorldGen` reference); when the world changes, reset the cache arrays, timestamps (`-10`), `FarCitadel.models`, and `FarCitadel.hits`.
  2. Guard every elapsed-clock check with `game.clock >= lastAt && game.clock - lastAt < interval` (and in `MapCache.use(_:)`, check `gen === g` rather than `ObjectIdentifier(g) == genID`, and reset `scanTimer = -10` whenever `gen` changes).
  3. Synchronize the `*Planning` flags with an `NSLock` (or `OSAllocatedUnfairLock` / atomic) alongside the cache updates.
- **Why it matters:** Switching worlds from the pause/title menu is a core Meta Quest store test path (`VRC.Quest.Functional`). Seeing floating citadels/smoke from a previous save, hitting invisible phantom citadel boxes with Tidebreaker shells, and having map discovery silently dead for 30+ minutes look like severe world-corruption bugs.
- **Risk:** Low. Localized cache invalidation on world switch.

---

## 3. [High] Destroyed Boreal Station radar beacon permanently resurrects on save/reload and becomes indestructible

- **Where:** `Sources/BorealAlarm.swift:71, 150-173`
- **What happens:**
  - `BorealBeacon.standing(_:cx:cz:)` tracks whether a Boreal Station's radar dish has been destroyed using an in-memory `static var counts: [String: (n0: Int, n: Int, at: Double)]` (never persisted to `world.json` or `StationOp`):
    ```swift
    let n0 = max(counts[key]?.n0 ?? 0, n)
    counts[key] = (n0, n, g.clock)
    let up = n0 < 20 || n * 2 >= n0
    ```
    (`BorealAlarm.swift:164-166`).
  - During the session in which the player blows up the radar dish, `n0` was recorded while the dish was intact (~60 blocks), `n` drops below `n0 / 2`, and `up` becomes `false` ("The station's radar is down: they have lost track of you").
  - After saving and reloading the world, `counts` is empty. On the next tick, `standing` counts the rubble left on the mast (say `n = 0` or `n = 8`), sets `n0 = max(0, n) = n`, and evaluates `n0 < 20 || n * 2 >= n0` — which is **`true` for every destroyed dish** (`0 < 20` and `0 >= 0`).
  - Worse, once `n0 < 20`, **the player can never disable the radar again** because there are no dish blocks left to break: the station permanently spots the player by radar anywhere inside its fence or bunker (`BorealAlarm.swift:71`) and lays its guns on them forever.
  - Additionally, `BorealBeacon.counts` (`BorealAlarm.swift:156`) has the same `g.clock - c.at < 1` negative-clock freeze and static cross-world state (`counts`, `downTold`).
- **Concrete suggested change:**
  1. Persist `beaconDown: Bool` on `StationOp` (already saved per Boreal Station in `BorealOps.swift` alongside `blown` and `cleared`), or compare `n` against a fixed structural threshold (e.g., `BorealBeacon.intactBlocks` computed from the station blueprint, ~25+ non-natural blocks) instead of a volatile runtime maximum `n0` that treats `n0 < 20` as "up".
  2. When `n` falls below the threshold, mark `ops[key].beaconDown = true` (and ensure the `13×13` scan box `(x0 - 6)...(x0 + 6)` verifies all 4 corners are loaded via `w.isLoaded`, not just the center `(x0, z0)`, so a half-loaded chunk never falsely triggers destruction).
  3. Move `counts` / `downTold` onto `BorealAlarmState` (per-`Game`) and check `g.clock >= c.at`.
- **Why it matters:** Destroying the radar beacon is a flagship stealth/infiltration objective at Boreal Stations (P508). Having the destroyed dish silently resurrect and become unbreakable after a reload breaks stealth gameplay completely.
- **Risk:** Low. Uses the existing `StationOp` persistence path.

---

## 4. [High] Ledger 362 `FarForest.emitCards` clips far tree cards at `rin - 24` from the 128-block build-cell center, leaving 66–110 block bald treeless strips right outside loaded forests

- **Where:** `Sources/FarForest.swift:137-154, 235-260`; `Sources/FarRing.swift:97, 298, 306, 313-330, 452`; `quest/shaders/farcard.vert:50-52`
- **What happens:**
  - `FarRing` rebuilds only when the player crosses a 128-block cell boundary (`FarRing.swift:97`), so the player routinely stands up to `64` blocks in X and `64` blocks in Z — **`sqrt(64² + 64²) ≈ 90.5` blocks** — away from the ring's build center `(cx, cz)`.
  - `FarRing.build` explicitly accounts for both this cell offset and `ViewGovernor` render-distance step-downs by building terrain quads inward to `skip = min(rin - 100, rin * 0.55)` (`FarRing.swift:298`). When `forest != nil`, `S(_:_:)` (`FarRing.swift:313-330`) strips the canopy height lift (`s.y -= s.lift`) and green canopy tint off the ground across the entire `forestReach`, relying on `FarForest` to cover that ground with tree cards.
  - The card vertex shader (`quest/shaders/farcard.vert:50-52`) **already** clips cards dynamically against the player's live loaded disc (`float d = length(foot.xz - pc.m[1].xy); if (d < pc.m[1].z - 20.0) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); }`).
  - However, `FarForest.emitCards` (`FarForest.swift:139-143`) pre-culls tree cards on the CPU using `let from = rin - 24` measured from the **build cell's center `(cx, cz)`**!
  - Whenever the player approaches a cell edge (`64–90.5` blocks off `(cx, cz)`), the loaded chunk boundary on the near side pulls inward to `rin - 90.5` from `(cx, cz)`, while tree cards don't start until `rin - 24` from `(cx, cz)` — exposing a **up to 66.5-block-wide crescent of canopy-stripped, completely bald ground** directly outside the loaded forest edge. When `ViewGovernor` steps `renderDistance` down (e.g., 12 → 6, dropping `rin` from 188 to 92) before the background rebuild finishes, that bald ring widens to **~96 blocks** all the way around the player.
  - Secondary waste: in `FarForest.plan` (`FarForest.swift:235-260`), when `FarForest.cards == true`, the function still populates `all: [(Float, Tree)]` (~70k entries in a jungle) and `byRing` before immediately returning at line `260` (`if FarForest.cards { ...; return }`) without using either array.
- **Concrete suggested change:**
  1. Pass `from: max(0, skip)` (the exact inner radius `FarRing.build` already computes at `FarRing.swift:298`) into `forest.emitCards(gen, cx: cx, cz: cz, rin: rin, from: max(0, skip), into: &out)` and use `from` instead of `rin - 24` (`FarForest.swift:139`). The vertex shader (`farcard.vert:50-52`) continues to discard every card under loaded chunks at zero fragment cost, while covering the full 90.5-block cell wander and governor step-downs.
  2. In `FarForest.plan` (`FarForest.swift:235-260`), skip populating `all` and `byRing` when `FarForest.cards` is `true` (only populate `lists`, set `planReach = FarForest.reach`, and return), avoiding a ~70k-element temporary allocation on every cell crossing.
- **Why it matters:** Far Scenery (`FarRing.layer`) is enabled by default on Quest 3 as of Ledger 385 (`FarRing.swift:31`). Walking or flying toward any 128-block cell boundary in taiga, forest, or jungle currently exposes a stark bald belt of bare terrain between loaded trees and far cards.
- **Risk:** Low. Adds ~10–15% more card quads (still well below `SceneRenderer.maxQuads = 131,072` even in solid jungle) that are vertex-clipped when inside `rin - 20`.

---

## 5. [High] `Hollow.dragonDied` silently drops the End Gateway at radius 96 when that chunk is unloaded, yet still increments `gateways`

- **Where:** `Sources/Hollow.swift:309-328`
- **What happens:**
  - When the Ender Dragon dies, `dragonDied(_:)` computes the End Gateway position `(gx, gy, gz)` on a ring of **radius 96** (`6` chunks from `(0, 0)`) and writes the gateway blocks directly via `world.setBlock` (`Hollow.swift:321-327`):
    ```swift
    let gx = Int(round(96 * cos(a))), gz = Int(round(96 * sin(a)))
    let gy = YOFF + 75
    world.setBlock(gx, gy - 1, gz, BEDROCK)
    world.setBlock(gx, gy, gz, Blocks.id("end_gateway"))
    world.setBlock(gx, gy + 1, gz, BEDROCK)
    gateways += 1
    ```
  - `world.setBlock` silently no-ops if chunk `(gx >> 4, gz >> 4)` is not currently loaded.
  - On Quest 3, `ViewGovernor` commonly operates at `renderDistance = 5...6` (80–96 blocks), and even at `renderDistance = 8` a player standing on the opposite side of the ~100-block main island from `(gx, gz)` is 140+ blocks away — so `(gx >> 4, gz >> 4)` is unloaded.
  - All three `setBlock` calls are dropped, no End Gateway exists anywhere on the island, yet `gateways += 1` still runs (and `first` is consumed). On the first dragon kill, the player is locked out of the outer End islands (and the jetpack End Ship) unless they craft crystals to respawn and re-kill the dragon (or bridge 1,000 blocks over the void).
- **Concrete suggested change:**
  - Before writing the gateway blocks at `Hollow.swift:324-326`, ensure the target chunk is loaded synchronously (or queue a persistent pending-gateway placement in `EndState` that stamps the gateway the moment `(gx >> 4, gz >> 4)` loads), and similarly ensure `(0, 0)` is loaded before `HollowGen.fountainBlocks` activates the exit portal (`Hollow.swift:317`).
- **Why it matters:** Losing the first End Gateway after beating the Hollow boss is a severe progression soft-lock on Quest 3 at normal VR view distances.
- **Risk:** Low. Loading 1 chunk on a once-per-boss-kill event (or stamping on chunk load) has negligible cost.
