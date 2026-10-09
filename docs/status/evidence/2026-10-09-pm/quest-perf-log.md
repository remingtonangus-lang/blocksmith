# Quest performance: Oct 9 PM playtest device logs (item 11)

Sources: `docs/playtests/2026-10-09-pm/blocksmith.prev.log` (build 310d4a1, 36 min of play) and `blocksmith.log`
(build 4d304de, 46 min): 990 `perf:` windows of 5 s, about 82 minutes in total. Summarized with
`python3 tools/quest_perf_log.py blocksmith.prev.log blocksmith.log [--windows]`.

## What the logs say

**Refresh rate.** The app asked for 90 Hz every session (`QuestSettings.refreshRate` defaulted to 90; the runtime offers
72/80/90/120). The store gate is 72 fps.

**Render distance in use.** The comfort guard (Auto Render Distance) kept stepping the distance down because the CPU
average sat above 80% of the 90 Hz budget (8.9 ms):
- prev log: world loaded at 16 -> guard to 15; second world loaded at 12 -> guard 11, 10, 9; Remington raised it to 24
  -> guard 23, 22, then back down through 9 ... 5.
- current log: the world reopened at **5** (the guard's step-downs were saved into the world file and `Game.apply`
  restored them over the headset setting), Remington raised it to 16 -> guard 15 ... 9.
- Time spent: 47.6 min at 9, 9.2 min at 8, 7.1 min at 10, 1.2 min at 12, 5.3 min at 14-15, 4.3 min at 5-7 (5.2 min labelled 22 ran with ~110 sections: a menu change after a guard step,
  not logged then, so that label is unreliable).

**Frame rate.** Median 81 fps at 90 Hz at every distance from 6 to 12 (p10 77-81). 951 of 990 windows were at or
above 72 fps; the 39 below were pause/resume windows and windows with more than 200 mobs (CPU 15-17 ms, 58-64 fps).

| rd | min | fps p50/p10 | missed/min | >25 ms windows/min | CPU p50/p90 | tick | record | GPU p50/p90 | sections | quads | mobs p50/max |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 9.2 | 81.0/80.6 | 224 | 12.0 | 8.4/9.4 | 3.2 | 5.0 | 5.7/6.5 | 158 | 71k | 81/116 |
| 9 | 47.6 | 80.8/77.7 | 231 | 11.8 | 10.0/11.6 | 3.6 | 6.0 | 6.4/8.1 | 302 | 95k | 109/265 |
| 10 | 7.1 | 81.0/79.8 | 219 | 12.0 | 9.0/9.6 | 3.3 | 5.3 | 5.7/7.6 | 229 | 83k | 95/131 |
| 12 | 1.2 | 81.1/78.8 | 232 | 12.0 | 9.2/11.6 | 3.1 | 5.7 | 7.6/8.8 | 339 | 135k | 117/171 |
| 14 | 3.9 | 77.8/74.3 | 164 | 11.7 | 12.7/13.1 | 4.4 | 8.0 | 8.8/9.5 | 507 | 195k | 212/223 |
| 23 | 0.2 | 52.4/49.2 | 1800 | 12.0 | 17.5/18.2 | 5.6 | 11.9 | 15.3/18.4 | 1669 | 541k | 279/284 |

**Missed frames and hitches.** ~220-240 missed frames a minute at every distance from 6 to 12: the losses do not scale
with distance, so they are not the GPU. 975 of the 990 windows held a frame over 25 ms (11.8 a minute), and in 961 of
them the worst frame was the **game tick** (world streaming inside it: ~0 ms; GPU never the cause):
- 889 windows: a 40-150 ms tick (typically 55-70 ms) in every 5 s window, at 30 mobs and 158 chunks as at 250 mobs.
- 72 windows: a 180-220 ms tick about every 65 s: the 60 s autosave (`Game.saveNow` JSON-encoding mobs, drops, orbs and
  the meta on the frame thread).

**Where the frame goes at rd 9-12.** CPU 9-10 ms (tick 3.1-3.6, command recording 5-6 ms, recording grows with the
section count), GPU 6-8 ms. That does not fit 90 Hz (11.1 ms) with any spike, but fits 72 Hz (13.9 ms): CPU p90 11.6.
At 14-15 the CPU is 12.7-12.8 ms p50: too close to 13.9.

**Mobs.** Median 110, max 284 loaded. The 89 windows above 200 mobs ran CPU 15-17 ms (tick up to 7 ms); surface
density is being halved separately (playtest item 4).

**Memory and loading.** Resident 341-628 MB (peak at rd 23), mesh slabs 76-104 MB: far under the 3 GB gate. Launch:
textures painted 1.44 s + cached 0.45 s, world ready 3.7-4.7 s after launch, 1.1-2.0 s for a world switch; the first
frame after a switch took 72 ms (tick 49). One `SceneRenderer: scratch ring full (11.5 MB)` line.

