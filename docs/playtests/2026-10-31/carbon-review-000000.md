# Carbon blind review (full resolution, in parts)

## Part 1 of 4

### Recorder Corruption Note
Recorder buffer/tiling corruption appears from `09:37:19 + 00:00:08.792` through `09:47:11 + 00:00:08.417` as frozen/repeated frame strips along the right and bottom margins of the capture (stacking into multiple nested borders from `09:41:51 + 00:00:05.542` onward). Per instructions, this capture artifact is excluded from the game bugs below.

---

### Game Bug Findings

1. **Playtest debug banner & voice-recording UI visible on HUD**
   - **Time:** `09:37:05 + 00:00:00.458`–`00:00:02.458`, `09:37:10 + 00:00:00.500`–`00:00:02.500`, `09:37:10 + 00:00:02.500` (`Note` recording indicator top-left, also at `09:46:26 + 00:00:07.083`)
   - **What you see:** Floating text `"Playtest build: voice bug notes ON, your speech is saved (Options > Interface)"` sits directly above the hotbar.
   - **Severity:** **Store-blocking**
   - **Likely cause:** Debug/playtest telemetry flag enabled by default in build configuration.

2. **Loading screen has rolled/tilted horizon and raw debug placeholder avatars**
   - **Time:** `09:37:10 + 00:00:09.500`–`00:00:10.500`, `09:37:19 + 00:00:00.792`–`00:00:01.792`
   - **What you see:** During `"Generating terrain... 62%"`, the player stands on a bare green plane with a visibly tilted/rolled horizon (severe VR nausea/VRC violation) and floating cat-head debug avatars with stacked icon columns.
   - **Severity:** **Store-blocking**
   - **Likely cause:** Loading scene inherits HMD roll into world up-vector or lacks horizon lock, and staging/debug NPC prefabs were left in the transition lobby.

3. **Shoreline seam artifact and underwater vertical curtain geometry**
   - **Time:** `09:37:10 + 00:00:12.500`, `09:37:19 + 00:00:03.792`
   - **What you see:** A flat tan strip cuts along the snow-to-water shoreline, and vertical striped walls hang beneath the water surface at chunk boundaries.
   - **Severity:** **Should fix**
   - **Likely cause:** Missing water-skirt culling between adjacent coastal chunks and unblended shore biome transition blocks.

4. **Black triangular hole and missing faces in snow terrain**
   - **Time:** `09:37:19 + 00:00:04.792` (mid-left), `09:37:26 + 00:00:47.167`–`00:00:48.167` (left slope)
   - **What you see:** A pitch-black triangular hole in the snow mesh (`09:37:19 + 00:00:04.792`) and a dark grey missing-face gap along stepped snow blocks (`09:37:26 + 00:00:47.167`).
   - **Severity:** **Should fix**
   - **Likely cause:** Marching-cubes / sloped-voxel greedy mesher winding-order or neighbor-face culling bug on partial snow layers.

5. **Severe terrain mesh starvation, blurry blob LODs, and torn/floating chunk pop-in**
   - **Time:** `09:37:26 + 00:00:28.167`–`00:00:35.167`
   - **What you see:** Voxel chunks fail to stream in for ~7 seconds, leaving smooth untextured grey-green heightmap blobs directly under the player; at `09:37:26 + 00:00:34.167`, cliff/foliage chunks pop in floating mid-air with stretched vertical spike triangles at bottom-right.
   - **Severity:** **Store-blocking**
   - **Likely cause:** Chunk mesh generation queue starves under fast movement, and LOD-to-voxel seam stitching has corrupted vertex indices.

6. **Blinding water specular highlight on solid ice/snow & popping icebergs**
   - **Time:** `09:37:26 + 00:00:36.167`–`00:00:50.167`
   - **What you see:** A huge, blown-out white oval sun reflection slides across matte frozen snow/ice blocks, bordered by harsh stair-stepped ice shelves with vertical striped walls, while small icebergs/entities pop in and out (`00:00:37.167` vs `00:00:47.167`).
   - **Severity:** **Should fix**
   - **Likely cause:** Ice/snow-over-ocean chunks share the ocean water specular shader or render transparent water specular straight through opaque ice above it; short entity cull distance.

7. **Detached floating voxel fragments on first-person held items & VR hands**
   - **Time:** `09:37:26 + 00:00:39.167`–`00:00:50.167` (book), `09:37:26 + 00:01:33.167`, `00:01:48.167` (rifle), `09:40:36 + 00:00:21.208`–`00:00:22.208`, `09:43:30 + 00:00:32.917` (pistol)
   - **What you see:** Detached brown voxel strips float beside the held book; during rifle/pistol reloads and movement, disembodied grey blocks float detached from the weapon with no hand/wrist model.
   - **Severity:** **Should fix**
   - **Likely cause:** Misaligned child bone offsets on voxelized item meshes and placeholder cube meshes used for off-hand VR controllers.

8. **Massive vertical geometry spikes shooting to the top of the skybox**
   - **Time:** `09:37:26 + 00:00:54.167` (also oversized pillar in fog at `09:37:05 + 00:00:00.458`–`00:00:01.458`)
   - **What you see:** Two enormous flat-shaded grey triangular spikes erupt from distant mountain terrain straight into the clouds.
   - **Severity:** **Store-blocking**
   - **Likely cause:** Uninitialized or overflowed heightmap Y-values in distant LOD terrain mesh generation.

9. **Bolt-action rifle ADS blocks entire sight picture with opaque black box + HUD overlap**
   - **Time:** `09:37:26 + 00:01:46.167`–`00:01:47.167`, `09:39:30 + 00:00:12.208`–`00:00:14.208`, `09:39:40 + 00:00:01.792`–`00:00:03.792`, `09:39:40 + 00:00:37.792`–`00:00:50.792`
   - **What you see:** Aiming down sights with the Kestrel Bolt Rifle places a large hollow black/brown receiver block directly over the camera, completely hiding the target and iron sights while depth-disabled HUD text renders inside the black box.
   - **Severity:** **Store-blocking**
   - **Likely cause:** Two-handed VR weapon grab/stock-anchor pivot positions the rear stock mesh over the eye camera without near-clip or rear-cap geometry, and world/wrist HUD ignores depth occlusion.

