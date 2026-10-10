# Blocksmith performance: what costs what (plain English)

Updated 2026-10-10 (task 25b2). Device numbers are from Remington's Oct 9 headset logs (`perf:` lines, 82 minutes);
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
   Distance still steps it down for the session if the headset misses frames.
6. **Better device numbers next time**: the `perf:` line now ends with `record ms: cull, hud, terrain, ships, mobs,
   entities, rest`, so the 5-6 ms of frame recording can be split on the headset (no Mac proxy exists for it).

Quest proxy gate at render distance 16 (`tools/quest_perf_gate.sh --rd 16`, Mac shared with other work): frame p99
8.4-12.8 ms on all six routes (budget 13.9). Hitches left: about 1-5 a minute on some runs, varying run to run, from
background load on the shared Mac (encode/GPU side, not the game tick) and the citadel tick.

## Still to measure on the headset

- A 72 Hz session at rd 16: `adb logcat -s Blocksmith | grep perf:` (or `tools/quest_perf_log.py` on the pulled log).
  Good: `missed 0-2`, cpu under ~11 ms, gpu under ~11 ms. If the guard keeps stepping down, the `record ms:` split
  says which part of recording to cut next (likely candidates: terrain draw calls, then entities).
- The old logs had one 40-150 ms tick in nearly every 5 s window; the `slowest tick N ms: <stage>` field (added Oct 9)
  names it. The fixes since (deferred remeshing of random-tick edits, background autosave, water queue, path budget)
  cover the candidates found on the proxy.
- Thermal soak (30 min) and a 200+ mob scene.
