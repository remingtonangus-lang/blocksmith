# Frontier — status (session G, branch claude/frontier-game)

Original open-world Western (working title **Sable River**, codename Frontier) for Mac (flagship) and Meta Quest 3.
Project: `frontier/` (Godot 4.7.1). Bar: `frontier/QUALITY_BAR.md`. World bible: `frontier/design/WORLD.md`.
Story: `frontier/design/STORY.md`. Licences: `frontier/LICENSES.md`.

## Engine decision
Godot 4.7.1: Metal (Forward+) on macOS with MetalFX upscaling, Vulkan Mobile + built-in OpenXR on Quest 3 (Godot ≥ 4.6
bundles the Khronos loader, so the APK needs no vendor plugin), one text-based project (scenes/resources/shaders as
text, game logic in typed GDScript), headless import/export/tests in CI, MIT licence. Unreal/Unity rejected: no
editor-free text workflow, heavy on an 8 GB M1, licensing, and neither builds Mac + Quest from Linux/mac CI as simply.
A custom engine was rejected: Godot already has Jolt physics, OpenXR, MetalFX, volumetric fog, SDFGI/VoxelGI, skeletal
IK modifiers (TwoBoneIK3D, LookAtModifier3D, SpringBoneSimulator3D) and AnimationTree.
Local loop (cloud session, no GPU): Godot Linux + lavapipe (software Vulkan) under xvfb renders Forward+ screenshots
(slow: 10-60 s/frame; the `preview` preset is chosen automatically). Real quality/perf numbers come from CI (macOS M1
runner, Metal) and the Mac monitor.

## How to run / test
- Setup (cloud session): `bash frontier/tools/session_setup.sh` (Godot, lavapipe, Python deps, worldgen, assets).
- World data: `python3 frontier/tools/worldgen.py` (65 s) → `frontier/data/world/` (gitignored; map.png too).
- Assets: `bash frontier/tools/fetch_assets.sh` (CC0 pack from release `frontier-assets`), then
  `python3 frontier/tools/pack_textures.py`, then `godot --headless --path frontier --import` (8 min first time).
- Parse check: `bash frontier/tools/check.sh`.
- Bots: `godot --headless --path frontier -- --bot all --seconds 75` (road, explore, town, gunfight, missions,
  systems; oracles: stuck, below terrain, free fall, NaN, out of bounds, frame spikes, script/shader errors via a
  Logger, NPC stuck rate, softlocks, save/load equality, crime→wanted→bounty).
- Screenshots: `xvfb-run -a godot --path frontier -- --tour DIR [--only a,b]` or `--shot PNG --at x,z|town:id
  --up 1.7 --yaw 90 --pitch -3 --time 10 [--weather storm] [--player] [--menu pause|map|journal|settings]`.
- Benchmark: `--benchmark [--quality high]` → `~/Library/Logs/Frontier/benchmark.json` (fps, 1 % low, p50/p95/p99,
  spikes, RSS/VRAM) on macOS, `user://benchmark.json` elsewhere.
- Vegetation lineup: `godot --path frontier res://scenes/veg_lineup.tscn -- --out x.png`.

