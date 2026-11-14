### Recorder Corruption Note
Aside from the expected top-left crop, one frame (`06:15:42 + 00:00:03.500`) displays a horizontal band of flat grey/tan screen-aligned rectangular tiles cutting across the world during a damage flash; this appears to be Quest tile-buffer/recorder corruption rather than a game bug and is excluded below.

---

### Game Bugs Found (Chronological)

1. **Exposed developer staging room on world load**
   - **Time:** `06:12:04 + 00:00:07.000` to `00:00:10.000` (also `06:12:14 + 00:00:00.000` and `13:22:08 + 00:00:07.500` to `00:00:10.500`)
   - **What you see:** Before spawning on the beach, the player briefly stands in a bare green box world with floating 2D debug icons, a placeholder cat NPC, and clipped floating text (`S... ILL`).
   - **Severity:** Should fix
   - **Likely cause:** VR camera activates in a staging lobby scene before initial terrain chunks finish generating instead of holding a loading fade/overlay.

2. **Floating flat water planes over caves/pits**
   - **Time:** `06:12:14 + 00:00:17.000` to `06:12:30 + 00:00:06.500`, and `06:13:04 + 00:00:03.500` to `00:00:06.500`
   - **What you see:** Thin blue water surfaces hang suspended mid-air across open sand sinkholes/caves with empty air underneath, and adjacent tree roots float unsupported over the pit rim.
   - **Severity:** Should fix
   - **Likely cause:** Water table meshes generate prior to cave carving without fluid volume filling or post-carve support checks.

3. **Pitch-black floating tree trunk & detached sky canopies**
   - **Time:** `06:12:43 + 00:00:02.000` to `00:00:10.000`
   - **What you see:** A completely black, unlit tree trunk hovers above the water (`00:00:02.000`–`00:00:03.000`), and detached leaf canopies float high in the sky on the left with no trunks (`00:00:05.000`–`00:00:09.000`).
   - **Severity:** Should fix
   - **Likely cause:** Tree prefabs clipped across chunk generation boundaries and missing vertex/lightmap baking on cut trunks.

4. **See-through hole in grass terrain mesh**
   - **Time:** `06:14:50 + 00:00:00.500` to `00:00:01.500`
   - **What you see:** A jagged triangular tear in the grass terrain exposes the skybox void underneath, with black corrupted grass alpha splats along the missing faces.
   - **Severity:** Store-blocking
   - **Likely cause:** Degenerate triangles or chunk-seam stitching failure in the smooth-voxel (Marching Cubes / Dual Contouring) surface mesher.

5. **Garbled overlapping controller prompts on Inventory UI**
   - **Time:** `06:14:54 + 00:00:15.500` to `00:00:37.500`
   - **What you see:** Bottom button legends (`Drop held`, `Grab Stack`, `Clear`) collide horizontally into an illegible overlapping string beneath the inventory panel.
   - **Severity:** Should fix
   - **Likely cause:** Fixed UI text anchors without horizontal layout spacing or dynamic width bounds.

6. **HUD text collisions & aiming reticle obstruction**
   - **Time:** `06:15:42 + 00:00:11.500` to `00:00:25.500`, and `06:28:08 + 00:00:27.500` to `00:00:30.500`
   - **What you see:** Multiple HUD readouts stack on top of one another (`Rounds 67` merges into `Fuel` as `Rounds 67Fuel`; radar/city distances overlap), and head-locked status text floats directly across the rifle's iron sights during firefights.
   - **Severity:** Should fix
   - **Likely cause:** Overlapping HUD canvas anchors and rendering world/head-locked text in the weapon aiming plane without depth/angle fade.

7. **Broken procedural railway junctions, missing rails, and ocean dead-ends**
   - **Time:** `06:16:26 + 00:00:01.000` to `00:00:06.000`, and `13:26:32 + 00:00:01.000`
   - **What you see:** Two tracks collide at a sharp 90° V-angle with no curved rail (`06:16:26 + 00:00:02.000`), sections of gravel bed lack rail meshes while adjacent rails float over sand (`00:00:04.000`–`00:00:06.000`), and coastal tracks run straight underwater into the sea (`13:26:32 + 00:00:01.000`).
   - **Severity:** Should fix
   - **Likely cause:** Track spline generator lacks corner curve fitting and fails block placement across uneven/submerged terrain heights.

