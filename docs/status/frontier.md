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
- Character pipeline (`frontier/design/CHARACTERS.md`): MakeHuman CC0 bodies via MPFB2 run headless in the `bpy`
  module, game rig with Godot humanoid bone names + eye bones, 34 face blend shapes (CC0 ARKit units + visemes),
  procedural 1899 garments/hats/beards, 36 seeded NPCs over 12 roles + Ruth Caddell (hero LOD, duster variant),
  CMU mocap retargeted to `animations.glb` (65 clips incl. procedural aim/hit/lean, root motion, foot contacts).
  Godot: `CharacterFactory.spawn(seed, role)` → `FrontierCharacter` (clips, visemes, expressions, blink, gaze).
  CI job `characters` publishes `characters.zip`; `tools/fetch_assets.sh characters` fetches it.

## Ranked gaps
(Scores from blind critic rounds against QUALITY_BAR.md; gap = weight × (10 − score).)
1. Everything playable: no game exists yet — build the vertical slice (terrain render, sky, player, horse, town).

## Session log
- 2026-10-04: branch created from claude/blocksmith-playtest; Blocksmith mac.yml ignores this branch.
- 2026-10-05: character pipeline (worktree agent): tools/characters, src/actors, shaders/characters, CI job.
