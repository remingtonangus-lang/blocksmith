# Frontier — status (session G, branch claude/frontier-game)

Original open-world Western (working title **Sable River**, codename Frontier) for Mac (flagship) and Meta Quest 3.
Project: `frontier/` (Godot 4.7.1). Bar: `frontier/QUALITY_BAR.md`. World bible: `frontier/design/WORLD.md`.

## Engine decision
Godot 4.7.1: Metal (Forward+) on macOS with MetalFX upscaling, Vulkan Mobile + built-in OpenXR on Quest 3, one
text-based project (scenes/resources/shaders as text, game logic in typed GDScript), headless import/export/tests in
CI, MIT licence. Unreal/Unity were rejected: no editor-free text workflow, heavy on an 8 GB M1, Unity licensing, and
neither builds Mac + Quest from Linux CI. A custom engine was rejected: Godot already has Jolt physics, OpenXR, MetalFX,
volumetric fog, SDFGI/VoxelGI, skeletal IK modifiers (TwoBoneIK3D, LookAtModifier3D, SpringBone) and AnimationTree.
Local loop: Godot Linux + lavapipe (software Vulkan) under xvfb renders Forward+ screenshots in the cloud session.

## What exists
- World generator `frontier/tools/worldgen.py`: 8 × 8 km heightmap (2 m), stream-power + droplet erosion, Kestrel
  Range, Thornwood hills, Ocotillo Breaks mesas, Corrigan Plains, Lake Agnes, meandering Sable River + 2 creeks,
  4 towns + 8 POIs flattened, A*-routed graded roads, graded railroad; control map (roads, moisture, biome, sediment).
- Asset pipeline: `frontier-assets` workflow (ubuntu) → release `frontier-assets` (catalog.zip, ext.zip).
- Audio (`frontier/src/audio/`, `frontier/tools/audio/`, doc `frontier/design/AUDIO.md`): AudioDirector
  (`Game.audio`, added in main.gd; `--noaudio` skips, `--audiotest` self-test) with buses, pooled 3D one-shots +
  occlusion, gunshot model (speed of sound, close/far/distant/indoor, terrain/facade echoes), footsteps/hooves by
  surface and gait, ambience mixer (biome/time/weather/water/towns, creature calls, thunder), adaptive stem score
  (explore/town/tension/combat/mission/Nerve), Nerve slow-time audio, UI, voice lines with visemes, volume settings.
  Content: ~190 synthesized SFX/ambience ids (~800 files), 16 original music tracks rendered with FluidSynth
  (FluidR3 GM, MIT), Kokoro-82M TTS (Apache-2.0) for Ruth + NPC barks (`design/dialogue/`), CC0/PD Commons recordings
  in CI. CI job `audio` in frontier-assets.yml publishes `audio.zip`; `tools/fetch_assets.sh audio` fetches it.

## Ranked gaps
(Scores from blind critic rounds against QUALITY_BAR.md; gap = weight × (10 − score).)
1. Everything playable: no game exists yet — build the vertical slice (terrain render, sky, player, horse, town).

## Session log
- 2026-10-04: branch created from claude/blocksmith-playtest; Blocksmith mac.yml ignores this branch.
- 2026-10-04: audio workstream (worktree): director + generators + score + TTS + Commons pipeline; first CI audio
  build pending (frontier.yml should also fetch audio on asset-cache hits, see AUDIO.md gaps).
