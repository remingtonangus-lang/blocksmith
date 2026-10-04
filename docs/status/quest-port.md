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
| X / Y | pick block or reload / inventory |
| Left grip | hotbar left (LB) |
| Right stick click | hotbar right, hold: weapon wheel (RB) |
| Left stick click | sprint (L3) |
| Menu (left) | pause |
| In menus | the laser is the mouse: trigger = click, grip = right click; the left stick also moves the pad cursor |

Physically walking moves the player (with collision). Ducking lowers the view. Snap turns and fast movement darken the
edges of the view (comfort vignette). The HUD is a panel in the lower view that follows the head lazily; menus open
as a panel in front of you. Rumble from the game (hits, explosions, block breaks) plays on both controllers.

## Milestones

| | Milestone | State |
|---|---|---|
| 1 | CI APK launching to an OpenXR session (test scene) | first APK published (run 37243571730); device run pending |
| 2 | Real world in stereo (multiview), head tracking, 72 Hz budget | renderer verified offscreen (lavapipe); device numbers pending |
| 3 | Touch controller play (locomotion, turning, vignette, hand rays, panels, haptics) | implemented; device test pending |
| 4 | Game content (mobs, structures, vehicles, soldiers, saves, actions) | in progress |
| 5 | Performance and comfort pass with measured numbers | pending |

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

- 2026-10-04: groundwork (shims, seams, headless check), Vulkan renderer verified offscreen, OpenXR layer verified up
  to a focused session on Monado, app/controls/audio/Android entry, CI pipeline. `.claude/ALLOW_STOP` removed on this
  branch (standing order: never stop).