10. **Fortress structure generation carves a player-trapping dirt trench around walls**
    - **Time:** `09:37:26 + 00:02:03.167`–`00:02:06.167`, `09:39:30 + 00:00:16.208`, `09:40:36 + 00:00:01.208`–`00:00:08.208`
    - **What you see:** Greywall Garrison's flat bounding box cuts a steep 1–2 block wide vertical dirt trench into surrounding snow hills, trapping the player against the wall with stretched vertical dirt UVs.
    - **Severity:** **Should fix**
    - **Likely cause:** Structure placement flattens an exact footprint box without terrain height blending/skirt beveling.

11. **HUD elements and VR contract menus severely overlap and clip**
    - **Time:** `09:39:40 + 00:00:13.792`–`00:00:14.792`, `09:42:25 + 00:00:18.833`, `09:42:25 + 00:00:24.833` (HUD); `09:44:33 + 00:00:07.875`–`00:00:19.875` (Contracts UI)
    - **What you see:** Boss/enemy health bars, waypoint markers, minimap coordinates, and ammo counters pile on top of each other into an unreadable jumble; Quartermaster's Contracts menu rows crowd and clip text at low VR font resolution.
    - **Severity:** **Should fix**
    - **Likely cause:** World-space/wrist HUD elements lack layout stacking or collision avoidance, and UI canvas text scale/padding is undersized for Quest resolution.

12. **Eating animation smears food item mesh across camera near-clip plane**
    - **Time:** `09:42:25 + 00:00:27.833`–`00:00:30.833`, `09:45:26 + 00:01:02.875`, `09:46:26 + 00:00:03.083`–`00:00:05.083`
    - **What you see:** Eating a Golden Apple stretches the 3D item into a long, distorted yellow streak filling the lower-right view.
    - **Severity:** **Minor**
    - **Likely cause:** Procedural eat animation scales/translates the held mesh inside the HMD camera's near-clip/wide-FOV periphery instead of scaling it down or fading it out.

13. **Ground navigation arrow has black backface/z-fighting artifacts**
    - **Time:** `09:41:51 + 00:00:00.542`–`00:00:01.542`, `09:41:51 + 00:00:04.542`
    - **What you see:** Large cyan 3D waypoint arrow hovering over courtyard gravel displays pitch-black unlit faces and a harsh circular shadow ring clipping into uneven terrain.
    - **Severity:** **Minor**
    - **Likely cause:** Inverted normals or unlit backface material on the guide mesh combined with unprojected flat circle shadow.

14. **Bulkhead doors swing through player camera and staircase geometry**
    - **Time:** `09:41:51 + 00:00:15.542`–`00:00:16.542`, `09:42:25 + 00:00:40.833`–`00:00:42.833`, `09:43:30 + 00:00:50.917`–`00:00:53.917`
    - **What you see:** Opening multi-block bulkhead doors sweeps the solid door mesh straight through the player's head (filling the screen with flat grey wall) and clips into adjacent stairs, while `[L Trigger] Use Bulkhead Door` floats through walls (`09:41:51 + 00:00:17.542`).
    - **Severity:** **Should fix**
    - **Likely cause:** Animated door kinematic collider does not push/block player capsule or check clearance, and interaction raycast ignores wall occlusion.

15. **Explosion destruction leaves unsupported turrets, masts, and blocks floating mid-air**
    - **Time:** `09:42:25 + 00:00:08.833`–`00:00:09.833`, `09:43:30 + 00:00:04.917`, `09:43:30 + 00:00:09.917`–`00:00:11.917`, `09:43:30 + 00:00:21.917`, `09:43:30 + 00:00:25.917`–`00:00:26.917`
    - **What you see:** After shelling the garrison roof, a tall black antenna mast, scattered stone blocks, the rooftop cannon, and a detached yellow-and-black turret handle remain suspended in empty air over the crater.
    - **Severity:** **Store-blocking**
    - **Likely cause:** Voxel destruction removes blocks without running structural connectivity/collapse checks or destroying/dropping attached multi-block props.

16. **Indoor enemy AI freezes/faces walls and dead corpses clip inside floors and stairs**
    - **Time:** `09:42:25 + 00:00:23.833`–`00:00:24.833`, `09:42:25 + 00:00:35.833`–`00:00:36.833` (AI); `09:42:25 + 00:00:39.833`, `09:46:44 + 00:00:01.708` (corpses)
    - **What you see:** Enemies stand staring into room corners or freeze at point-blank range; killed enemies sink halfway into stone stairs and floors.
    - **Severity:** **Should fix**
    - **Likely cause:** Navmesh/pathfinding fails inside tight voxel rooms, and death ragdoll/pose colliders penetrate voxel floor geometry.

17. **Distant villages float in mid-air and Capital Citadel renders as untextured white boxes before popping in**
    - **Time:** `09:45:00 + 00:00:24.292`–`00:00:26.292` (Bitter Ridge); `09:45:26 + 00:00:07.875`–`00:00:09.875` (Capital Citadel)
    - **What you see:** Village houses render floating in empty blue sky before terrain loads beneath them; the Capital Citadel appears as crude untextured white/grey boxes (`00:00:07.875`), flashes into a flat grey silhouette (`00:00:08.875`), and abruptly pops into full skyscraper geometry with an unsupported floating stone disc (`00:00:09.875`).
    - **Severity:** **Store-blocking**
    - **Likely cause:** Structure proxy/impostor LODs render at longer range than terrain chunks and lack textures/materials on distant LOD tiers.

18. **Citadel rooftop twin cannon barrels clip straight through solid stone parapet**
    - **Time:** `09:47:11 + 00:00:02.417`–`00:00:06.417`
    - **What you see:** Both long grey barrels of the rooftop AA/artillery turret pass directly through the solid stone wall blocks in front of the mount.
    - **Severity:** **Should fix**
    - **Likely cause:** Turret prefab placed one block too low or without clearing an embrasure gap in the structure template.

---

### Top 10 Worst Issues in Priority Order for Store Release