8. **Moving train clips straight through hillside terrain and dozens of trees**
   - **Time:** `06:18:18 + 00:00:01.000` to `06:20:05 + 00:00:03.000`
   - **What you see:** While riding the Hollow & Greywall Railway, the train drives directly through an uncarved grass hillside (`06:18:18 + 00:00:02.000`) and continuously plows through full trees and leaf canopies spawned on the rails (`06:18:27 + 00:00:05.000`–`06:20:05 + 00:00:03.000`), shoving foliage repeatedly through the player's VR viewpoint.
   - **Severity:** Store-blocking
   - **Likely cause:** Tree scatter pass ignores railway exclusion corridors, and tunnel carving does not clear terrain to the train's bounding profile.

9. **Severed skyscraper top & helipad float unsupported in mid-air**
   - **Time:** `06:20:43 + 00:00:16.500` to `06:21:56 + 00:00:06.500`, and `13:24:39 + 00:00:16.500` to `13:25:06 + 00:00:08.000`
   - **What you see:** Blasting out the middle floors of the central Citadel tower leaves the entire multi-story upper penthouse, disconnected debris blocks, and severed helipad hovering motionless in the sky.
   - **Severity:** Store-blocking
   - **Likely cause:** Static world building voxels lack connected-component structural integrity / collapse physics when supporting blocks are destroyed.

10. **Unloaded terrain void & stars visible below horizon during night flight**
    - **Time:** `06:23:32 + 00:00:11.500` to `06:24:34 + 00:00:12.500`
    - **What you see:** For over a minute while traversing regions (`Entering Rhandor`), terrain fails to render at all, leaving the player surrounded by pitch-black void with skybox stars visible across the lower half of the view where terrain should be.
    - **Severity:** Store-blocking
    - **Likely cause:** Chunk streaming/meshing falls behind fast player traversal, exposing the full-sphere starbox through missing ground chunks.

11. **Pitch-black unlit building monoliths in night city**
    - **Time:** `06:28:08 + 00:00:08.500` to `00:00:44.500`
    - **What you see:** Several skyscrapers in the illuminated city render as completely black, featureless rectangular silhouettes (`00:00:08.500`, `00:00:16.500`, `00:00:39.500`) right beside lit towers and streetlamps.
    - **Severity:** Should fix
    - **Likely cause:** Missing voxel light baking or broken distant LOD shader/material assignment on specific city building prefabs.

12. **Camera clips inside Ironback Crawler hull during view transitions**
    - **Time:** `06:32:14 + 00:00:11.500` to `00:00:13.500` (also `06:35:03 + 00:00:10.000` and `06:35:13 + 00:00:01.000`)
    - **What you see:** Switching between the interior helm and exterior vehicle camera clips the VR viewpoint through hollow armor blocks and roof geometry.
    - **Severity:** Minor
    - **Likely cause:** Chase camera offset lacks collision sweeps or an instant cut/fade when transitioning out of interior vehicle seats.

13. **Giant wheeled Ironback Crawler climbs vertical walls & hovers high in mid-air**
    - **Time:** `06:32:14 + 00:00:16.500` to `06:37:17 + 00:00:15.000`
    - **What you see:** The massive wheeled crawler drives 45°+ up a vertical fortress wall with wheels hanging in air (`06:32:14 + 00:00:16.500`–`00:00:28.500`), and later sits completely suspended 30+ meters in mid-air above trees and grass (`06:34:25 + 00:00:15.000`–`00:00:20.000`, `06:35:13 + 00:00:19.000`–`00:00:24.000`, `06:37:17 + 00:00:06.000`–`00:00:15.000`), alongside floating detached turrets/wreckage (`06:36:26 + 00:00:10.500`).
    - **Severity:** Store-blocking
    - **Likely cause:** Vehicle rigidbody freezes/kinematic-locks when unmanned or rests on stale/unupdated colliders left behind by destroyed building voxels.

14. **Inside-out / hollow fallen log props & undercut floating snow ledges**
    - **Time:** `13:22:08 + 00:00:24.500` to `13:23:11 + 00:00:02.000`
    - **What you see:** Fallen log/cradle props in the snow biome have missing bottom/side faces (backface culling makes the bark shell transparent from the side, showing snow behind it) and float off sloped ground; nearby snow terrain forms thin floating overhangs (`13:22:30 + 00:00:12.500`).
    - **Severity:** Should fix
    - **Likely cause:** Uncapped single-sided mesh geometry or inverted face normals on log props, spawned without slope alignment.

