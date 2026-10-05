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
doesn't walk you), Recenter View, Dominant Hand, Refresh Rate (72 / 80 / 90 / 120 Hz), Foveated Rendering, HUD Position (Middle / Low / Lower), Texture Detail (High 128 px / Medium 64 px, next launch), Auto Render Distance (on: if frames are missed at the headset's limit the render distance steps down for the session, with a message).

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
   ...`, `xr: LOCAL_FLOOR space` (or STAGE/LOCAL), `xr: swapchain WxH x2 layers`, `xr: refresh rates [...], using 72 Hz`,
   `xr: session state 5` (FOCUSED). In the headset: an immersive scene opens (not a flat window). A crash here shows
   as `FATAL:` or a native backtrace in `adb logcat` (unfiltered: `adb logcat -d | grep -A40 "Fatal signal"`).
2. **Loading scene, then the world (M2).** While the world generates (several seconds), a sky-blue scene with eight
   coloured cubes circling you and a progress bar 2 m ahead; then a new world appears around you at the right scale (blocks ~1 m, eyes at player
   height), both eyes agree (no double vision), head turns and leans track with no swim. logcat `load: ...` lines
   with timings, then a `perf:` line every 5 s (fps, missed frames, worst frame, cpu/gpu ms, sections, draws, chunks). The number to report: fps (72
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

- 2026-10-05: first APKs (packaging fixes: case of the output dir, pipefail exits, Bionic FILE/open), first headset
  run (v13) works at 72 fps; perf (bee-nest and heart scans, exclusivity checks off); ship riding, container hint,
  VR comfort page, teleport, seated mode (v17).
- 2026-10-04: groundwork (shims, seams, headless check), Vulkan renderer verified offscreen, OpenXR layer verified up
  to a focused session on Monado, app/controls/audio/Android entry, CI pipeline. `.claude/ALLOW_STOP` removed on this
  branch (standing order: never stop).
