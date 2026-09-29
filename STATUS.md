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
- New blocks 23–26: Birch Log, Birch Leaves, Spruce Log, Spruce Leaves (appended; old saves stay valid).

## Known risks / unverified assumptions
- Water is static (no flow); placing water isn't in the block cycle.

## Next
Remaining list, in order: (d) block light + torches,
(e) flowing water, (f) creative inventory, (g) survival, (h) sounds, (i) passive mobs.
