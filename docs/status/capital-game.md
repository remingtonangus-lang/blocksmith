# Alabaster: The Capital game (Godot 4), session notes

Working title **Alabaster**: a native Godot 4 game in `game/`, separate from Blocksmith (no voxels, blocks, crafting,
mining or villagers). It takes Blocksmith's military world, The Capital (an opulent, authoritarian, sleek white
civilisation; see STATUS.md "Future ideas" #1), and pushes it to full-scale detail. The rival faction is the
**Cinder Pact**, a rugged rust-and-olive coalition on the western plateau. Branch: `claude/capital-game` (only).

## Current state (2026-10-05, handoff)
- All seven milestones are done. Each later change fixes a measured bug or quality gap (see the Log).
- Playable build: release `capital-latest` (Apple Silicon, ad-hoc signed); fetch and run as in
  "Running it on the Mac". The world contains:
  - a 16 km island: mountains, river valleys, coast, forests and grass;
  - Candor (695 towers, the Spire, skyways), the citadel with twin 42 cm turrets, the radar summit,
    Fort Lumen, the airfield, the harbour and the Cinder camps;
  - a live front, crawlers you can drive or ride, gunships, dropships, the sky frigate, convoys, ships
    and artillery;
  - four weapons plus grenades, collapsing towers and wrecks, weather and day-night;
  - synthesized audio.
- Checks:
  - every push: 86 headless tests and 10 scripted scenarios (ride, drive, fly, dropship, battle, weapons,
    destroy, trees, stand, menu), 33 screenshots on lavapipe, a 60 s smoke test;
  - the macOS export with a smoke test, padcheck, a benchmark (`benchmark.json` on `capital-shots/mac/`)
    and the pad bridge build.
- Benchmark on CI's paravirtual Mac GPU (High): city/battle/forest about 33-38 / 31 / 35 fps. Numbers from
  Remington's M1 are still to come (the fleet monitor reruns at each GAME BUILD READY).
- Waiting on hardware: the PowerA pad through the bundled pad bridge (untested without the pad), and M1
  fps against the 60 fps High target.
- Next ideas, in order of measured need:
  - M1 profiling once numbers arrive (shadow cascades and cloud steps are the likely levers);
  - switchback roads for mountain sites;
  - richer soldier models, view-model sleeves that read against white ground;
  - Quest 3 (OpenXR) export preset.

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
1-4 pick a weapon, G grenade, V melee, LMB fire, RMB aim, T camera, M map, F3 perf HUD, F6 quality preset, F7 weather, F8 +1 hour,
F9 debug fly, F12 screenshot, Esc options menu.
Gamepad (Halo Infinite-style default): LS move, RS look, A jump, B crouch, X reload / interact (hold: enter vehicle),
Y switch weapon, RT fire, LT zoom, LB grenade, RB melee, LS click sprint, RS click equipment, D-pad up flashlight,
D-pad down camera, View map, Menu: the options menu (pauses; D-pad/stick to move, left/right to change, B back). Look tuning (Controls.gd, saved in `user://controls.cfg`): horizontal and
vertical sensitivity, look acceleration, centre and axial deadzones, max input threshold, response curve, zoom
sensitivity, invert; all of it, plus quality preset, FOV, mouse sensitivity and volumes, is in the in-game options
menu (Esc / Menu) and saved on close. Vehicles steer Halo-style (push the stick toward where you look) unless switched off.

