### Recorder Check
No frame-wide mosaic/tiling corruption from the recorder was observed in this capture (aside from the expected top-left frame crop). Note that `18:22:47 + 00:00:00.000` through `18:22:47 + 02:37:06.000` is a single static frame while the headset was idle, confirmed at `18:22:47 + 02:37:07.000` when the `"Paused while you were away (2h 37m)"` menu appears.

---

### Game Bug Findings

1. **`18:22:59 + 00:00:00.000` – `18:22:59 + 00:00:22.000`**
   * **What:** Sheep’s wool coat looks semi-transparent/patchy over its inner body mesh.
   * **Severity:** Minor
   * **Likely cause:** Incorrect alpha blending or depth-sorting on the outer wool layer shader.

2. **`18:22:59 + 00:00:23.000`**
   * **What:** A vertical tree-trunk/log block hangs suspended in mid-air beneath a wooden roof structure with its bottom cap exposed and no support underneath.
   * **Severity:** Should fix
   * **Likely cause:** Structure prefab placement or tree-clearing pass removed lower trunk blocks without clearing upper logs or extending supports to terrain.

3. **`18:22:59 + 00:00:36.000` (also `18:24:33 + 00:00:55.000` – `00:00:57.000`)**
   * **What:** A sharp, solid cyan-blue band appears behind the trees where distant terrain/water chunks are unloaded, clashing hard with the clouded skybox.
   * **Severity:** Should fix
   * **Likely cause:** Far-clip plane cutting off terrain before distance fog blends geometry into the horizon sky color.

4. **`18:22:59 + 00:00:45.000` – `18:22:59 + 00:00:51.000`**
   * **What:** Multiple green tree canopies float in mid-air on distant hills with no trunks beneath them.
   * **Severity:** Should fix
   * **Likely cause:** Aggressive LOD culling hiding thin trunk geometry at closer distances than leaf clusters, or chunk boundary truncation during tree generation.

5. **`18:22:59 + 00:00:56.000` – `18:22:59 + 00:00:57.000` (and `18:25:35 + 00:00:28.000` – `00:00:31.000`, `18:25:35 + 00:01:36.000`, `18:28:26 + 00:00:53.000` – `00:00:59.000`, `18:29:55 + 00:00:16.000`, `18:29:55 + 00:00:31.000` – `00:00:36.000`)**
   * **What:** Stretched cloud UVs near the horizon (`18:22:59 + 00:00:56.000`) and abrupt full-screen dark/bright flashes when flying through cloud altitude bands—uncomfortable in VR.
   * **Severity:** Store-blocking
   * **Likely cause:** Camera intersecting volumetric/planar cloud layers that darken screen exposure or lack smooth camera-fade transitions, combined with spherical skybox UV distortion.

6. **`18:22:59 + 00:01:05.000` (also `18:25:35 + 00:00:09.000`, `18:35:53 + 00:01:05.000`, `18:36:58 + 00:00:00.000`)**
   * **What:** Mode-switch confirmation modal (`"Switch to Survival?"` / `"Switch to Creative?"`) has overlapping, garbled, and clipped description text on the right (`"Fly freely, giv..."` colliding with `"sutton back he..."`, including a `"sutton"` typo).
   * **Severity:** Should fix
   * **Likely cause:** Unwrapped or mispositioned UI text elements overflowing fixed-width modal bounds.

7. **`18:24:33 + 00:00:49.000` – `18:24:33 + 00:00:54.000`**
   * **What:** The left half of the massive grey fortress (`Greywall Command Fortress`) is sliced off vertically into white fog/sky while the right half is crisp and solid.
   * **Severity:** Should fix
   * **Likely cause:** Chunk draw-distance culling cutting mid-structure without low-LOD impostor geometry.

8. **`18:25:35 + 00:00:04.000` – `18:25:35 + 00:00:06.000`**
   * **What:** On player death, the camera clips inside/underneath sloped rock terrain, exposing smeared subterranean faces and a black void hole at bottom-left (`00:00:04.000`).
   * **Severity:** Store-blocking
   * **Likely cause:** Death/ragdoll camera lacks terrain collision or drops below the player capsule collider.

