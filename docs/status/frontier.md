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
- Feature evidence shots (HUD, combat, menus, wildlife, riding, camp, dialogue, satchel, wheel):
  `xvfb-run -a godot --path frontier -- --features DIR [--only a,b]`.
- Bots: `--bot road,explore,ride,gaits,town,gunfight,hunt,missions,camp,systems` (or `all`); missions bot options
  `--choices 0,1,...`, `--force_fail mission:checkpoint`, `--standing N --expect_ending high|middle|low`.
- Profiling: `--prof` prints frame spikes with per-system attribution (spawns, system loops, actor ticks).
- Kill-switches: `--disable vfog,ssr,ssao,shadows,grass,trees,scatter,water,roads,backdrop,cloudshadows,characters,horse,sss`,
  `--no_settlements`, `--no_actor_lod`, `--noaudio`.
- Self-tests: `--pokertest`, `--audiotest`, `--script res://src/missions/ch3/herd_selftest.gd`,
  `--script res://src/missions/ch5/train_selftest.gd`.

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
  hunting (12 species, pelt quality, skinning); camp; road graph + GPS routes on map/HUD; hold-ups and store
  robberies (src/systems/robbery.gd); fishing (8 species by river/creek/lake, cast/strike/line-tension fight,
  keep or release, sold at the butcher; src/systems/fishing.gd).
- **Story complete (first pass)**: chapters 1-6, 27 missions, three endings locked by Standing, playable spring-1900
  epilogue, credits from LICENSES.md; retry from checkpoint; camp life with companions and 105 camp lines.