### The PowerA pad (USB 20D6:2074)
Godot 4.7 reads pads through its bundled SDL3 on macOS, built with IOKit HID, GameController (MFi) and HIDAPI over
IOHIDManager, but **without libusb**. The PowerA pad is a GIP device with vendor class 0xFF (not HID), and no macOS
driver claims it, so neither GameController nor SDL's HID paths can open it. From the source alone: Godot will most
likely **not** see it. `--padcheck` records what the engine actually sees (`padcheck.json`; the macOS CI runner has no
pad, so this needs one run on the Mac). The fallback is the pad bridge (`game/tools/padbridge`, a userspace GIP driver
over IOUSBHost that sends pad state to the game over UDP 127.0.0.1:47731); `Controls.gd` reads it as a virtual pad.
The bridge (`game/tools/padbridge/main.m`, Objective-C: the IOUSBHost Swift names did not match on CI) is compiled on the macOS runner into `Alabaster.app/Contents/MacOS/
padbridge` (its build log is `ci/ci-padbridge.log` on capital-shots); the game starts it by itself 1.5 s after
launch when the engine sees no pad (`--no-padbridge` turns that off) and stops it on quit. It opens interface 0 of
20D6:2074 (other GIP pads: `padbridge VID PID` in hex), sends the GIP power-on, parses input reports 0x20 and the
guide report 0x07 (acknowledged) and keeps the game's virtual pad alive every 0.5 s. Untested on real hardware:
the cloud session has no pad and no Mac. If the pad still does nothing, `game.log` says whether the bridge started,
and running `Alabaster.app/Contents/MacOS/padbridge` in Terminal prints what it finds.

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
shots on lavapipe. `godot --headless --path game -- --scenario all` (ride, drive, fly, dropship, battle, weapons,
destroy) for scripted play with oracles. Bisecting: `CAPITAL_SKIP=vegetation,weather,vehicles` leaves world systems
out (vehicles also drops the HUD and weather).

## Milestones
1. [x] Skeleton, CI, release publishing, perf HUD, benchmark, screenshot tests
2. [x] Landscape, sky, atmosphere, vegetation, day-night, weather (polish continues)
3. [x] Capital cities and bases (Candor; citadel, radar station, Fort Lumen, airfield, harbour, Cinder camps)
4. [x] Soldiers, factions, battles (first pass; polish continues)
5. [x] Vehicles (crawler, frigate, dropships, helicopters, convoys, warships, artillery) with riding and driving
6. [x] Weapons, destruction, FX, audio
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
- 2026-10-05 12:40: GAME BUILD READY 60b25d8 (capital-latest, 12:23 UTC). Since 95849c0:
  - graphite view-model sleeves;
  - dusk clouds lit by the sky glow, night clouds cool grey;
  - fog no longer leaves distant towers on a dark band;
  - soldiers kneel on the ground;
  - no dark muzzle-flash stars.
  CI Mac (paravirtual, High): city 37.5 fps (p99 52.1 ms), battle 32.3 (p99 61.8), forest 36.6 (p99 51.9); draws
  274 / 646 / 330.
- 2026-10-05 12:25: two soldier/FX bugs from troops_lineup (vegetation hidden to see the legs):
  - kneeling soldiers hovered 0.35 m. The pose dropped the torso but left the hip pivots up. The kneel is now
    built from the leg lengths: hips down 0.42 m, front shin vertical, rear knee on the ground.
  - a dark teal star hung in mid-air. The additive muzzle-flash shader went negative (star arms past the quad's
    circle, and the last frame of an expiring flash), and additive negative subtracts orange from the scene.
    Clamped.
- 2026-10-05 12:10: in fog, distant towers stood out as flat-topped grey blocks over a dark band (river_valley;
  probed: Candor 3.2 km away, which should be about 97% fogged). Cause: fog and aerial perspective colour distant
  geometry with the sky in its own direction, and the sky shader drew everything below the horizon 30% darker
  in one step at 0 degrees. Below-horizon sky is now continuous with the horizon and darkens gradually down to
  -8.6 degrees.
- 2026-10-05 11:50: clouds at dusk rendered near-black against the glowing sky. Their only light was the zenith,
  which is dim after sunset. They now also take light from the sky around them, using the sky colour behind each
  cloud that is already computed (free; only while the sun is above about -10 degrees). Night clouds are tinted
  cool grey: moonlight through the atmosphere had turned them beige. Checked capital_dusk, capital_night,
  radar_night, capital_noon and coast.
- 2026-10-05 10:55: view-model sleeves are graphite cloth (new Kit style CLOTH), not white. Measured on
  weapon_view: with the world hidden, the forearm (only ~20 cm of it is ever on screen) was white against the
  Capital's white ground. Now a dark sleeve with a grey cuff frames the white carbine.
