# Alabaster: The Capital game (Godot 4), session notes

Working title **Alabaster**: a native Godot 4 game in `game/`, separate from Blocksmith (no voxels, blocks, crafting,
mining or villagers). It takes Blocksmith's military world, The Capital (an opulent, authoritarian, sleek white
civilisation; see STATUS.md "Future ideas" #1), and pushes it to full-scale detail. The rival faction is the
**Cinder Pact**, a rugged rust-and-olive coalition on the western plateau. Branch: `claude/capital-game` (only).

## Engine and rules
- Godot **4.7.2-stable** (latest stable on 2026-10-04). Forward+, Metal on macOS (`rendering_device/driver.macos`),
  Jolt physics, GDScript; C++ GDExtension only for proven hot spots (none yet).
- Everything is text and code: `project.godot`, `main.tscn` (one node), `.gd` scripts, `.gdshader` files. The world,
  textures, meshes and sounds are generated at load (cached in `user://`, i.e.
  `~/Library/Application Support/CapitalGame` on the Mac). Assets: procedural or CC0 only.
- Logs and benchmark output: `~/Library/Logs/CapitalGame/` (`game.log`, `benchmark.json`, `padcheck.json`).

## Running it on the Mac
```
curl -L -o Alabaster.zip https://github.com/remingtonangus-lang/blocksmith/releases/download/capital-latest/Alabaster-macos-arm64.zip
ditto -x -k Alabaster.zip . && xattr -dr com.apple.quarantine Alabaster.app
./Alabaster.app/Contents/MacOS/Alabaster                 # play (fullscreen)
./Alabaster.app/Contents/MacOS/Alabaster --benchmark     # fixed flythrough, writes benchmark.json, quits
./Alabaster.app/Contents/MacOS/Alabaster --padcheck      # what the engine sees of the gamepad, writes padcheck.json
```
Options (after the binary, or after `--`): `--preset Low|Medium|High|Ultra`, `--windowed`, `--res 2560x1600`,
`--scale 0.67` (3D render scale), `--time 18.5`, `--weather clear|cloudy|overcast|fog|rain|storm|snow`,
`--only city|battle|forest` (benchmark segment), `--seed N`, `--regen` (ignore the world cache), `--smoke SECONDS`.

## Controls
Keyboard/mouse: WASD, mouse look, Space jump, C/Ctrl crouch, Shift sprint, E/F interact, R reload, Q switch weapon,
G grenade, V melee, LMB fire, RMB aim, T camera, M map, F3 perf HUD, F6 quality preset, F7 weather, F8 +1 hour,
F9 debug fly, F12 screenshot.
Gamepad (Halo Infinite-style default): LS move, RS look, A jump, B crouch, X reload / interact (hold: enter vehicle),
Y switch weapon, RT fire, LT zoom, LB grenade, RB melee, LS click sprint, RS click equipment, D-pad up flashlight,
D-pad down camera, View map, Menu pause. Look tuning (Controls.gd, saved in `user://controls.cfg`): horizontal and
vertical sensitivity, look acceleration, centre and axial deadzones, max input threshold, response curve, zoom
sensitivity, invert. Vehicles steer Halo-style (push the stick toward where you look) unless switched off.

### The PowerA pad (USB 20D6:2074)
Godot 4.7 reads pads through its bundled SDL3 on macOS, built with IOKit HID, GameController (MFi) and HIDAPI over
IOHIDManager, but **without libusb**. The PowerA pad is a GIP device with vendor class 0xFF (not HID), and no macOS
driver claims it, so neither GameController nor SDL's HID paths can open it. From the source alone: Godot will most
likely **not** see it. `--padcheck` records what the engine actually sees (`padcheck.json`; the macOS CI runner has no
pad, so this needs one run on the Mac). The fallback is the pad bridge (`game/tools/padbridge`, a userspace GIP driver
over IOUSBHost that sends pad state to the game over UDP 127.0.0.1:47731); `Controls.gd` already reads it as a
virtual pad.

## CI (`.github/workflows/capital.yml`)
- Linux (ubuntu-24.04): official Godot 4.7.2 headless import + `tests/run_tests.gd`, screenshot shots under xvfb with
  Mesa lavapipe (software Vulkan, Forward+), a 60 s smoke run. Shots, the test log and the README go to the orphan
  branch **`capital-shots`** (`git fetch origin capital-shots`).
- macOS (macos-15, Apple Silicon): exports the arm64 `.app` (ad-hoc signed, shader baker on), runs a 40 s Metal smoke
  test, `--padcheck` and `--benchmark`, then publishes `Alabaster-macos-arm64.zip` (and the CI `benchmark.json`) to
  the rolling pre-release **`capital-latest`**. Mac logs land in `capital-shots/mac/`.
