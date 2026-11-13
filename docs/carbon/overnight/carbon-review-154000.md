### Recorder Corruption Check
No frame-wide mosaic tile corruption appears in any sampled frame. However, the recorder produces multi-second wall-clock overlaps between consecutive clips (`15:44:28 + 00:00:06.000`–`10.000` repeats as `15:44:34 + 00:00:00.000`–`04.000`; `15:44:34 + 00:00:09.000`–`15.000` repeats as `15:44:43 + 00:00:00.000`–`06.000`; `15:44:43 + 00:00:13.000`–`16.000` repeats as `15:44:56 + 00:00:00.000`–`03.000`), which is a recording quirk rather than a game bug.

---

### Findings (Chronological)

1. **`15:43:17 + 00:00:00.000`–`00:00:03.000` (also `15:44:28 + 00:00:00.000`, `15:45:14 + 00:00:03.000`–`00:00:04.000`) — Illegible menu button text**
   - **What you see:** Button labels on the *Game Paused* and *Create New World* panels break up into severely aliased, unreadable pixel noise.
   - **Severity:** Store-blocking (violates Meta Quest VRC usability/text legibility expectations).
   - **Likely cause:** Missing mipmaps or poor SDF font scaling/filtering on the world-space VR UI canvas.

2. **`15:43:17 + 00:00:04.000`–`00:00:08.000` — Player spawns into an empty, unpopulated world for 4 seconds**
   - **What you see:** After starting a new world, the player stands on a bare flat green plane with blocky distant silhouettes (`04.000`–`07.000`) before trees, grass, and shadows abruptly pop in all around the camera (`08.000`).
   - **Severity:** Store-blocking.
   - **Likely cause:** Camera/scene activates before initial spawn-chunk meshing and foliage placement finish, with no loading screen or VR fade curtain holding until completion.

3. **`15:43:17 + 00:00:08.000`–`00:00:10.000` & `15:43:32 + 00:00:03.000` — Broken procedural tree branch geometry**
   - **What you see:** A rigid plank-like diagonal beam cuts straight across the white birch trunk (`15:43:17 + 00:00:08.000`–`10.000`), and an upper-left tree branch bends sharply into an unnatural hanging V-elbow (`15:43:32 + 00:00:03.000`).
   - **Severity:** Minor.
   - **Likely cause:** Procedural tree spline/extrusion generator lacking angle clamping and collision checks against adjacent trunks.

4. **`15:43:17 + 00:00:08.000`, `15:43:32 + 00:00:02.000`, `15:43:41 + 00:00:00.000`, `15:43:41 + 00:00:05.000`–`00:00:06.000` — White pinhole cracks in leaf canopies**
   - **What you see:** Bright single-pixel sky dots leak through dark overhead leaf clusters and shimmer as the head moves.
   - **Severity:** Minor.
   - **Likely cause:** T-junctions/subpixel seams between adjacent foliage voxel faces or overly harsh alpha-test cutouts without MSAA alpha-to-coverage.

5. **`15:43:32 + 00:00:00.000`, `15:43:32 + 00:00:04.000`–`00:00:06.000`, `15:43:41 + 00:00:02.000`–`00:00:05.000`, `15:44:11 + 00:00:01.000` — Unoccluded red "Note" markers & debug coordinates**
   - **What you see:** Red `Note` labels render right through solid tree trunks and hills across a brand-new world, and raw `X/Y/Z` coordinates float on the HUD (`15:44:11 + 00:00:00.000`).
   - **Severity:** Should fix.
   - **Likely cause:** Leftover debug/waypoint world-space UI with depth testing disabled (`ZTest Always`) and no distance cutoff.

6. **`15:43:32 + 00:00:05.000`–`00:00:08.000`, `15:43:41 + 00:00:03.000`–`00:00:05.000`, `15:44:11 + 00:00:01.000`–`00:00:02.000` — Pitch-black Dark Oak trunks**
   - **What you see:** Dark Oak tree trunks crush to solid `#000000` silhouettes with zero visible bark detail while surrounding grass and birch trees are well lit.
   - **Severity:** Should fix.
   - **Likely cause:** Dark Oak albedo tint/vertex color is multiplied too dark and receives insufficient ambient/indirect light under canopy shadow.