- 2026-10-05 10:50: GAME BUILD READY 95849c0 (capital-latest, 10:45 UTC). Adds the overcast sky fix and solid
  tree trunks. CI Mac (paravirtual, High): city 36.2 fps (p99 60.6 ms), battle 32.1 (p99 65.2), forest 37.5
  (p99 43.8); draws 272 / 701 / 330 (within run-to-run noise of 57ae121).
- 2026-10-05 10:30: tree trunks are solid. Measured: the new `trees` scenario walked the player 9.4 m through a
  broadleaf; a battle shot showed a soldier standing inside a spruce. Each near cell's worker build now also
  returns its trunks in 8 m buckets. Cells within 60 m of the player (or their vehicle) get one static body of
  shared cylinders on physics layer 16, one new body per 10 frames. The player, crawlers, bullets and grenades
  collide with it; wheel rays and the vehicle camera's spring arm ignore it. Soldiers step round trunks with
  `Vegetation.avoid()` (0.87 us per call, so under 1 ms at the 900-soldier cap). Now the player stops at the bark
  (1.04 m from the axis of a 0.68 m trunk). All 10 scenarios pass.
- 2026-10-05 10:05: the overcast sky looked clear. Measured on the mountains shot: overcast (cover 0.82) showed
  less cloud than clear. A thick deck shades itself to black, and its only remaining light was the blue zenith
  ambient, so it read as blue sky. Fixes:
  - cloud interiors get a grey multiple-scattering ambient and a soft sun octave that survives self-shadow;
  - past the 25-60 km marched range the deck fades toward its average look, not clear sky (front_line had a gold
    band under the overcast);
  - the sun and moon discs dim by the clouds actually in front of them (the half-res pass passes transmittance in
    alpha);
  - the noon horizon is pale, not gold (same single-scattering gap; only with the sun high, so sunsets keep colour);
  - coverage remapped so that clear is mostly blue.
  Clear, cloudy and overcast now step visibly. battle_ground frames the fight over a Capital soldier's shoulder
  (it often faced an empty slope).
- 2026-10-05 09:35: GAME BUILD READY 57ae121 (capital-latest, 09:13 UTC). Adds the options menu (Esc / Menu) and
  the 1200 m tree line. CI Mac (paravirtual, High): city 38.1 fps (p99 50.8 ms), battle 32.9 (p99 49.1),
  forest 38.5 (p99 36.4); draws 276 / 657 / 330.
- 2026-10-05 09:30: in-game options menu (Esc / pad Menu): pauses; quality preset, FOV, look sensitivity both axes,
  acceleration, deadzones, response curve, zoom and mouse sensitivity, inverts, Halo-style vehicle steering, volumes,
  quit; pad-navigable for TV play; saved on close. Before this, look tuning was only in user://controls.cfg. New
  scenario `menu` (9 scenarios) and shot `pause_menu`. Tree line at 1200 m.
- 2026-10-05 08:55: GAME BUILD READY 95fb880 (release capital-latest, published 08:24 UTC).
  - For the fleet monitor: `Alabaster --benchmark` should run three segments with a progress line every 5 s
    and write benchmark.json in about 2 minutes.
  - CI Mac (paravirtual GPU, High, 1024x656): city 36.2 fps (p99 66.6 ms), battle 33.4 (p99 39.1 ms),
    forest 38.2 (p99 40.0 ms); draws 275 / 652 / 329; primitives 5.0 / 6.4 / 5.5 M; load 5.9 s; RSS 720 MB.
  - Since the last ready build (6cc8be3):
    - floating rivers, buried and slot-canyon roads and the radar crater fixed; Pass Road ends at a road head;
    - fog sky and water;
    - tree LOD rings and shadow proxies; a tree line at 1200 m;
    - riding without drift;
    - Cinder helmets;
    - searchlights sweep the sky;
    - friendly splash removed and front gunships replaced 120 s after being shot down;
    - the pad bridge ships in the app and starts when no pad is seen.
  - CI fixes along the way: a freed gunship broke the fly scenario's setup, and a respawn landed 2 m in the air.
    The CI log now prints the first script error with its backtrace.