**Correlation with play.** The perf lines carry no player state, so horse riding cannot be singled out; the bad windows
follow mob count (> 200) and the autosave minute, not chunk jobs (jobs are 0 in most windows) or render distance.

## Causes found on the Mac proxy (`--quest` bench, tick stages from the new TickProf)

- **Random ticks, snow, falling blocks, mobs: synchronous remeshing.** `World.setBlock` meshed up to eight sections on
  the frame thread for every grass spread, crop, snow layer, sheep eating grass or falling block. On the M1 the
  random-tick stage spiked to 330-470 ms on three routes (rd 8). Now `Game.advance` sets `World.deferRemesh` and those
  edits remesh on the workers a frame or two later; the player's own edits stay synchronous.
- **Autosave:** mobs, drops, orbs and the meta are encoded and written on the save queue (`SaveIO.writeJSON`) from value
  snapshots; quit/pause saves stay synchronous; `loadMeta` flushes the queue first.
- **Fluid ticks:** up to 1024 cells per tick (streamed-in chunks queue up to 96 springs each), and each tick copied the
  whole pending set. The copy is gone and the Quest (and the `--quest` bench) stops a fluid tick after 2 ms
  (`World.fluidSeconds`); the Mac keeps whole batches.
- **90 Hz:** the comfort guard now drops 90 -> 72 Hz first, and only then steps the render distance down.
- **Render distance leak:** the Quest uses its own setting after `Game.apply`; a saved distance under 12 is raised once;
  the pause menu steps from a guard value to the next option instead of wrapping to 4.

## Bench (Mac proxy, `tools/bench_routes.sh --quest`, two eyes at 1440x1584, 30 s a route)

The Mac was shared with four other agents' builds the whole time, so single hitches are noise; the A/B pairs ran
back to back on the same binary (old behaviour switched on by a temporary flag).

Frame p99 ms / hitches > 25 ms per minute / tick p99 ms. "Before" = synchronous remeshing, whole fluid batches,
autosave on the frame thread (the A/B flag); "after" = this change (fluid copy fix in the last two columns only).

| route | rd 8 before | rd 8 after (run 1) | rd 8 after (run 2) | rd 12 before | rd 12 after (30 s) | rd 12 after (60 s, gate) |
|---|---|---|---|---|---|---|
| plains | 23.4 / 40 / 15.3 | 7.8 / 2 / 3.1 | 8.6 / 2 / 5.5 | 15.3 / 14 / 11.3 | 11.3 / 2 | 9.7 / 1 |
| forest | 14.3 / 6 / 5.4 | 9.6 / 0 / 2.8 | 15.8 / 22 / 5.2 | 12.7 / 4 / 2.6 | 10.8 / 0 | 10.8 / 3 |
| village | 20.0 / 32 / 10.2 | 8.9 / 0 / 4.7 | 9.4 / 2 / 4.0 | 10.5 / 8 / 6.2 | 10.8 / 2 | 11.1 / 1 |
| cave | 35.8 / 74 / 21.9 | 10.2 / 0 / 7.8 | 12.3 / 12 / 7.9 | 14.7 / 12 / 11.6 | 8.6 / 0 | 8.9 / 0 |
| capital | 40.4 / 144 / 23.1 | 9.1 / 0 / 2.5 | 10.0 / 6 / 3.5 | 16.5 / 18 / 7.1 | 10.2 / 0 | 10.2 / 0 |
| ashvault | 16.6 / 18 / 6.1 | 11.2 / 0 / 3.0 | 14.0 / 12 / 3.6 | 14.4 / 20 / 6.2 | 11.7 / 0 | 11.1 / 0 |

Tick p99 drops 2-9x on every route that had a world-edit spike; the remaining hitches in "run 2" have small ticks
(p99 3.5-7.9 ms), so they sit in the render/GPU side of the proxy while the other agents' compiles ran. Largest tick
stages left (rd 12, 60 s): water 10-15 ms (plains, cave), mobs up to 27-31 ms (village, forest: one frame each), a
`bases` (capital citadels) second-tick of 12 ms. Mac (not --quest) rd 8 after: 6/6 PASS, p99 5.5-10.6 ms, 0 hitches
(scorecard before: 3/6). `./smoke.sh 40 8`: PASS.

## Regression check

`tools/quest_perf_gate.sh [--secs N] [--rd N]` (about 7 min; run it on a quiet Mac): the six routes in `--quest` mode
at the Quest default render distance read from `QuestSettings.swift`; exit 1 when a route's frame p99 is over 13.9 ms or
it has more than one hitch over 25 ms a minute. It also prints each route's tick spikes by stage.

## Still needs the device

- A 72 Hz session at rd 12: the new perf line ends with `slowest tick N ms: <stage> N ms`, and `perf: render distance N`
  lines mark every change, so `tools/quest_perf_log.py` splits by distance and names any remaining tick spike.
- Command recording (5-6 ms CPU at rd 9-12, 8 ms at 14) is Vulkan-side and has no Mac proxy.
- Thermal soak (30 min at 72 fps) and 200+ mob scenes after the density cut.
