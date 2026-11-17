# Fast proof: one named check in about a minute

**The rule:** `tools/prove.sh` is for iterating. The final proof before a merge is still the full suite, alone, on the
whole-module `-Ounchecked` build (`QUEST_OPT=-Ounchecked quest/tools/linux-check.sh build`, then the whole questcheck run).
Every timing and frame-rate number also comes from that build, never from the incremental one.

## The three commands

```
tools/prove.sh NAME                      # build what changed (-O, incremental), run questcheck's NAME check, terse output
tools/prove.sh --both BS_SWITCH NAME     # the same check twice: BS_SWITCH unset, then BS_SWITCH=1; both results
build/quest-inc-o/questcheck --list-checks   # every named run with its one-line comment
```

- `NAME` is `rail` for `--rail-only`; a run without `-only` works too (`placerow` -> `--placerow`), or give the whole flag.
- `ENV=VAL` arguments go to the check's environment (`tools/prove.sh rail BS_OLDWETROW=1`); arguments after `--` go to
  questcheck (`tools/prove.sh oct14 -- P251`).
- It runs from the repo dir at `BLOCKSMITH_TEXRES=32` and prints only `FAIL` lines, lines that mention NAME, the final
  pass/fail line and the times. `PROVE_ALL=1` prints everything. Exit code = failures (100 = build failed).
- `PROVE_OPT=onone` builds unoptimized (faster to build, checks run ~9x slower); `PROVE_BIN=path` uses a binary you
  already have (e.g. the WMO build) and builds nothing.
- `tools/qbuild.sh [onone|o|ounchecked]` is the build alone. It keeps its objects in `build/quest-inc-<mode>/` (one per
  worktree): delete that dir to start clean. It writes generated files only when they change, so they stay built.
- `quest/tools/listchecks.py` prints the same list from the source, without a build; `linux-check.sh` and `qbuild.sh`
  generate `CheckList.swift` from it.

## Measured (cloud box, 4 cores, 15 GB; Nov 16, quest-port 26ceac53)

