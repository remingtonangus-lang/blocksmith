# Quest 3 Render-Distance & 72 fps Code Review

Goal: hold **view distance ≥ 12 chunks** most of the time at a steady **72 fps** (13.89 ms GPU/CPU budget, 0 s < 60 fps, < 2% < 70 fps on `tools/headset_gate.sh --route all`).

**Short answer:** Two separate walls keep the store build stuck at view 6–8:
1. **A stale software cap** (`ViewGovernor.quadCap = 105_000`, `startView = 6`, `quadFloor = 6`) calibrated *before* Ledger 235's shader rewrite still forces launches to view 6 and permanently locks wooded biomes at 6–8 even when the GPU has headroom.
2. **Real GPU headroom is still too thin for view 12 at 100% eye resolution**: after Ledger 235, Quest 3 at fixed view 8 / 100% eye res already uses **11.39–12.40 ms** of the 13.89 ms budget (`docs/status/bug-ledger.md:309`). Simply raising `quadCap` without cutting GPU cost will push view 12 over 13.9 ms in jungle/taiga. Steady-state CPU is **not** the blocker (headset CPU 1.2–3 ms, Ledger 234).

---

## Causes Ranked by Impact

### 1. Stale `quadCap = 105_000`, `startView = 6`, and overly sticky governor rules (costs **4–10 chunks** of view distance directly)
- **Evidence:**
  - Ledger 234 (`docs/status/bug-ledger.md:308`, build `4de891e5`) measured Quest 3 *before* the Ledger 235 shader rewrite: at 60% eye res, view 6 held 72 fps (jungle 102k quads, 12.7 ms) while view 8 missed (jungle 141k, 14.1 ms; taiga 66–69 fps). It set `ViewGovernor.quadCap = 105_000`, `quadFloor = 6` (`Sources/ViewGovernor.swift:61-62`), and `QuestSettings.startView = 6` (`quest/src/app/QuestSettings.swift:126`).
  - Ledger 235 (`docs/status/bug-ledger.md:309`, build `0b790b21`) cut GPU time roughly in half at fixed view 8 / **100% eye res** (jungle 24.27 → 12.40 ms, taiga 21.80 → 11.92 ms, savanna 17.58 → 11.39 ms, forest 13.89 → 12.00 ms; full 8-min route held 72 fps at 100% eye res throughout). `quadCap` was never recalibrated, and Ledger 298 (`quest/src/app/QuestApp.swift:969,982-999`) also applied the 105k cap when Auto View is OFF.
  - Raise guard (`Sources/ViewGovernor.swift:220-221`) requires `quads * (next/current)^1.2 <= 94_500`. In jungle (102k at view 6) `102k * (8/6)^1.2 = 144k > 94.5k` → **locked at 6 forever**. In taiga/forest (~88–141k at view 8) → **locked at 8 forever**. Any 1-second spike over 105k immediately drops view via `overQuads` (`:151-160`).
  - Even in open plains, climbing 6 → 8 → 10 → 12 takes ≥ **135–159 s** (`baseHold = 45.0` s + `settle = 8.0` s per step, `:38,44`), and any single frame-miss drop caps raises with `lid` for **10 minutes** (`lidFor = 600.0`, `:44,189,199,215`).
  - `ViewGovernor.scaleAt` (`:115-126`) refuses to raise view if predicted dynamic-res scale falls below `keepScale = 0.85` (leaving 0.85 → 0.60 dynamic resolution headroom unused) and scales geometry by `exponent = 1.2` despite headset measurements of `0.68` (jungle) and `0.9` (taiga) (`:56,331`).

### 2. Solid & cutout fragment shader cost still eats ~7–9 ms at view 8 (costs **~3.5–5.5 ms GPU**)
- **Evidence (`docs/status/bug-ledger.md:309`, fixed view 8, 100% eye res):**
  - `QUEST_SKIP=solid`: jungle 6.4 ms, taiga 2.6 ms, savanna 2.9 ms, forest 4.8 ms.
  - Plain single-fetch shader (`BS_FXADD=2048`): jungle 12.0 (+5.6), taiga 6.4 (+3.8), savanna 6.1 (+3.2), forest 8.5 (+3.7) ms.
  - Shipped `mainLean()` (Ledger 235): jungle 12.40 (+6.0), taiga **11.92 (+9.3)**, savanna **11.39 (+8.5)**, forest **12.00 (+7.2)** ms.
  - Even accounting for run-to-run clock differences, `mainLean()` costs **~3.5–5.5 ms more** than plain texturing in ground-heavy biomes.