- `mac.yml` (Blocksmith's Swift CI) ignores this branch.

## Local loop (cloud session)
Godot 4.7.2 built from source at `/home/user/godotsrc/godot/bin` (GitHub release downloads are blocked here), linked
as `/usr/local/bin/godot`. `godot --headless --path game -s res://tests/run_tests.gd` for tests;
`xvfb-run -a godot --path game --rendering-driver vulkan --resolution 1280x720 -- --shots /tmp/shots --only a,b` for
shots on lavapipe.

## Milestones
1. [x] Skeleton, CI, release publishing, perf HUD, benchmark, screenshot tests
2. [x] Landscape, sky, atmosphere, vegetation, day-night, weather (polish continues)
3. [x] Capital cities and bases (Candor; citadel, radar station, Fort Lumen, airfield, harbour, Cinder camps)
4. [x] Soldiers, factions, battles (first pass; polish continues)
5. [ ] Vehicles (crawler, frigate, dropships, helicopters, convoys, warships, artillery) with riding and driving
6. [ ] Weapons, destruction, FX, audio
7. [ ] Performance and polish pass with benchmark numbers

## What is in the world
- 16 km island: northern mountains to 2100 m with snow, the Cinder Pact plateau in the west with canyons, forested
  southern hills, the Capital's coastal plain in the east, a river from the mountains to the eastern sea plus a
  tributary from the plateau. CDLOD terrain (one MultiMesh, geomorphing, near levels cast shadows), procedural
  ground materials (grass, meadow, forest floor, triplanar rock, sand, snow, paving, asphalt), a 256 m physics window.
- Sky: single-scattering atmosphere, raymarched cumulus slab (steps per preset), stars, moon; 32-minute days;
  weather (clear, cloudy, overcast, fog, rain, storm, snow) with rain/snow particles, wet ground, fresh snow, storm
  lightning; ocean with Gerstner swell, refraction and its own haze; rivers.
- Forests: spruce, broadleaf, birch, bushes (procedural meshes, painted leaf atlas), impostors baked from the meshes
  to 5 km, GPU grass in two lattices.
- Candor, the Capital's city: 695 towers on a raised podium, the 430 m Spire, skyways, landing pads, terrace
  gardens, 12k trees, lamps; HLOD cells. Bases: citadel with twin 42 cm turrets, radar station, Fort Lumen,
  airfield, naval harbour, Cinder camps, artillery park; searchlights and beacons at night.
- War: Capital and Cinder squads fight over three capture points at the front (west of Fort Lumen), with
  reinforcements and barrages; Capital patrols in the citadel and the city plaza.

## CI benchmark (GitHub macOS runner, paravirtual Apple5 GPU, 1024x656, High, vsync on; not Remington's M1)
Run 4 (1e8f6d7): city 45.1 fps (p99 26.1 ms, 432 draws, 5.2 M prims), battle 44.3 (p99 28.6, 1103 draws,
7.7 M prims), forest 49.8 (p99 24.0, 605 draws, 6.4 M prims); load 6.6 s from cache, 39 s first run; VRAM 500 MB.
The runner reports no GPU timestamps on Metal (gpu_ms 0) and no static memory in release builds (RSS is used now).

## Log
- 2026-10-04 23:50: fleet monitor reported the release c237e81 never benchmarked on the M1 (`Alabaster --benchmark`
  logged empty args, then sat in normal play). Cause: `--benchmark` is one of Godot's own engine options
  (main.cpp consumes it before the game sees it; `--windowed` too). Fix: the game reads its real command line
  (`ps -o args= -p PID`) on macOS/Linux, `--bench` is an alias, `CAPITAL_ARGS` env works too; game.log now has
  the raw command line, each loading stage, benchmark segment starts and a progress line every 5 s; a watchdog
  writes partial results (`"timeout": true`, exit code 2) if the run overruns its segments + 180 s, and loading
  that takes over 300 s in benchmark/smoke mode quits with code 3.
- 2026-10-04 23:05: GAME BUILD READY 1e8f6d7 (walkable world: landscape, forests, weather, Candor and the bases;
  the battle commit e82323f follows). Fixed for the next build: Metal allows 16 samplers per stage, anisotropic
  repeat samplers are index 17 and failed to compile (foliage, terrain): now trilinear.
- 2026-10-04: engine switched from three.js to Godot 4 (Remington's decision via chat-Claude); the web/ scaffold was
  never pushed. Branch claude/capital-game created from claude/blocksmith-playtest.