1. **Bolt-action rifle ADS blocks the entire camera view with a black receiver box (`09:37:26 + 00:01:46.167`, `09:39:40 + 00:00:37.792`)** — Core VR gunplay is broken when aiming two-handed weapons.
2. **Tilted/rolled horizon and raw debug avatars in terrain-loading lobby (`09:37:19 + 00:00:00.792`–`00:00:01.792`)** — Rolled horizon violates Meta Quest VR comfort requirements (instant VRC rejection) and exposes placeholder assets.
3. **Playtest debug speech banner & recording indicator left on HUD (`09:37:05 + 00:00:00.458`)** — Automatic store-review rejection for shipping debug/playtest overlays.
4. **Severe terrain chunk starvation, floating cliff pop-in, and torn mesh spikes (`09:37:26 + 00:00:28.167`–`00:00:34.167`)** — World visibly fails to load around the player during fast traversal.
5. **Untextured white-box Citadel impostors and mid-air floating village houses (`09:45:00 + 00:00:25.292`, `09:45:26 + 00:00:07.875`–`00:00:09.875`)** — Major landmarks look unfinished/broken from medium distance.
6. **Giant vertical geometry spikes shooting into the skybox (`09:37:26 + 00:00:54.167`)** — Obvious, immersion-breaking heightmap/LOD corruption visible across the map.
7. **Floating antenna mast, detached turret handles, and unsupported roof blocks after explosions (`09:42:25 + 00:00:08.833`, `09:43:30 + 00:00:09.917`)** — Destructible fortresses leave hovering debris and broken multi-block props.
8. **Overlapping, illegible HUD cluster and cramped VR contract menu text (`09:39:40 + 00:00:14.792`, `09:44:33 + 00:00:13.875`)** — Critical combat and quest UI becomes unreadable in headset.
9. **Bulkhead doors swinging straight through the player's head and stairs (`09:43:30 + 00:00:50.917`–`00:00:52.917`)** — Blinds the player in combat and looks unpolished in every bunker interior.
10. **Indoor AI freezing/facing walls, corpses sinking into floors, and turrets clipping through parapets (`09:42:25 + 00:00:23.833`, `09:46:44 + 00:00:01.708`, `09:47:11 + 00:00:03.417`)** — Makes garrison/citadel combat encounters feel broken.

## Part 2 of 4

### Recorder Corruption Note
Yes, **recorder tiling/border corruption is visible throughout almost the entire clip**: nested/repeated frame strips appear along the right and bottom margins (`09:47:11 + 00:00:09.458` through `16:12:23 + 00:00:16.708`), with additional horizontal mosaic tiling along the bottom edge starting around `09:52:10 + 00:00:33.250`. Per instructions, these recorder artifacts are excluded from the bug list below.

---

### Game Bugs Found (Chronological)

1. **Disembodied arm / vanishing turret mesh when mounting (`09:47:18 + 00:00:01.083` – `09:47:18 + 00:00:02.083`)**
   - **What:** While transitioning onto/rotating the turret, the turret geometry disappears and leaves a detached blocky white player arm floating in midair (`09:47:18 + 00:00:01.583`).
   - **Severity:** Should fix
   - **Likely cause:** Turret entity bounding-box frustum culling or seat-attachment sync delay when mounting.

2. **Oversized food viewmodels block half the VR view (`09:47:18 + 00:00:19.083` – `09:47:18 + 00:00:24.083`)**
   - **What:** Held/eaten bread and apple sprites are extruded at huge scale right in front of the eye, covering ~40% of the FOV and clipping the near plane.
   - **Severity:** Should fix
   - **Likely cause:** Item viewmodel scale tuned for flatscreen FOV rather than VR hand-to-HMD distances.

3. **HUD hotbar & prompts overlap open Chest UI (`09:47:18 + 00:00:26.583`)**
   - **What:** The floating hotbar, ammo text (`LOADED 18 / 364`), and controller hints intersect and clip directly through the bottom of the Chest inventory panel.
   - **Severity:** Should fix
   - **Likely cause:** World-space HUD canvas remains active at the same depth as modal container menus instead of hiding or offsetting.

4. **Red damage/death vignette is a hard-edged square quad inside VR FOV (`09:48:01 + 00:00:00.083` – `09:48:01 + 00:00:01.583`, `09:50:45 + 00:00:07.083`, `09:51:29 + 00:00:34.458`, `09:53:39 + 00:00:01.625`, `09:55:00 + 00:00:12.542`)**
   - **What:** Taking damage or dying displays a flat red quad whose sharp outer borders sit visibly inside the VR view; opening the pause menu while dead (`09:48:01 + 00:00:01.083`) turns the inner circle pitch black inside the red square.
   - **Severity:** Store-blocking
   - **Likely cause:** Flatscreen-sized UI overlay quad not scaled to cover the full stereo VR eye frustum, combined with broken depth/alpha sorting against the pause vignette.

5. **Harsh jagged snow cutout & pitch-black unlit terrain chunks (`09:48:01 + 00:00:14.583` – `09:48:01 + 00:00:15.583`, `09:48:01 + 00:00:51.583` – `09:48:01 + 00:00:53.583`)**
   - **What:** Homesteads cut an abrupt stair-stepped circle out of snow (`09:48:01 + 00:00:14.583`), and forest terrain has pitch-black unlit patches (`09:48:01 + 00:00:52.083`).
   - **Severity:** Minor
   - **Likely cause:** Hard radius check on structure snow suppression and skipped chunk light-propagation updates during fast movement.

6. **Untextured floating structure proxy & misaligned pop-in (`09:48:01 + 00:00:49.083` – `09:48:01 + 00:00:57.583`)**
   - **What:** A bright grey, untextured 3-pronged silhouette floats high in the sky (`09:48:01 + 00:00:54.583` – `56.083`), vanishes at `56.583`, and the Citadel pops in lower and further right at `09:48:01 + 00:00:57.583`.
   - **Severity:** Should fix
   - **Likely cause:** Distant landmark impostor/LOD mesh has an incorrect world transform/Y-offset and unlit fallback shader.

7. **Severe Z-fighting / shadow acne on heavy weapon mesh (`09:50:15 + 00:00:00.167` – `09:50:15 + 00:00:20.667`, `09:51:29 + 00:00:11.958` – `09:51:29 + 00:00:32.458`)**
   - **What:** Large black diagonal锯齿/striped moiré artifacts flicker across the flat white/grey faces of the heavy gun's side magazine and receiver.
   - **Severity:** Store-blocking
   - **Likely cause:** Coplanar duplicate faces in the weapon mesh or insufficient shadow-map depth bias causing self-shadowing acne on Quest mobile GPU precision.

8. **Black box / void swallows weapon middle & foreground (`09:50:59 + 00:00:00.333` – `09:50:59 + 00:00:07.833`)**
   - **What:** The entire middle body of the held heavy weapon and part of the foreground render pitch black, leaving only the front iron sights and rear stock floating around a black void (`09:50:59 + 00:00:02.333`).
   - **Severity:** Store-blocking
   - **Likely cause:** Corrupted material/lighting buffer on the weapon submesh or broken occlusion/near-clip geometry attached to the hand.

