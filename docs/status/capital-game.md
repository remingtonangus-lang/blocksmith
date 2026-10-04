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
1. [ ] Skeleton, CI, release publishing, perf HUD, benchmark, screenshot tests
2. [ ] Landscape, sky, atmosphere, vegetation, day-night, weather
3. [ ] Capital cities and bases
4. [ ] Soldiers, factions, battles
5. [ ] Vehicles (crawler, frigate, dropships, helicopters, convoys, warships, artillery) with riding and driving
6. [ ] Weapons, destruction, FX, audio
7. [ ] Performance and polish pass with benchmark numbers

## Log
- 2026-10-04: engine switched from three.js to Godot 4 (Remington's decision via chat-Claude); the web/ scaffold was
  never pushed. Branch claude/capital-game created from claude/blocksmith-playtest.
