# Status

## CI (compile/test loop)
- `.github/workflows/mac.yml` runs on every push (macos-14, arm64, newest Xcode 16 on the image): `./build.sh` then `./snap.sh`.
- Snapshots + `build.log` + `snap.log` are force-pushed to the orphan branch **`ci-snaps`** each run
  (browse https://github.com/remingtonangus-lang/blocksmith/tree/ci-snaps — its README embeds every PNG and the timings).
  Also uploaded as the `snaps` workflow artifact. The runner has a (paravirtual) Metal device, so snapshots are real renders.
- Development happens on Linux without a Swift toolchain; CI is the compiler. Timings on the CI VM are
  slower than a real M1, so treat them as upper bounds.
- `snap.sh` gained `--find <biome>` (spirals from spawn to the middle of a biome) for biome-specific shots.

## Feature log (newest last)
| Feature | State |
|---|---|
| v0.1 base game (terrain, AO, water, fog, day/night, HUD, save) | verified on M1 |
| CI workflow + ci-snaps publishing | verified (run 1 green) |
| (a) Tree variety: jittered 5×5 grid + density noise, oak / big oak / birch / spruce, birch groves, lower forest density | verified in CI snapshots (forest/snowy) |
| (b) Tall grass + red/yellow/blue flowers as crossed cutout sprites (meadow patches) | untested on Mac |

## Design decisions
- Trees: one candidate per 5×5 cell at a hashed offset (0–3), so trunks are ≥2 apart and there is no lattice.
  Density = `flora` noise (1/64 scale): forests 15–70 % of cells, plains ~2 % (12 % in "copse" patches),
  snowy spruce/oak mix, mountains sparse. Tree validity is decided from `column()` only (not chunk data),
  so canopies crossing chunk borders always match. Max canopy radius 3 = generation margin.
- Plants: new `BlockKind.plant` (no collision, no sky/AO occlusion, targetable). Meshed as 2 diagonal
  quads × 2 windings into the opaque (cutout) buffer; vertex face slot 6 = plant shade. Breaking the block
  under a plant pops the plant; right-clicking a plant replaces it; plants need an opaque block below.
  New blocks 27–30: Tall Grass, Red/Yellow/Blue Flower.
- Clouds: a single camera-relative quad; `cloudFS` picks cloud/no-cloud per 12×12-block cell from two
  octaves of value noise, so it costs one full-screen-ish blended draw and zero CPU work.
  Stars: 1400 quads in a static buffer, rotated by `rotationZ(dayFraction·2π)` (same axis as the sun) and
  faded in as daylight drops below 0.6.
- Lighting: the mesher gathers the 3×3 chunk neighbourhood into one 48×48×192 region, fills direct
  skylight (15 straight down until a sky-stopping block: solids, leaves, water), then BFS-floods sky and
  block light (−1 per step, solids block). Light reaches ≤15 blocks, so the region contains every source
  affecting the centre chunk; no light is stored, remeshing recomputes it (simple, always consistent).
  Vertex w1 now = tex(8) | sky(4)<<8 | block(4)<<12, averaged per vertex over the face/side/corner cells
  (smooth lighting). Shader: `max(sky·daylight, block·warm)`. Block edits remesh the chunk + edge
  neighbours synchronously and the other neighbours in the background (light radius).
  Torch = cross sprite (plant kind), placeable on floor or against a wall; Lamp = solid glowing block.
  Known limit: wall torches don't pop when their wall is broken.
- Water flow: level lives in the block ID (WATER = source, 33–39 = flow 1–7, 40 = falling; hidden from the
  inventory). `World.fluidTick()` runs every 0.2 s of unpaused time on a pending-cell set (budget 1024
  cells/tick); any edit enqueues itself + neighbours if water is involved, so still oceans cost nothing.
  Rules: non-source cells re-derive their level (water above → falling; else min(side levels)+1, dry at >7;
  two side sources over solid/source → new source); water falls first, spreads sideways only when
  standing on a non-water block. Flow edits use `setBlockAsync` (background remesh of chunk + touched
  edge neighbours). Surface corners take the highest of the 4 adjacent cells → sloped water;
  3 bits of w0 (26–28) now hold the per-vertex surface drop in eighths.
  Limits: no "flow toward nearest drop" pathing (spreads evenly); pending updates aren't saved, so a
  flow interrupted by quitting freezes until something nearby changes.
- Inventory: drawn in the Metal HUD (no AppKit views) so it works on a TV with a pad. `HudLayout` holds
  all HUD geometry and is shared by drawing and mouse hit-testing. Open/close: E or pad View (B/Esc also
  close). Navigate: D-pad, left stick (auto-repeat), arrow keys, or mouse hover. A / Enter / click puts the
  highlighted block in the selected hotbar slot; LB/RB, 1–9, scroll or clicking a hotbar slot changes the
  slot. The mouse is released while it's open; the world keeps running (creative). Item names show as toasts.
  Water is now in the block list (placing it starts a flow).
- Survival (toggle: pause menu "Mode" button or pad X while paused; saved per world): no flying; 20 half-heart
  health, 20 hunger + saturation; exhaustion from walking 0.01/m, sprinting 0.1/m, jumping 0.05 (0.2 sprinting),
  breaking 0.005; 4 exhaustion = −1 saturation/hunger. Regen 1 HP / 4 s at hunger ≥ 18 (costs 6 exhaustion);
  starvation 1 HP / 4 s at hunger 0 (never below 1 HP); no sprint at hunger ≤ 6. Fall damage = ceil(fall − 3.5)
  (water landings are free). 15 s of air, then 2 HP/s. Death respawns at the world spawn with full stats.
  Apple (new `item` kind, id 41): hold it and right-click/LT to eat (+4 hunger, +2.4 saturation).
  Intentional simplification: the inventory stays creative-style (unlimited blocks, instant breaking) —
  item drops, counts, mining time and crafting are the next survival steps.
  WorldMeta gained optional fields (survival/health/hunger/saturation), so old world.json still loads.
- Sound: `SoundBank` synthesizes everything at launch (noise bursts through one-pole filters, grain clouds for
  crunchy materials, damped-sine modes for wood/glass, a filtered saw "voice" for grunts and mob calls), 3
  pitch/seed variants each. `SoundEngine` = AVAudioEngine + 12 AVAudioPlayerNodes round-robin, distance
  attenuation (28 blocks) and stereo pan from the listener yaw. If the audio engine can't start, the game runs
  silently. `./snap.sh` also runs `--sounds snaps/sounds`, which writes every sound as a WAV (published on
  ci-snaps) — listen there. AVFoundation was added to build.sh (the user asked for AVAudioEngine).
- Mobs: `MobManager` keeps ≤ 20 animals; every 1.5 s it may spawn a group of 2–4 on grass 2–6 chunks away
  (biome decides the species), and despawns mobs that leave the loaded area. Models are cuboids built each
  frame straight into the renderer's scratch ring (no arrays; ~400 verts/mob), coloured with a model-space
  pixel pattern in `mobFS` (cow patches, wool, feathers). Lighting is daylight × (0.55 if something is above).
  Left-click/RT hits (3 damage, knockback, 5 s panic); dead mobs just disappear (no drops yet). Mobs are not
  saved. Chickens fall slowly.
- New blocks 23–26: Birch Log, Birch Leaves, Spruce Log, Spruce Leaves (appended; old saves stay valid).

## Known risks / unverified assumptions

## Next
All requested items (a)–(i) are implemented. Suggested follow-ups: item drops + counts + mining time for
survival, food from animals, crafting, greedy meshing, mob lighting from real light values, first-person hand,
controller-driven pause menu (currently AppKit buttons + pad shortcuts).