9. **Detached thin wall planes & black trench along Citadel perimeter (`09:50:59 + 00:00:25.333` – `09:50:59 + 00:00:30.333`)**
   - **What:** Paper-thin floating wall slabs stick out beside a pitch-black unlit strip along the outer Citadel wall (`09:50:59 + 00:00:26.333`).
   - **Severity:** Should fix
   - **Likely cause:** Structure-to-terrain chunk seam leaving unculled interior/boundary faces and broken ambient occlusion/lighting under overhangs.

10. **Enemies clipping into walls and stuck tilted at 45° (`09:51:29 + 00:00:07.458` – `09:51:29 + 00:00:12.458`, `09:51:29 + 00:00:21.458` – `09:51:29 + 00:00:26.958`)**
    - **What:** A white-armored guard is wedged halfway inside the outer Citadel wall at a 45° angle (`09:51:29 + 00:00:08.458`, `11.958`), and enemies/corpses inside the lobby remain frozen tilted sideways above the floor (`09:51:29 + 00:00:21.458`, `26.958`).
    - **Severity:** Should fix
    - **Likely cause:** Spawn/navmesh bounds overlapping structure blocks and death/hit-tilt rotation failing to clear or ragdoll onto floor collision.

11. **Combat HUD text & alerts collide in 3D space (`09:51:29 + 00:00:25.458`, `09:53:55 + 00:00:18.083`)**
    - **What:** Alert banners (*"Missile launch: take cover!"*, *"Alarm! The garrison is coming..."*), boss/enemy health bars, `LOADED` ammo text, and minimap coordinates overlap and become unreadable.
    - **Severity:** Should fix
    - **Likely cause:** Uncoordinated layout anchors on floating HUD widgets when multiple combat notifications trigger simultaneously.

12. **Natural dirt/rock terrain generated high up on skyscraper wall (`09:51:29 + 00:00:30.958` – `09:51:29 + 00:00:32.458`)**
    - **What:** A large mass of rough brown/tan voxel terrain is fused onto the upper glass-and-steel facade of the Citadel tower (`09:51:29 + 00:00:31.458`).
    - **Severity:** Should fix
    - **Likely cause:** Procedural biome terrain/cave/cliff pass running after or overlapping structure placement without a full bounding-volume clear.

13. **Creative mode & debug Commands exposed in Normal Survival pause menu (`09:52:10 + 00:00:07.750` – `09:52:10 + 00:00:11.250`)**
    - **What:** Pause menu in a "Normal" survival world exposes instant `Creative` mode switching and a debug `Commands` console (`/bases`, `/time`, `Day`/`Night`).
    - **Severity:** Minor (unless unintentional dev build leak, in which case Should fix)
    - **Likely cause:** Developer/cheat UI buttons not gated behind a world-creation "Allow Cheats" flag.

14. **Detached VR off-hand floats inches away from rifle barrel (`09:53:51 + 00:00:03.125` – `09:53:51 + 00:00:08.625`, `09:53:55 + 00:00:20.583` – `09:53:55 + 00:00:32.583`)**
    - **What:** A disembodied white blocky hand floats loosely in midair to the left of the rifle instead of gripping the forend (`09:53:51 + 00:00:03.625`, `09:53:55 + 00:00:30.583`).
    - **Severity:** Should fix
    - **Likely cause:** Off-hand VR controller mesh rendered at raw controller position without snapping/IK-clamping to the weapon's secondary grip point.

15. **Death dialog promises a chest, but items spill loose with no chest (`09:54:37 + 00:00:17.708` – `09:54:54 + 00:00:02.667`)**
    - **What:** After dying to a turret shell, the UI states *"Your things are in a chest where you fell..."*, yet `09:54:54 + 00:00:01.667` shows all armor and items scattered loose on the snow with no chest present.
    - **Severity:** Should fix
    - **Likely cause:** Explosive shell damage immediately destroyed the spawned death chest, or snow-layer collision blocked chest placement and fell back to raw drops.

16. **Lingering "Flying" HUD label after switching to Survival in midair (`09:54:54 + 00:00:09.667`, `09:55:00 + 00:00:11.542`)**
    - **What:** Immediately after switching from Creative to Survival in midair, the HUD still displays `Flying` while gravity drops the player to their death.
    - **Severity:** Minor
    - **Likely cause:** Stale movement-mode UI string not refreshed on game-mode change until landing/tick update.

17. **Oversized blurry stims & keycard smear/clip across camera (`09:55:45 + 00:00:00.458` – `09:55:45 + 00:00:01.458`, `09:56:17 + 00:00:05.250` – `09:56:17 + 00:00:05.750`, `16:12:18 + 00:00:02.667`)**
    - **What:** Field/Combat Stims look like huge, blurry, dark-banded clubs and clip/smear into a wide black/grey plane across the lens when used (`09:55:45 + 00:00:00.958`, `09:56:17 + 00:00:05.250`); the keycard (`16:12:18 + 00:00:02.667`) is blurry from bilinear filtering on low-res pixel art.
    - **Severity:** Should fix
    - **Likely cause:** Overscaled extruded 2D sprites intersecting the HMD near-clip plane during use animations, plus bilinear texture filtering instead of point/nearest filtering.

18. **Floating tree leaves & stretched log/camera clipping at camp (`16:12:23 + 00:00:15.208` – `16:12:23 + 00:00:16.708`)**
    - **What:** A green leaf block cluster floats completely unattached in midair to the right of the NPC (`16:12:23 + 00:00:15.708`), the NPC stands right on the campfire edge (`16:12:23 + 00:00:16.208`), and stepping onto the log (`16:12:23 + 00:00:16.708`) clips/stretches the bark texture across the lower view.
    - **Severity:** Minor / Should fix
    - **Likely cause:** Incomplete trunk-to-canopy pruning/generation around camp clearings and camera/collider clipping on custom log blocks.

---

### Top 10 Worst Bugs in Priority Order for Store Release

