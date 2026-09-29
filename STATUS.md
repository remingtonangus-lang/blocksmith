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
| (a) Tree variety: jittered 5×5 grid + density noise, oak / big oak / birch / spruce, birch groves, lower forest density | untested on Mac |

## Design decisions
- Trees: one candidate per 5×5 cell at a hashed offset (0–3), so trunks are ≥2 apart and there is no lattice.
  Density = `flora` noise (1/64 scale): forests 15–70 % of cells, plains ~2 % (12 % in "copse" patches),
  snowy spruce/oak mix, mountains sparse. Tree validity is decided from `column()` only (not chunk data),
  so canopies crossing chunk borders always match. Max canopy radius 3 = generation margin.
- New blocks 23–26: Birch Log, Birch Leaves, Spruce Log, Spruce Leaves (appended; old saves stay valid).

## Known risks / unverified assumptions
- Skylight is a heightmap approximation (no propagation) — caves are dark by design, overhangs uniformly shaded.
- Water is static (no flow); placing water isn't in the block cycle.

## Next
Remaining list, in order: (b) tall grass + flowers, (c) clouds + stars, (d) block light + torches,
(e) flowing water, (f) creative inventory, (g) survival, (h) sounds, (i) passive mobs.