7. **`15:44:11 + 00:00:02.000`–`00:00:04.000`, `15:44:11 + 00:00:09.000`–`00:00:10.000`, `15:44:28 + 00:00:01.000`–`00:00:02.000` — Floating detached leaves and paper-thin foliage sheets**
   - **What you see:** Chopped trees leave floating leaf clumps hovering mid-air (`15:44:11 + 00:00:03.000`–`04.000`, `09.000`); world-generated tall trees also spawn isolated square leaf blocks floating in open sky (`15:44:28 + 00:00:01.000`–`02.000`), and nearby foliage forms flat intersecting planes with square holes (`15:44:11 + 00:00:10.000`).
   - **Severity:** Should fix.
   - **Likely cause:** Incomplete leaf-decay flood-fill after trunk removal and canopy stamps exceeding support radius during tree generation.

8. **`15:44:28 + 00:00:05.000` & `15:45:14 + 00:00:01.000` — Single-frame full-screen dark flash mid-flight**
   - **What you see:** While flying in clear sky, the entire view abruptly dims dark gray/black for one frame and snaps back to full brightness the next frame.
   - **Severity:** Should fix (discomforting flicker in VR).
   - **Likely cause:** VR head-collision/comfort fade triggering spuriously against invisible sky/chunk bounds or cloud volumes.

9. **`15:44:28 + 00:00:06.000`–`00:00:10.000` & `15:44:34 + 00:00:00.000`–`00:00:07.000` — Stair-stepped flat ocean bands and raw shoreline seams**
   - **What you see:** Ocean water renders as flat untextured blue polygons with jagged rectangular stair-steps between depth colors and raw blocky grass/sand seams along the Greywall shore (`15:44:34 + 00:00:05.000`–`07.000`).
   - **Severity:** Should fix.
   - **Likely cause:** Per-chunk/per-voxel water depth coloring with no shoreline foam, alpha blending, or normal-mapped water shader at mid/far LOD.

10. **`15:44:34 + 00:00:09.000`–`00:00:11.000` & `15:44:43 + 00:00:00.000`–`00:00:04.000` — Turret-roof terrain hole and camera clipping inside solid geometry**
    - **What you see:** Ragged grass tufts and a hole sit right beside the Greywall cannon turret (`15:44:34 + 00:00:09.000`); dropping down reveals a raw brown dirt block embedded in the stone shaft ceiling (`10.000`), massive blocky white cubes filling the view (`11.000`), and the VR camera clipping completely inside a flat brown/black solid box (`15:44:43 + 00:00:04.000`).
    - **Severity:** Store-blocking.
    - **Likely cause:** Structure prefab failed to clear terrain voxels cleanly, and player/camera collider lacks head-pushback or near-clip protection during vertical drops.

11. **`15:44:34 + 00:00:13.000`–`00:00:15.000` & `15:44:43 + 00:00:05.000`–`00:00:07.000` — NPC culling/pop, broken spine pose, and clipping/illegible dialogue UI**
    - **What you see:** The *Greywall Dispatch* officer is invisible/culled at `15:44:43 + 00:00:05.000` while his dialogue prompt floats in empty air, appears with his upper torso twisted ~50° backward at `15:44:34 + 00:00:15.000`, and has unbacked white dialogue text that clips through his body/chest and washes out against the sky (`15:44:43 + 00:00:06.000`–`07.000`).
    - **Severity:** Should fix.
    - **Likely cause:** Aggressive skinned-mesh frustum bounds culling, un-clamped look-at IK twisting the spine bone, and unbacked world-space text with depth test disabled.