- **Missions**: MissionDirector (goto/say/spawn/wait_dead/interact/checkpoint, markers, autopilot, softlock oracle);
  Chapter 1 complete (5 missions: Rider from the West, The Drover, Inquiries, Greer's Post, A Fire at Willow Bend)
  with original dialogue (design/dialogue/ch1.json); letterboxed cinematic dialogue camera.
- **Chapter 2 "Paper and Iron"** (`src/missions/ch2/`, `design/dialogue/ch2.json`): 5 missions; director verbs choose
  (bots: `--choices 0,1,0`), follow, sneak_to, escape, paper, minigame, post_bounty; five-card-draw poker with a
  catchable stacked deck (`src/minigames/`, self-test `--pokertest`).
- **Chapter 3 "Dry Season"** (`src/missions/ch3/`, `design/dialogue/ch3.json`): 5 missions (water war, a mounted cattle
  drive with strays and a stampede, Doc joins, Cutter Shale killed or jailed); verbs mount_up, lead, ride_with, drive,
  stampede, defend; failed missions offer retry from checkpoint / restart / abandon (decisions replayed).
- **Chapter 4 "Silver and Snow"** (`src/missions/ch4/`, `ch4.json`): 5 missions (strike, mine blast, climb + cold +
  avalanche on the Kestrel Pass, Asa spared/killed → flag `spared_asa`, Joseph joins); verbs set_snow, cold_begin/
  warm_spot, climb, avalanche, timed_tasks, pursue. **Camp life** (`src/ai/camp.gd`, `camp.json`): companions' spots
  and routines, fireside talk/barks picked from flags and deeds, stew/drink/cards with Del; `--bot camp`.
- **Chapters 5-6 + epilogue + credits** (`src/missions/ch5/`, `ch6/`, `credits.gd`): the Meridian express (procedural
  train + track on the worldgen rail, gallop alongside and board, `--script res://src/missions/ch5/train_selftest.gd`),
  Hap's fate, the Outfit's split, Standing locks the ending (bots: `--standing N`), three endings, spring 1900
  epilogue reading every flag, credits from LICENSES.md. Story scenes in chapters 1-4 moved into the real buildings
  (`src/missions/places.gd`: saloons, sheriff's offices, the bank vault, the newspaper, the cantina).
- **Side content**: ten Strangers missions (`src/missions/strangers/`, `strangers.json`; world markers by chapter,
  choices remembered in camp talk and other strangers; fishing, hunting, poker, glass balls, sneaking, a runaway
  Locomobile), eighteen roadside encounter kinds (`src/ai/encounters.gd`, `--bot encounters`), and a journal page per
  mission in Ruth's voice with ink sketches drawn in code (`src/missions/journal.gd`; `--journal_all` for shots).
- **World reactivity** (`src/systems/social.gd`, `newspaper.gd`, `social.json`, `newspaper.json`): greet / antagonize
  (T: insult → shove → draw or flee) / defuse (N) with lines by voice and Standing band; gossip and reactive barks
  from flags, crimes, bounties, weather and hour (lawmen eye a wanted Ruth, shop clerks remember robberies); 5¢
  newspapers per town with dated front pages (32 story templates + weather, markets, ads, notices); five companion
  missions (`src/missions/companions/`) that change camp talk. `--bot social`.
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
  module, game rig with Godot humanoid bone names + eye bones, 38 face blend shapes (CC0 ARKit units + visemes +
  gaze-following lids), procedural 1899 garments (bisect-cut edges, drape/blouse/trouser break, stitch + wrinkle
  shading, spring-bone skirts/coat tails), women's updos, shell beards, corneas, skin cavity/oily/stubble masks,
  36 seeded NPCs over 12 roles (<= 24 k tris) + Ruth Caddell (<= 39 k, duster variant), LOD1/LOD2 meshes.
  CMU mocap + IK-keyframed clips in `animations.glb` (76 clips: locomotion, aim with forend support hand, reloads,
  holster, riding seat set + mount/dismount left). Godot: `CharacterFactory.spawn(seed, role)` →
  `FrontierCharacter` (AnimationTree driver incl. ride blend space and action one-shots, lip-sync from AudioDirector
  viseme events + emotion moods, blink, gaze).
  CI job `characters` publishes `characters.zip`; `tools/fetch_assets.sh characters` fetches it.
- **Horses** (`frontier/design/HORSES.md`): procedural horse generator
  `frontier/tools/animals/horse_gen.py` (Blender bpy: SDF anatomy → mesh/LODs, rig, weights, mane/tail cards, eyes,
  stock-saddle tack, IK-solved gait cycles + idles/actions → `horse.glb` + `horse_gaits.json`; CI job `animals` in
  frontier-assets.yml → `animals.zip`, `fetch_assets.sh animals`), `Horse` riding controller, `HorseVisual`
  (AnimationTree, coats), `HorseIK` (terrain foot IK + foot locking), coat/hair shaders, `--bot ride|gaits` with gait
  oracle, look-dev scene `scenes/horse_test.tscn`, player's horse spawned in `main.gd`.
- **VR**: OpenXR start on Android, XROrigin rig, controller → intent mapping, snap turn, comfort vignette.

## In flight (parallel worktree agents; merged here when they report)
- Settlements: NPC routines, draw-call and memory cuts (settlements ≈ 680 MB headless), sign renames.
- Characters: memory/VRAM compression (`--charmem`), quality pass follow-ups.
- Weapons: VR hands and guns (`--vr_sim`).
- Writer: greet/antagonize, gossip, newspapers, companion missions.
- Impostors: baked tree impostors replacing the distant billboards.
- Wildlife/horses: fur shells, face detail, turn-in-place, rider polish (reins, mount clips), gallop spine flex.

## Ranked gaps
Critic round 1 (2026-10-05, 2 blind critics, pack = CI tour a4d48b8 + character/horse look-dev sheets; averaged
scores, gap = weight × (10 − score)):
| System | A | B | avg | gap |
|---|---|---|---|---|
| AI and towns | 1 | 1 | 1 | 27 |
| Combat and gunplay | 1 | 1 | 1 | 27 |
| Open-world systems | 1 | 1 | 1 | 27 |
| Writing and missions | 1 | 1 | 1 | 27 |
| Animation and locomotion | 2 | 2 | 2 | 24 |
| Performance and stability | 3 | 2 | 2.5 | 22.5 |
| Characters and faces | 3 | 3 | 3 | 21 |
| Horses | 3 | 3 | 3 | 21 |
| Terrain and vegetation | 4 | 3 | 3.5 | 19.5 |
| Lighting and atmosphere | 4 | 3 | 3.5 | 19.5 |
| VR | 0 | 0 | 0 | 20 |
| Wildlife / Audio / UI | 1 | 1 | 1 | 18 each |
Reading: half the 1s are missing evidence (no town/NPC/gun/HUD/menu/wildlife/audio in the pack; non-moving bots
print zeros in their summary line). Real visual defects both critics named: lake = opaque peach plane with a black
horizon band; autumn billboards glow at night; storm has no darkening/wetness, rain rods and square splashes; flat
brown horizon band at the map edge; heavy haze in the mountains; terraced "sawtooth" mesas and contour stripes on
Kestrel slopes; white ruts + orange road smear (fixed after the round); clothing holes/beards/waxy skin; gallop
stiffness; 2 s streaming hitch on the river ride.
Work order from this round:
1. Evidence pipeline: CI feature shots (HUD on foot in a populated town, gunfight + Nerve, map/journal/shop/poker
   screens, wildlife, riding, camp at night, mission dialogue), per-bot metrics in the summary line, audio verify
   report and voice coverage in the pack.
2. Lake/water, night foliage, storm look, horizon backdrop beyond the map, haze, terrain stripes.
3. Towns (settlements agent), guns (weapons agent), characters (character agent), horses + wildlife (horse agent),
   distant trees (impostor agent), Chapter 3 + checkpoint retry (writer agent).
4. Streaming hitches (river ride 2 s, town 0.6 s).

## Session log
- 2026-10-04: branch created from claude/blocksmith-playtest; Blocksmith mac.yml ignores this branch and
  frontier-bench. First CI run cancelled (benchmark hung on slow tree placement — fixed with a river spatial grid).
- 2026-10-04: audio workstream (worktree): director + generators + score + TTS + Commons pipeline; first CI audio
  build pending (frontier.yml should also fetch audio on asset-cache hits, see AUDIO.md gaps).
- 2026-10-05: audio merged; frontier.yml fetches audio.zip on every run.
- 2026-10-05: horse workstream (worktree): generator, controller, IK, oracles, CI animals job (see HORSES.md).
- 2026-10-05: character pipeline (worktree agent): tools/characters, src/actors, shaders/characters, CI job.
- 2026-10-05: weapons workstream (worktree): tools/weapons/gun_gen.py (10 guns + variants, baked PBR, LOD1), CI weapons job -> weapons.zip, WeaponModel/WeaponHolder/WeaponFX, weapon_lineup scene (see WEAPONS.md).
- 2026-10-05: combat feel (worktree): arm IK onto guns, leather belt/holster/sling/scabbard, death ragdolls, surface impacts + fading decals, night muzzle light, casing sounds, Nerve grade/ink marks/camera cuts (see WEAPONS.md).
- 2026-10-05: character quality pass (worktree agent): garments/drape/springs, updos, faces + lip-sync, riding and
  weapon-handling clips, tri budgets + LODs.
- 2026-10-05: wildlife workstream (worktree): quadruped.py + 11 species, animal coat shader, animal.gd model wiring, per-species gait oracle (wildlife_test.tscn, `--bot hunt`), RiderIK (see WILDLIFE.md).
- 2026-10-05: CI device-lost bisected (3ba9a99): the paravirtual GPU still lost the device with every world feature
  off and rendered once screen-space subsurface scattering (character skin) was off too. The probe now tries
  sss / horse / characters first, so evidence renders keep the whole world. Open risk: confirm SSS on a real M1
  (Metal) with the monitor benchmark; if it hitches there, drop skin SSS on medium/low.
