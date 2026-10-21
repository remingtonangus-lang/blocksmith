# P385: CPU record time at view 24

All numbers are host numbers from `questcheck` built with the headset's compiler setting (`QUEST_OPT=-Ounchecked`),
on Remington's seed 13480747113613945685, Polygons world, Quest settings, at the Stone Gulch perfscene
(`questcheck --perfscenes --only gulch --rd 8,24 --flyframes 0 --turnframes 288`). Each run stands for 360 frames,
then turns the head a steady 360 degrees over 288 frames (4 s at 72 fps). The timings were taken on a quiet machine
(no build running). There is no GPU here: lavapipe draws the frames on the CPU, and the headset-only checks
(Adreno GPU time, the headset's own CPU log) are skipped.

"Before" is measured two ways:
- `p384d`: P384's final binary, the true starting point.
- The new binary with every P385 change switched off (`BS_FASTCULL=0 BS_MOBTHREAD=0 BS_LMSPLIT=0
  BS_TABLEEPOCH=0 BS_OCCPAR=0`). This one splits the old cull into the same stages as the new one, so the two
  tables line up.

The off mode still includes one change that has no switch, `Section.owner` (step 4), which is why it records
faster than `p384d`.

Two notes on the host build:
- It is not whole-module and keeps Swift's exclusivity checks. The APK builds with `-wmo -enforce-exclusivity=unchecked`.
- The host's 4 cores are shared with lavapipe's threads and with the mesh workers, which use about 2 cores the whole
  time at Stone Gulch (water flowing, grass spreading). The headset has its own GPU and more cores.

So the headset should record a little faster than these numbers.

## Result

| view 24, Stone Gulch | standing | turning 360 |
|---|---|---|
| before, `p384d` | 9.40 / 10.51 ms (two runs) | not measured (no turn in that binary) |
| before, P385 off (same binary as after) | 8.18 ms | 7.39 ms |
| after, run 1 | 3.09 ms | 3.37 ms |
| after, run 2 | 3.38 ms | 2.62 ms |
| after, run 3 | 2.63 ms | 2.79 ms |

| view 8, Stone Gulch | standing | turning 360 |
|---|---|---|
| before, `p384d` | 2.39 ms | not measured |
| before, P385 off | 2.46 ms | 3.05 ms |
| after | 1.46 ms | 1.46 ms |

The target was host record at view 24 at or under 3.5 ms. It is met in every run, standing and turning (mean
record a frame; the p95 is 4.0-5.4 ms). The sections and draws are the same as before (step 5).

## Step 1: where the record went (ms a frame, mean)

The stages are timed inside `WorldRenderer.record`:
- **uniforms**
- **cull**, in five parts:
  - **table**: the per-column cull table (new; step 2)
  - **walk**: the cave-culling walk with its frustum test, and the sort
  - **horizon**: horizon culling
  - **occlusion**: occlusion culling (with the wait for its worker)
  - **list**: the visible list
- **records**: section records
- **hud**: the HUD panel
- **terrain**: the slab draw lists, built and recorded
- **ring**: the middle ring
- **ships**
- **landmarks**: impostors, horizon ground and smoke
- **mobs**: with the wait for their worker
- **entities**
- **particles**
- **sky**
- **translucent**
- **ui**: outline, hands and overlays

`p384d` had only the coarse split (cull, terrain, ships+landmarks, mobs, entities, rest). At view 24, standing, it
gave:
- cull 6.44
- terrain 1.40
- ships+landmarks 0.44
- mobs 0.70
- entities 0.25
- rest 0.16

| stage | v24 before, standing | v24 before, turning | v24 after, standing | v24 after, turning | v8 before, standing | v8 before, turning | v8 after, standing | v8 after, turning |
|---|---|---|---|---|---|---|---|---|
| uniforms | 0.04 | 0.03 | 0.03 | 0.04 | 0.04 | 0.04 | 0.03 | 0.03 |
| table | - | - | 0.03 | 0.02 | - | - | 0.02 | 0.02 |
| walk (frustum + caves) | 3.28 | 2.83 | 1.15 | 1.16 | 0.25 | 0.36 | 0.14 | 0.11 |
| horizon | 0.82 | 0.73 | 0.32 | 0.30 | 0.11 | 0.15 | 0.03 | 0.04 |
| occlusion | 0.81 | 0.67 | 0.36 | 0.34 | 0.28 | 0.33 | 0.16 | 0.19 |
| list + records | 0.18 | 0.17 | 0.03 | 0.04 | 0.02 | 0.04 | 0.00 | 0.00 |
| terrain draw lists | 1.17 | 1.09 | 0.33 | 0.41 | 0.12 | 0.19 | 0.06 | 0.05 |
| middle ring | 0.11 | 0.10 | 0.15 | 0.15 | 0.01 | 0.01 | 0.02 | 0.02 |
| landmarks | 0.52 | 0.49 | 0.20 | 0.22 | 0.54 | 0.60 | 0.20 | 0.19 |
| mobs | 0.78 | 0.81 | 0.08 | 0.11 | 0.81 | 0.97 | 0.54 | 0.55 |
| entities | 0.28 | 0.30 | 0.26 | 0.40 | 0.21 | 0.27 | 0.18 | 0.21 |
| particles, sky, ui | 0.05 | 0.03 | 0.04 | 0.07 | 0.04 | 0.05 | 0.04 | 0.03 |
| translucent | 0.15 | 0.12 | 0.10 | 0.11 | 0.03 | 0.03 | 0.02 | 0.02 |
| **record** | **8.18** | **7.39** | **3.09** | **3.37** | **2.46** | **3.05** | **1.46** | **1.46** |

Ships and the HUD panel are 0.00 here: Stone Gulch has no ships and the harness has no panel.

What the profile showed before the work (gdb samples of the frame thread in `p384d` at view 24):
- The cull was 26 of 40 record samples, nearly all of it in the Swift runtime's slow paths for retain and release.
- `buildLandmarks` was 6 samples.
- The terrain draw lists were 4.
- Mob vertices were 2.

## Step 2: the draw list kept between frames

`SceneRenderer` keeps a cull table: one slot per column in reach. It is toroidal, so moving a chunk refills only the
columns that came into reach. Each slot holds:
- the column's facts (`ColInfo`);
- per section, the walk's vis bits and flags in two packed arrays;
- per section, the draw entries (`SecInfo`): its slab pair, vertex offset and quad counts, for the opaque, detail and
  translucent streams.

A column is re-read only when its chunk changed. Chunks note such changes in `CullNotes`:
- a section's mesh applied (`Chunk.cullStamp`)
- its blocks
- its detail level
- its shell state
- its tint table

So each frame reads only the noted chunks (0.4-0.7 columns a frame standing at Stone Gulch). It re-reads every
column only when a chunk was loaded or dropped (`World.chunksEpoch`), when the eye moved to another chunk, or when
the notes overflowed.

A frame's draw lists are then built from the visible sections' kept entries, sorted into their slab pairs. Nothing
reaches into a chunk, a section or a mesh buffer object.

Results:
- table 0.02-0.03 ms
- terrain draw lists 1.17 → 0.33 ms
- records 0.15 → 0.02 ms

`BS_FASTCULL=0` switches back to the old walk and draws; `BS_TABLEEPOCH=0` reads every column every frame.

## Step 3: mobs, townsfolk and repeated entity parts

The mobs' vertices (every mob, corpse and ragdoll, with townsfolk and soldiers among them) are now written on a
worker, while the frame thread culls and draws the terrain. They go into a vertex buffer of the slot's own and are
drawn when the frame reaches them (`WorldRenderer.startMobs` / `drawMobs`). The worker reads the mobs, the light and
the model tables; none of the passes before the mobs touch the mob writer's shared state.

`FrameWork` hands the work out. If the frame thread needs it before the worker has begun (on a busy CPU a queued
worker can start late), the frame thread takes it back and does it itself, so handing it out never costs more than
before. At view 24 that happened in 2 of 360 frames.

Result: mobs on the frame thread, 0.78 → 0.08 ms at view 24.

At view 8 the cull is short, so the frame thread waits for the worker to finish: mobs 0.81 → 0.54 ms there.

Instancing (one draw per model, transforms per instance) was not built. With the vertex writing off the frame
thread, at view 24 the mobs cost the frame thread 0.08 ms, the wait alone, so instancing has no record time left to
lower there. It would move the worker's own 0.7 ms onto a vertex shader that would have to carry the per-part
poses, bevels, ragdoll bones and per-vertex light. The entities stage (dropped items, decor, shadows, halos;
0.26-0.40 ms) has no repeated model that is a large part of it.

`BS_MOBTHREAD=0` writes the mobs in place, as before.

## Step 4: everything else over 0.5 ms in step 1

- **The walk (3.3 ms, and the 6.4 ms cull before it).** The cause was the Swift runtime. `Section.owner` was a
  `weak` reference, which gives every `Chunk` a side table, so every retain and release of a chunk took the slow
  path. That covered the walk's three retains a step, and also the tick's chunk lookups. It is now
  `unowned(unsafe)`, cleared by the chunk's `deinit`. On top of that, the walk now runs over the table:
  - plain arrays, no chunk objects;
  - its marks in memory of their own (`RawMarks`), so there are no exclusivity or uniqueness checks per access on the
    host build;
  - each section's frustum and fog test once a frame (up to 26 neighbours ask for the same one).

  Walk: 3.28 → 1.15 ms.
- **Horizon culling (0.82 ms).** Two changes:
  - A column's footprint (5 `atan2`s) was computed for every section; it is now computed once per column.
  - Pending occluders are kept sorted by distance, so a section applies only the prefix nearer than itself. It used
    to scan every pending one; the prefix is still applied in the order they were taken, so the result is the same.

  Horizon: 0.82 → 0.32 ms.
- **Occlusion culling (0.81 ms).** The occluder boxes need only the table, so they are drawn into the depth buffer
  on a worker while the walk runs (`BS_OCCPAR=0`: on the frame thread). The test runs over plain arrays.
  Occlusion: 0.81 → 0.36 ms.
- **Landmarks (0.52 ms).** While a camp's smoke rises, the landmark shell was rebuilt every second frame, horizon
  ground and all. The horizon ground was most of each build. Now only the landmarks and the smoke are rebuilt, over
  the last full build's ground; the ground itself is rebuilt every 36 frames, or once the eye moved or the far plane
  changed (`BS_LMSPLIT=0`: whole builds). Landmarks: 0.52 → 0.20 ms.
- **What is still over 0.5 ms: the walk itself, 0.9-1.2 ms at view 24.** That is the cave-culling walk through about
  4,750 sections (with P335's 26-neighbour peeks round partly open sections), about 200 ns a section, with no runtime
  overhead left in it. It would shrink with fewer sections to walk, such as culling the cave sections under the
  surface (P384's finding: 1,035 of the 1,626 sections drawn past 182 blocks are caves).

## Step 5: no popping or late sections

`questcheck --view OUT.png --turnshots 24` renders a steady 360 degree head turn as a shot sequence: one renderer for
the whole turn, as in play, turning 15 degrees a frame from P381's spot over Stone Gulch (6080, 190, 700, facing 123
degrees, 15 down). It ran once with every P385 change off and once with all of them on, and each frame was compared:
- Every one of the 24 frames has the same visible sections and the same draw count in both runs.
- The quad counts differ by 0-5 quads.
- The pixels differ in at most 4 of 565,248 per frame.

Both of those differences are mobs: in --view mode the mobs spawn differently from run to run. A second off run
differs from the first off run in exactly the same pixels, and is pixel-identical to the on run.

Shots, too big for the repo, are in `/mnt/project-files/p385-shots/`:
- `turn-kkk-off-top-on-bottom.jpg`: both eyes, before above, after below.
- `turn-kkk-diff-over8.png`: white where the two differ by more than 8 of 255.
- `turn-off.txt` / `turn-on.txt`: per frame sections, draws, quads and record ms.

## Step 6: target

Host record at view 24 is 2.6-3.4 ms against the 3.5 ms target, standing and turning. Before it was 9.4-10.5 ms
(`p384d`), or 7.4-8.2 ms (this binary with P385 off).

## Switches (all default on)

| switch | what off does |
|---|---|
| `BS_FASTCULL=0` | the old cull walk and draws |
| `BS_TABLEEPOCH=0` | every column looked up every frame |
| `BS_OCCPAR=0` | occluder raster on the frame thread |
| `BS_MOBTHREAD=0` | mob vertices on the frame thread |
| `BS_LMSPLIT=0` | whole landmark builds |

New harness flags:
- `--turnframes N` (perfscenes): the turn phase.
- `--turnshots N` (--view): the turn as a shot sequence.

The stage line also gives:
- the table's re-read columns a frame;
- the occluder raster's own time;
- how often each worker's work was taken back.