9. **`18:25:35 + 00:00:07.000` – `18:25:35 + 00:00:10.000` (and `18:28:26 + 00:01:03.000` – `00:01:05.000`)**
   * **What:** Completely untextured, flat-shaded green and cyan low-poly hills appear right next to the player on respawn and at mid-range during flight before chunks populate.
   * **Severity:** Store-blocking
   * **Likely cause:** Slow voxel chunk streaming after teleport/fast flight exposing raw untextured terrain proxy meshes.

10. **`18:25:35 + 00:01:17.000` – `18:25:35 + 00:01:29.000`**
    * **What:** Black controller-help tooltip above the held item renders tiny, shimmering, nearly illegible text; meanwhile, distant world-space waypoint text (`"Greywall Command Fortress"`) draws directly on top of the player’s close-up hand/weapon (`00:01:20.000` – `00:01:25.000`).
    * **Severity:** Should fix
    * **Likely cause:** Missing mipmaps/VR text scaling on the hand tooltip, and depth-test disabled on world-space waypoint UI causing stereo/depth conflict over first-person items.

11. **`18:25:35 + 00:01:55.000` – `18:25:35 + 00:01:57.000`**
    * **What:** Skyscraper city blocks stream in floating in mid-air with sky and clouds visible underneath their foundations.
    * **Severity:** Should fix
    * **Likely cause:** Vertical chunk loading order prioritizing upper structure chunks before ground/base chunks.

12. **`18:25:35 + 00:02:07.000` – `18:25:35 + 00:02:09.000` (and `18:28:26 + 00:00:47.000` – `00:00:48.000`)**
    * **What:** Interior stone-brick ceiling textures are severely smeared into 1D parallel streaks across the entire room ceiling, and camera briefly clips into grey triangles at `18:28:26 + 00:00:46.000`.
    * **Severity:** Store-blocking
    * **Likely cause:** Broken triplanar/UV projection using X/Y wall coordinates on horizontal bottom-facing ceiling quads without Z-axis mapping.

13. **`18:25:35 + 00:02:20.000` – `18:25:35 + 00:02:52.000` & `18:28:26 + 00:00:00.000` – `18:28:26 + 00:00:45.000`**
    * **What:** Destroying the base/midsection of a skyscraper leaves huge upper stories (`18:28:26 + 00:00:07.000` – `00:00:20.000`), severed skybridges, thin green/brown strips, and black vehicle/turret props (`00:00:28.000` – `00:00:45.000`) permanently floating in mid-air.
    * **Severity:** Store-blocking
    * **Likely cause:** Incomplete connectivity/structural-integrity graph check on large multi-chunk structures and non-voxel entity props not receiving gravity updates when support blocks are destroyed.

14. **`18:29:55 + 00:00:55.000` & `18:29:55 + 00:01:15.000` – `18:29:55 + 00:01:16.000`**
    * **What:** Village NPCs render with completely blank, untextured solid-grey cube heads and bodies (`00:01:15.000`).
    * **Severity:** Store-blocking
    * **Likely cause:** Missing NPC skin material/texture assignment or failed async texture load on villager variants.

15. **`18:29:55 + 00:01:31.000` – `18:29:55 + 00:01:33.000`**
    * **What:** Torchlight produces harsh stair-stepped square banding on walls and three black crack/line artifacts at stepped ceiling block edges (`00:01:33.000`).
    * **Severity:** Minor
    * **Likely cause:** Unsmoothed per-voxel light propagation and greedy-meshing T-junction cracks or ambient-occlusion seam bleeding.

16. **`18:34:43 + 00:00:00.000` – `18:34:43 + 00:00:02.000` & `18:37:32 + 00:00:04.000`**
    * **What:** Detached tree trunk block (`18:34:43 + 00:00:00.000`) and isolated stray leaf/wood blocks (`18:37:32 + 00:00:04.000`) float in mid-air in the forest.
    * **Severity:** Minor
    * **Likely cause:** Procedural tree-branch generator placing disconnected blocks or chunk-seam clipping during worldgen.

