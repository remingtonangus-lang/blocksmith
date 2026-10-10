# Known test issues

Checks that fail for reasons other than a game bug, and what was done about them.

- **perf `mesh.chunk_ms_mean` gate (CI run 37990566272, 2026-10-09)**: 3.347 -> 5.579 ms on the runner. Not a mesher
  regression: a local A/B on the M1 (dad2af84 vs 05dd5699, `--bench --scenes mesh`, three runs each) gives
  3.48-3.54 vs 3.44-3.55 ms/chunk. The baseline dates from 3763 quads/chunk (now ~4950) and the previous run already
  read 4.38 ms (1.31x), so runner noise crossed the 1.6x gate. Baseline mesh / mesh_lod1 means and quads refreshed to
  run 37970910818 (4.38 / 4.10 ms, 4996 / 2535 quads).
- **ridecheck `ride crew`**: fails on the local M1 at dad2af84 and HEAD alike (crew "deck lost"), passes on CI.
  Pre-existing, not touched.
- **ridecheck `ride troops`** (troop inside the troop-bay engines' z 71 face for one tick): pre-existing flake; troops
  are mobs (Mob physics), the player-side fix for the same face is in Player.update's unstuck.
- **playthrough `blight`**: pre-existing (the bot's arrows can't finish the Blight in 600 s).
