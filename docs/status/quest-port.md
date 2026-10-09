# Blocksmith on Meta Quest 3 — port status (session E, branch `claude/quest-port`)

Native Quest 3 build of Blocksmith: the shared Swift game code (world gen, chunks, meshing, simulation, mobs,
structures, saves, menus, audio synthesis) cross-compiled with the official **Swift SDK for Android** (Swift 6.4.0,
NDK r30), with a new **Vulkan + OpenXR** renderer and a **NativeActivity** entry point (no Java), packaged as a
sideloadable debug APK by GitHub Actions.

## Install on the Quest 3 (Remington's Mac)

The CI publishes every build two ways:
- branch **`quest-dist`**: just `blocksmith-quest.apk` + `BUILD.txt` (one line: commit, milestone, run id, versionCode).
- the workflow artifact `blocksmith-quest-<run>` (APK + `questcheck.log` + `stereo.png` render test).

```sh
cd ~/ClaudeTools/quest            # any folder
git clone --depth 1 --branch quest-dist https://github.com/remingtonangus-lang/blocksmith.git quest-dist 2>/dev/null \
  || (cd quest-dist && git fetch --depth 1 origin quest-dist && git reset --hard FETCH_HEAD)
cat quest-dist/BUILD.txt
~/ClaudeTools/quest/platform-tools/adb install -r quest-dist/blocksmith-quest.apk
```
The APK is signed with a fixed debug key (`quest/android/debug.keystore`), so `install -r` updates in place and keeps
saves. If an install ever fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, run `adb uninstall com.blocksmith.quest`
once (this deletes the Quest worlds).

Launch: Quest library → filter **Unknown Sources** → **Blocksmith**. Or `adb shell am start -n com.blocksmith.quest/android.app.NativeActivity`.