17. **`18:35:45 + 00:00:12.000` – `18:35:45 + 00:00:14.000` & `18:35:53 + 00:00:03.000` – `18:35:53 + 00:00:12.000`**
    * **What:** While aiming through the sniper scope, the floating HUD hotbar (emerald, apple, bread icons, `"LOADED"` text, controller prompt) clips right across the zoomed scope view and black vignette mask.
    * **Severity:** Store-blocking
    * **Likely cause:** World/hand-attached HUD canvas is not hidden when scope overlay mode is active and renders in a conflicting render queue.

18. **`18:35:53 + 00:00:50.000`**
    * **What:** On the pause menu, the `"Save and Quit"` button overlaps directly on top of the bottom `"Tip:"` text box, colliding with the text.
    * **Severity:** Store-blocking
    * **Likely cause:** Extra menu button (`"Report a Bug..."` / survival options) pushes vertical layout stack past container height without dynamic resizing.

19. **`18:38:31 + 00:00:20.000` – `18:38:31 + 00:00:22.000`, `18:38:50 + 00:00:00.000` – `18:38:50 + 00:00:21.000`, `18:39:06 + 00:00:00.000` – `18:39:06 + 00:00:14.000`**
    * **What:** Volcano lava has cantilevered shelves floating in mid-air (`18:38:50 + 00:00:01.000`), paper-thin jagged edges hovering above rock (`18:38:50 + 00:00:21.000`), triangular holes/gaps in the lava surface mesh (`18:38:50 + 00:00:19.000`, `18:39:06 + 00:00:08.000`), and dark blotchy shadow smears across glowing lava (`18:39:06 + 00:00:09.000`).
    * **Severity:** Should fix
    * **Likely cause:** Fluid-mesh generator failing to stitch sloped flow vertices to neighboring magma/solid blocks, unsimulated static worldgen lava overhang, and terrain shadow/AO baking onto emissive fluid surfaces.

---

### Top 10 Worst Bugs in Priority Order for Store Release

1. **Sniper scope obstructed by clipping HUD/hotbar icons** (`18:35:53 + 00:00:04.000`, `18:35:45 + 00:00:12.000`) — Directly breaks core VR aiming gameplay and causes severe stereo depth discomfort.
2. **Abrupt full-screen dark/bright flashes when moving through cloud altitude layers** (`18:25:35 + 00:00:28.000` – `00:00:31.000`, `18:28:26 + 00:00:53.000` – `00:00:59.000`) — High VR comfort/photosensitivity risk during flight; likely to fail Meta VRC comfort review.
3. **Pause menu `"Save and Quit"` button overlapping bottom tip text** (`18:35:53 + 00:00:50.000`) and **garbled/overlapping modal text + typo** (`18:35:53 + 00:01:05.000`, `18:25:35 + 00:00:09.000`) — Immediately visible broken system UI that store reviewers flag on sight.
4. **Severely smeared 1D-streaked ceiling textures in building interiors** (`18:25:35 + 00:02:07.000`, `18:28:26 + 00:00:47.000`) — Obvious broken UV mapping across entire rooms.
5. **Untextured solid-grey placeholder village NPCs** (`18:29:55 + 00:01:15.000` – `00:01:16.000`) — Looks unfinished/missing assets to any player visiting a village.
6. **Death/interior camera clipping inside terrain and geometry** (`18:25:35 + 00:00:04.000`, `18:28:26 + 00:00:46.000`) — Exposes out-of-bounds black void and jagged polygons in VR.
7. **Broken skyscraper destruction leaving floating towers, debris strips, and vehicles in mid-air** (`18:28:26 + 00:00:07.000` – `00:00:45.000`) — Undercuts the sandbox destruction spectacle with permanent floating garbage.
8. **Untextured flat-green/cyan proxy hills on respawn and during flight** (`18:25:35 + 00:00:07.000`, `18:28:26 + 00:01:03.000`) — Makes the world look unrendered after respawning or moving quickly.
9. **Volcano lava mesh holes, floating lava overhangs, and dark blotches on emissive lava** (`18:38:50 + 00:00:01.000` – `00:00:21.000`, `18:39:06 + 00:00:08.000`) — Visually broken landmark biome.
10. **World-space waypoint labels drawing over close-up hands/weapons & unreadable tiny controller tooltips** (`18:25:35 + 00:01:17.000` – `00:01:25.000`) — Breaks VR stereo depth perception and makes controls hard to learn.