| Build | Full | One-file body edit | New member on `World` |
|---|---|---|---|
| WMO `-Ounchecked` (`linux-check.sh build`, the merge gate) | 1,929 s (32 min) | everything again | everything again |
| incremental `-O`, file by file (`qbuild.sh o`, prove's default) | 455 s | 18-22 s | 367 s |
| incremental `-Onone` (`qbuild.sh onone`) | 134 s | 12-15 s | 106 s |

Running a check: `--throw-only` takes 28 s on the `-O` build and 250 s on `-Onone`, so prove defaults to `-O`.
`tools/prove.sh throw` after a one-file body edit: about 1 minute wall. Most of a small check's time is the shared
world load main.swift does before the `--X-only` runs, not the check itself.

Why it is fast: the old host build is one `swiftc` call with no incremental state, so every build compiles all 813
files (257k lines) again; whole-module optimization can't split the work. `qbuild.sh` passes `-incremental
-enable-batch-mode -j N -output-file-map`, so the driver recompiles only the changed files and the files that use
what changed, four at a time. Splitting the test harness was not needed: the harness is 13k of the 257k lines.

Things to know:
- An interface change (a new or changed member, type or global) in a widely used file recompiles most of the tree:
  about 6 minutes at `-O`. Body-only edits are seconds.
- Non-WMO `-O` code is not the shipped code (nothing inlines across files): fine for logic, never for timings.
- Don't run two builds at once on 4 cores with a WMO build (memory: ~7 GB each).

## What a named run starts with (job 2, Nov 16)

Before, every `--X-only` run paid ~27 s of setup before its check: the natural census (NaturalCensus.swift, ~70
sample chunks generated, 18 s: questcheck points its data root at a per-run temp dir, so the census's disk cache never
hit), the shared world (World + Game + loadSync radius 4, ~5 s) and four inline whole-run checks (axis place, block
feet, stale light, driving HUD, ~4 s), plus GunFittingsCheck before the later runs.

Now, on a run that names a check (any `--X-only` argument):
- **No world:** gunfittings, factions-structures, water, overlaps, musiclevels, settings, savesoak and capitals run
  before the shared world is made (they make their own worlds or none).
- **Census kept per binary:** the census is copied to `/tmp/questcheck-census-<exe path hash>-<size>-<date>.txt`
  after the first named run of a build and read back by the next (same binary, same result). The whole run always
  computes it. `QC_KEEP_CENSUS=0` turns it off; `=1` turns it on for a whole run too.
- **Whole-run-only checks skipped:** the four inline checks and GunFittingsCheck run on the whole run only (the
  gunfittings run still runs its own check).
- **Full world:** every other named check still gets the same radius-4 world as before. A smaller world was not added:
  it would save ~3 s and could make a check pass alone that fails in the suite.

| Check | Before | After (census kept) |
|---|---|---|
| `--gunfittings-only` (no world) | 27 s | under 1 s |
| `--throw-only` (full world, small check) | 28 s | 6 s |
| `--rules-only` (full world, mid check) | 27 s | 9-10 s |

The first named run of a new build still computes the census once (+18 s). The whole suite runs exactly as before.

## Scene files: a voice note's bug played back (job 3, Nov 17)

`questcheck --scene FILE [--seed S] [--headset] [--out DIR]` reads a text file, one command a line (`#` comments), and
plays it against the game through the calls play uses: Game.tick at 72 Hz, and the player's look, walk, break and place
through the bot's input path (Agent.apply, the same InputState the window fills). One result line a command;
`expect` lines print `ok`/`FAIL` and a failed one makes the exit non-zero. `--headset` makes a field world with polygon
ground, as the headset makes new worlds. Shots go to `--out DIR` (default the temp dir), never into the repo.

Coordinates are as the game shows them (a voice note's Position line): y is the displayed height. `look` takes the
note's facing and pitch in degrees.

| Command | Does |
|---|---|
| `at X Y Z`, `look YAW PITCH`, `load R` | stand there, face there, load R chunks round him |
| `tick SECONDS` | play on (prints tick avg and worst ms) |
| `survival on\|off`, `fly on\|off`, `give ITEM [N]` | mode, flying, an item in his hand |
| `block X Y Z` | the block there, or `ground(material)` for a field world's natural ground |
| `set X Y Z KEY` | set a block (World.setBlock) |
| `ground X0 Y0 Z0 X1 Y1 Z1 MAT\|air` | a box of natural ground (field density, as the weigh checks build fixtures) |
| `break X Y Z` | turn onto the cell and hold attack until it is gone (10 s at most) |
| `place X Y Z` | turn onto the top of the cell under it and press use once with what he holds |
| `blast X Y Z [POWER]` | Explosion.explode, half a second, then the ground's weighing played out (as `--blasts`) |
| `dump X0 Y0 Z0 X1 Y1 Z1` | every cell, a row a line, runs joined (4,096 cells at most) |
| `shot NAME.png [W H]` | the `--view` render (both eyes) at his eye |
| `spawn mob KIND`, `spawn vessel KIND` | a mob 6 ahead; a ShipTest vessel (car, airship, plane...) assembled ahead |
| `ride nearest train\|ship`, `drive THROTTLE SECONDS`, `walk forward SECONDS` | board as he boards (Trains.use, the helm), hold the throttle or walk |
| `train at station` | the nearest line's passenger train (within 3,000 blocks), its clock run on until it stands at the station nearest him; he is put beside it (classic worlds: no `--headset`) |
| `stand in coach N`, `ride until step N MIN [SECONDS]` | in coach N's aisle, aboard; play on until the floors' step where coach N meets coach N-1 is MIN or more either way (a change of grade) |
| `walk to coach N [SECONDS]` | walk toward coach N as ledger 141's check walks; sets `walk.there` (1/0), `walk.lowest` (least height over the rail in the coach he is in), `walk.step` |
| `print player\|train\|ship\|fps` | place, speed, held, aboard, hull; tick avg and worst over the last tick |
| `expect block X Y Z == KEY`, `expect ground X Y Z == true\|false`, `expect NAME OP N` | NAME: player.x/y/z/speed/health, ship.speed/blocks/y, train.speed, walk.there/lowest/step, fps.worst/avg, felled.count/blocks/tilt/spin (the felled trees in the world: tilt 0 lying level, 1 upright or upside down) |

Scenes in `quest/scenes/` (each passes on the fix and fails with its switch):

| Scene | Fixed | With the switch |
|---|---|---|
| `rock-place-break.scene --headset` (ledger 136) | all passed | `BS_OLDROCKLUMP=1`: 1 FAILED (the placed stone is ground) |
| `crater-settle.scene --headset` (ledgers 127, 216) | all passed | `BS_GROUNDWEIGH=0`: the stub and cap hang; `BS_OLDWEIGHSPARE=1`: 3 FAILED (the cap's ring hangs) |
| `coach-to-coach.scene` (ledger 215) | all passed: there in 2.3 s, never lower than 0.95 | `BS_OLDGANGWAYSTEP=1`: 2 FAILED (falls through at the coupling, -3.35) |
| `overhang-stays.scene --headset` (ledger 216's guard) | all passed: the ledge beside the blast stays | `BS_OLDWEIGHSPARE=1`: passes too (a guard, not a repro) |
| `tree-stump-stays.scene --seed 7780452129890778212 --headset` (ledgers 226, 227) | all passed: stump and neighbour stand, one body of 144 | `BS_OLDFELLSTUMP=1`: 5 FAILED (246 blocks fall) |
| `tree-lies-down.scene --seed 3084501862406496736 --headset` (ledger 228) | all passed: tilt 0.79, spin 0 | `BS_OLDCROWNWEIGHT=1`: 1 FAILED (upside down) |
| `bush-on-the-ground.scene --seed 3084501862406496736 --headset` (ledger 229) | all passed; bush.png | `BS_OLDBUSHMOUND=1`: 3 FAILED |

Each runs in about 15 s after the census is kept. `ride nearest train` needs a train in the loaded land.