Logs (startup, load timings, a `perf:` line every 5 s): `adb logcat -s Blocksmith`. The same output is written to
a file on the headset for the whole session (the previous launch's is kept too), so it can be fetched afterwards:
`adb pull /sdcard/Android/data/com.blocksmith.quest/files/blocksmith.log` (and `blocksmith.prev.log`).
Stop: `adb shell am force-stop com.blocksmith.quest`

## Controls (Touch controllers; right-handed default)

| Touch | Game (Mac pad equivalent) |
|---|---|
| Right hand ray | aim: the block/mob the laser points at is the target (the game's look is aimed from the eye at the ray's hit) |
| Right trigger | break / attack / fire (RT) |
| Right grip, or left trigger | use / place / aim (LT) |
| Left stick | move (relative to the left controller; Quest options: head) |
| Right stick left/right | snap turn 45° (or smooth turn) |
| Right stick flick up / down | fly toggle (D-pad up) / drop item (D-pad down) |
| A / B | jump / sneak (in menus: select / back) |
| X / Y | pick block or reload / inventory (tap); hold X: swap offhand, hold Y: world map |
| Left grip | hotbar left (LB) |
| Right stick click | hotbar right; hold: weapon wheel, then push the right stick at a gun and let go (no turning while held) |
| Left stick click | sprint (L3) |
| Menu (left) | pause |
| In menus | the laser is the mouse: trigger = click, grip = right click; the left stick also moves the pad cursor |

Physically walking moves the player (with collision). Ducking lowers the view. Snap turns and fast movement darken the
edges of the view (comfort vignette). The HUD is a panel in the lower view that follows the head lazily; menus open
as a panel in front of you. Rumble from the game (hits, explosions, block breaks) plays on both controllers.

Interact hint: when the laser rests on something the grip opens or uses (chest, barrel, furnace, crafting table, door,
lever, a ship's helm), a label beside the dot names it ("Grip Open Chest") and the controller gives a light tick. Works
on ships too (the laser now tests ship blocks).

Riding ships: panels (HUD, inventory, menus) live in your room's space and travel with you; the ship's turns turn your
view with the deck (the horizon stays level when the hull pitches or rolls); ship physics steps once per displayed
frame (no judder). While the ship moves or turns, a faint ring at your feet gives a steady reference, and the vignette
reacts to the ship turning and changing speed (not to cruising).

**Pause → VR Comfort & Controls** (A or trigger on a row; the stick left/right steps a value): Turning (Snap / Smooth),
Snap Angle (15-90°) or Smooth Turn Speed, Movement (Smooth / Teleport: push the left stick forward, aim the arc, release),
Move Direction (Controller / Head), Comfort Vignette (Off / Low / Medium / High), Ship Deck Ring, Seated Mode (leaning
doesn't walk you), Recenter View, Dominant Hand, Refresh Rate (72 / 80 / 90 / 120 Hz; 90 by default), Foveated Rendering, HUD Position (Middle / Low / Lower), Texture Detail (High 128 px / Medium 64 px, next launch), Auto Render Distance (on: if frames are missed at the headset's limit the render distance steps down for the session, with a message).

## Milestones

| | Milestone | State |
|---|---|---|
| 1 | CI APK launching to an OpenXR session (test scene) | done: runs on Remington's Quest 3 (versionCode 13) |
| 2 | Real world in stereo (multiview), head tracking, 72 Hz budget | done: 72.0 fps, 0 missed, cpu ~2.9 ms, gpu ~2.9 ms on device |
| 3 | Touch controller play (locomotion, turning, vignette, hand rays, panels, haptics) | played on device (v13); ship panels, chests and comfort options fixed in v17 |
| 4 | Game content (mobs, structures, vehicles, soldiers, saves, actions) | shared game unchanged on the Quest; checked headless: all 99 mob kinds draw, ships/frigates ridden, chests, guns + weapon wheel, death/respawn, saves round-trip; device: played v13 |
| 5 | Performance and comfort pass with measured numbers | device v13: 72 fps, cpu/gpu ~2.9 ms; comfort options (v17); tick/path/scan optimizations measured headless; auto render distance guard |

### QUEST APK READY log
(The Mac monitor installs these; newest last.)

**QUEST APK READY 37243571730** (2026-10-04, versionCode 9, commit 6f520c1, `quest-dist` BUILD.txt says run
37243571730). First APK ever: nothing has run on a headset yet, so this is the bring-up build. What to check, in order
(each step depends on the one before; a `adb logcat -s Blocksmith` capture from launch to the first problem is the
most useful report):
1. **Starts at all (M1).** logcat shows `Blocksmith Quest 6f520c1 ... starting`, `xr: runtime ...`, `xr: Vulkan device
   ...`, `xr: LOCAL_FLOOR space` (or STAGE/LOCAL), `xr: swapchain WxH x2 layers`, `xr: refresh rates [...], using 90 Hz`,
   `xr: session state 5` (FOCUSED). In the headset: an immersive scene opens (not a flat window). A crash here shows
   as `FATAL:` or a native backtrace in `adb logcat` (unfiltered: `adb logcat -d | grep -A40 "Fatal signal"`).
2. **Loading scene, then the world (M2).** While the world generates (several seconds), a sky-blue scene with eight
   coloured cubes circling you and a progress bar 2 m ahead; then a new world appears around you at the right scale (blocks ~1 m, eyes at player
   height), both eyes agree (no double vision), head turns and leans track with no swim. logcat `load: ...` lines
   with timings, then a `perf:` line every 5 s (fps, missed frames, worst frame with its own cpu / tick / world streaming /
   record / gpu split, average cpu/gpu ms, sections, draws, chunks). The number to report: fps (72
   expected) and GPU ms (< 13.8 ms needed).
3. **Controls (M3)** per the table above: left stick walks, right stick snap-turns, A jumps, the right hand's laser
   targets blocks (outline), right trigger breaks, right grip places, Y opens the inventory as a panel the laser
   clicks, menu button pauses. Controllers drawn as small grey bodies with the laser; held item in the right hand.
4. **Comfort**: edges darken during snap turns and fast moves; nothing flickers; the HUD panel stays low in view.
5. Pause → Quit saves and closes the app (back to Home).

**QUEST APK READY 37247239826** (2026-10-05, versionCode 13, commit 6c996db): supersedes the one above; same checks.
New: the whole session's log also lands in `/sdcard/Android/data/com.blocksmith.quest/files/blocksmith.log` (pull it
after playing); the block textures are cached after the first launch (the second launch should reach the world
noticeably sooner: compare the `textures:` lines, "painted in N ms" then "from cache"); volcanoes and Ancient Spires
show on the horizon past the render distance; if OpenXR/Vulkan setup fails the app returns to Home (with `FATAL:` in
the log) instead of hanging in an empty scene.

**QUEST APK READY 37254222137** (2026-10-05, versionCode 17, commit 9560534): fixes from the first headset test. Check:
1. **Moving frigate**: stand on a moving ship (or `/vessel skyward` and board it): the HUD stays low in view and an
   opened inventory / chest stays in front of you while the ship moves and turns; the view turns with the deck, no
   judder against the world; a faint ring at your feet while the ship moves or turns; the edges darken when it turns.
2. **Chests**: point the laser at a chest (on the ship and on land): a label "Grip Open Chest" appears beside the dot
   with a light tick; the right grip opens it. Same for barrels, furnaces, crafting tables, doors, levers, the helm.
3. **Comfort**: Pause (left menu button) → **VR Comfort & Controls**: try Movement: Teleport (push the left stick
   forward, aim the green arc, release), Snap Angle, Smooth turning, Comfort Vignette strength, Seated Mode,
   Refresh Rate 90 Hz.
4. At the helm, the left stick steers and throttles regardless of where the controller points.
5. The moment the world appears: logcat lines `adopt: ...` (each hand-over step's ms) and `first world frame: ...`;
   the long frame seen last time (367 ms) should be gone or show which step it is.

**QUEST APK READY 37263324278** (2026-10-05, versionCode 24, commit cb3ec66): everything in 17, plus:
- Render distance 8 by default (was 6; the headset had ~10 ms of GPU headroom). Pause → Render Distance now sticks
  across launches. Check the `perf:` lines stay at 72 fps with `missed 0`; if not, set 6 there and report the numbers.
- Weapon wheel: hold the right stick click, push the right stick at a gun, let go (it used to open but couldn't pick,
  and the stick snap-turned you). In menus the right stick scrolls lists and flips crafting-book pages.
- The pause menu no longer shows rows that do nothing in VR (Photo Mode, Split Screen, Fullscreen, Display, VSync,
  Max Frame Rate, Resolution, World Scale, Graphics, Field of View, Bug Notes).
- Mob path searches 4x faster (fewer hitches near villages and herds); the latest playtest-branch content (vehicle
  riding fixes, plant support, crafting book).
- Not mapped on Touch yet: D-pad left (chat; Commands is in the pause menu) and the View tap (third-person camera, not
  useful in VR). (Later builds: hold X swaps the offhand, hold Y opens the map.)

**QUEST APK READY 37267431530** (2026-10-05, versionCode 29, commit 7139f83): everything in 24, plus:
- 128-pixel block textures (sharper up close; Pause → VR Comfort & Controls → Texture Detail goes back to 64 if memory
  or the first launch's painting is a problem: the first launch after an update paints them, later launches load
  them from the cache; compare the `textures:` log lines).
- Far terrain past the loaded world: a hazy height field out to ~1.3 km (from the playtest branch), with the volcano
  and spire impostors standing on it. Check the horizon looks continuous and frame time is unchanged.
- The `perf:` lines end with `resident N MB` (process memory): please include a few from a long session.
- After a recenter (hold the Meta button) the HUD and an open menu come back in front of you.
- New content from the playtest branch: aircraft and capital air bases (at a helm the left stick is raw throttle and
  steering; the view stays level while the aircraft banks).

**QUEST APK READY 37270248211** (2026-10-05, versionCode 33, commit 746fe9a): everything in 29, plus:
- Screen effects cover the view instead of tinting the HUD panel: underwater / lava / portal / sleeping tints, and
  getting hurt, burning and freezing as red / orange / pale glows at the edges of the view. Check: take damage (red
  edges, not a red rectangle on the HUD), sleep in a bed (the view fades).
- Gliding steers with your head (it followed the right hand's laser).
- The spyglass and sniper scope no longer black out the HUD panel (no zoom in VR yet).

**QUEST APK READY 37275086406** (2026-10-05, versionCode 39, commit 52b85b6): everything in 33, plus:
- Comfort: walking up stairs and slabs eases the view up over ~0.1 s instead of jumping (falls and jumps unchanged);
  Auto Render Distance (frames missed at the headset's limit step the render distance down for the session, with a
  message); HUD Position (Middle / Low / Lower) on the VR page.
- Taking the headset off or opening the system menu stops the world; the pause menu is up when you come back.
- Relaunching right after quitting starts cleanly (the app quits its process when it ends; before, a quick relaunch
  could exit at once or reuse stale GPU state).
- The playtest branch's citadel patrol and crew fixes.

**QUEST APK READY 37277759406** (2026-10-05, versionCode 42, commit c893928): everything in 39, plus:
- Hold Y opens the world map (a tap still opens the inventory, on release); hold X swaps the offhand (a tap is still
  pick block / reload). Check: hold Y ~0.5 s for the map, tap Y for the inventory.
- Pause > VR Comfort & Controls > Touch Controls: a reference page of every Touch button; the pad / keyboard
  reference, key binding and button mapping rows are hidden in the headset.

**QUEST APK READY 37295092290** (2026-10-05, versionCode 45, commit 72f84a8): everything in 42, plus:
- Fewer hitches: tables the game used to build the first time something happened (the first footstep, the first
  block change, the first vehicle) are built on the loading screen (5-7 ms each, a missed frame); sounds not
  synthesized yet play a moment later instead of being synthesized inside the frame.
- The frame thread registers with the runtime as the app's main and render thread (XR_KHR_android_thread_settings):
  check logcat for `xr: frame thread <tid> registered (main 0, renderer 0)` (0 = success).
- Game ticks allocate almost nothing now (median 219 -> 5 heap allocations a tick: mob collision); the playtest
  branch's NaN-trap and wooden shelf crash fixes.
- Check: perf lines' worst frame after the first minute (was 20.8 ms on versionCode 13).

### Device reports

**2026-10-05 21:50 ADT, versionCode 13 (6c996db), Remington's Quest 3.** Works: launches into an immersive session,
the world loads, playable. Refresh rates offered [72, 80, 90, 120], using 72. perf: right after load 65.9 fps, 8
missed, worst 367 ms (the world appearing); then 72.0 fps, 0 missed, worst 20.8 ms, cpu ~2.9 ms, gpu ~2.9 ms,
~136 sections / ~294 draws / ~123k quads, 193 chunks (render distance 6): large GPU and CPU headroom. Problems (his
priority): (1) on a moving frigate the UI panels fly away and the view lurches; (2) a chest on the frigate could not
be opened; (3) motion sickness: wants a comfort pass (vignette on smooth movement and ship riding, stable reference
aboard, teleport option, snap-angle option, seated mode, less camera motion on ships).

## Architecture

- `quest/shims/{simd,os,Metal}`: pure-Swift stand-ins so the shared code's `import simd` / `import Metal` / `import os`
  compile unchanged: SIMD helpers, float3x3/float4x4, simd_quatf; os_unfair_lock; MTLDevice/MTLBuffer protocols.
- `quest/mac-only.txt`: shared files the Quest build leaves out (App, main, Renderer, Vibrant, Clouds, AppKit/AV-only
  files, Mac-only test harnesses). Everything else in `Sources/` is compiled as is.
- Seams in shared code (behaviour-neutral on the Mac, `#if canImport(...)` guards only): Input.swift imports,
  Controller.swift PadManager, SoundEngine.swift AVAudioEngine class, Music.swift MusicStream, Narrator.swift speech,
  ShipRender.swift Metal drawing.
- `quest/src/common`: what the excluded files provided — `SoundEngine` (software mixer: panning, rolloff, occlusion,
  underwater low-pass, reverb, music and jukebox streams), `PadManager` (Touch controllers as a pad + haptics),
  zlib-backed `NSData.compressed`, `NSHashTable`, `CFAbsoluteTimeGetCurrent`, data folders, the HUD host.
- `quest/tools/extract_hud.py`: generates the Mac HUD/menu builder (`buildHUD`, from Sources/Renderer.swift) at build
  time, so every HUD and menu change on the Mac shows up on the Quest without edits.
- `quest/src/vk`: Vulkan: `QuestDevice` (MTLDevice whose buffers are persistently mapped VkBuffers — MeshArena slabs
  are drawn in place), `SceneRenderer` (multiview render pass, pipelines, texture array, the Mac's cave-culling walk,
  base-vertex section draws), `WorldRenderer` (the Mac's Fast-path draw order: terrain, mobs, entities, outline, sky
  dome/stars/sun/moon, water), `HudPanel` (HUD/menus into an image shown as a world-space panel).
- `quest/shaders`: GLSL 450 ports of the Fast-path Metal shaders, `GL_EXT_multiview` (both eyes in one pass);
  compiled to SPIR-V by `quest/tools/shaders.py` (glslc from the NDK).
- `quest/src/xr/XRSession.swift`: OpenXR (Khronos loader): XR_KHR_vulkan_enable2, LOCAL_FLOOR, 2-layer swapchain,
  Touch action set + haptics, FB refresh rate, EXT performance settings, session lifecycle.
- `quest/src/app`: `QuestApp` (frame loop, background loading with a loading scene, frame stats), `QuestRig`
  (tracking space → world: body yaw, recentring, eye height calibration), `QuestControls` (input mapping, aiming,
  panels, vignette, roomscale), `QuestSettings`.
- `quest/src/android/AndroidMain.swift`: `android_main` (android_native_app_glue), logcat redirect, lifecycle, saves.

## Testing without a headset

- `quest/tools/linux-check.sh [build]`: type-checks / builds everything for Linux (Swift 6.4 toolchain, Vulkan +
  OpenXR headers). `build/quest-linux/questcheck` runs world gen + meshing, 20 s of Touch-pad play through
  Game.tick, the mixer, a save round trip; `--render out.png` renders a stereo frame through the Quest renderer on any
  Vulkan device (lavapipe): docs/status/quest-render-lavapipe.png.
- `questcheck --xr SECONDS` runs the real QuestApp against a desktop OpenXR runtime. Against Monado (simulated HMD) on
  lavapipe it reaches a FOCUSED session with the swapchain created; Monado's compositor then crashes inside lavapipe
  (no external-memory support) even for a clear-only frame, so frame submission is verified on the device only.

## Log

- HANDOFF (2026-10-05, usage nearly out): everything is pushed. Latest: 90 Hz default, VR fuzz test (QuestFuzz,
  6 seeds clean), head-in-wall fade (view fades to black with the head inside a solid block; QuestSim checks it).
  APK versionCode 46 (5183939) is on quest-dist; 1928b68's Quest run is green, the Mac run was still queued.
  Next: READY entry for the next published build (90 Hz, wall fade, allocation pass); device check of the
  `perf:` worst-frame split at 90 Hz; the Mac heavy lane's tours duplicate (tv_craftbook2 = tv_craftbook_all) belongs
  to the playtest branch.
- 2026-10-05 (afternoon): spike and allocation pass with questcheck's new allocation counter / tracer
  (quest/tools/alloccount.c + alloctrace.py): first-use tables warmed at load, frame thread registered with the
  runtime, tick allocations 219 -> ~8 a tick (collision boxes, pathfinding 311 -> 7 a search, banners, simd shim),
  options cached, overlay vertex buffers reused, perf line splits the worst frame. Merged playtest twice (sweep and
  pathfinding conflicts resolved to the playtest's versions plus our scratch reuse). Mac CI note: the heavy lane's
  tours job is red on the playtest branch too (run 37281846206) and here (run 37295092357): imagecheck duplicate_frame,
  tv_craftbook2 and tv_craftbook_all render the same image (shared crafting-book content, not the Quest port);
  shots went green here once the playtest's cave_dark_mobs fix (a71187a) was merged.
- 2026-10-05: first APKs (packaging fixes: case of the output dir, pipefail exits, Bionic FILE/open), first headset
  run (v13) works at 72 fps; perf (bee-nest and heart scans, exclusivity checks off); ship riding, container hint,
  VR comfort page, teleport, seated mode (v17).
- 2026-10-04: groundwork (shims, seams, headless check), Vulkan renderer verified offscreen, OpenXR layer verified up
  to a focused session on Monado, app/controls/audio/Android entry, CI pipeline. `.claude/ALLOW_STOP` removed on this
  branch (standing order: never stop).

## TODO (queued 2026-10-05, from PENDING-REQUESTS.md; not implemented)
- Quest: lying-down / reclined mode. Add a recenter that resets world, horizon, UI panels and HUD to the current gaze
  direction including pitch (not just yaw/height). Easy toggle (controller button + menu option), remembered between
  launches. Extend the existing comfort/seated options (v48).
- Blocksmith (Mac + Quest) BUG: can't place blocks quickly in a row. Suspect input read as a fly attempt (double-tap
  jump) or a rate limiter. Held or rapid placement should be smooth, ~4 ticks. Reproduce with a controller test, fix.
- Factions (decided): the Capital is separate from Steelhold, not a replacement; Crawlers are their own faction; all
  three are hostile to each other on contact.
- 2026-10-05: playtest merged into quest-port (65 commits, no conflicts); new APK via quest CI to quest-dist.

HANDOFF 2026-10-05: local branch claude/quest-port in worktree blocksmith-playtest holds the clean merge (committed, NOT pushed:
no GitHub credentials in the headless session). Next: `git push origin claude/quest-port`, wait for quest.yml, adb install -r.

2026-10-05 (task 15): DONE in code, NOT pushed (no GitHub credentials; no gh/adb here). (1) Quest Reclined Mode: Options > Reclined Mode
(QuestSettings.reclined, saved); Recenter View / Meta-button recenter then tilts the rig (QuestRig.tilt) so the gaze pitch is level;
implies seated leaning. Not yet checked on a headset or in QuestSim. (2) Placement: held place cooldown 0.25 -> 0.2 s (4 ticks), and
the double-tap-jump fly toggle is ignored while right-click is held / within 0.4 s of a placement (Game.swift). Also committed on
claude/blocksmith-playtest (edeca149). Next: push both branches, wait for CI, adb install -r the Quest APK.

2026-10-05 (task 16): pushed dc74393e + follow-up; Quest CI run 37377397178 green, APK versionCode 51 on quest-dist (includes cc12b60f rapid placement).
(1) Water: no code change to water.frag since the port except the sRGB finalColor wrap; best guess = linear blending of gamma-authored water on the sRGB
swapchain (darker/more opaque). Compensated in water.frag (alpha x0.8, colour lifted). UNVERIFIED on device; if still wrong, try preferring UNORM swapchain
formats in XRSession.swift:277. (2) Caves: Mac's caveFill ported to chunk.vert (misc.w = QuestSettings.brightness, default 0.75) + Brightness row on the VR
page. (3) Smooth turning is now default at 90 deg/s; snap kept as an option; QuestSim snap checks set it explicitly. (4) cc12b60f verified in the build.
No Quest was attached to adb, so nothing installed.

## Task 17 (Quest controls, untested on headset; Quest sources compile only in the quest CI lane)
- Rapid placing: the real limiter was AimAssist.sticky (Sources/PadActions.swift): it kept the old target while a freshly placed block
  in front of it was only ~1 closer (centre test, 0.6 margin), so every held placement after the first hit an occupied cell. Now compares
  entry distances (0.3 margin). Also helps Mac pads. The 0.2 s cooldown from cc12b60f was fine.
- Water: quest/shaders/water.frag restored byte-for-byte from 6c996db (v0.13); the sRGB "compensation" in dc74393e was the regression.
  chunk.vert is unchanged since (cave fill/brightness kept).
- Controls: snap turn default (key renamed quest.smoothTurn2 so old saved values reset); R stick up/down = reclined-only pitch steps
  (QuestRig.stepPitch, 15 deg); L trigger = fly toggle; hold L grip = drop (0.4 s, keep holding = stack); R grip alone places;
  hotbar by pointing + R trigger (QuestControls.hotbarPointer; Game.padHotbarScroll=false); HUD raised so the hotbar centre is
  `hudDrop` below eye level (0.42 at 1.25 m ~ 18 deg). Help rows in QuestOptions.touchRows updated.

## Task 20 (2026-10-06): water, waves, controls, combat, mobs

### WATER-NOTES (fourth attempt: cause found)
Cause: the Quest cave fill (dc74393e, chunk.vert) puts a cool minimum light of 0.26-0.57 (Brightness 0.75, x2 Fast)
on every vertex with skylight 0. Water is skyStop and skylight drops 1 per block below the surface, so every ocean floor
deeper than ~15 blocks is "skylight 0" exactly like a cave: the deep seabed went from the old 0.055 floor (near black)
to a lit grey-blue that shows through the translucent water, flattening the dark deep-ocean look into a mediocre teal.
The task-20 skylight gate (fill off at skylight 5+) only fixed shallow seabeds. The Brightness contrast term (g = 0.2)
also lifted mid-depth seabeds ~15-20%. The Mac A/B missed it (that view's seabed was shallow; Fancy has its own water).
Fix: misc.y = eye darkness (from the smoothed eye skylight caveK: 0 at skylight 12+, 1 at 6 or less; 1 without sky).
chunk.vert scales the fill by it and blends Brightness toward neutral 0.5 by it, with the v48 0.055 floor back: standing
in daylight the world (and every seabed) shades exactly like v48; in caves / deep dives / the Emberdeep the fill and
Brightness work as before (eased in over ~0.5 s by caveK's smoothing). No cost (one uniform, two multiplies).

#### Earlier attempts (kept for history)
Builds: versionCode = quest.yml run number. v48 = 2a9b5c3 (water looked good), v51 = c2eaa41 (first green build of
dc74393e), v52 = db2596a (water.frag restored to v0.13), v57 = adf1e7b.
Ruled out (diff of quest/ v48..HEAD: only chunk.vert, WorldRenderer.swift misc.w, controls/options/sim files):
- water.frag: identical to v48 since db2596a, so not the cause.
- Swapchain / sRGB: unchanged since the first port (fc5b3598 / 520c6cf6; `git log -S SRGB`). There was no sRGB switch
  in "v0.49" (run 49 was cancelled). Blend state, depth write, far-to-near translucent order (SceneRenderer "water"
  PipeDesc), textures, fog, sky: unchanged in quest/.
- chunk.vert cave fill (dc74393e, Mac Fast caveFill port) is the ONLY quest render change in the window. Mac A/B with
  the same fill on/off (seed 777 ocean, noon, Fast): mean colour of the ocean region (72,134,174) vs (72,134,173),
  i.e. no visible daytime effect. Kept anyway, now gated by vertex skylight (fades out by skylight 5) in chunk.vert and
  the Mac Fast chunkVS, so the night surface / dark seabeds aren't lifted.
Best remaining suspects:
1. Shared Sources/ changes merged after v48 that feed the Quest mesh: Mesher.swift waterlogging (kelp/seagrass cells
   now drawn as water source cells, internal water faces next to kelp gone), Blocks.swift waterlogged twins
   (`skyStop = true`, changes heightmap/skylight under water), World.swift fluid changes. A v48-vs-HEAD Mac Fast A/B of
   a low ocean view (seed 777 --up 2 --fast) was started, then stopped; do that first next time (two fast builds).
2. The Brightness contrast term in chunk.vert (`lit + lit*(1-lit)*g`, g = 0.2 at default 0.75): lifts mid-tones of the
   seabed slightly; try Brightness 0.5 on the headset (g = 0) as a quick device test.
3. Time of day / position differences in what Remington compares; ask for the bug note's seed/position if one exists.

### Ocean waves (new)
chunk.vert: water corners at 14/16 of a cell (source surfaces) at sea level (world y 124.5-127.5) under open sky
move by `oceanWave` (common.glsl: three long sines, ~6 cm). All corners at that height move, so tops and side faces
stay joined. water.frag tilts the ripple normal by the wave slope. A few ALU per water vertex only.

### Other task-20 fixes (checked by `Blocksmith --questbugs`, all pass on the Mac build; Quest-only parts compile in quest CI)
- Movement: left stick follows head yaw only (the "Move Direction: Controller" option is gone); sprint-swimming and
  ladder pushes follow the head (Player.moveLook), not the aiming hand.
- Swim-out: pushing into a wall in water lifts you (5 m/s while there's room 0.6 up), step-up works in water and for
  0.15 s after leaving it (Player.wetGrace): a 1-block bank above the surface is climbed in ~1.4 s.
- Held tools/weapons: sprites at real size (sword ~0.85 m diagonal, other tools/bows ~0.7 m), gripped at the handle.
- Swing Mode: every landed swing is a full hit (was 0.8-1.5x from swing speed, a normal swing gave 0.8x); sword values
  were already 4/5/6/7/8 (stone kills a 20 HP zombie in 4). Note swings faster than the 0.5 s hurt invulnerability
  don't add damage (reference behaviour).
- Ore drops were already lapis 4-9 / sparkstone 4-5 with reference Fortune; now covered by the check.
- Skeletons/strays/parched/bogged hold a bow (bowParts), raise it while drawing and shoot from it (Mob.bowMuzzle).
- Mob sounds: snow golem voice, creeper / magma cube idle; Quest mixer adds interaural delay + far-ear head shadow.
- Mob looks: more detail boxes (zombie, skeleton, creeper, spider, farm animals), feet/underside shading in
  writeMobVertices, full Mac mob shader ported to quest mob.frag (all patterns, emissive, gloss).

## Task 21 (2026-10-07): Remington's v61 bug round (18 items + corrections a-d)

### Movement: what was actually wrong
The Quest walked in the *aim* frame: the stick was rotated by `headYaw - player.yaw`, and `player.yaw` is the right
hand's aim. Anything that moved `player.yaw` later in the same tick (`aimGame`, gun aim assist, PadLook) leaked into
the walk direction, so waving the right hand bent movement. `headYaw` was also `atan2` of the head's forward vector,
which jitters and spins when looking steeply up or down. Now: `Player.moveYaw` is a separate locomotion yaw,
`QuestRig.updateMoveYaw` takes the head's *level* yaw (`XRMath.levelYaw`, stable under pitch and roll, no position
or lean term), smooths it (~80 ms) and adds the snap-turn/recenter body yaw; the left stick is passed raw. Walking,
flying, swimming and ladders use only it. `--questbugs` proves a randomly waving hand changes displacement by 0.

### Status
- [x] 1 movement: left stick + smoothed head yaw only (correction b); questbugs walk/strafe/fly/swim/ladder checks
- [x] 2 sneak: left stick click (hold; tap latches), on the Shortcuts page
- [x] 3 melee: swing mining 8x; swing damage = trigger damage on average, 0.75x-1.25x by swing speed (correction a)
- [x] 4 troopers: muzzle-to-target `World.clearShot` (any collidable block stops fire); mobtests glass-wall check
- [x] 5 lily pads: water top face no longer culled under lily pads (Mesher)
- [x] 6 spawn: seed-random origin across x and the latitude bands (`Game.spawnOrigin`)
- [x] 7 rare buildings: spacing x1.5 (about 0.44x as many)
- [x] 8 military bases: `--structscan` (24 seeds: min 2, mean 9.7 per 4096^2; gating in snap.sh)
- [x] 9 guns loaded/empty: magazine hidden + red indicator strip when empty, loaded/last-round sounds, HUD text
- [x] 10 crafting: manual grid removed, recipe book only
- [x] 12 inventory search (inventory and recipe book)
- [x] 15 commands: suggestions/autocomplete, /bases /citadels /frigates /villages /rare, wrapped log lines;
      spaces or hyphens accepted for underscores, autocomplete inserts them, keyboard has "_" (correction c)
- [x] d guns: more model detail, held guns 2.4x on Quest
- [x] 11 nights: renderers light the world with `Game.renderDaylight` (floor 0.26 instead of 0.12, still moon-blue);
      Fancy night ambient raised; gameplay daylight (spawning, sleep, sensors) unchanged
- [x] 13 saddle: craftable (3 leather over leather-iron-leather; there was no recipe), found by search; use it while riding a tamed horse saddles it; on a wild horse a toast says how to tame it
- [x] 14 bed remodel (frame, headboard, footboard, quilted mattress, pillow; turned per facing) + furnace retexture
      (stone blocks, riveted iron band, arched mouth, iron top plate with flue; dispensers keep the old stone)
- [x] 16 Quest held tools ~1.4x bigger again
- [x] 17 fall damage: 4 free blocks, then 0.6 per block (10 blocks: 4 hp, was 7)
- [x] 18 sea state from the weather (`Weather.sea`/`swell`): Quest swell 0.6x calm .. 5x thunderstorm (uniform
      `waves.x`), boats ride it; boats wear while sailed (~100 min per point calm, ~3 min rain, ~30 s storm) with
      warnings. The Mac's water stays flat (no swell there).

## Task 22 (2026-10-07): Remington's v63 bug round 2 (11 items + water port)

Causes found (fixed unless noted):
- Sprint: the only Quest path was the pad's auto-sprint (stick y > 0.95 after the dead-zone curve, held 0.35 s); the
  Touch stick's round gate rarely gives that, and a latched sneak (stick click) blocked it. QuestControls now starts it
  at >0.8 deflection within ~40 deg of forward after 0.1 s (game L3 edge), clears a latched sneak, ticks the left hand,
  and toasts the first time.
- Horses: speeds already varied (4.8-14.5 b/s, uniform) but unridden horses all wandered at the same spec speed. Now
  4.8-16 b/s, and wander/bolt speed scales with the stat (fast horses visibly move faster); ridden steering uses the
  head yaw (Player.moveYaw), not the aiming hand.
- Cave light -> dark -> light: eye adaptation was the eye block's skylight at 4 %/frame against a narrow 12-6 ramp, and
  the cave fill stopped at vertex skylight 5, leaving cave-mouth walls (skylight 5-10) darker than both outside and the
  filled inside. Now: eye + 4 open neighbours, ~0.7 s real-time ease, ramp 13.5-4.5, fill fades out by skylight 10.
- Mobs dark in caves: the Quest never set MobLight.fill / nightVision (the Mac Renderer does): mobs kept a 0.21 fill
  against ~0.57 cave walls. WorldRenderer sets them per frame (same fill and eye darkness as chunk.vert).
- Trigger damage: hits landed at the cooldown's charge (0.2 + 0.8 c^2); Quest players click every ~0.3 s, so an iron
  sword did ~2.5. Game.bufferAttacks (Quest): a click before the cooldown waits for it (0.7 s) and lands full strength.
  questbugs: a click every 0.25 s kills a 20 HP husk in 4 iron-sword hits.
- Swing Mode is physical: the drawn blade (fist for bare hands) must enter a mob box or a block (swept segment, so
  passing near does nothing) at >= 2.2 m/s tip speed; power = tip speed / 4.5 (0.5-1.5x); one hit per swing; the
  swing hits what it touched (Game.swingBlock / swingMob), not the laser target. QuestSim: an air swing with the laser
  on a block does nothing, a punch into it breaks it.
- Held tools with Swing Mode off: no code path hides them (drawHeld ignores Swing Mode). QuestSim now renders an iron
  sword held up with Swing Mode off (vrsim_held.png) to check on CI; not reproduced.
- Water (the pretty Mac water had never been ported): water.frag is now a port of the Fancy waterVibFS without scene
  copies: Schlick Fresnel to a sky-dome reflection, ripple + swell normals, sun glint, depth absorption from the
  mesher's per-corner water depth (Mesher.waterDepthAO, Quest only: AO bits of water faces), shore foam, rain rings,
  tumbling side faces, the surface from below. Swell: 11/7/4.5 m waves, 14 cm crest x Weather.swell (calm 0.6, storm
  5; it was 20-40 m long and ~4 cm: invisible), damped on shores. Edge see-through: the translucent pass culls back
  faces above water (inner side faces blended over the surface). questcheck renders a shore view (stereo_water.png).
- Water on lava: worldgen never ticked lava touching water; WorldGen.hardenLava turns it to obsidian / cobblestone.
  Water not flowing: saved chunks scheduled no fluid ticks, and surface water beside air was skipped; World.springs
  now covers saved chunks, flowing cells and the surface band; pistons schedule fluids.
- Villagers did go to bed but stood beside it (no lying pose): Mob.lying draws them on their back on the mattress.
- Bed heads dropped nothing (the head half has no item) while removing the foot: either half drops the bed now.
- Saddles: MountMenu (inventory while riding, or sneak-use a tamed mount): saddle, horse armour, chested pack; saddles
  and horse armour drop when the mount dies.

## Task 23 (2026-10-07): Remington's round 3 bug list (10 items; features queued in docs/requests/round3-features-after-reset.md)

Causes found (fixed unless noted):
- Sprint (third report): a Touch stick shoved forward also *clicks*; that click was sneak (held = sneaking), and
  sneaking blocks sprinting. A stick click that starts with the stick pushed out (> 0.45) is now a sprint, only a
  centred click sneaks; the push zone is wider (> 0.7 within ~45 deg). A ">> SPRINT" tag shows left of the hotbar
  while sprinting, "Too hungry to sprint" toasts in survival at hunger <= 6. QuestSim 1b checks a push and a pushed
  click both sprint (> 4 blocks in 1 s, not sneaking). Never had a device-path test before.
- Capital friendly fire: Capital shells (bases.quiet) broke citadel blocks and hurt Capital troops; Explosion now
  spares both inside a citadel. Capital ships never pick or keep a target inside a citadel (they'd shell their own
  walls), so a stationed frigate no longer harasses a player raiding its base. Frigate wrecks don't crater a base.
- Manned heavy gun: the gunner stood 1.3 m behind the turret centre at deck height: inside the 5.5 m gunhouse model.
  Now on the roof ahead of the cupola (eye ~7 m up, over the barrels); leaving puts him behind the rear overhang.
- Magazines: rifle 45, SMG 60, shotgun 10, sniper 8, launcher 2, arc 12, sidearm 18.
- Spawning: the hostile spawner walked down from a random y to the first floor, so every sample inside rock became a
  cave spawn. Now half the attempts take the surface, the rest an exact random y that must already be open.
- Cave pools: aquifer cells filled flat 16-block slabs with rock plugs at chunk edges and stone plates under them.
  Now carved wet cells fill, then drainAquifers lets out any water touching air beside/below (or the chunk edge):
  only basin pools remain. gencheck (3 seeds, 288 chunks): no underground water leaks.
- Horses: the attack ray skips the mount you ride (raycast except:); mount hearts replace the hunger row (survival).
- Held tools vanishing: not reproduced; likely the 8 MB scratch ring filling on busy frames (drawHeld draws last
  and silently returns when < 96 verts fit) or an aim-pose tracking blip. Now 12 MB with a 1 MB tail only hands and
  the held item may use (overflow logged once), and drawHeld keeps the last tracked aim pose.
- Blurry tools: entity.frag samples texel-exact from mip 0 within 4 m of the eye (min filter + mip blend smeared it).
- Voidwalkers: 1.5 s of steady stare (drains 2x when looking away), not a glance.

## Round 4 (2026-10-08): Remington's v0.66 playtest list (docs/requests/round4.md, 16 items)
All 16 done, one commit each (see `git log --grep "Round 4"`). Gameplay items (1-7, 9, 11, 12, 14, 15) are also on
claude/blocksmith-playtest as cherry-picks.
- Capital: dropships land at a random bearing round the podium (1); deck guns fire only with a live gunner (2); heavy
  shells fly flat at 260 m/s and burst on hulls, one hit kills a Capital vessel's drive and blasts the hull (3, 4);
  shells hitting another hull add a 1.5x ship blast (5); Capital ships need a clear line of fire within 180 blocks (6).
- Vehicles: Capital fliers can be commandeered: the use button aboard or within 6 blocks of a crewed helm (9 for a
  hovering dropship), toast + 'Take command' label; frigate bridge helm and a new dropship helm fly kinematically (7, 9).
  On a ship's deck the head-yaw walk is turned into the ship's frame (8).
- Swing Mode: a real swing attacks what the laser picks within 6 blocks, nearest block first; a sword prefers a mob on or
  within 10 degrees of the ray (10).
- Spawning: monster cap 70 -> 24; underground 1 attempt in 4, packs of 2, none with 6 monsters within 32 blocks (11, 12).
- Laser always drawn: keeps the last hand pose through tracking blips, priority scratch room, 3 m beam fading to 0.2 (13).
- Bonded horse (14): the last tamed horse ridden is yours (saved); unridden it stays within ~10 blocks; Y (fly button) in
  survival calls it: gallops over if near, otherwise it is brought ~14 blocks behind you from any distance, even stored
  with a chunk 2,000+ blocks off. questbugs checks a call from 2,100 blocks.
- Junk pickup (15): dirt-like blocks, flowers, grass, ferns, saplings, leaves, vines, seeds need standing over them 1 s or
  crouching; drops from blocks you break still come straight in.
- VR sprint (16): 1.3x a full walk in any stick direction at any push past 0.3.
- Shipped: Quest CI run 37812876024 green, APK versionCode 69 on quest-dist (commit 6968b57). Not installed (adb saw no
  Quest). The first run failed QuestSim's VR ship chest check: 5b left Swing Mode on, and the test's one-frame aim snap
  onto the deck chest counted as a swing, which since item 10 breaks the laser's block. Fixed in the test (Swing Mode off
  for shipRide). The check now also prints the interaction state when it fails.

## Round 3 features (2026-10-08): docs/requests/round3-features-after-reset.md (6 items + save safety)
One commit each (`git log --grep "Round 3 ("`); all shared gameplay is also cherry-picked to claude/blocksmith-playtest.
- Save safety (SaveMigration.swift): renamed/removed block and item keys resolve through alias tables (chunk palettes,
  ship grids, item stacks) before the unknown -> air fallback; a world without extra["format"] >= 3 is copied once to
  `<Blocksmith>/Backups/<world>-before-r3-<time>` before it loads (Quest: next to its Worlds folder). Remington's Mac
  worlds were also copied by hand to Backups/all-worlds-before-r3-manual-20261008.
- Titanium replaces diamond: save keys stay `diamond_*` (so saved diamonds ARE titanium, nothing to migrate); names,
  ingot sprite, grey-blue tier colour, worn tint; the ore drops Raw Titanium (smelts to the ingot); ore = five small
  silver flecks at ~1/3 of iron ore's contrast, no Fancy glint; veins rarer (5x3 + 2x6 + 1-in-12 x8).
- Steel: 2 iron ingots + coal/charcoal -> 2 Steel Blend; Steel Blend smelts ONLY in a blast furnace -> Steel Ingot;
  steel armour 17 points (iron 15, titanium 20), toughness 1, anvil repair with steel ingots.
- Copper replaces sparkstone: the ores are gone (saved ones load as copper ore via the alias table, +2 deep copper veins);
  Copper Wire = copper ingot + stick -> 4; circuit parts keep their keys and read Copper Wire / Signal Torch / Lamp /
  Battery / Repeater / Comparator with copper textures.
- Jetpack (Jetpack.swift): chest slot; steel/copper wire/bucket/copper recipe; 60 s tank (durability bar + HUD gauge);
  hold jump in the air (Quest: A) to climb ~6 b/s; refuel by crafting it with coal/charcoal (+15 s) or blaze powder (+30 s).
- Gun enchantments (table + anvil books, guns only): Extended Magazine I-III (+25 %/lvl), Quick Reload I-III (-18 %/lvl),
  Stability I-III (spread, bloom, recoil -18 %/lvl), Penetration I-IV (a bullet passes through that many mobs at 70 %
  each; named Penetration because the crossbow's Piercing owns that key), Incendiary (4 s burn, orange tracers).
- Lighting (Mac Fast path + Quest, same maths, per-vertex): sky-lit faces blend toward a cool sky ambient + warm sun
  diffuse (golden at dawn/dusk); amber torch light at low levels; a cheap filmic shoulder + 1.08 saturation on world
  surfaces (not HUD); sun disc with a soft halo in the sky dome. ~14 ALU per fragment, no new passes or uniforms.
  Quest GLSL can now be checked locally: glslang from KhronosGroup/glslang release main-tot
  (glslang-main-macos-universal-release.tar.gz), symlinked as glslangValidator, then `python3 quest/tools/shaders.py OUT`.
- Also: heavy shells expire after 3.5 s (mobtests 'shells land'), mobtests rifle reload expects 45 rounds.
- Checks: `--questbugs --only r3` (44 checks: migration, titanium, steel, copper circuit, jetpack flight/fuel, gun
  enchantments) 0 failures; mobtests 0 failures. Known, not from this round: snap checks shard structcheck 8 issues,
  collisiontest walk_through 3, agent life unmet goals (same on the playtest branch's last heavy run). The questbugs
  sword hits-to-kill check was flaky (zombie natural armour rounds at random); it now allows one extra hit.
- Shipped: Quest CI run 37865688060 green, APK versionCode 70 on quest-dist (commit 34eb124); questcheck renders look
  right (directional face shading visible). Not installed: adb saw no Quest. Playtest branch: b48260e1.
- Tip: `EXTRA_SWIFTC_FLAGS=-O ./build.sh fast` gives an optimized build in a few minutes; harness runs are ~40x faster.

## Task 21 store-quality pass (2026-10-08): Remington's own list (8 items)
One commit per item (`git log --grep "store-quality"`). Mac worlds backed up first to
`~/Library/Application Support/Blocksmith/Backups/all-worlds-before-task21-store-20261008`; no block/item IDs changed.
- 1 Lily pads: a single leaf 1/16 over the water surface (was a 1/16 slab 2/16 above it, edges showing), darker leaf
  with a wet edge (the bright rim outlined it); the Quest's chunk.vert bobs them with the swell (0.7 of the wave).
- 2 Horse family (Animals.swift horseParts): barrel + deep chest + rump, jointed legs (upper, cannon, dark hoof) with
  knee/hock bend, arched maned neck ~40 deg, long head with muzzle/eyes/ears/forelock, two-part tail; walk in diagonal
  pairs with head nod and tail sway, gallop above ~4.5 b/s, idle grazing; donkey/mule longer ears, shorter legs. Saddle,
  chests and armour follow; rider height unchanged. Harness: `./snap.sh NAME --mobs --mobkind horse,donkey [--mobwalk A
  --mobspeed S --mobgraze --saddled --mobyaw DEG]`.
- 3 Water: the Quest mirrored the sky dome's horizon/zenith colours, the Mac's Fancy water mirrors the fog-coloured haze
  up to fogColor x (0.45, 0.6, 0.92) plus a sun disc: the Quest's reflection read darker/more saturated. Ported that
  skyAlong, the Mac glint (7) and ripple fade. questcheck now renders three water views (shore to sea, deep water out
  to sea, deep water side-on) and logs the matching Mac snap flags. Quest GLSL checked locally with glslang
  (~/ClaudeTools/glslang/bin on PATH, `python3 quest/tools/shaders.py OUT`).
- 4 Movement: still head yaw + left stick only; reclined it now uses the levelled gaze (it read the room-space head,
  unstable lying down). QuestSim checks a waving aim hand doesn't bend reclined walking.
- 5 Animals: generation packs in 3.5% of chunks (was 10%), creature cap 5 (was 10). Already-generated chunks keep theirs.
- 6 Held items: tools/swords/items 1.3x, guns 3.2x the screen model (was 2.4), blocks 17 cm; tool sprites are five
  stacked layers (one texel thick) rolled 40 deg toward the eye: held straight they were seen edge-on as slivers.
  QuestSim renders vrsim_carry_sword/gun.png (hand at the hip).
- 7 Mac Xbox: Halo Infinite layout preset (default on the Mac only; Quest unchanged): Y tap = switch to the previous
  hotbar slot, Y hold = inventory, B crouch, R3 melee, L3 sprint, X reload, LB/RB hotbar (Halo's grenade/equipment have
  no slot equivalent). Look: 170 deg/s at sens 3, vertical 75%, acceleration after 0.15 s to 1.9x, dead zone 0.10,
  ADS speed scales with zoom. Options > Controller > Button Mapping > Layout switches Halo / Classic. `--padtest`.
- 8 Recenter: hold the left Menu button 0.7 s (a tap still pauses) or Recenter View. Reclined Mode (saved) levels world,
  horizon, HUD and menus to the gaze incl. pitch: the HUD/menus are now placed in the levelled frame (before, they were
  placed in the room's horizontal plane, which the tilt swung below the view). QuestSim "VR reclined" checks.
- First-30-min polish (subagent hunt, seeds 12345/777/4242): stars faded by daylight showed near-full in a bright sunset
  sky (now Game.starAlpha from the sun's height; Quest too); animal pack placement read the world top-down per block
  (7-25 ms ticks every ~1 s near spawn; now a chunk-array scan); a ~50 ms first tick built three block tables (now in
  Game.init behind the loading screen). Not fixed: 15-75 ms first frame after load, one 20-35 ms sound tick, ~50 ms first
  block placement.
- fidelitycheck hurt-invulnerability used a zombie (natural armour rounds at random: flaky) -> pig. ridecheck crew/troops
  failures also reproduce on 3e1dc99e (pre-existing flakes).
- Checks: Quest CI run 37875068649 green (VR reclined checks pass), APK versionCode 73 on quest-dist (final: run 37878386108, versionCode 74, commit 291e838); Mac CI fast lane
  questbugs 0 failures; mobtests 0 failures; padtest new checks pass. Not installed: adb saw no Quest.
- Note: a subagent once ran `Blocksmith --mobtests` without --snapshot, which opens the GUI game; use `./snap.sh NAME --mobtests`.

## Task 22 world depth + final battle (2026-10-09)
One commit per item (`git log --grep "Depth item"`). Mac worlds backed up first to
`~/Library/Application Support/Blocksmith/Backups/all-worlds-before-task22-depth-20261009`; no block/item IDs changed
(the old bedrock floor in saved surface chunks is migrated on load; DeepTests load every saved Mac world).
- 1 No bedrock floor: below y -24 emberslate takes over with magma and sealed lava pockets; monsters deep down are
  tougher (Mob.power, saved: damage taken / power, dealt x power).
- 2 The Deep (Dim.deep, DIM-2): a 384-tall dimension stacked under the surface. Dig through the surface floor and you
  carry on at its top; climb out of its top to come back. Layers top-down: upper crust, a hell band (EmberGen at base
  200, Emberdeep fortresses), lower crust, the Ash Vault (open ~100-block cavern, pillars, lava rivers, lumenstone
  roof), molten core. Vault updrafts give slow falling on long drops. F3 y continues below -64.
- 4a The Ashguard's sites (AshSites.swift): citadel at x 0, z 0 of the vault (walls, towers, command bunker, barracks,
  motor yard, gun pits), staging column, motor pools, fuel depots, supply hubs, artillery batteries, eight pillbox
  outposts on a 470 ring, patrol camps beyond; roads along both axes and a ring road. Black ashcrete/plating with red
  lamps and ember marks; no real insignia anywhere.
- 4b The fight (AshUnits.swift, AshWar.swift): Cinder tanks (close to 12-26 blocks, 0.6 s tell + muzzle glow before
  the main gun, coaxial MG; 1.6x damage from behind), half-tracks (circle, pintle MG), field guns (high arc on whatever
  any unit spotted, helpless inside 20 blocks), trucks (fuel trucks explode), Ashguard soldiers (Steelhold AI in
  black/red, faction saved), the Ash Marshal (boss bar; marked barrages: a red flare 2 s before each shell; calls four
  guards at 2/3 and 1/3 health). His death is the victory: the army stands down, an epilogue scrolls, a lift plate in
  the command bunker carries you to your spawn. Advancements: Bottom of the World, The Vault Below, Tank Buster,
  Ashes to Ashes. In the Deep a compass points to the citadel. Balance: worst single hit on an unarmoured player 11.
- Checks: `--questbugs --only deep` (layers, seam, sites, war: tank/half-track/field gun engage, brew-up + salvage,
  barrage + guard, victory, stand-down, save round trip, lift); full questbugs 0 failures; mobtests + posecheck 0.
- Perf notes: idle Ashguard vehicles more than 90 blocks away skip their AI; shells from Ashguard guns never break
  blocks and spare Ashguard units (Game.ashQuiet).
- Shipped: Quest CI run 37887470068 green, APK versionCode 75 on quest-dist (commit 5226983); Mac CI fast lane green.
  Also on claude/blocksmith-playtest (324cd95c). Not installed: adb saw no Quest.

## Task 23 factions (2026-10-09)
- 1 The Meridian Navy (new Faction.meridian, raw 5; ship role stays "capfrigate"): its own faction, hostile to the
  Capital (citadels, cities, soldiers, Capital vehicles), the Stormwarden Fleet, the Ironback Legion and the Ashguard
  (nearestFoe: any other non-none faction). New 160-block hull (CapitalFrigate.swift): long dark-grey spine, twin
  lower bow booms with two rows of lit portholes each, raised bridge with smoked glass and a sensor dome, a bulky
  octagonal engine block with four big glowing thrusters (exhaust trails). Hangar deck y 9 inside the spine (flank
  doors z 100-112), ladder to the bridge, helm at (0,25,74), point-defence mounts, missile pods. Commandeered it flies
  at 42 b/s. MAC: a flat 420 b/s slug, ShipCombat kind 3 -> Explosion.crater (radius-9 bowl through every breakable
  block, citadel walls included; containers spill). AI fires it every 20 s; the player at the helm every 6 s
  (attack; HUD "MAC ready / MAC n s"). Meridian crew livery (olive, gunmetal, amber visors).
- 2 Capital cities (CapitalCity.swift; "capital_city", 56-chunk regions): low flat white buildings with window
  bands, terraces that follow the ground, grey paving, covered walkways (white pillars, slab roofs) between lots,
  plazas with fountains, gardens, planter trees, cafe seating with umbrellas, benches, guards. No towers.
  `/locate capital_city`, `/cities`, map "C" markers.
- 3 Citadels did generate (about 1 per 4 regions; Remington's nearest was 773 blocks away, outside his explored
  ground). A failed region spot now tries 6 alternates, so about half the regions hold one. Saved worlds keep their
  explored ground: structure-guard.txt (written once from the saved chunk files) blocks new structures there.
  `--structnear SEED X Z` lists the nearest ones. World377: nearest citadel 773, nearest city 811 blocks.
- 4 Post-game (dragon or Ash Marshal beaten): the faction warships (Meridian frigate, Stormwarden frigate, Ironback
  crawler, battles) only appear then, and very rarely (2048-block regions; Meridian about 3% of regions); no frigates
  are stationed at citadels any more. Citadel and frigate loot: firing mechanisms, targeting optics, radar modules
  and intercepted orders. Guns (sidearm, rifle, SMG, shotgun, sniper, launcher, arc) and the radar set craft only
  from those components. The radar (held: a bearing panel; use: marks contacts on the map) shows Capital sites, and
  warships after the end. Intercepted orders mark the nearest unmapped city or citadel (after the end, a warship's
  patrol) and are used up.
- Checks: `--questbugs --only factions` (structures on 6 seeds, the guard, every saved Mac world, loot, recipes,
  radar, orders, MAC crater on a citadel, foe logic, helm MAC); full questbugs, mobtests 0 failures; ridecheck
  frigate scenes rewritten for the new hull (all pass). Pre-existing flakes on both old and new builds: ride
  "crew" (0 shots) and "troops" (1-2 troop-ticks). DeepTests' Marshal check made deterministic.
- Shipped: Quest CI run 37896814716 green, APK versionCode 77 on quest-dist (commit ab57733); Mac CI run 37896814733
  green. Also on claude/blocksmith-playtest (f471759e; Shortcuts.swift doesn't exist there, so no city shortcut).
  Not installed: adb saw no Quest. Backup before the first load:
  ~/Library/Application Support/Blocksmith/Backups/all-worlds-before-task23-factions-20261009.

## Task 24 audio + visual polish (2026-10-09)
- Audio (AV polish 1-4, all synthesized: no direct ElevenLabs SFX key is set up, and OpenRouter's ElevenLabs models
  are speech only): block foley (contact resonators, grain textures, heel/toe steps, fracture + debris; grass and
  leaves materials; 6 step takes, 4 break/place/hit takes), gunfire (N-wave blast, mechanism, slapbacks, distant
  echoes, whizz cracks, casings, impacts), engines/propellers, gusting wind, layered rain, four songbirds, layered
  explosions, melee swooshes, hurt grunts, pickup, UI chimes, level-up. `Blocksmith --sounds DIR`: 785 sounds, level
  check (peak/RMS/clipping) finds none silent or clipped. Music untouched.
- Visual (AV polish 5; Fast on the Mac and the Quest shaders kept in step): the Fast path draws the same sky dome as
  Fancy/Quest (haze band hugging the horizon, deep blue by ~40 degrees), a paler hazy horizon colour, aerial haze
  that starts near (max 30 % by day, off underwater), ambient 0.6 / sun key 0.54 for more shape, filmic saturation
  1.0 with acid yellow-greens pulled 28 %, grass/foliage tints 18 % less saturated toward olive, water tints 15 %
  less saturated. Fast fog glows toward the dusk sun (Fast packs the glow in eye.w below 0.5, its Fast flag).
- Not done, by choice: higher-resolution block textures. 16 px is the game's look, and 4x texture memory would cost the
  Quest (8 GB Mac / Quest frame rate budget); the realism comes from light, haze and colour instead.
- No IDs changed, so no save migration. Checks: build clean, 785-sound level check, snapshots judged (day, forest,
  sunset, aerial ocean, night; Fast + Fancy). `[fast: --questbugs]` timed out at CI's 24-minute focus limit (the full
  suite has outgrown it); the heavy lane (run 37916232494, tours) ran questbugs: 0 failures. Its other failures are
  pre-existing (playthrough obsidian/gather/stronghold, agents, padtest worlds menu, physicstest, rulescheck) except
  perf ships.edit_ms_mean 0.5 -> 2.0 ms (unrelated ship-edit bench, likely runner noise). The Fast sky dome costs
  ~0.8 ms GPU at 800p on the runner; playtest branch fast lane green. Quest CI 37912600891 green, APK on quest-dist
  (310d4a1). Not installed: adb saw no Quest. Also on claude/blocksmith-playtest (quest shaders dropped there).

## Task 25b1 (2026-10-09): Remington's v78 playtest fixes

Causes found and fixed (one commit each, `git log --grep "Playtest v78"`; also on claude/blocksmith-playtest):
1. Sprint (fourth report): the real cause was that a full stick push auto-sprinted (QuestControls push zone + the pad's
   auto-sprint, on by default), so there was no full-push walk to compare against, only 1.3x vs a partial push, and the
   comfort vignette tunnelled harder at sprint speed, hiding the flow. Now: a full push walks (4.3 b/s); clicking the
   pushed left stick sprints at 1.6x (Player.vrSprintSpeed 6.9 b/s) in any direction until the stick comes back to the
   middle; no VR auto-sprint; the vignette caps at walking speed; faint speed streaks at the view's edges, a stronger
   haptic tick, the ">> SPRINT" tag, and a one-time "Click the left stick while moving to sprint" hint after 4 s of
   full-push walking. Tests: QuestSim 1b drives the Touch stick in 4 directions (walk must not sprint; click sprint
   >= 1.5x walk: CI measured 6.9 vs 3.9 b/s, x1.75); questbugs checks 4 directions at the Player level (x1.60).
2. Reach: blocks break/place from 6 blocks (ground and ship decks, Mac too); melee on mobs 3.5 (Swing Mode was 6).
3. Riding: the B that closes a menu fired a sneak tap on release outside the menu, and sneak dismounts. Game ignores a
   sneak still held from a menu (`sneakHeldFromMenu`), QuestControls drops a B release that started in a menu (`bBlock`).
   Pickup while mounted reaches down to the mount's feet and 1.9 wide (was -0.8 below the rider's feet).
4. Spawning: caves got zero monsters (the cave sample had to hit the exact floor cell, then a 1-in-4 gate, and night
   surface mobs filled the cap). The cave sample now falls through open air to the floor, half the samples are at the
   player's depth when underground, no 1-in-4 gate; with the cap full, caves keep a small share (at most 4 within 32
   blocks). Monster cap 24 -> 36 before render-distance scaling. 60 s at night, rd 6: surface 15 -> ~20, cave 0 -> 6-10
   within 48 blocks, 0-2 within 32.
5. Hisser: fuse 1.75 s (was 1.5); a hit makes it flinch (swell back 0.6 s, paused 0.4 s): iron sword every cooldown
   kills it in 4 hits with no blast; left alone it still blows at ~2 s.
6. Plants: new ground has no tall grass, ~1/3 short grass, half the flowers/ferns, fewer plains bushes; short grass
   draws at 9/16, ferns 11/16, small flowers 12/16 everywhere (saved worlds too: `Blocks.crossSize`, Mesher).
Checks: `--questbugs --only v78` (12 checks) inside the full `--questbugs` (0 failures locally, incl. every saved Mac
world loading). No save IDs changed; Mac worlds backed up to Backups/all-worlds-before-task25b1-20261009.
Quest CI run 37942994351 green, APK versionCode 79 (6300439) on quest-dist. Not installed: adb saw no Quest.
Task 25b1b: the heavy `agent cave seed 12345` failure (bot drowned) is older than 25b1 (same failure on the playtest
branch, runs since 37875068675) and was a bot bug, not plants/spawning: its path dives into a pond and under a grass
overhang, but Steer always swam up in water (bobbed at the surface, then drowned idle), and pushing into a 2-high gap
gave the swim climb-out boost (Player, matches the reference). Steer now sinks to a lower waypoint without pushing
until level with it; idle bots tread water. All agent lanes green locally (cave 3/3 seeds). Test-only: no ship.

## Task 25b1zzx (2026-10-09): voice bug notes on the Quest (playtest builds only)
Say bugs out loud while playing; nothing to press. Code: quest/src/android/QuestVoiceNotes.swift (recorder),
Sources/VoiceNoteCore.swift (speech segmenter, context, 2 GB cap; shared), quest/c/voice (AAudio mic + AAC encoder),
quest/src/vk/QuestScreenshot.swift (screenshot per note), tools/quest-bugnotes.py (Mac side).
- First launch of a playtest build: after ~6 s it turns Bug Notes to Always Listening, asks for the microphone once and
  says so in a message. Pause > Options > Interface > Bug Notes: Always Listening / Push-to-Talk (click both sticks) / Off.
  A small dot top-left shows it is listening (grey) or saving a note (red, "Note").
- Only speech is kept (0.5 s before, 1 s after); silence is never written. Per note in
  /sdcard/Android/data/com.blocksmith.quest/files/voicenotes: vn-*.aac (16 kHz mono AAC 24 kb/s, flushed as it goes),
  vn-*.jsonl (build, position, dimension, biome, held item, mount, fps, recent events, a repro line, state every 5 s),
  vn-*.png (what you saw). Folder capped at 2 GB, oldest first. The mic stops while the app is paused.
- Game sound: the mic uses the VOICE_COMMUNICATION preset (echo cancellation) and the speech threshold rises with the
  game's own output level, so music/explosions don't open notes; the synthetic test drops a game-sound-only clip.
- Store builds: `STORE=1 quest/tools/build-apk.sh` leaves the recorder, mic code and RECORD_AUDIO out;
  quest/tools/storecheck.sh proves it (a `[store]` commit builds and checks both APKs in the quest lane).
- On the Mac: `~/ClaudeTools/quest/bugnotes` (headset plugged in) pulls new notes, transcribes them with ElevenLabs
  Scribe via OpenRouter, drops wordless clips and writes docs/playtests/<date>/voice-notes.md (time, words, where you
  were, screenshot). `--clean` also deletes the pulled notes from the headset.
- Quest CI run 37970910923 green, APK versionCode 84 (24538e3) on quest-dist; storecheck 0 failures on both APKs. Not
  installed: adb saw no Quest.
- Checks: `--questbugs --only voice` (10). Fix after the first CI pass: the Bug Notes row was hidden in the Quest pause
  menu along with the Mac-only rows.