15. **Bullion Train spawns derailed/clipping into buildings & wall void clipping**
    - **Time:** `13:26:08 + 00:00:08.500` to `13:26:22 + 00:00:15.500`
    - **What you see:** Armored train cars sit crooked at mismatched angles, intersecting sandstone terrain and a coastal building (`13:26:08 + 00:00:09.500`), and jumping between cars clips the camera into grey out-of-bounds void (`13:26:22 + 00:00:08.500`).
    - **Severity:** Should fix
    - **Likely cause:** Multi-car train spawned along uneven terrain without flattening the right-of-way or clearing overlapping village structures.

16. **Deep chasm floating black cubes, stretched rock UVs, and open void at world bottom**
    - **Time:** `13:27:38 + 00:00:25.000` to `13:28:16 + 00:00:34.000`
    - **What you see:** Descending the fissure reveals floating black cube artifacts (`13:27:38 + 00:00:40.000`, `13:28:16 + 00:00:04.000`), smeared vertical rock textures (`13:28:16 + 00:00:12.000`), and an unsealed world floor where the player drops out into empty purple starry void looking up at the circular underside of loaded chunks (`13:28:16 + 00:00:32.000`–`00:00:34.000`).
    - **Severity:** Store-blocking
    - **Likely cause:** Missing vertical terrain/portal seal between the Overworld chasm bottom and Underworld ceiling, plus planar UV projection stretching and stray unmeshed voxel cells.

17. **Grid-clipped hillside lava pools, floating rock blobs, and fog-ignoring red moon**
    - **Time:** `13:29:11 + 00:00:06.000` to `00:00:08.000`, and `13:29:37 + 00:00:13.000` to `00:00:39.000`
    - **What you see:** Bright lava pools sit on steep hillsides and terminate along razor-sharp rectangular chunk boundaries without flowing (`13:29:11 + 00:00:07.000`, `13:29:37 + 00:00:34.000`), disconnected rock chunks float mid-air (`13:29:37 + 00:00:38.000`), and the giant red moon renders at full contrast through dense horizon fog (`13:29:11 + 00:00:08.000`).
    - **Severity:** Should fix
    - **Likely cause:** Surface lava decorator paints blocks inside bounding boxes without basin checks or fluid updates, and skybox moon shader bypasses atmospheric fog blending.

---

### Top 10 Highest-Priority Fixes for Meta Horizon Store Release

1. **Ironback Crawler hovering 30m in mid-air & climbing vertical walls (`06:34:25 + 00:00:15.000`, `06:32:14 + 00:00:16.500`)** — Flagship ground vehicle completely defies gravity and parks in the sky.
2. **See-through hole in grass terrain mesh (`06:14:50 + 00:00:00.500`)** — Obvious open tear into the skybox void during normal surface exploration.
3. **Train driving straight through trees and uncarved hillsides (`06:18:18 + 00:00:02.000` – `06:20:05 + 00:00:03.000`)** — Over a minute of continuous geometry clipping right into the VR player's face; major comfort and polish failure.
4. **Unloaded world void & stars below horizon during night flight (`06:23:32 + 00:00:11.500` – `06:24:34 + 00:00:12.500`)** — Complete loss of visible terrain for 60+ seconds when moving quickly across biomes.
5. **Unsealed chasm bottom opening into out-of-bounds starry void (`13:28:16 + 00:00:32.000` – `00:00:34.000`)** — Player sees the raw underside of the loaded chunk cylinder floating in empty space.
6. **Severed Citadel skyscraper top & helipad floating unsupported (`06:20:43 + 00:00:17.500`, `13:24:39 + 00:00:16.500`)** — Core voxel destruction leaves massive multi-story building tops hanging in mid-air.
7. **HUD text collisions & sightline obstruction (`06:15:42 + 00:00:18.500`, `06:28:08 + 00:00:27.500`)** — Overlapping HUD strings (`Rounds 67Fuel`) and UI text blocking gun iron sights hurt basic readability and VR combat.
8. **Inside-out / see-through fallen log props in snow biome (`13:22:08 + 00:00:24.500` – `13:23:06 + 00:00:05.500`)** — Missing/culled faces on common world props immediately look broken up close in VR.
9. **Garbled overlapping button prompts in Inventory UI (`06:14:54 + 00:00:15.500` – `00:00:37.500`)** — Store QA routinely flags unreadable/overlapping controller button legends.
10. **Exposed green debug staging room during world creation (`06:12:04 + 00:00:07.000`, `13:22:08 + 00:00:07.500`)** — First impression on starting a new world briefly shows an unfinished developer test room.