1. **Red damage/death vignette renders as a hard-edged flat square inside VR FOV** (`09:48:01 + 00:00:00.083`, `09:51:29 + 00:00:34.458`) — Instant Meta Horizon Store VR comfort/presentation fail; screen-space overlays must cover the entire stereo frustum.
2. **Weapon middle & foreground swallowed by pitch-black occlusion void** (`09:50:59 + 00:00:00.333` – `09:50:59 + 00:00:07.833`) — Store-blocking rendering corruption directly on the player's primary held item.
3. **Severe Z-fighting / shadow acne stripes across weapon faces** (`09:50:15 + 00:00:00.167`, `09:51:29 + 00:00:26.458`) — Constant, high-contrast flickering right in the player's hands throughout combat.
4. **Oversized, blurry 2D-extruded items (stims/food) clip and smear across the HMD near plane** (`09:47:18 + 00:00:19.583`, `09:55:45 + 00:00:00.958`, `09:56:17 + 00:00:05.250`) — Obstructs vision and causes uncomfortable near-eye clipping whenever healing or eating.
5. **Enemies clip halfway into walls and freeze tilted at 45° angles** (`09:51:29 + 00:00:08.458`, `09:51:29 + 00:00:21.458`) — Breaks combat readability and makes AI encounters look unfinished.
6. **Death screen claims items are in a chest when gear actually spilled loose on the ground** (`09:54:37 + 00:00:17.708` – `09:54:54 + 00:00:01.667`) — Misleads players and risks permanent item despawn after explosive deaths.
7. **Detached VR off-hand floating away from rifle & vanishing turret mesh** (`09:53:51 + 00:00:03.625`, `09:53:55 + 00:00:30.583`, `09:47:18 + 00:00:01.583`) — Breaks VR hand presence on two-handed weapons and vehicles.
8. **HUD text, combat alerts, hotbar, and Chest UI overlap and collide** (`09:47:18 + 00:00:26.583`, `09:51:29 + 00:00:25.458`, `09:53:55 + 00:00:18.083`) — Makes inventory management and combat status hard to read in VR.
9. **Broken Citadel worldgen: terrain chunks stuck high on skyscraper walls & floating perimeter slabs** (`09:51:29 + 00:00:31.458`, `09:50:59 + 00:00:26.333`) — Highly visible structural generation defects on a major landmark.
10. **Untextured grey landmark proxy floating in the sky & popping to a different position** (`09:48:01 + 00:00:54.583` – `09:48:01 + 00:00:57.583`) — Jarring distant-LOD mismatch when approaching major POIs.

## Part 3 of 4

### Recorder Corruption Note
Throughout almost the entire clip (starting at `16:12:34 + 00:00:07.458` and persisting through `16:23:28 + 00:00:32.292`), the right and bottom borders of the frame display repeated, stale mosaic strips from earlier frames. As instructed, this recorder tiling garbage is excluded from the game bugs below.

---

### Chronological Game Bug Findings

1. **Detached floating NPC tool & overlapping dialogue UI**
   - **Time:** `16:12:34 + 00:00:12.458` – `00:00:16.458`
   - **What:** The camp NPC's wooden pitchfork/staff floats completely detached in midair several inches beside his right shoulder (`00:00:14.458` – `00:00:16.458`), and his white floating dialogue text clips into his chest/chin at tiny, barely legible scale.
   - **Severity:** Should fix
   - **Cause:** Misaligned hand-socket attachment offset on the NPC rig and unscaled world-space billboard text without depth/offset padding.

2. **Terrain LOD spike & tree leaf biome-color pop**
   - **Time:** `16:12:34 + 00:00:23.458` – `00:00:24.458` and `16:12:58 + 00:00:01.208` – `00:00:02.208`
   - **What:** A sharp, low-poly green pyramid spike juts out of the terrain on the far left (`00:00:23.458`, `00:00:01.208`). Simultaneously, the entire forest renders with white/grey leaves at mid-LOD and abruptly snaps to bright green 1 second later (`00:00:24.458`, `00:00:02.208`).
   - **Severity:** Should fix
   - **Cause:** Coarse LOD heightmap vertex mismatch at a chunk boundary, and distant tree LODs using an incorrect snow/grey biome tint or untinted atlas before switching to full-detail foliage.

3. **Floating untextured Capital blockout & missing terrain chunks showing sky/void**
   - **Time:** `16:12:58 + 00:00:04.208` – `00:00:13.208` (worst at `00:00:12.208`)
   - **What:** Approaching the Capital city, the structure appears as a stark, untextured grey box floating in midair (`00:00:12.208`) while snowy terrain chunks directly underneath are missing, exposing empty sky/fog through gaping holes in the ground before popping in at `00:00:13.208`.
   - **Severity:** Store-blocking
   - **Cause:** Structure proxy LOD loads ahead of terrain chunk streaming without skirt geometry or fog masking, and uses an unshaded placeholder mesh.

4. **Severe HUD & notification text overlap over weapon sights**
   - **Time:** `16:12:58 + 00:00:59.208` – `00:01:03.208`, `16:15:20 + 00:00:00.000` – `00:00:05.000`, `16:15:30 + 00:00:25.208`, `16:23:28 + 00:00:21.292`
   - **What:** Combat alerts (`The garrison opens fire!`, `+2 Honour`, `You protected the town`), NPC dialogue, and `/locate` output render directly on top of the hotbar, `LOADED` ammo counter, and minimap, while depth-ignoring HUD elements draw straight across the held rifle barrel/sights.
   - **Severity:** Store-blocking
   - **Cause:** Multiple HUD widgets share the same anchor region without layout stacking, and world/hand-locked UI uses `ZTest Always` right in the aiming line of sight.

5. **Black unlit triangles along smooth-voxel grass slopes & wall bevels**
   - **Time:** `16:12:58 + 00:01:07.208` – `00:01:09.208`, `16:14:05 + 00:00:00.292`, `16:15:20 + 00:00:12.000`, `16:15:30 + 00:00:02.208`
   - **What:** A jagged pitch-black band runs along the entire stepped grass slope bordering the Capital lawn, and a sharp black triangle artifact appears on the bevel corner of the white stone wall (`16:12:58 + 00:01:09.208`, `16:14:05 + 00:00:00.292`). Flowers also float partially detached on sloped edges.
   - **Severity:** Store-blocking
   - **Cause:** Inverted/zeroed vertex normals or missing triplanar UV mapping on vertical transition faces of the smooth-voxel mesher.

6. **Camera-clipping opaque explosion quads blinding VR view**
   - **Time:** `16:14:05 + 00:00:03.292`, `16:14:21 + 00:00:11.292`, `16:14:27 + 00:00:04.708`, `16:21:25 + 00:00:24.583` – `00:00:28.583`, `00:00:35.583` – `00:00:36.583`
   - **What:** Explosions spawn huge, flat, unshaded orange and grey pixel quads right against the VR near-clip plane, filling 80–95% of the viewport and slicing abruptly across geometry.
   - **Severity:** Store-blocking
   - **Cause:** Oversized billboard particle sprites lacking near-camera fade/soft-particle depth fade, causing severe VR comfort and visibility issues.

