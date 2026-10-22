# Saves across versions (P395)

## Field-world save changes since Oct 14 (step 1)

From `git log` on Save.swift, SaveMigration.swift and the field files:

| Date | Commit | Change | What an older save lacks, and how the loader copes |
|---|---|---|---|
| Oct 14 | 06cf699b, 00eba7bf | Field file per chunk, `FLD1` (lzfse: materials + densities) | The first field-default save. Chunks without a field file generate their field and lay the saved blocks over it. |
| Oct 18 | 836b50ea (P338) | `pieces.json`: free-build pieces | No file: no pieces (an older build had none). |
| Oct 19 | 8874defd (P377) | `FLD2`: FLD1 plus fine sections for edited ground | FLD1 is still read; a chunk without fine sections is still written as FLD1, so older builds read newer saves too. |
| Oct 19 | 6b0bcc0d | `meshcache/`: section meshes on disk | Versioned header; a missing or stale file is rebuilt. Never the source of truth. |
| Oct 19 | e52f4b6f (P337) | `trains.json`: delay, robbed and wrecked state per train | No file: every train on its timetable. |
| Oct 21 | f6330321 (P389) | `objects.json`: object cells, parts and cuts | No file: every object loads whole, as cells (edits to the cells kept). |
| (earlier) | SaveMigration | world.json `format` 4 | Older worlds are backed up once, then migrated (animal thinning). |

Every change is additive: a newer build reads each older form, and nothing older is rewritten in place except by the
format-4 migration, which backs the world up first.

## Round trip (step 3)

`questcheck --saveacross write DIR` (Sources/SaveAcross.swift) builds a world with player edits (placed and broken
blocks, a dug hole in the field ground, a free-build piece, a pool), water and lava, falling sand, and (where the build
has them) a delayed, robbed and wrecked train and an object struck three times. It saves, writes what it expects to
DIR/expect.json, and exits. `questcheck --saveacross read DIR` on the current build loads the world and compares.

Results (seed 424243; each old build checked out in its own worktree and built with `QUEST_OPT=-Ounchecked`):

| Saved by | Blocks (placed, broken, fluids) | Ground round the pit, crater, pool | Falling sand | Train | Struck object | Result |
|---|---|---|---|---|---|---|
| e62ae416 (Oct 14, the first field-default build) | 220 of 220 as saved | 405 points, 0 changed side, largest density change 0 | lost by that build's save | (none then) | (none then) | OK |
| f6330321 (Oct 21, P389 objects) | 221 of 221 | 405, 0, 0 | lost by that build's save | delay, robbery, wreck as saved | 3 cuts, 80 pieces, volume as saved | OK |
| this build | 221 of 221 | 405, 0, 0 | kept, falls on after the load | as saved | as saved | OK |

What can't load: nothing that was saved. The one loss was in the saving: a gravity block (sand, gravel, an anvil)
falling while the game saved was gone after a load, in every build before this one (the cell it left was saved
empty and the falling entity isn't kept). Now each is saved in the cell it has reached, its cell goes in
falling.json, and the load lets it fall on.