12. **`15:44:43 + 00:00:09.000`–`00:00:16.000` & `15:44:56 + 00:00:00.000`–`00:00:10.000` — Flying Dreadnought crashes straight through the Greywall tower, leaving floating blocks and broken tilted architecture**
    - **What you see:** Tower walls shatter outward (`15:44:43 + 00:00:09.000`–`13.000`) as a black Dreadnought vessel flies straight out through the middle of the building (`14.000`–`16.000`). Afterward, the tower's upper arch sits crookedly collapsed at ~30° while black voxel blocks and foliage hang completely detached in mid-air above it, accompanied by a stretched red horizontal bar in the sky (`15:44:56 + 00:00:00.000`–`10.000`).
    - **Severity:** Store-blocking.
    - **Likely cause:** Dreadnought spawn/flight spline intersects the Greywall prefab with voxel destruction active, triggering partial structural physics collapse that orphans un-updated floating blocks and stretches a world-space boss/health bar.

13. **`15:45:14 + 00:00:06.000`–`00:00:12.000` — Harsh LOD terrain boundary, untextured neon-green hills, and terrain tear**
    - **What you see:** Smooth, plastic-looking neon-green low-LOD hills meet detailed sand and trees along an abrupt chunk boundary where trees cut off instantly, with a dark jagged gash/tear at the bottom-left hill seam (`08.000`, `12.000`).
    - **Severity:** Should fix.
    - **Likely cause:** Missing LOD terrain splatmap/shader parity with near chunks and un-stitched vertex skirts between mismatched terrain LOD levels.

---

### Top 10 Worst Bugs in Priority Order for Store Release

1. **Dreadnought flies straight through Greywall tower, wrecking the structure and leaving floating debris/UI (`15:44:43 + 00:00:09.000`–`16.000`, `15:44:56 + 00:00:00.000`–`10.000`)** — Store-blocking; breaks a major landmark/event right in front of the player.
2. **Illegible menu UI button text (`15:43:17 + 00:00:00.000`–`03.000`, `15:45:14 + 00:00:03.000`–`04.000`)** — Store-blocking; core menus are unreadable and risk failing Meta Horizon Store VRC review.
3. **Turret-roof terrain hole and VR camera clipping inside solid interior blocks (`15:44:34 + 00:00:09.000`–`11.000`, `15:44:43 + 00:00:04.000`)** — Store-blocking; falling through messy prefab seams into solid geometry breaks navigation and comfort.
4. **Spawning into an empty flat world for 4 seconds before forest pop-in (`15:43:17 + 00:00:04.000`–`08.000`)** — Store-blocking; makes the opening seconds look broken instead of holding on a loading fade.
5. **NPC disappearing/culling, twisted spine IK, and clipping/unreadable dialogue text (`15:44:34 + 00:00:15.000`, `15:44:43 + 00:00:05.000`–`07.000`)** — Should fix; severely degrades quest/NPC interaction quality.
6. **Single-frame full-screen dark flash during flight (`15:44:28 + 00:00:05.000`, `15:45:14 + 00:00:01.000`)** — Should fix; full-field brightness flicker is uncomfortable in a VR headset.
7. **Floating detached leaf clusters after tree chopping and in worldgen canopies (`15:44:11 + 00:00:03.000`–`04.000`, `09.000`, `15:44:28 + 00:00:01.000`–`02.000`)** — Should fix; immediately noticeable during core woodcutting gameplay.
8. **Harsh untextured neon-green LOD hills and terrain seam tears (`15:45:14 + 00:00:06.000`–`12.000`)** — Should fix; makes open-world vistas and flight look unfinished.
9. **Blocky stair-stepped ocean color bands and raw voxel shorelines (`15:44:34 + 00:00:00.000`–`07.000`)** — Should fix; prominent whenever viewing coastal areas from elevation.
10. **Pitch-black Dark Oak trunks and unoccluded red "Note" debug/waypoint markers (`15:43:32 + 00:00:04.000`–`08.000`)** — Should fix; hurts visual polish and clutters the starting forest.