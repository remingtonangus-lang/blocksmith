# Known test issues

Checks that fail for reasons other than a game bug, and what was done about them.

- **perf `mesh.chunk_ms_mean` gate (CI run 37990566272, 2026-10-09)**: 3.347 -> 5.579 ms on the runner. Not a mesher
  regression: a local A/B on the M1 (dad2af84 vs 05dd5699, `--bench --scenes mesh`, three runs each) gives
  3.48-3.54 vs 3.44-3.55 ms/chunk. The baseline dates from 3763 quads/chunk (now ~4950) and the previous run already
  read 4.38 ms (1.31x), so runner noise crossed the 1.6x gate. Baseline mesh / mesh_lod1 means and quads refreshed to
  run 37970910818 (4.38 / 4.10 ms, 4996 / 2535 quads).
- **ridecheck `ride crew` / `ride troops`** (fixed 2026-10-15, 0430fec / ff2fb16, green on run 1691): freed crew of a
  wrecked crawler walked down its lowered ramp (a half-block step down is now a ledge to them); a troop turning for the
  doorway at 0.6 from a waypoint cut the troop-bay engines' corner (waypoints reached at 0.3).
- **playthrough `blight`** (fixed 2026-10-16, ca63ec1): a game bug, not the bot. Any mob in the crosshair within 3.5
  blocks swallowed every use (Game.interact's mob branch always returned), so once the Blight hovered close overhead
  the bow never drew. Defeated in 26 s on the fast lane of ca63ec1.