- **Root causes in shader code:**
  - **Dead `mainOld()` register bloat (`quest/shaders/chunk_solid.frag:21-40,126-195`):** `main()` still compiles all of `mainOld()` (global `vec2 triUV[3], triGX[3], triGY[3]` = 18 floats, `triTex()`, nested 4×4 corner-blend loops, `textureGrad`) into the same SPIR-V binary behind a runtime UBO bit (`fxOn(524288)`). Adreno 740 allocates GPRs statically across the whole shader, hurting wave occupancy even when `mainLean()` returns early at `:127`.
  - **Unconditional ALU + divergent 2nd fetch in `mainLean()` (`chunk_solid.frag:47-109`, `common.glsl:44-56,158-164`):** calls `textureSize(tex, 0)` every fragment; computes `dFdx/dFdy(wp)` + `dFdx/dFdy(uv)` + Ledger 266's `cross(dx,dy); length(fn); fn /= fl` (`:63-71`, added *after* Ledger 235); runs `sharpUVs` (with `mod()`) + `log2` + `textureLod`; runs the 4-corner material-blend unpack (`:93-109`) on every smooth-terrain fragment **and** every far leaf blob (`Mesher.swift:2352-2355` emits `blobFar` via `groundVert`, which sets `uu=30` → `tri=true`, `oLW!=0` in `chunk.vert:61,150`), firing a divergent 2nd `texAt` on borders (Ledger 235 measured corner blend alone at **4.6 ms** in taiga).
  - **`detail` pipeline shares `chunk_solid.frag` (`SceneRenderer.swift:656`):** `chunk_detail.vert:66-68` always outputs `oLW=0, oLayers=0, oNrm=0`, yet every tree trunk/rock pays `chunk_solid.frag`'s full register footprint and branches.
  - **`chunk_cut.frag` (`quest/shaders/chunk_cut.frag:26-36`):** runs `textureSize`, `dFdx/dFdy`, `turnOf`, `turnUV`, `sharpUVs`, `log2`, `textureLod` before `discard` (which also disables Early-Z on Adreno). Leaving out solid leaves 6.4 ms in jungle largely from cutout foliage + `detail` + sky/water.
  - **Cannot know exact split without headset measurement:** how much of the 3.5–5.5 ms gap is `mainOld()` register occupancy vs Ledger 266 `cross/length` vs corner blend vs `sharpUVs`/`log2` vs `pow(c, 2.2)` (`common.glsl:248`).

### 3. Fixed/Dynamic Foveated Rendering is OFF by default (leaves **~1.5–3.5 ms GPU** on the table, headset-dependent)
- **Evidence:** `QuestSettings.foveation` defaults to `0` (`quest/src/app/QuestSettings.swift:141`), and `XRSession.applyFoveation` hardcodes `XR_FOVEATION_DYNAMIC_DISABLED_FB` (`quest/src/xr/XRSession.swift:470`). Every frame shades full pixel density to the lens corners even though `VK_EXT_fragment_density_map` is already wired (`XRSession.swift:355-394`, `SceneRenderer.swift:408-426,964-976`).
- **Complication:** `QuestApp.swift:601` disables `DynamicResolution` whenever `xr.foveated` is true (unless `BS_FOVDYN=1`, `:485`) because shrinking the viewport to a corner sub-rect misaligns with a full-image FDM. Using `XR_FOVEATION_DYNAMIC_LEVEL_ENABLED_FB` (runtime scales foveation automatically under GPU load) avoids that conflict — exact ms gain and visual periphery softness **must be measured on the headset**.