7. **Held 2D-extruded tool/food items detach from hand, smear, and clip into VR camera**
   - **Time:** `16:14:27 + 00:00:21.708`, `16:14:52 + 00:00:01.833` – `00:00:06.833`, `16:15:00 + 00:00:06.125` – `00:00:07.125`, `16:17:17 + 00:00:08.333` – `00:00:11.333`
   - **What:** During use/swing (`16:14:52 + 00:00:03.833`, `00:00:06.833`), the held sprite-item floats far forward completely detached from the grey VR hand model; at `16:14:27 + 00:00:21.708` its edge-on geometry stretches into black/white streaks; and eating a Golden Apple shoves giant stretched side-texels directly into the player's eyes (`16:15:00 + 00:00:07.125`).
   - **Severity:** Should fix
   - **Cause:** Non-VR eating/swinging keyframe offsets applied to 6DoF VR hand items, plus broken UV extrusion on generated 2D-sprite item meshes.

8. **Destroyed/undermined turret barrels remain floating in midair**
   - **Time:** `16:14:21 + 00:00:13.292`, `16:15:30 + 00:00:14.208`, `16:16:32 + 00:00:08.125`, `16:16:43 + 00:00:00.000` – `00:00:05.000`
   - **What:** After explosions destroy turret bases or ceiling blocks beneath them, dark double-barrel turret heads stay suspended in midair (`16:15:30 + 00:00:14.208`, and overhead through the ceiling hole at `16:16:43 + 00:00:00.000` – `00:00:05.000`).
   - **Severity:** Store-blocking
   - **Cause:** Multi-part turret entities do not check for supporting voxel destruction or fail to clean up child barrel meshes upon base destruction.

9. **Enemy AI clips into ceiling lights & launches 20 blocks into the air**
   - **Time:** `16:15:30 + 00:00:33.208` – `00:00:34.208` and `16:16:43 + 00:00:11.000` – `00:00:13.000`
   - **What:** Indoors, a Capital Trooper vaults onto supply crates with his head/upper torso clipping inside a ceiling lamp (`16:15:30 + 00:00:33.208`). Outdoors, a heavy armored enemy launches ~20 blocks straight into the sky in a standing walk pose with no jetpack VFX (`16:16:43 + 00:00:11.000` – `00:00:12.000`). Also, tilted flat decals/signs float detached below the supply-room ceiling (`16:15:30 + 00:00:32.208`, `00:00:41.208`).
   - **Severity:** Should fix
   - **Cause:** Uncapped knockback/jump impulse on NPC physics capsule, oversized step-up height indoors, and orphaned decorative entities.

10. **2D screen-locked fire overlay in VR**
    - **Time:** `16:16:43 + 00:00:12.000` – `00:00:14.000`, `16:16:55 + 00:00:00.667` – `00:00:01.667`, `16:20:58 + 00:00:10.958` – `00:00:13.958`
    - **What:** When the player is burning, a flat 2D row of jagged orange triangles is glued directly to the VR camera viewport with a hard cutoff edge.
    - **Severity:** Should fix
    - **Cause:** Legacy flat-screen HUD damage/fire overlay ported without converting to a 3D vignette or world/body-space particles for stereoscopic VR.

11. **Enemy laser beams clip straight through solid terrain/walls & deck gun flashes mob-red**
    - **Time:** `16:18:30 + 00:00:08.375` – `00:00:09.375`, `00:00:15.375`, `00:00:21.375`, `16:22:42 + 00:00:13.417`
    - **What:** Red targeting/laser beams pass unobstructed through solid stone walls and grass ledges (`16:18:30 + 00:00:08.375`), the deck gun's black T-handle floats detached behind its breech (`16:18:46 + 00:00:05.333`), and the entire metal turret flashes bright red like a wounded creature (`16:18:30 + 00:00:21.375`, `16:22:42 + 00:00:13.417`).
    - **Severity:** Minor / Should fix
    - **Cause:** Beam rendering skips voxel raycast occlusion clamping; turret is implemented as a living mob entity inheriting default red hurt-tint shader behavior.

12. **Massive unsupported floating skyscraper & house sections after voxel destruction**
    - **Time:** `16:22:06 + 00:00:12.875` – `16:23:00 + 00:00:28.083` (clearest at `16:22:42 + 00:00:02.417` and `16:23:00 + 00:00:04.083`, `00:00:11.083`, `00:00:22.083`)
    - **What:** Shelling the Capital tower obliterates its middle stories, leaving the entire multi-story top roof, skybridge, trees, and dozens of rubble blocks floating completely disconnected in midair. Shelling the town building (`16:23:00 + 00:00:22.083`) similarly leaves floating roofs, and a natural snow cave at `16:23:00 + 00:00:10.083` – `00:00:11.083` undercuts the town building's foundation over an empty pit.
    - **Severity:** Should fix
    - **Cause:** Lack of structural integrity / connectivity collapse checks when voxels are destroyed by artillery, and structure generation not filling foundations down to solid ground over caves.

13. **Chunk cutoffs, floating sky blocks, and broken orange tree shader in snow biome**
    - **Time:** `16:23:28 + 00:00:22.292` – `00:00:32.292`
    - **What:** Flying across the snow biome outruns chunk loading, exposing sharp terrain cutoffs into void fog (`00:00:22.292` – `00:00:24.292`). At `00:00:30.292` – `00:00:32.292`, three dark rectangular blocks float high in the sky near the horizon, and a distant pine tree on the far left renders as a flat glowing peach/orange silhouette (`00:00:31.292` – `00:00:32.292`).
    - **Severity:** Store-blocking
   - **Cause:** Slow chunk meshing/streaming during fast flight, leftover floating world-gen blocks, and corrupted fog/impostor shader lighting on distant tree billboards at sunset.

---

### Top 10 Worst Bugs in Priority Order for Store Release