- 2026-10-05 06:40: second sweep.
  - The radar station had sunk into a crater: the road relaxation moved road ends too, lowering Pass Road's
    radar end by 740 m. Road ends are now pinned to their sites.
  - Pass Road cannot climb 1300 m in 5 km. It now ends at a road head at 519 m, and the radar is served by
    gunship (its embankment had raised a 380 m mound at the citadel).
  - Roads: 20 % grades, 30 % ramps in the last 600 m before a site, banks and strips carved in two passes.
    Every road sits within 1 m of the ground, the ground 40 m off stays within 20 m, and Airfield Road
    reaches the airfield.
  - Searchlights sweep the sky (they lay on the slopes as white rods).
  - The Cinder helmet's wide flat brim read as a conical straw hat; it is now a domed helmet with a neck
    skirt, visor ridge and goggles.
  - troops_lineup stands on open ground, and FX warm-up particles no longer show as a grey column.
- 2026-10-05 05:40: terrain and road bugs from the shot sweep.
  - Front Track was buried 18 m under Red Track: the two share a corridor. A road now pins its height to
    earlier roads where they overlap.
  - Pass Road ran in a 190 m slot canyon with vertical walls. Carving now uses real cut-and-fill (0.8 banks
    sized by cut depth, measured before carving), a level strip one texel wider than the road, and a
    symmetric 16 % grade relaxation. Banks never cut under a river.
  - Fort Lumen's roads started at its centre and ran through the barracks; the patrol crawler hit them and
    threw its rider off. Roads now meet the fort at its gate.
  - Riding: standing still on a moving vehicle holds the player's spot in the deck frame (1.5 m drift in
    20 s before; the oracle now requires under 0.5 m).
  - Fog weather: the far sea showed as a dark band and the river as a bright cyan ribbon. Fog, terrain haze
    and water haze now share the sky's pale tone, and the water's glints fade in fog.
  - The sea vanished from shots after horizon_test (its setup hid the ocean).
  - Cloud raymarch jitter now uses interleaved gradient noise (the sky was speckled).
  Tests 82, scenarios 8, all green locally.
- 2026-10-05 04:20: M7 continued.
  - Pad bridge: rewritten in Objective-C after Swift's IOUSBHost names did not match; it now compiles on the
    macOS runner, ships as `Alabaster.app/Contents/MacOS/padbridge`, and the game starts it when no pad is
    seen (game.log: "pad bridge started").
  - Trees: cells within 140 m of the camera keep full-detail meshes and per-cell culling. Further out, the
    coarse tree build is merged into 3x3-cell super-cells and casts shadows through ~20-triangle proxies.
    Forest view (lavapipe, High): 1412 draws / 9.3 M primitives before; 663 / 6.8 M after.
    CI Mac (c3a918d): city 33.1, battle 31.4, forest 35.2 fps; this paravirtual GPU varies by about 15 %
    between runs.
  - Rivers hung in the air: up to 230 m at the main river's source, and the "dark slab" in river_valley was a
    floating river sheet. The surface is now computed after all carving, from the carved channel (GEN_VERSION
    11; a new test checks no point floats), and the bed fills the base terrain's narrow ravines under the water.
  - Fog weather turned the horizon black and gold: single scattering extinguished horizontal rays (a sky-only
    render read RGB 3,1,0). The sky shader now blends toward a pale multiple-scattering colour in heavy haze.
  - Found while hunting: the bisecting aids SHOT_HIDE, SHOT_PROBE, SHOT_HOUR, SHOT_WEATHER and
    `--drawreport` (see the code).
  Open (2026-10-05 05:40): white sleeves vanish against white aprons in the first-person view; the main river
  sits on a short cliff beside Pass Road's cut.
- 2026-10-05 02:20: GAME BUILD READY 6cc8be3 (release capital-latest). M6 complete: weapons (1-4, R, G, V, RMB aim),
  collapsing towers, burning vehicle wrecks, visible explosions/smoke/dust, synthesized audio. The benchmark now
  runs on the Mac: CI's macOS runner (paravirtual GPU, High, 1024x656) completed all three segments and wrote
  benchmark.json (city 36.3 fps, battle 27.9, forest 30.5; draws 294/661/302; primitives 6.1/9.2/8.4 M). For the
  fleet monitor: `Alabaster --benchmark` (or `--bench`) should now log segment progress every 5 s and finish in
  about 2 minutes. Known: fps is below run 4's (45/44/50) although draws halved; primitives rose ~30% (suspect: one
  LOD per merged tree MultiMesh) and particles now really draw; being measured next.
