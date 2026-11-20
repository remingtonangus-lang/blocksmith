# Area 1 Review: Quest Platform, OpenXR, Vulkan & Shaders

Scope: `quest/src/android/`, `quest/src/xr/`, `quest/src/vk/`, `quest/shaders/`, `quest/src/common/` on `origin/claude/quest-port` (`89369b4`).
Excludes findings already covered in `docs/status/render-distance-review.md`, `docs/status/neon-review-2.md`, and Ledger 380–383. Findings ranked by value.

---

### 1. Vulkan Use-After-Free in `QuestGraveyard` & `MeshArena` during active command buffer recording (random GPU crashes & corrupted geometry)
- **Evidence:**
  - `quest/src/vk/SceneRenderer.swift:1011-1041,1096-1110`: `SceneRenderer.beginFrame()` waits on the slot's previous fence and calls `MeshArena.frameCompleted(s.submitted)` and `QuestGraveyard.frameCompleted(s.submitted)`, then begins recording Frame N into `s.cmd`. However, `MeshArena.frameSubmitted()` and `QuestGraveyard.frameSubmitted(s.submitted)` are NOT called until `SceneRenderer.submit(s)` (`:1099-1100`) — **after** all vertex/index/slab draws for Frame N have already been recorded.
  - `quest/src/vk/QuestDevice.swift:42-47`:
    ```swift
    static func retire(_ o: AnyObject) {
        lock.lock()
        if completed >= submitted { lock.unlock(); return }  // frees immediately!
        items.append((o, submitted))
        lock.unlock()
    }
    ```
  - `Sources/MeshArena.swift:218,234-235`:
    ```swift
    let after = f.completed >= f.submitted ? 0 : f.submitted
    ```
  - Whenever a background chunk/ship mesher or `world.remesh` drops a `QuestBuffer` or `MeshSlice` **while Frame N is being recorded** (after its buffer/offset was bound into `s.cmd`):
    1. If the previous frame already completed (`completed >= submitted`, common at steady 72 fps), `QuestGraveyard.retire` **immediately calls `vkDestroyBuffer` + `vkFreeMemory`** and `MeshArena` immediately marks the slab range reusable (`after = 0`, even rewinding `bump = at` at `:234`), destroying or overwriting live GPU vertex data before `vkQueueSubmit` even runs.
    2. If Frame N-1 is still in flight (`submitted == N-1`), the retired resource is tagged with `N-1` instead of `N`, so `frameCompleted(N-1)` frees/overwrites it **while Frame N is actively executing on Adreno 740**.