1. **Missing terrain chunks & untextured floating structure proxies** (`16:12:58 + 00:00:12.208`, `16:23:28 + 00:00:22.292`) — Store-blocking: Seeing sky/void holes through the ground and grey box placeholders breaks core visual quality requirements.
2. **Camera-clipping opaque explosion quads blinding the VR headset** (`16:14:05 + 00:00:03.292`, `16:21:25 + 00:00:25.583`, `00:00:35.583`) — Store-blocking: Giant near-plane flashing squares cause acute VR discomfort and complete loss of visibility during combat.
3. **Black unlit geometry bands along smooth-voxel terrain slopes & wall corners** (`16:12:58 + 00:01:07.208` – `00:01:09.208`, `16:15:30 + 00:00:02.208`) — Store-blocking: Immediately visible broken rendering/normals across major landmark terrain.
4. **Overlapping HUD text, notifications, and depth-conflicting weapon UI** (`16:12:58 + 00:01:01.208`, `16:15:20 + 00:00:01.000`, `16:23:28 + 00:00:21.292`) — Store-blocking: Unreadable stacked text and UI rendering through held weapons fail Meta VR UI legibility/comfort standards.
5. **Destroyed turret barrels floating in midair** (`16:15:30 + 00:00:14.208`, `16:16:43 + 00:00:00.000` – `00:00:05.000`) — Store-blocking: Prominent combat entities remain suspended in empty air after their floors/bases are blown up.
6. **Floating blocks in sky & glowing orange tree LOD shader glitch** (`16:23:28 + 00:00:30.292` – `00:00:32.292`) — Store-blocking: Obvious world-gen garbage in the sky and broken distant billboard shading.
7. **Screen-locked 2D fire overlay in VR** (`16:16:43 + 00:00:12.000`, `16:20:58 + 00:00:11.958`) — Should fix: Head-locked 2D HUD triangles with hard edges are a classic flat-screen port artifact that causes eye strain in VR.
8. **Held/eaten 2D-extruded items detaching from VR hands, streaking, and clipping into eyes** (`16:14:27 + 00:00:21.708`, `16:14:52 + 00:00:03.833`, `16:15:00 + 00:00:07.125`) — Should fix: Breaks VR hand presence and shoves stretched pixels into the near clip plane when eating.
9. **Entire skyscraper tops & building roofs left floating in midair + undercut foundations** (`16:23:00 + 00:00:04.083`, `00:00:10.083`, `00:00:22.083`) — Should fix: Destructible-fortress showcase looks broken when disconnected multi-story roofs hang in the sky and town houses float over caves.
10. **LOD terrain spikes, snowy-to-green foliage color popping, and sky-high NPC physics launches** (`16:12:34 + 00:00:23.458`, `16:16:43 + 00:00:11.000`) — Should fix:Jarring visual pop-in while exploring and erratic boss/heavy NPC physics during firefights.

## Part 4 of 4

### Recorder Corruption Note
Recorder tiling/frame-buffer corruption appears throughout most of Part 4 (e.g., `16:23:28 + 00:00:36.792`–`38.292`, `16:24:02 + 00:00:03.000`–`40.000`, `16:26:27 + 00:00:00.250`–`15.750`, `16:29:23 + 00:00:00.125`–`36.625`) as repeated hall-of-mirrors strips along the right and bottom edges of the cropped frame. Per instructions, these recorder artifacts are excluded from the bug list below.

---

### Game Bugs Found (Chronological)

1. **Floating blocks/structures in sky**
   - **Time:** `16:23:28 + 00:00:32.792` – `16:23:28 + 00:00:38.292` (repeated at `16:24:02 + 00:00:00.000` – `05.500`)
   - **What you see:** Three large rectangular voxel masses float high in mid-air above the left snow horizon (`32.792`–`34.292`), and two/three cubic blocks float in the sky above the radar station on the right (`35.292`–`38.292`).
   - **Severity:** Should fix
   - **Likely cause:** Worldgen feature/prefab placement using an invalid Y-offset or failing to clear temporary structure blocks in air chunks.

2. **Hovering pine tree / detached dirt ledge on snow slope**
   - **Time:** `16:23:28 + 00:00:34.292` (and `16:24:02 + 00:00:00.500`)
   - **What you see:** A pine tree on the right snow ridge sits on a flat floating dark strip with its trunk hovering above the smoothed snow slope.
   - **Severity:** Minor
   - **Likely cause:** Tree decorator snapping to integer voxel grid height without extending trunk/root blocks down to meet smoothed terrain geometry.

3. **See-through black seam under station perimeter foundation**
   - **Time:** `16:24:02 + 00:00:10.500` – `16:24:02 + 00:00:22.000`
   - **What you see:** A long black crack/void gap runs beneath the snow station's concrete perimeter wall where the blocky foundation meets the sloped snow mesh.
   - **Severity:** Should fix
   - **Likely cause:** Smooth terrain surface meshing pulling away from axis-aligned structure blocks without foundation skirt/fill voxels underneath.

4. **Overlapping 3D HUD alerts, reload prompts, waypoints, and status bars**
   - **Time:** `16:24:02 + 00:00:15.000` – `16.000`, `16:24:02 + 00:00:29.500` – `30.000`, `16:25:13 + 00:00:41.167` – `42.167`, `16:29:23 + 00:00:21.625` – `27.125`
   - **What you see:** Alert/dialogue text (`The station alarm is sounding!`, `Ruth Underhill...`), red `EMPTY - Reload` prompts, death-chest waypoint text (`Your things 1920 m`), and health/hunger bars collide on the same floating HUD plane and become unreadable.
   - **Severity:** Should fix
   - **Likely cause:** Unstacked 3D UI canvas layers sharing overlapping local coordinates on the wrist/head-locked HUD.

5. **Missing terrain chunk / sky hole through snow mountain**
   - **Time:** `16:24:02 + 00:00:20.500` – `16:24:02 + 00:00:21.500`
   - **What you see:** Left of the pine tree in the background, a sharp geometric cutout in the mountain exposes bright sunset sky straight through the terrain.
   - **Severity:** Store-blocking
   - **Likely cause:** Faulty occlusion/frustum culling or dropped chunk mesh rebuild at a terrain LOD boundary.

6. **Floating foliage in sky and unrendered stair-stepped chunk borders after respawn**
   - **Time:** `16:24:48 + 00:00:00.083` – `16:24:48 + 00:00:06.083`
   - **What you see:** Right after respawning/flying, dark blocks and tree canopies float detached in mid-air (`00.083`–`00.583`), and a distant tree/structure sits on a sharp cutoff cliff (`04.083`–`06.083`) bordered by unloaded chunk seams.
   - **Severity:** Should fix
   - **Likely cause:** Chunk streaming bottleneck after respawn teleport and decorator/foliage pass executing before base terrain chunks finish meshing.

7. **Disembodied VR hands floating far ahead of player during flight**
   - **Time:** `16:25:07 + 00:00:04.000`
   - **What you see:** Two detached blocky grey hands/arms float in mid-air well below/in front of the camera while descending toward the garrison.
   - **Severity:** Minor
   - **Likely cause:** VR avatar hand transforms lagging behind high-velocity player movement by a physics/render tick.