- 2026-10-05: M7 started. `--drawreport SEGMENT` (under xvfb) measures draw calls by ablation: it hides each
  owner group in turn and reads the renderer's count. Battle view (High, 1024x656): 1361 draws, of which
  vegetation 1145 and the sun's shadow passes 778. Near trees were one MultiMesh per species/variant per 128 m
  cell; now 3x3 cells share one (super-cells rebuilt from cached cell buffers). After: 603 draws (vegetation 439,
  shadows 278). Also new: a first-person carbine from extruded side profiles, sleeved arms and gloves; scenarios
  always start on foot (a gunship in flight refused the exit, failing CI run 10's `weapons` check).
- 2026-10-05: M6. Weapons (`scripts/combat/weapons.gd`): LC-7 carbine (680 rpm), LM-2 marksman (4x), sidearm,
  RL-4 launcher, grenades, melee; first-person models from the Kit, sway, bob, ADS, reloads, recoil that climbs the
  view, spread bloom, rumble. Destruction (`scripts/combat/destruction.gd`): towers take blast damage and at zero
  are cut by their own plan into wedges and slabs (a closed prism each, convex rigid body), the lower floors go up
  in dust, the rest drops and topples; the city re-meshes the cell without the tower and drops its collision and
  occluder; vehicles break into burning pieces; debris is capped by the preset. One damage path for every blast
  (`Combat.explode`: soldiers, player, vehicles, buildings), so grenades, rockets and barrages all hurt. Audio:
  procedural bank (32 sounds, cache `user://audio_v3`), speed-of-sound delay, vehicle loops, ambience director.
  New scenarios `weapons` and `destroy` (in `--scenario all`); shot `collapse`.
  Bugs found and fixed on the way (measured):
  - Every particle effect was invisible: `emit_particle()` particles are dropped while `amount_ratio` is 0, which
    the FX systems used to silence their own emitters. Now ratio 1 with `emitting = false` (checked in a 3-system
    test render), plus a warm-up particle per system so the pipelines compile at start, not on the first blast.
  - Far explosions were silent: the sound sat after the "near the camera" early return.
  - Swapping a MeshInstance's mesh under a visibility-range parent errors in renderer_scene_cull and corrupted the
    heap; cells are refilled in place (`ArrayMesh.clear_surfaces` + commit).
  - Parked vehicles and debris outside the 256 m terrain collision window fell through the world (a crawler at
    y -1600 in the `all` run); `Terrain.guard_body` freezes them on the analytic ground until the window arrives.
  - Player interaction scan assigned freed nodes to a typed variable every frame (destroyed vehicles).
  - Rockets ignored buildings and vehicles (only the ground); they now trace physics and skip the shooter.
  - Every run aborted at exit with glibc heap corruption (exit 134; it failed CI run 9 after all scenarios
    passed, so the Mac release for f5b508a never published). Bisected with `CAPITAL_SKIP` (world systems) down
    to the convoy trucks' interactable: a lambda kept in G's static registry, freed at engine teardown after its
    script. Now a bound method, and `G.reset()` drops all static references when the world leaves the tree.
  - Teleports put the player on the analytic ground, inside Fort Lumen's base platform (1.4 m higher);
    depenetration pushed them 45 m down through the heightmap. New `World.surface_at` (ray onto the top static
    surface) for spawns, scenarios and shots, plus a safety net that puts a player found below the ground back on
    top. New scenario `stand` (7 sites) and first-person shot `weapon_view` (shots mode now spawns the player
    for it; the view model was never in a shot before).
  - The `drive` oracle measured 3D distance, so a crawler falling through the world "travelled 767 m"; it now
    measures horizontal distance and checks the crawler is on the ground.
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