### 4. LOD, culling, and batching cutoffs miss the view 8–12 band (costs **~20–40% excess quads** and extra draw calls at view 12)
- **`GroundMerge.farDistance = ~180 blocks` (11.25 chunks) (`Sources/GroundMerge.swift:21`):**
  - At view 12 (192 blocks), `mergedFar` (`SceneRenderer.swift:1723-1729,2779`) only activates on the outer 12 blocks (< 1 chunk). ~90% of view 12 draws full near-detail ground (`0.05` block tol), full bevelled chamfers, and full ground drapes instead of the `farCopy` already sitting in VRAM.
  - **Worse: buried-cave culling (`sealLow`, P392) is also gated on `GroundMerge.farDistance` (`SceneRenderer.swift:2292,2301`)!** At view 12, buried caves 2–11 chunks out are not seal-culled (and `smoothWalls` peeks all 26 neighbors, `:2364-2378`).
- **Tree/foliage LODs leave too many cutout/detail quads in jungle & taiga:**
  - `SceneRenderer.swift:1740-1759`: `blobFarFrom = 64`, `plantFarFrom = 64`, `trunkFarFrom = 32`, `canopyFrom = 1e9` (`BS_CANOPY` off, `Mesher.swift:2644-2647`). At view 24, 85% of jungle's 703k quads are past 64 blocks (`docs/roadmap/backlog.md:23`), and `canopy` + `canopyLogs` is gated on `far` (`>= 180` blocks, `SceneRenderer.swift:2796`).
- **`World.lodNear = 99` on Quest (`quest/src/app/QuestApp.swift:36`) disables two F5 ocean optimizations:**
  - `underDeepWater` / `deepWaterAbove` (`SceneRenderer.swift:1707,2156`) checks `c.lod == 1` → **dead on Quest**, even though `water.frag:145` already zeroes seabed transmittance past 76 blocks.
  - `drawFarTranslucentBatched` / `drawFarTranslucentBatchedT` (`SceneRenderer.swift:1996,2956`) checks `c.lod == 1` / `lod1` → **dead on Quest**, issuing per-section `vkCmdDrawIndexed` calls for all water sections.
- **Pass order (`SceneRenderer.swift:2739-2922`):** `drawOpaqueBatchedT` draws terrain `solid` → `cut`, *then* `detail` (solid trunks/rocks) → `detailCut`. Solid `detail` trunks don't prime the depth buffer before alpha-tested `cut` leaves.