8. **Overlapping controller button legends and tab tooltips in inventory/chest UI**
   - **Time:** `16:25:13 + 00:00:03.167` – `29.667`, `16:29:03 + 00:00:06.417`, `16:29:23 + 00:00:05.625`
   - **What you see:** Controller button prompts along the bottom of inventory and chest menus (`[L Grip]`, `[R Grip]`, `Next tab`, `Quick move`, `Sort`) overlap and mash together horizontally; top category hover tooltips (`03.167`, `28.667`) also overlap the tab bar.
   - **Severity:** Should fix
   - **Likely cause:** Hardcoded prompt positions without a horizontal auto-layout group or dynamic string width spacing.

9. **Detached off-hand floating beside machine pistol instead of gripping it**
   - **Time:** `16:26:37 + 00:00:11.542` – `16:26:37 + 00:00:51.542`
   - **What you see:** While two-handing the Hagel Machine Pistol, the grey blocky left hand floats several inches to the left of the weapon rather than holding the foregrip/magazine.
   - **Severity:** Should fix
   - **Likely cause:** Misaligned or missing secondary-grip IK socket on the Hagel Machine Pistol prefab.

10. **Black geometry blocking left half of VR view during close-range attack**
    - **Time:** `16:26:37 + 00:00:27.542`
    - **What you see:** When an enemy lunges at point-blank range, a solid black polygon covers nearly half of the player's viewport.
    - **Severity:** Should fix
    - **Likely cause:** Enemy mesh or player weapon clipping inside the VR camera near-clip plane without collision pushback or dither fade.

11. **Dead enemies freeze mid-air, hover above furniture, and clip into camera**
    - **Time:** `16:27:50 + 00:00:02.083` – `09.583`, `16:28:07 + 00:00:01.000` – `05.500`, `16:28:07 + 00:00:42.500` – `45.500`, `16:29:23 + 00:00:04.625` – `05.125`
    - **What you see:** Enemy corpses freeze tilted at 45° angles in the courtyard (`16:27:50 + 00:00:02.583`), hang suspended waist-high in narrow hallways (`16:28:07 + 00:00:01.000`, `16.000`), float horizontally ~1m above a room floor/table (`16:29:23 + 00:00:04.625`–`05.125`), and clip straight through the player's face when walked past (`16:28:07 + 00:00:45.000`–`45.500`).
    - **Severity:** Store-blocking
    - **Likely cause:** Corpse physics/gravity disables immediately on death or snags on walls/crates due to an oversized upright AABB collider.

12. **Two-block Bulkhead Doors split/desynchronize between upper and lower halves**
    - **Time:** `16:28:07 + 00:00:25.000` – `26.500` and `16:28:07 + 00:00:49.500`
    - **What you see:** Opening a Bulkhead Door toggles only one block half—leaving a floating closed top half (`25.500`) or closed bottom half (`49.500`) blocking the doorway mid-firefight.
    - **Severity:** Store-blocking
    - **Likely cause:** Multi-block Bulkhead Door lacks atomic state synchronization when interacted with by player raycasts or NPC AI.

13. **Enemies clip into ceiling and through closed Bulkhead Doors**
    - **Time:** `16:28:07 + 00:00:27.500` and `16:28:07 + 00:00:32.000`
    - **What you see:** `Capital Vanguard` bounces upward until its head/upper torso penetrates the ceiling (`27.500`), and another vanguard clips halfway through a closed/split Bulkhead Door (`32.000`).
    - **Severity:** Should fix
    - **Likely cause:** Excessive hit/jump vertical impulse with inadequate ceiling capsule sweep, and NPC pathing ignoring door collision bounds.

14. **Garrison deck gun barrels blocked by own roof battlements (self-detonates in face) + floating hands**
    - **Time:** `16:29:23 + 00:00:32.125` – `16:29:23 + 00:00:36.625`
    - **What you see:** Entering turret mode (`Manning the deck gun`) leaves disembodied VR hands floating over the turret hatch (`32.625`–`36.625`), and the twin gun barrels sit lower than the surrounding stone battlements (`34.125`–`34.625`). Firing immediately impacts the turret's own parapet wall, blinding the player with giant opaque grey/orange explosion voxels (`35.125`–`35.625`).
    - **Severity:** Store-blocking
    - **Likely cause:** Garrison prefab places stone crenelations directly in front of the deck gun muzzle height, plus unhidden/unattached VR hand avatars while possessing the turret camera.

---

### Top 10 Worst Bugs in Priority Order for Store Release

1. **Deck gun blocked by its own roof battlements & self-exploding in player's face (`16:29:23 + 00:00:32.125` – `36.625`)** — Store-blocking; a major interactive turret feature is unusable because its prefab geometry blocks its own barrels and blinds the VR user.
2. **Enemy corpses freezing mid-air, hovering over floors, and clipping camera (`16:28:07 + 00:00:01.000`, `16:29:23 + 00:00:04.625`)** — Store-blocking; occurs on nearly every kill indoors, obstructing narrow corridors and breaking immersion.
3. **Bulkhead Door top and bottom halves desynchronizing (`16:28:07 + 00:00:25.500`, `49.500`)** — Store-blocking; traps the player in doorways during combat with floating half-doors.
4. **Missing terrain chunk / sky visible through snow mountain (`16:24:02 + 00:00:20.500` – `21.500`)** — Store-blocking; obvious rendering hole exposing skybox through solid terrain.
5. **Overlapping controller button legends in inventory and chest menus (`16:25:13 + 00:00:11.167`, `16:29:03 + 00:00:06.417`)** — Should fix; illegible mashed button prompts on core UI screens frequently fail store QA review.
6. **Colliding 3D HUD text, reload warnings, alerts, and status bars (`16:24:02 + 00:00:29.500`, `16:25:13 + 00:00:41.167`)** — Should fix; critical combat feedback (`EMPTY`, health/hunger, alarms) renders on top of itself.
7. **Floating voxel structures/blocks in the sky (`16:23:28 + 00:00:32.792` – `38.292`)** — Should fix; highly visible worldgen artifacts in open daylight.
8. **Detached left VR hand floating beside two-handed firearm (`16:26:37 + 00:00:11.542` – `51.542`)** — Should fix; constantly in the player's central VR field of view whenever holding the machine pistol.
9. **See-through black gap under station concrete foundation (`16:24:02 + 00:00:10.500` – `22.000`)** — Should fix; exposes void along the entire length of a major point-of-interest wall.
10. **Enemies clipping into ceilings and through doors (`16:28:07 + 00:00:27.500`, `32.000`)** — Should fix; janky indoor combat physics and collision penetration.