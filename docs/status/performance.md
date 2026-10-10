# Blocksmith performance: what costs what (plain English)

Updated 2026-10-10 (task 25b2; Oct 10 playtest render-distance section below). Device numbers are from Remington's Oct 9 headset logs (`perf:` lines, 82 minutes);
the "after" numbers are from the Mac Quest proxy (`tools/bench_routes.sh --quest`: the six routes, two eye views at the
Quest's 1440x1584 each frame, 72 Hz ticks). The proxy runs on an M1, which is roughly 2-3x faster per core than the
Quest 3, so a 4 ms spike on the Mac is about a whole frame on the headset.

## The budget

At 72 Hz the headset gives every frame 13.9 ms. Two things must each fit in it, side by side:
- **CPU** (the game itself): the game tick (mobs, water, crops, physics, AI) plus *recording* the frame (telling the
  GPU what to draw). Device, render distance 9-12, before this pass: tick 3.1-3.6 ms + record 5-6 ms = 9-10 ms.
- **GPU** (drawing pixels for both eyes): device 6-8 ms at render distance 9-12, 8.8 ms at 14.

A single slow frame (a "hitch", over 25 ms) is felt in VR as a stutter even when the average is fine, so spikes
matter as much as averages.

## What costs compute

| Feature | What it costs | Why |
|---|---|---|
| **Render distance** | GPU and CPU, grows with the area (distance squared) | 12 -> 16 is 1.8x the chunks. Every visible 16x16x16 section is 1-3 draw calls (solid, cut-out like leaves, water) and its triangles. Device: 158 sections / 71k quads at 8, 507 / 195k at 14, 1669 / 541k at 23 |
| **Far detail (LOD)** | saves GPU | Chunks past the LOD line are meshed simpler: merged faces, no grass/flowers, "fast" leaves. Now from 5 chunks out on Quest (was 8) |
| **Mobs** | CPU, per mob per frame and per tick | Each drawn mob is rebuilt from boxes every frame on the CPU (no GPU skinning), and each mob thinks every tick. 200+ loaded mobs pushed the device CPU to 15-17 ms |
| **Mob path finding** | CPU spikes | A villager searching up to 1500 cells for a route took 4-7 ms in one go |
| **Water and lava** | CPU spikes | Every flowing cell is re-checked 4 times a second; newly loaded chunks queue their springs |
| **Crops, grass spread, snow, falling sand** | CPU | Random block ticks; each changed block has to be re-meshed |
| **Chunk generation and meshing** | background CPU (worker threads) | Off the frame thread; only the hand-over to the game is on the frame (budget 4 ms a frame) |
| **Autosave** | CPU spike every 60 s | Encoding mobs and items as JSON. Now on a background queue |
| **HUD and menus** | small | Rebuilt every frame, but measured at 0.04 ms on the M1 |
| **Citadels (Capital bases)** | occasional CPU spike | The base AI ticks once a second near a citadel; one 19 ms tick seen on the forest route (left to the military-base project) |

## What costs memory

The headset has plenty of room: resident memory was 341-628 MB (store gate: 3 GB).
- **Chunks**: block arrays, light and heightmaps, about 0.3-0.5 MB per loaded chunk column. Grows with render
  distance squared (rd 16 loads about 900 columns).
- **Meshes** (the triangles on the GPU): 76-104 MB of mesh slabs in the device logs. Far detail makes far meshes smaller.
- **Textures**: the block/item texture array (High 128 px or Medium 64 px in the Quest options).
- No leak found: resident memory on the routes grows 6-15% in the first 30-45 s while the world fills in, then holds.

## What changed in this pass (task 25b2)

1. **Water ticks** (all platforms). The waiting-cells list was a hash set, and taking each batch of 1024 cells out of it
   cost 2-5 ms by itself (more than the Quest's 2 ms water budget). It is now a queue. Mac proxy, rd 16: water tick
   spikes over 4 ms, plains 97 -> 0, cave 104 -> 1; tick p99 7.3 -> 2.5 ms and 6.7 -> 2.4 ms.
2. **Mob path finding and village scans** (all platforms). Path searches now pause when the tick's 1.5 ms path budget runs
   out and carry on next tick; the villager bell/bed/job-site searches read blocks chunk by chunk instead of one lookup
   per cell (the bell search was 7-14 ms); lookup tables are built when a world loads instead of mid-play. Mobs-stage
   spikes over 4 ms: village 12 -> 0, forest 1 -> 0, capital 4 -> 0.
3. **Mob drawing on Quest**. The headset rebuilt every loaded mob every frame, even those behind you or past the fog
   (the Mac already skipped them). Now it skips the same ones as the Mac.
4. **Far detail from 5 chunks** on Quest: 17-23% fewer terrain quads at rd 16; screenshots at 80+ blocks differ in
   0.00-0.01% of pixels.
5. **Render distance 16 by default** on Quest (was 12, originally 8). Saved distances under 16 are raised once. Auto Render
   Distance steps it down while the headset misses frames and back up when it has headroom (see the Oct 10 section).
6. **Better device numbers next time**: the `perf:` line now ends with `record ms: cull, hud, terrain, ships, mobs,
   entities, rest`, so the 5-6 ms of frame recording can be split on the headset (no Mac proxy exists for it).

Quest proxy gate at render distance 16 (`tools/quest_perf_gate.sh --rd 16`, Mac shared with other work): frame p99
8.4-12.8 ms on all six routes (budget 13.9). Hitches left: about 1-5 a minute on some runs, varying run to run, from
background load on the shared Mac (encode/GPU side, not the game tick) and the citadel tick.

## Oct 10 playtest: render distance drifting down (16 -> 15 -> 14 -> 13)

What Remington saw (build 0.95, 72 Hz, voice notes 09:23:10 and 09:25:54): the distance stepped down while he flew and
never came back, and fps dipped to 53-66 over the taiga and its village.

**Why it only ever went down.** The comfort guard was one-way: one 5 s window with more than 5% missed frames and the
CPU or GPU near the budget took a step off "for this session", and nothing ever put it back. It also counted windows
spent streaming in new terrain: he was flying at about 60 blocks a second (fast flight), generating 150+ chunks a
second, so every few windows looked like a miss. On top of that the save stored the stepped-down distance (the world
meta wrote the world's current distance), so a world reopened in another dimension came back lowered.

**What it does now** (`Sources/RenderDistanceGovernor.swift`, a pure type fed one window of frame stats at a time):
- Down: only two missed windows in a row (10 s), and never for a window with a chunk-loading burst (over 40 chunks a
  second), a menu or pause, a save or a dimension change. Refresh rate first (above 72 Hz), then one step at a time,
  not below 4.
- Up: once frames have headroom (no misses, and the busier of CPU and GPU, scaled up by the next step's extra area,
  still under 70% of the budget) for 20 s, one step back up, with a toast ("Render distance back to 16"). Never above
  the player's setting.
- No see-saw: the raise test (70% after scaling) sits well below the drop test (80%), every step waits 10 s, and a
  drop within a minute of a raise doubles the wait before the next try (20, 40, 80, 160, 300 s). Five quiet minutes
  back at the chosen distance reset it.
- Only the player's choice is saved (`Game.chosenRenderDistance`): the save, the options and the pause menu row
  ("Render Distance: 16 (auto 13 now)") all use it; picking a distance resets the controller.
- Tested on synthetic frame-time traces (`Blocksmith --snapshot x.png --rdgovernortest`, snap.sh checks shard,
  QuestSim): a heavy minute takes 16 down to 13 and normal play brings it back to 16 in about a minute, with one
  direction change; single bad windows, loading bursts and menus never lower it; an edge scene retries at growing gaps
  (30, 90, 190, 370, 690, 1010 s) and misses frames in under 10% of windows; the save keeps 16 while the world runs at 13.

**What actually cost the frames** (Mac Quest proxy, rd 16, new `taiga` and `flyover` bench routes on the playtest seed):
- The taiga is GPU-bound, not tick-bound: 512k terrain quads and 921 draws a frame, against 63k on the plains village
  route. Leaves are about two thirds of the far quads and half the near ones (spruce canopies, alpha-tested). The game
  tick is small there (mean 0.8-1.0 ms CPU on the M1; mobs 0.2 ms).
- Fast flight adds streaming on the frame thread: installing generated chunks and meshes (up to a 4 ms budget a frame),
  the unload / detail-level pass at every chunk crossing, and the scheduling scan.

**Permanent fixes (all platforms' meshing; Quest settings in QuestApp):**
1. "Fast" leaves from 3 chunks out on Quest (`World.leafNear = 2`): no faces between leaf blocks, as far detail already
   did from 5 chunks. Taiga route: 512k -> 460k quads (-10%), 921 -> 854 draws (-7%). Screenshots at the two playtest
   spots differ in 0.00% and 0.03% of pixels. Only sections that actually have faces between leaves are remeshed when a
   chunk crosses that ring (`Section.leafy`), which keeps the extra meshing on the workers to about +12% while flying.
2. Far canopies: solid faces against leaves (trunks, ground inside the canopy) are dropped and far leaf light comes in
   steps of 4 so neighbouring faces merge (part of the quad cut above).
3. Frame-thread hand-over of streamed chunks capped at 1.5 ms a frame on Quest (`World.handoverSeconds`, was 4 ms):
   still about 108 ms of installs a second, several times what fast flight produces, so pop-in does not grow (drawn
   disc not meshed: 0.5-1.3% before, 0.6-1.0% after, flyover route).
4. The device `perf:` line's "slowest tick" now names `world.results`, `world.unload+lod` or `world.update` (the scan)
   separately, so the next headset log says which part of streaming a hitch was.

Before/after, Mac Quest proxy at rd 16, 30 s a route, back to back (before = 704dee11 for the six routes; for taiga
and flyover the same build with `--leafnear 99 --handover 4` and `BS_FARLEAF=0`, which restore the old meshing and
budget). The Mac was shared with 2-3 other helpers' builds (load average 9-27), so wall-clock frame times moved by
±30% run to run and are not shown; the counted work is stable:

| route | quads before -> after | draws before -> after | tick CPU p99 (thread clock) |
|---|---|---|---|
| taiga (village, playtest seed) | 512k -> 460k (-10%) | 921 -> 854 | 2.6-4.0 -> 3.1-3.6 ms (no change) |
| flyover (fast flight, 50 up) | 348k -> 321k (-8%) | 707 -> 680 | 4.0-5.2 -> 3.5-5.0 ms |
| forest | 193k -> 157k (-19%) | 827 -> 807 | |
| capital | 167k -> 146k (-13%) | 681 -> 675 | |
| plains, village, cave, ashvault | unchanged (95k, 63k, 30k, 65k) | unchanged | |

Gate: `tools/quest_perf_gate.sh [--routes "village taiga flyover"]` runs the controller test, the six routes'
frame p99 / hitch budgets and counted-work budgets for taiga (quads <= 500k, tick CPU p99 <= 4.5 ms) and flyover
(quads <= 360k, tick CPU p99 <= 6 ms, <= 30% of the drawn disc not meshed).

What the proxy can't settle: whether the headset's taiga frames were GPU- or CPU-bound. The proxy says GPU (terrain
quads); the next `perf:` log at rd 16 over a taiga says it directly (gpu vs cpu ms). If it is still GPU-bound there,
the next lever is drawing far leaves as opaque blocks (no alpha test, which tile GPUs pay for), a texture-side change.


## Still to measure on the headset

- A 72 Hz session at rd 16: `adb logcat -s Blocksmith | grep perf:` (or `tools/quest_perf_log.py` on the pulled log).
  Good: `missed 0-2`, cpu under ~11 ms, gpu under ~11 ms. If the guard keeps stepping down, the `record ms:` split
  says which part of recording to cut next (likely candidates: terrain draw calls, then entities).
- The old logs had one 40-150 ms tick in nearly every 5 s window; the `slowest tick N ms: <stage>` field (added Oct 9)
  names it. The fixes since (deferred remeshing of random-tick edits, background autosave, water queue, path budget)
  cover the candidates found on the proxy.
- Thermal soak (30 min) and a 200+ mob scene.