## Delivery
- `.github/workflows/frontier.yml` (push to this branch, paths frontier/**): macOS-14 runner → worldgen (cached),
  CC0 pack + import (cached), script check, bots, benchmark (High, 1080p), screenshot tour, export ad-hoc-signed
  arm64 `.app` → `SableRiver-mac-arm64.zip` on the rolling pre-release **frontier-latest** (+ `BUILD_COMMIT.txt`,
  `benchmark-ci.json`); Linux job exports `SableRiver-quest.apk` there too. Shots/logs → branch
  `ci-snaps-claude-frontier-game`.
- `.github/workflows/frontier-assets.yml`: CC0 fetch on ubuntu → release `frontier-assets` (`catalog.zip`, `ext.zip`;
  characters/animals/audio/weapons zips as their pipelines land).
- Mac monitor: on the Mac run `bash frontier/tools/mac_monitor.sh install` once (LaunchAgent, checks every 30 min,
  benchmarks only when idle > 10 min on AC power); results go to branch `frontier-bench` as `bench/<commit>.json`.

## What exists
- **World**: 8 × 8 km Sable River country (worldgen.py): stream-power + droplet erosion, Kestrel Range, Thornwood,
  Ocotillo Breaks mesas, Corrigan Plains, Lake Agnes, meandering Sable River + 2 creeks, 4 towns + 8 POIs flattened,
  A*-routed graded roads, graded railroad (cut/fill capped), control map, paper map (map.png).
- **Terrain**: CDLOD quadtree (one MultiMesh draw), vertex morphing, skirts, per-pixel heightmap normals, 13 CC0 PBR
  layers (Poly Haven/ambientCG) with height-blend, biplanar cliffs, macro variation, wetness/puddles, snow line;
  collision tiles (HeightMapShape3D) around every focus; distant grass-cover tint (ground takes the grass colour where
  blades fade); wagon-road ribbons (wheel ruts, churned crown, verges, puddles in the ruts after rain).
- **Sky/atmosphere**: single-scattering sky shader (half-res pass), sun/moon with phases, stars + milky band, cloud deck
  + cirrus with weather coverage, CPU port of the scattering model driving sun/ambient/fog colour, AgX tonemap, auto
  exposure, volumetric fog, valley mist, weather states (clear…storm with lightning, fog, dust), wetness globals;
  world-anchored clouds with matching cloud shadows (deck density rendered to a 256² map, sampled by terrain/grass/
  trees/roads); weather particles (wind-slanted rain + splashes, snow, dust).
- **Water**: lake + river ribbons, refraction/absorption via depth, lit scattering body colour + silt murk, flowing
  normals calmed with distance, foam, rain ripples, Fresnel.
- **Vegetation**: 10 procedural species (ponderosa, fir, cottonwood, aspen, juniper, oak, mesquite, snag, sagebrush,
  rabbitbrush) with crown-volume leaf clusters + procedural leaf atlas, wind; region billboards (1 draw/region) +
  near full meshes with per-instance fade; trunk colliders; GPU grass clumps (geometry blades, control-map density,
  wind, player push).
- **Player**: weighty third-person locomotion (walk/jog/sprint, stamina, slope, momentum turns, fall damage), orbit
  camera with collision, aim/fire/reload/holster/weapon switch, recoil, hitboxes, regen, death/respawn.
- **Combat**: 10 original period firearms (weapons.gd), ballistics (drop past 80 m), zone hitboxes, impacts/decals/
  muzzle flash, **Nerve** slow-time marking + execution with sepia/vignette overlay, difficulty damage scale.
- **NPCs**: Human actor + brain: perception (sight cone, hearing via Game.noise), cover search by raycasts, peek/burst,
  flanking, suppression, flee/cower/surrender, group target sharing, crime judging on death; ambient population
  (stable residents per town, travellers on roads).
- **Systems**: Standing, crimes with witnesses, bounties per county, wanted levels with cool-down, money, satchel
  items, save/load (user://saves), autosave on mission complete; shops (general store, gunsmith, butcher) with
  Standing/town prices and pelt/meat selling; 6 roadside encounter types; sheriff bounty boards (dead or alive);
  hunting (12 species, pelt quality, skinning); camp; road graph + GPS routes on map/HUD.
- **Missions**: MissionDirector (goto/say/spawn/wait_dead/interact/checkpoint, markers, autopilot, softlock oracle);
  Chapter 1 complete (5 missions: Rider from the West, The Drover, Inquiries, Greer's Post, A Fire at Willow Bend)
  with original dialogue (design/dialogue/ch1.json); letterboxed cinematic dialogue camera.
- **UI**: HUD (rotating paper-map inset, 3 gauges, ammo, crosshair + hit marks, prompts, subtitles, place titles),
  pause menu, settings, full-screen map with waypoints, journal; OFL period fonts (IM Fell, Rye, Sancreek, Old
  Standard); 1080p canvas scaling.
- **Audio** (`frontier/src/audio/`, `frontier/tools/audio/`, doc `frontier/design/AUDIO.md`): AudioDirector
  (`Game.audio`, added in main.gd; `--noaudio` skips, `--audiotest` self-test) with buses, pooled 3D one-shots +
  occlusion, gunshot model (speed of sound, close/far/distant/indoor, terrain/facade echoes), footsteps/hooves by
  surface and gait, ambience mixer (biome/time/weather/water/towns, creature calls, thunder), adaptive stem score
  (explore/town/tension/combat/mission/Nerve), Nerve slow-time audio, UI, voice lines with visemes, volume settings.
  Content: ~190 synthesized SFX/ambience ids (~800 files), 16 original music tracks rendered with FluidSynth
  (FluidR3 GM, MIT), Kokoro-82M TTS (Apache-2.0) for Ruth + NPC barks (`design/dialogue/`), CC0/PD Commons recordings
  in CI. CI job `audio` in frontier-assets.yml publishes `audio.zip`; `tools/fetch_assets.sh audio` fetches it.
- **Characters** (`frontier/design/CHARACTERS.md`): MakeHuman CC0 bodies via MPFB2 run headless in the `bpy`
  module, game rig with Godot humanoid bone names + eye bones, 34 face blend shapes (CC0 ARKit units + visemes),
  procedural 1899 garments/hats/beards, 36 seeded NPCs over 12 roles + Ruth Caddell (hero LOD, duster variant),
  CMU mocap retargeted to `animations.glb` (65 clips incl. procedural aim/hit/lean, root motion, foot contacts).
  Godot: `CharacterFactory.spawn(seed, role)` → `FrontierCharacter` (clips, visemes, expressions, blink, gaze).
  CI job `characters` publishes `characters.zip`; `tools/fetch_assets.sh characters` fetches it.
- **Horses** (`frontier/design/HORSES.md`): procedural horse generator
  `frontier/tools/animals/horse_gen.py` (Blender bpy: SDF anatomy → mesh/LODs, rig, weights, mane/tail cards, eyes,
  stock-saddle tack, IK-solved gait cycles + idles/actions → `horse.glb` + `horse_gaits.json`; CI job `animals` in
  frontier-assets.yml → `animals.zip`, `fetch_assets.sh animals`), `Horse` riding controller, `HorseVisual`
  (AnimationTree, coats), `HorseIK` (terrain foot IK + foot locking), coat/hair shaders, `--bot ride|gaits` with gait
  oracle, look-dev scene `scenes/horse_test.tscn`, player's horse spawned in `main.gd`.
- **VR**: OpenXR start on Android, XROrigin rig, controller → intent mapping, snap turn, comfort vignette.

## In flight (parallel worktree agents; merged here when they report)
- Settlements: procedural 1899 building kit, interiors with Poly Haven props, doors, navmesh, night lights.
- Weapons: Blender models of the 10 firearms, WeaponHolder, fire/reload animation, casings/smoke.
- Chapter 2 "Paper and Iron": 5 missions, dialogue choices, follow verb, poker minigame.

## Ranked gaps
(Provisional self-assessment until the first blind critic round; gap = weight × (10 − score).)
1. Characters and faces (3 × 9): capsule stand-ins — waiting on the character pipeline.
2. Horses (3 × 5): procedural horse with gaits (oracle-checked footfalls), riding, IK, care, bonding; close-up anatomy, hair physics and rider animation missing.
3. Animation and locomotion (3 × 9): no skeletal animation yet.
4. AI and towns (3 × 7): towns are empty discs until the settlement kit lands; routines need building spots.
5. Writing and missions (3 × 7): 2 of ~40 missions; no cinematics/camera direction.
6. Audio (2 × 5): AudioDirector, synthesized SFX, original score and TTS voices in; real CC0 recordings pending (CI).
7. Wildlife (2 × 9): none yet (plan: reuse the horse SDF/rig pipeline for deer, elk, wolves, coyotes, bison...).
8. Combat (3 × 6): mechanics in place; no weapon models, hit reactions or ragdolls.
9. Terrain/vegetation (3 × 5): good base; trees still card-y up close, no rocks/props scatter, roads need ruts.
10. Lighting (3 × 4): solid sky/fog + cloud shadows; GI interiors untested.
11. Open-world systems (3 × 5): law/standing/economy, shops, encounters, bounties, hunting, camp; no robberies,
    fishing, horse care, gang hideouts yet.
12. UI (2 × 4), Performance (3 × ?: first CI numbers pending), VR (2 × 6).

## Session log
- 2026-10-04: branch created from claude/blocksmith-playtest; Blocksmith mac.yml ignores this branch and
  frontier-bench. First CI run cancelled (benchmark hung on slow tree placement — fixed with a river spatial grid).
- 2026-10-04: audio workstream (worktree): director + generators + score + TTS + Commons pipeline; first CI audio
  build pending (frontier.yml should also fetch audio on asset-cache hits, see AUDIO.md gaps).
- 2026-10-05: audio merged; frontier.yml fetches audio.zip on every run.
- 2026-10-05: horse workstream (worktree): generator, controller, IK, oracles, CI animals job (see HORSES.md).
- 2026-10-05: character pipeline (worktree agent): tools/characters, src/actors, shaders/characters, CI job.