### 5. Perceived draw distance & unused platform headroom (fog wall + `FarRing` off + GPU clock level + SpaceWarp)
- **Fog wall + `FarRing` off (`WorldRenderer.swift:223-225,240-244`, `QuestSettings.swift:116`):** Under Auto View, `clearStart = 0.7` starts opaque-ramping fog at **70% of view** (59 blocks at view 6, 81 at view 8, 126 at view 12), and `FarRing` is hidden because `farLayer` defaults to `false` (Ledger 361's `FarForest` low-poly horizon out to 560 blocks is built & tested on host but unmeasured on headset).
- **GPU clock capped at `SUSTAINED_HIGH` (`XRSession.swift:757-773`):** Headset logs showed `545 MHz` (Ledger 231) and `640 MHz` of `690 MHz` (Ledger 234) while 90–98% busy. `BS_GPULEVEL=boost` (`XR_PERF_SETTINGS_LEVEL_BOOST_EXT`) exists but is untested for steady-state/thermal behavior; also `XR_META_recommended_layer_resolution` (`XRSession.swift:182`) may gate top clocks (headset-only check).
- **SpaceWarp (`QuestSettings.swift:151`, Ledger 232):** doubles GPU budget to 27.8 ms (36 → 72 Hz) and now computes real depth motion vectors, but is unverified visually by Remington and adds depth-store + motion-pass overhead (disables `TRANSIENT_ATTACHMENT` depth, `SceneRenderer.swift:374,970`). Keep as fallback only.

---

## Recommended Changes (Implementation Order)

### Phase 1 — Zero/low-risk GPU & culling wins (get view 12 under 13.9 ms first)

#### 1. Strip `mainOld()` out of `chunk_solid.frag` & give `detail` / `blobFar` a lean shader
- **Files:** `quest/shaders/chunk_solid.frag:21-40,43-124,126-195`, `quest/shaders/common.glsl:44-56,158-164,248`, `quest/src/vk/SceneRenderer.swift:653-657`, `quest/src/vk/WorldRenderer.swift:305`
- **Change:**
  1. Remove `mainOld()`, `triW`, `triUV[3]`, `triGX[3]`, `triGY[3]`, `triTex()`, and the `BS_FXADD=524288` branch from `chunk_solid.frag` (or compile it as a separate debug pipeline only when `fxAdd & 524288 != 0`) so Adreno 740 doesn't allocate registers for dead code.
  2. Create a dedicated `chunk_detail.frag` for the `detail` pipeline (`SceneRenderer.swift:656`) with no triplanar, no `oLW` corner blend, no lava/turn/sheen branches (just `texAt` / `texture` + fog + `worldColor`).
  3. Pass texture resolution as a uniform (or constant `u.misc`/push constant) instead of calling `textureSize(tex, 0)` per fragment (`chunk_solid.frag:47`, `chunk_cut.frag:28`).
  4. In `chunk_solid.frag:93`, skip the corner-blend block when `oDist > 96.0` (6 chunks; far biome borders are sub-pixel/mip-blended) and for `blobFar` (encode a flag or skip `oLW` in `chunk.vert:150` when `tintMode == 2u`, since foliage blobs never blend two ground materials!).
  5. Replace `sharpUVs` `mod(seam, sz)` (`common.glsl:53`) with `fract(seam / sz) == 0.0` (or skip `sharpUVs` when `d >= 1.0`, i.e., minified distant terrain, and test `texture()` vs `texAt()` on headset). Test replacing `pow(c, vec3(2.2))` (`common.glsl:248`) with `c * (c * (c * 0.305306 + 0.682171) + 0.012522)` (exact sRGB within 0.5/255, zero `pow`).
- **Expected gain:** **~2–4 ms GPU** in taiga/savanna/forest, ~1–2 ms in jungle (exact split between register occupancy, corner blend, and `sharpUVs`/`pow` **cannot be known without headset measurement**).
- **Risk & quality trade-offs:** Removing `mainOld()` only drops the `BS_FXADD=524288` diagnostic toggle. Skipping corner blend past 96 blocks makes distant material boundaries revert to per-quad vertex material (hardly visible past 6 chunks; verify with host `--view` screenshot diff). `chunk_detail.frag` has zero visual change.
- **How to measure:** `tools/headset_gate.sh --route spots --env "BS_VIEWFIX=12;BS_DYNRES=0"` before vs after; compare GPU ms per spot against `BS_FXADD=2048` floor. Also run host visual regression shots on jungle/taiga/farm border.

#### 2. Enable Fixed/Dynamic Foveated Rendering by default
- **Files:** `quest/src/app/QuestSettings.swift:141`, `quest/src/xr/XRSession.swift:355,462-487`, `quest/src/app/QuestApp.swift:115,485,601`
- **Change:**
  1. Change default `QuestSettings.foveation` from `0` to `2` (Medium) — or `3` with dynamic foveation: set `lp.dynamic = XR_FOVEATION_DYNAMIC_LEVEL_ENABLED_FB` in `XRSession.applyFoveation` (`:470`) so the runtime lowers peripheral density only when GPU load rises.
  2. First A/B test on headset with `BS_FOVEATION=2` (dynRes off) vs `BS_FOVEATION=2;BS_FOVDYN=1` (verify whether Meta's runtime maps FDM to the `viewExtent` sub-rect or full swapchain; if misaligned, keep `dynRes` disabled while foveated and rely on dynamic foveation + ViewGovernor).
- **Expected gain:** **~1.5–3.5 ms GPU** (15–30% fragment-bound savings on Quest 3; **must be measured on headset**).
- **Risk & quality trade-offs:** Slight softening at the extreme outer lens periphery (center gaze stays 100% sharp). Dynamic foveation (`level=2` or `3`) keeps edges sharp when GPU has headroom. `BS_FOVDYN=1` risks an off-center sharp region if the runtime doesn't remap FDM to sub-image rects — check visually in headset before enabling both together.
- **How to measure:** `tools/headset_gate.sh --route spots --env "BS_VIEWFIX=12;BS_DYNRES=0;BS_FOVEATION=2"` vs `BS_FOVEATION=0`, plus visual check in headset.

#### 3. Fix dead/too-far culling & pass order (`sealLow`, `underDeepWater`, water batching, `solid+detail` before `cut`)
- **Files:** `quest/src/vk/SceneRenderer.swift:1707,1996,2156,2292,2301,2739-2922,2956`
- **Change:**
  1. **`sealLow` distance (`SceneRenderer.swift:2292`):** decouple buried-cave culling from `GroundMerge.farDistance` (180 blocks) and use a dedicated `sealDistance = 48` (or `64`) blocks. Above ground, sealed caves 3–4+ chunks away are completely enclosed underground.
  2. **Deep-sea seabed culling (`:1707,2156`) & far water batching (`:1996,2956`):** replace `c.lod == 1` / `tabCol[...].lod1` with a distance check (`d >= 80` blocks for `deepWaterAbove`, matching `water.frag:145`'s 60–76 block opacity ramp; `d >= 64` blocks for batched water). Note: `deepWaterAbove` is cached in `fillColumn`, so compute the flag unconditionally for any all-water-above section and gate the skip in `cullT:2332` on distance `>= 80` blocks.
  3. **Draw order (`:2739-2922`):** draw terrain `solid` and `detail` (both depth-writing, no `discard`) **before** `cut` and `detailCut`, so solid tree trunks and rocks reject hidden cutout leaf fragments via Early-Z.
- **Expected gain:** **0.5–1.5 ms GPU** in cave-rich hilly terrain, forests, and oceans; fewer draw calls over water (exact GPU ms **must be measured on headset**; quad reduction measurable on host via `SceneRenderer.kindBreakdown()` / `--perfscenes`).
- **Risk & quality trade-offs:** **Zero visual quality trade-off** if distances are respected (`sealLow` already preserves cave mouths and 26-neighbors of sky-open sections; `water.frag` is already 100% opaque past 76 blocks). Verify no cave-mouth pop-in via `voidsweep` / `--perfscenes`.
- **How to measure:** Host `questcheck --perfscenes` (check `sealedSkipped`, `deepSeaSkipped`, `drawCalls`, `drawnQuads`) + headset `--route spots --env "BS_VIEWFIX=12"`.

#### 4. Pull terrain & foliage LOD switches into the view 8–12 range
- **Files:** `Sources/GroundMerge.swift:20-21`, `quest/src/vk/SceneRenderer.swift:1740-1759,2773-2816`, `Sources/Mesher.swift:2644-2647`
- **Change:**
  1. **`GroundMerge.farDistance` (`GroundMerge.swift:21`):** lower from ~180 blocks to **96–112 blocks** (6–7 chunks, via `BS_FARDIST` switch for A/B). At 112 blocks, `1/8` block is ~1.6 Quest 3 center pixels (and < 1 pixel under dynamic resolution or outside the fovea); this finally activates `farCopy` ground, plain built-block faces, and far drapes for the outer **60–70% of view 12's area**!
  2. **Foliage cutoffs (`SceneRenderer.swift:1740,1759`):** test lowering `blobFarFrom` from `64` → `48` blocks (moves more jungle/taiga leaves out of alpha-tested `chunk_cut.frag` into simplified solid `blobFar`) and `plantFarFrom` from `64` → `48` blocks.
  3. **Far canopy tier (`Mesher.swift:2644-2647`, `SceneRenderer.swift:1749,2796`):** enable `Mesher.canopy` (and test `canopyLogs`) from **112–128 blocks** (decoupled from 180) so dense jungle/taiga canopies beyond 7–8 chunks drop another 10–15% of quads (host-measured at view 24 in `backlog.md:23`; gain at view 12 needs host + headset measurement).
- **Expected gain:** **~15–30% fewer drawn quads** at view 12 in jungle/taiga/forest (estimated **1.5–3 ms GPU**; exact ms **must be measured on headset**).
- **Risk & quality trade-offs:** Slight geometric simplification of hills/chamfers between 6–11 chunks (`~1.5` px max error at 100% center res) and earlier solid-shell transition on tree canopies (48 vs 64 blocks). Enabling `canopy` adds ~11% worker meshing time (+24% with `canopyLogs`, `backlog.md:23`) — verify flying chunk-load rate on host `--streamtest`.
- **How to measure:** Host `--view` before/after pixel diffs at jungle & taiga + `questcheck --perfscenes` quad breakdown; headset `--route spots --env "BS_VIEWFIX=12;BS_BLOBFAR=48;BS_PLANTFAR=48;BS_CANOPY=112"`.

#### 5. Test `XR_PERF_SETTINGS_LEVEL_BOOST_EXT` on headset (GPU clock headroom)
- **Files:** `quest/src/xr/XRSession.swift:757-773` (and `:182` for `XR_META_recommended_layer_resolution` if needed)
- **Change:** Test `BS_GPULEVEL=boost` on the headset; if the runtime grants 690 MHz (up from 545–640 MHz) without thermal throttling over a 20–30 min run, make `XR_PERF_SETTINGS_LEVEL_BOOST_EXT` the default for GPU (keep CPU at `SUSTAINED_HIGH` since CPU is only 1.2–3 ms).
- **Expected gain:** **+7–26% GPU clock headroom (~1–3 ms)** depending on what clock `SUSTAINED_HIGH` currently sits at (545 vs 640 MHz). **Cannot be known without headset test.**
- **Risk & quality trade-offs:** Zero visual trade-off. Higher battery drain and heat; if Quest 3 thermally throttles back down mid-session, `DeviceClocks` / `perfNotice` will show it.
- **How to measure:** `tools/headset_gate.sh --route spots --env "BS_VIEWFIX=12;BS_GPULEVEL=boost"` (check `clocks:` MHz and `gpu ms`), followed by a 30-min off-charger thermal soak.

---

### Phase 2 — Recalibrate `ViewGovernor` & `QuestSettings` so view distance actually holds ≥ 12

*(Do this AFTER Phase 1 headset measurements give the real post-fix quads/ms curve at view 12!)*

#### 6. Raise/recalibrate `quadCap`, raise `startView` and `quadFloor`, and fix slow climb / 10-min lid
- **Files:** `Sources/ViewGovernor.swift:36,44,61-62,115,146,169,189,199,215,220-221`, `quest/src/app/QuestSettings.swift:123-127`, `quest/src/app/QuestApp.swift:982-1005`
- **Change:**
  1. **Recalibrate `quadCap` (`ViewGovernor.swift:61`):** raise from `105_000` to the post-Phase-1 headset-measured 72 fps quad ceiling (expect **~200_000–260_000** once Phase 1 lands; or disable `quadCap` for raises and keep it only as an emergency spike guard well above view 12's jungle/taiga quad count).
  2. **Start at 12 (or 10), not 6 (`QuestSettings.swift:124-127`, `ViewGovernor.swift:62`):** raise `quadFloor` from `6` to `8` (or `10` if Phase 1 holds 72 fps at 10 everywhere) and set `startView` to `min(renderDistance, 12)` (or `10`, climbing to `12` in one step) so players & reviewers open at real view distance instead of 6.
  3. **Faster recovery & less sticky lid (`ViewGovernor.swift:36,44,115,189`):**
     - Lower `baseHold` from `45.0` → `15.0–20.0` s when `current < 12` (keep `45.0` s above 12 so high views don't oscillate).
     - Lower `lidFor` from `600.0` s (10 min) → `90.0–120.0` s (or clear `lid` when the player moves > 64 blocks / changes biome, since leaving a jungle/taiga shouldn't punish plains for 10 minutes).
     - Lower `exponent` from `1.2` → `0.9` (matches headset measurements `0.68–0.9` in `:56,331`) and `keepScale` from `0.85` → `0.78` when `current < 12` (if dynamic resolution is active without FFR) so mild resolution scaling can protect view 12 in dense woods.
  4. **Update `ViewGovernorTest` (`ViewGovernor.swift:248-347`)** to match the new thresholds.
- **Expected gain:** Directly restores **view 12–16** in open/forest biomes and **view 10–12** in jungle/taiga, and eliminates the 2.5-minute crawl from view 6 on launch.
- **Risk & quality trade-offs:** Starting at 12 risks brief missed frames on launch *only if* Phase 1 leaves jungle/taiga over 13.9 ms at view 12 (which is why Phase 1 must be measured at `BS_VIEWFIX=12` first).
- **How to measure:** `questcheck --questsim` (ViewGovernor traces) + `tools/headset_gate.sh --route all` (verify PASS: 0 s < 60 fps, < 2% < 70 fps, and check per-leg `view` column stays ≥ 12 most of the run).

---

### Phase 3 — Horizon perception & optional fallback

#### 7. Enable `FarRing` / Far Scenery (`farLayer`) under Auto View and push fog start out
- **Files:** `quest/src/app/QuestSettings.swift:116`, `quest/src/vk/WorldRenderer.swift:223-225,240-244`, `Sources/FarForest.swift:18`
- **Change:**
  1. Benchmark `BS_FARLAYER=1` (Ledger 361) on the headset at view 12. Note `FarForest.maxQuads` is `80_000` (`FarForest.swift:18`, vertex-lit `far.vert`, no textures, 1 draw call, excluded from `drawnQuads`). If 80k adds > 1 ms GPU, lower `FarForest.maxQuads` to `35_000–45_000`.
  2. If the headset cost is ≤ ~1–1.5 ms and fits within 72 fps at view 12, flip `QuestSettings.farLayer` default to `true` (`QuestSettings.swift:116`) so land & woods extend to 560 blocks even when Auto View steps between 10 and 16.
  3. Push `WorldRenderer.swift:224` `clearStart` under Auto View from `0.7` to `0.82–0.85` (when `farRingOn` is false) so fog doesn't eat 30% of the already-limited chunk radius.
- **Expected gain:** Huge perceived render-distance jump (12 chunks of full world seamlessly backed by 560 blocks of low-poly hills/forests instead of a fog wall at 126 blocks). GPU cost **cannot be known without headset measurement** (Ledger 361 explicitly notes "not measured on the headset yet").
- **Risk & quality trade-offs:** Distant stand-in trees are untextured low-poly cones/boxes; bases/roads/frozen rivers aren't represented yet (`bug-ledger.md:352`). Verify no seam/pop-in or > 13.9 ms spike on `--route all`.
- **How to measure:** `tools/headset_gate.sh --route spots --env "BS_VIEWFIX=12;BS_FARLAYER=1"` vs `BS_FARLAYER=0`.

#### 8. Fallback only: Application SpaceWarp (`XR_FB_space_warp`, Ledger 232)
- **Files:** `quest/src/app/QuestSettings.swift:151`, `quest/src/app/QuestApp.swift:615-630`
- **Change:** Only if Phase 1+2 cannot hold 72 fps at view 12 in jungle/taiga without unacceptable softness: test `BS_SPACEWARP=1` (with `BS_SWDELTA` default / `inv` / `0`) on the headset for walking/turning comfort.
- **Expected gain:** Doubles GPU frame budget to **27.8 ms** (minus ~2–4 ms for non-transient depth resolve + `SpaceWarpPass`), easily allowing view 16–24.
- **Risk & quality trade-offs:** Motion-synthesis artifacts on fast turns, hands, water, and UI; previously rejected by Remington for walking jitter before Ledger 232's motion-vector fix — requires his visual sign-off in headset.
- **How to measure:** `tools/headset_gate.sh --route all --env "BS_SPACEWARP=1;BS_VIEWFIX=16"` + human playtest for motion artifacts.

---

## Suggested Headset Measurement Sequence (Before Shipping)

Run `tools/headset_gate.sh --route spots` (fixed views, ~3 min each) in this order so every change is proven on Adreno 740:
1. **Baseline at view 12 (current build, no code edits):** `--env "BS_VIEWFIX=12;BS_DYNRES=0"` (measures true GPU ms & quads at view 12 on current code) and `--env "BS_VIEWFIX=12;BS_DYNRES=0;BS_FOVEATION=2;BS_GPULEVEL=boost"` (measures zero-code-edit headroom from existing switches!).
2. **After Phase 1 (Changes #1–#4):** `--env "BS_VIEWFIX=12;BS_DYNRES=0"` + with `BS_FOVEATION=2` / dynamic foveation. Target: all 6 spots ≤ **11.5–12.5 ms GPU** at view 12.
3. **Far Scenery cost (Change #7):** add `BS_FARLAYER=1` to step 2 and check GPU ms delta.
4. **Full store gate (after Change #6):** `tools/headset_gate.sh --route all` on defaults (fresh reviewer install). Confirm **PASS** (0 s < 60 fps, < 2% < 70 fps) and per-leg view distance ≥ **12** across plains, forest, village, frigate, train, and ≥ **10–12** in jungle/taiga.