- **Recommended fix:** Add `beginRecording()` (or reserve `recording = submitted + 1` in `SceneRenderer.beginFrame()` before any commands are recorded) on both `QuestGraveyard` and `MeshArena.fences`; while a frame is being recorded, tag every retired object/slice with `recording` (never `0` and never the previous frame's `submitted`).
- **Expected effect:** Eliminates a subtle `VK_ERROR_DEVICE_LOST` / Adreno GPU page-fault crash and intermittent stretched/corrupted chunk or ship triangles during active remeshing.
- **Risk:** Very low (small self-contained change; preserves single-frame memory turnaround).

---

### 2. Capital-ship / Frigate GPU bottleneck (root cause of Ledger 382's "eye 0.55 at 12: its cost is the ships, not the land")
- **Evidence:**
  - **Double `textureSize(tex, 0)` + full `sharpUVs` + `pow(c, 2.2)` per ship fragment:** `quest/shaders/ship_solid.frag:16,18`, `ship_cut.frag:16,19`, `ship_trans.frag:16,19` call `texSharp(oUV, oLayer)` → `common.glsl:69` (`sharpUV`) calls `textureSize(tex, 0)` once for `fwidth`, then `sharpUVd` (`:57`) calls `textureSize(tex, 0)` a **second time**, plus `mod()` + `pow(c, 2.2)` (`worldColor`). A 160-block Meridian Frigate filling 40–60% of both eyes pays this on millions of stereo pixels.
  - **Worst-case terrain & FarRing overdraw behind capital ships (`quest/src/vk/WorldRenderer.swift:380-385`):** `scene.drawOpaque(s)` draws all terrain and `drawFarRing(s, eye)` **before** `ships.drawOpaque`. When piloting or fighting a capital ship covering half the screen, Adreno shades all terrain + FarRing pixels behind the hull first, then overdraws the ship right on top.
  - **Zero interior culling while piloting/aboard (`quest/src/vk/ShipDraw.swift:92-97`):** `let outside = !s.mesh.outerSecs.isEmpty && ShipMesh.eyeOutside(s, eye)`. Standing on the bridge/deck of a frigate makes `eyeOutside == false`, switching every section to `full` (drawing all below-deck engine bays, bunks, corridors, and interior bulkheads across ~50 sections with no interior occlusion).
- **Recommended fix:**
  1. Deduplicate `textureSize(tex, 0)` in `common.glsl:69` (or pass tile size as a constant/UBO uniform), skip `sharpUVs` on distant ship fragments (`oDist > 32.0`), and replace `pow(c, 2.2)` with a 3-mul sRGB approximation (matching `chunk_lean.frag` philosophy).
  2. Split `ships.drawOpaque` into `drawSolid` and `drawCut`: draw `shipSolid` **before** `drawFarRing` (and when a large capital ship is within ~80 blocks or piloted, draw `shipSolid` **before** terrain `scene.drawOpaque` so Early-Z rejects 30–60% of terrain fragments behind the hull).
  3. On capital ships, use `outerSecs` for hull sections more than 1 section below/away from the open helm when `eye` is on the top deck/bridge (keep `full` only for the player's local interior compartment or when actually below deck).
- **Expected effect:** Recovers ~2–5 ms GPU on frigate and crawler encounters (lifting Ledger 382's frigate eye scale from 0.55 toward 0.9–1.0 at view 12; must be measured on headset).
- **Risk:** Low; verify bridge/interior views on host `questcheck --view` to confirm no missing walls when walking inside the hull.

---

### 3. Fixed 256-entry `STORAGE_BUFFER` descriptor pool can silently exhaust in long sessions
- **Evidence:**
  - `quest/src/vk/SceneRenderer.swift:331-335`: `descPool` is created with a fixed capacity of `256` `VK_DESCRIPTOR_TYPE_STORAGE_BUFFER` descriptors and **no** `VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT`.
  - `quest/src/vk/SceneRenderer.swift:946-960`: `tintSet(for:)` allocates a descriptor set from `descPool` for each `QuestBuffer` backing a tint slab (`tintSets[ObjectIdentifier(b)]`) and never frees or recycles it. Once 256 tint slabs have been allocated over a long multi-world session (especially if `MeshArena.tints.trim()` is wired up), `allocSet(set1Layout)` fails with `VK_ERROR_OUT_OF_POOL_MEMORY` and returns `nil` silently (`:948`), dropping terrain tint binding or skipping draws.
- **Recommended fix:** Add `VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT` to `descPool` (or a dedicated tint pool), key `tintSets` by a monotonic buffer ID (not `ObjectIdentifier`, which aliases freed addresses), and free/remove the descriptor set when a tint slab's `QuestBuffer` retires via `QuestGraveyard`.
- **Expected effect:** Prevents silent terrain corruption / missing chunks in long multi-world sessions and makes `MeshArena.tints.trim()` safe.
- **Risk:** Very low.

---

### 4. OpenXR `xrEndSession` & swapchain error-path hazards (uninitialized frames / driver faults)
- **Evidence:**
  - `quest/src/xr/XRSession.swift:694-696`: On `XR_SESSION_STATE_STOPPING`, `xrEndSession(session)` is called immediately without waiting for the Vulkan queue/device (`scene.waitIdle()`). If Frame N is still executing on Adreno referencing the OpenXR swapchain images, ending the session can fault the driver.
  - `quest/src/app/QuestApp.swift:639-644`: If `try scene.submit(s)` throws, `QuestApp` only prints `"submit: ..."` and still calls `xr.endFrame(f)` with `f.shouldRender == true`, presenting an **unrendered / undefined swapchain image** (severe VR comfort flash / VRC risk).
  - `quest/src/xr/XRSession.swift:855-862`: If `acquire(swDepthSwapchain)` throws after `swapchain` and `mvSwapchain` were acquired, the earlier swapchains are never released, stalling the OpenXR swapchain queue.
- **Recommended fix:** Invoke an `onStopping` callback in `XRSession` that runs `scene.waitIdle()` before `xrEndSession`; if `scene.submit(s)` fails, release swapchains and submit 0 layers (`shouldRender = false`) to `xrEndFrame`; clean up acquired swapchains on partial failure in `beginFrame()`.
- **Expected effect:** Prevents garbage-frame flashes on GPU errors and prevents `xrEndSession` races on app close/sleep.
- **Risk:** Very low.

---

### 5. Unnecessary fragment ALU in `common.glsl`, `sky.frag`, `mob.frag`, and invalid `DynamicResolution` probe leakage
- **Evidence:**
  - `quest/shaders/common.glsl:57,69`: `sharpUV(uv)` queries `textureSize(tex, 0)` **twice** per fragment (once for `fwidth`, once inside `sharpUVd`) — impacts `ship_solid`, `ship_cut`, `ship_trans`, `entity`, and any caller of `texSharp`.
  - `quest/shaders/sky.frag:30-33`: Runs `pow(sd, 5.0)` and `pow(sd, 64.0)` on every sky pixel (~35–50% of stereo pixels) even though `sd8` (`sd^8`) is already computed on line 32 (`sd64 = sd16 * sd16` in 3 multiplies, zero `pow()`).
  - `quest/shaders/mob.frag:86-89`: Computes `cross(dFdx(oRel), dFdy(oRel))`, `normalize`, and specular/rim `pow` (`:77-78`) unconditionally at all distances with no `oDist` cutoff (hurts GPU when 20–40 fortress soldiers are in view).
  - `quest/src/common/DynamicResolution.swift:28,51-57`: `heavyQuads = 250_000` (above `ViewGovernor.quadCap = 170_000`), and `:52` updates `lastProbe` even when `gain <= 0` (when GPU time *rose* during the cut — marked `!trusted` on `:53`), feeding nonsense `lastProbe > 1` → `pixelShare = 0` into `ViewGovernor` (`QuestApp.swift:1151`).
- **Recommended fix:** Query `textureSize` once in `sharpUV` (or pass tile size in UBO); replace `pow(sd, 5.0)` / `pow(sd, 64.0)` in `sky.frag` with multiplications; skip `mobSheen` + `dFdx/dFdy` in `mob.frag` past `oDist > 48.0`; only update `DynamicResolution.lastProbe` when `gain > 0`.
- **Expected effect:** Free ~0.5–1.5 ms GPU savings across sky, ships, mobs, and entities, plus cleaner `pixelShare` input to `ViewGovernor`.
- **Risk:** Very low (visually identical; test `mob.frag` cutoff at 48 m).

---

### 6. Missing Vulkan destructors across `SceneRenderer`, `SpaceWarpPass`, `CloudMap`, `HudPanel`, `VkContext` + `QuestDevice.allocatedBytes` monotonic counter
- **Evidence:**
  - Only `RenderTarget`, `CullTable`, `VkBuf`, `VkImg`, and `PtrArena` implement `deinit` in `quest/src/vk/`. `SceneRenderer`, `SpaceWarpPass` (`mvViews`, `depthViews`, `framebuffers`, `renderPass`, `pipeline`, `motionPipes`), `CloudMap`, `HudPanel`, and `VkContext` never destroy their Vulkan objects; `AndroidMain.swift:260-265` relies on `exit(0)` to reclaim everything.
  - `quest/src/vk/QuestDevice.swift:23,31`: `allocatedBytes += length` never decrements on `QuestBuffer.deinit`, over-reporting GPU memory usage over time.
  - `quest/src/common/TextureCache.swift:83-88`: Background `store(l, u)` on `.utility` QoS pins the **166 MB** `[[UInt8]]` mip chain in RAM for several seconds on first launch of every update while worldgen and mesh slabs are spiking memory, and `exit(0)` can orphan `.part` files if the user quits early.
- **Recommended fix:** Add `deinit` cleanup (guarded by `vkDeviceWaitIdle`) to Vulkan owner classes; decrement `allocatedBytes` in `QuestBuffer.deinit` (or track via `VkBuf`); bump `TextureCache.store` QoS to `.userInitiated` so the 166 MB mip array releases promptly before world streaming peaks.
- **Expected effect:** Clean Vulkan validation-layer runs, accurate GPU memory stats, and ~166 MB lower peak RAM on first launch after store updates.
- **Risk:** Very low.
