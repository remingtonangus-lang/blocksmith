# Blocksmith CI snapshots (heavy lane)

Commit `a40f53025679bc5b996f1a3aa826ad8621d89247` on `claude/project-thread-kw71v5`: build **success**, heavy jobs **failure**
- checks: failure
- perf: success
- play: failure
- shots: failure
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38092326574

```
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 171 MB
memory: resident 227 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1730 layers at 128 px, BC3, 36.1 MB with mips (build 907 ms, upload 359 ms)
target: spruce_planks at 959 139 274, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(959.5, 138.0, 272.5)
light probe: eye sky 15 block 1 in air; floor+1 (y 69) sky 15 block 5 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 318 ms  mesh(all, parallel) 396 ms  mesh(1 section) 1.46 ms  quads 754189 opaque / 417 water
frame (encode+GPU, offscreen, median of 30) 6.19 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 249 MB  (section meshes 23 MB)
wrote snaps/agent_door_777.png
naming audit: 6759 names, 0 flagged
selftest: 1208 blocks, 104 mob kinds, 4/4 special recipes, bundle fill 32/64, 91 advancements
selftest ok: 102 mobs after 3 s
textures: 1730 layers at 128 px, BC3, 36.1 MB with mips (build 924 ms, upload 417 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0008 white=0.0063 std=55.5 hash=bbd1505a1676c795
imagecheck selftest.png magenta=0.00000 black=0.0008 white=0.0063 std=55.5 hash=bbd1505a1676c795
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 378 ms  mesh(all, parallel) 311 ms  mesh(1 section) 0.57 ms  quads 800253 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 6.31 ms  biome plains
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 183 MB
memory: resident 259 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (35 pieces, framed)
textures: 1730 layers at 128 px, BC3, 36.1 MB with mips (build 865 ms, upload 382 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=58.9 hash=c7d5ed794e5ea41e flicker=0.00016
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=58.9 hash=c7d5ed794e5ea41e flicker=0.00016
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 451 ms  mesh(all, parallel) 615 ms  mesh(1 section) 0.87 ms  quads 1644500 opaque / 70 water
frame (encode+GPU, offscreen, median of 30) 8.15 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 38 MB), Metal allocated 207 MB
memory: resident 287 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1730 layers at 128 px, BC3, 36.1 MB with mips (build 805 ms, upload 366 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 379 ms  mesh(all, parallel) 379 ms  mesh(1 section) 1.68 ms  quads 1169814 opaque / 73 water
frame (encode+GPU, offscreen, median of 30) 7.95 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 30 MB), Metal allocated 179 MB
memory: resident 243 MB  (section meshes 36 MB)
wrote snaps/flicker_forest.png
textures: 1730 layers at 128 px, BC3, 36.1 MB with mips (build 899 ms, upload 372 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 514 ms  mesh(all, parallel) 476 ms  mesh(1 section) 0.93 ms  quads 800454 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 8.22 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 167 MB
memory: resident 231 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 202 frames, no flags
snap.sh: 1 failing line(s): 424
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.20 ms (min 2.01, max 3.32) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 2.94 ms/chunk
bench gen slow chunk -80,-25: 6.3 ms (plants 4.3, caves 0.9, ores 0.3; starts 0.0, place 0.3)
bench gen slow chunk -59,14: 5.2 ms (caves 0.7, ores 0.3, columns 0.2; starts 0.0, place 3.6)
bench gen slow chunk 60,-15: 3.1 ms (caves 2.0, stone 0.3, columns 0.2; starts 0.0, place 0.2)
bench gen phases (ms/chunk): columns 0.25, stone 0.19, surface 0.04, caves 0.93, ores 0.23, trees 0.05, plants 0.31, starts 0.01, structures 0.19
bench gen structure starts (ms over 24 chunks): capital_city 53.7, wild_camp 45.8, military_base 43.6, boreal_station 40.7, village 18.6, temple 6.6, mansion 5.9, pillager_outpost 2.3
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 2.28 ms/chunk (p95 5.17, max 6.32) single-thread | 856 chunks/s parallel
bench: gen took 0.8 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 4.86 ms/chunk (24 sections, 81 non-empty), section mean 203 us p95 824 us max 1453 us, 4942 quads/chunk
bench mesh_lod1: 4.81 ms/chunk (24 sections, 81 non-empty), section mean 200 us p95 842 us max 1179 us, 2498 quads/chunk
bench: mesh took 0.7 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 15 ms, first load (r 4) 225 ms, renderer 1819 ms (textures 590 ms, shaders 0 ms), fill rd 12 4.42 s
bench: startup took 8.3 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 0.88 ms, GPU p50 3.52 ms (max 7.35), 258 chunks drawn
bench frame 1080p rd 16: encode p50 0.88 ms, GPU p50 4.09 ms (max 5.06), 270 chunks drawn
bench frame 4k rd 16: encode p50 0.84 ms, GPU p50 6.75 ms (max 7.03), 270 chunks drawn
bench frame: 697 visible sections, 1216 draw calls, 235k quads
bench: frame took 4.7 s (live worlds 0, games 0)
bench: edit starts
bench edit: break mean 0.81 ms max 1.83 ms, place mean 0.81 ms max 1.88 ms (synchronous remesh)
bench: edit took 0.9 s (live worlds 0, games 0)
bench: mobs starts
bench mobs: tick 0.20 ms empty, 0.48 ms with 150 mobs (p95 1.37, max 2.97), 156 alive
bench: mobs took 0.8 s (live worlds 0, games 0)
bench: save starts
bench save: 145 chunks, save 1.69 ms/chunk (main thread 3.1 ms total, unchanged re-save 1.7 ms), load 0.48 ms/chunk (145 ok), 6.2 KB/chunk
bench: save took 1.0 s (live worlds 0, games 0)
bench: tnt starts
bench tnt: blast mean 0.93 ms max 1.60 ms (main thread) | re-mesh done in 0.06 s, tick p95 1.09 max 1.09 ms
bench: tnt took 0.8 s (live worlds 0, games 0)
bench: fluids starts
bench fluids: tick p50 0.25 p95 1.41 max 5.23 ms, 6581 sections re-meshed in 6 s, 1166 cells still pending
bench: fluids took 6.9 s (live worlds 0, games 0)
bench: ships starts
bench ships: edit remesh 3.67 ms, blast 1.91 ms + remesh 5.47 ms (3035 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.96 ms encode, 0.41 ms GPU (66 draw calls)
bench ships: docked 3075 blocks in 11.15 ms (world remesh 0.09 s), assembled 3055 in 17.18 ms
bench ships: frigate 3035 blocks spawn 2.10 ms, mesh 2.23 ms; tick 0.33 ms (p95 0.86), physics 0.15 ms; collide 9.35 us near ships, 0.23 us far; 13 ships
bench: ships took 2.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.23 p95 2.90 p99 5.64 max 16.65 ms, 0 hitches >25 ms | tick p95 1.12 (update p95 0.47, max 3.82) encode p95 0.93 GPU p95 2.80 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.2 ms each on a worker) mesh 957 sections/s (250 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 25 MB, meshes 24 MB (slabs 40 MB), resident peak 202 MB, preload 527 ms
bench: flight8 took 14.6 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 3.39 p95 6.74 p99 13.46 max 46.14 ms, 2 hitches >25 ms | tick p95 2.16 (update p95 0.99, max 17.62) encode p95 2.15 GPU p95 5.97 ms
bench flight16: coverage min 74% mean 86% | gen 43 chunks/s (2.5 ms each on a worker) mesh 3247 sections/s (277 us each) | realtime 1.00x
bench flight16: 1052 chunks, chunk data 86 MB, meshes 46 MB (slabs 68 MB), resident peak 342 MB, preload 1908 ms
bench: flight16 took 16.1 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 4.06 p95 5.84 p99 8.67 max 31.79 ms, 1 hitches >25 ms | tick p95 2.01 (update p95 0.85, max 2.44) encode p95 2.86 GPU p95 5.55 ms
bench flight24: coverage min 73% mean 83% | gen 24 chunks/s (2.1 ms each on a worker) mesh 3393 sections/s (287 us each) | realtime 1.00x
bench flight24: 1700 chunks, chunk data 145 MB, meshes 67 MB (slabs 96 MB), resident peak 492 MB, preload 3876 ms
bench: flight24 took 18.0 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.831 | 3.05x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.812 | 1.82x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.706 | 1.19x |
| edit.place_ms_max | 0.732 | 1.883 | 2.57x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.813 | 1.79x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.708 | 1.19x |
| flight16.arena_free_mb | 0.864 | 15.005 | 17.37x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.858 | 1.16x |
| flight16.coverage_min | 0.962 | 0.744 | 1.29x |
| flight16.cull_ms_p50 | 0.708 | 0.337 | 0.48x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.989 | 0.86x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.834 | 0.56x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.154 | 0.91x |
| flight16.frame_ms_max | 12.652 | 46.143 | 3.65x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.394 | 0.71x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 6.743 | 1.16x |
| flight16.frame_ms_p99 | 7.443 | 13.458 | 1.81x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.181 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.376 | 0.70x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 5.969 | 1.05x |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.168 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3247.38 | 0.61x ✅ better |
| flight16.preload_ms | 1871.23 | 1908.16 | 1.02x |
| flight16.realtime | 0.998 | 0.998 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 342.034 | 1.20x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 17.873 | 2.09x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.641 | 1.65x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.155 | 1.04x |
| flight16.update_ms_max | 8.289 | 17.62 | 2.13x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.278 | 16.35x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.995 | 0.57x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.486 | 1.23x |
| flight16.worker_mesh_us | 177.949 | 276.735 | 1.56x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 20.134 | 47.15x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 145.299 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1700 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.831 | 1.20x |
| flight24.coverage_min | 0.974 | 0.732 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.665 | 0.56x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.486 | 0.54x ✅ better |
| flight24.cull_walked_sections | 7607 | 3931 | 0.52x ✅ better |
| flight24.draw_calls | 3175 | 1187 | 0.37x ✅ better |
| flight24.drawn_kquads | 821.704 | 220.274 | 0.27x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.324 | 0.54x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.861 | 0.55x ✅ better |
| flight24.frame_ms_max | 13.319 | 31.791 | 2.39x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.062 | 0.53x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.84 | 0.62x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 8.668 | 0.84x |
| flight24.gen_chunks_per_s | 63.73 | 24.047 | 2.65x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.032 | 0.52x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.546 | 0.59x ✅ better |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 67.183 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3393.48 | 0.72x ✅ better |
| flight24.preload_ms | 4742.83 | 3875.79 | 0.82x |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 491.847 | 0.96x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 29.946 | 2.58x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.624 | 1.56x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.009 | 0.68x ✅ better |
| flight24.update_ms_max | 4.586 | 2.44 | 0.53x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.293 | 19.53x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.853 | 0.34x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.074 | 0.88x |
| flight24.worker_mesh_us | 177.947 | 286.742 | 1.61x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.906 | 4.47x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.992 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.078 | 0.38x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.182 | 0.60x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.387 | 0.69x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.931 | 1.12x |
| flight8.frame_ms_max | 13.232 | 16.647 | 1.26x |
| flight8.frame_ms_p50 | 2.588 | 2.228 | 0.86x |
| flight8.frame_ms_p95 | 3.197 | 2.899 | 0.91x |
| flight8.frame_ms_p99 | 4.401 | 5.638 | 1.28x |
| flight8.gen_chunks_per_s | 23.603 | 23.681 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.217 | 0.86x |
| flight8.gpu_ms_p95 | 3.081 | 2.798 | 0.91x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 956.784 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 526.531 | 0.38x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 201.939 | 1.62x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 16.291 | 1.30x |
| flight8.tick_ms_p50 | 0.158 | 0.355 | 2.25x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.125 | 0.92x |
| flight8.update_ms_max | 12.421 | 3.816 | 0.31x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.006 | 0.60x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.468 | 0.54x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.152 | 0.67x ✅ better |
| flight8.worker_mesh_us | 181.115 | 249.572 | 1.38x ⚠️ worse |
| fluids.pending | 240 | 1166 | 4.86x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6581 | 2.53x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.226 | 1.53x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.247 | 1.09x |
| fluids.tick_ms_p95 | 1.872 | 1.412 | 0.75x ✅ better |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 1.878 | 1.67x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.876 | 1.40x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.065 | 1.92x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.091 | 1.77x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 0.966 | 0.60x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.842 | 1.22x |
| frame_4k.gpu_ms_max | 4.083 | 7.035 | 1.72x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.751 | 1.92x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.822 | 2.41x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.881 | 1.45x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 7.353 | 3.06x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.523 | 1.70x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 6.321 | 1.87x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.284 | 1.10x |
| gen.chunk_ms_p95 | 3.325 | 5.172 | 1.56x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 855.919 | 1.97x ⚠️ worse |
| gen.starts_cold_ms | – | 2.937 | new |
| gen.terrain_hash | 1238443285367868 | 849284524592011 | ⚠️ changed |
| genphase.caves_ms | – | 0.929 | new |
| genphase.columns_ms | – | 0.252 | new |
| genphase.ores_ms | – | 0.225 | new |
| genphase.plants_ms | – | 0.307 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.191 | new |
| genphase.structures_ms | – | 0.194 | new |
| genphase.surface_ms | – | 0.038 | new |
| genphase.trees_ms | – | 0.052 | new |
| mesh.chunk_ms_max | 5.758 | 6.416 | 1.11x |
| mesh.chunk_ms_mean | 4.38 | 4.863 | 1.11x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1453.04 | 0.90x |
| mesh.section_us_mean | 139.451 | 202.611 | 1.45x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 824.094 | 1.20x |
| mesh_lod1.chunk_ms_max | 5.44 | 5.877 | 1.08x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.81 | 1.17x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1179.1 | 0.80x |
| mesh_lod1.section_us_mean | 126.754 | 200.433 | 1.58x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 841.975 | 1.48x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.872 | 1.16x |
| mobs.tick_150_ms_max | 1.25 | 2.969 | 2.38x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.485 | 1.78x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.369 | 3.12x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.204 | 6.58x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.853 | 10.40x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.688 | 0.58x ✅ better |
| save.load_chunk_ms | 0.587 | 0.475 | 0.81x |
| save.main_thread_ms | 5.206 | 3.076 | 0.59x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.715 | 0.67x ✅ better |
| ships.assemble_ms | 19.313 | 17.177 | 0.89x |
| ships.assemble_remesh_s | 0.027 | 0.038 | 1.41x ⚠️ worse |
| ships.blast_ms | 2.675 | 1.914 | 0.72x ✅ better |
| ships.blast_remesh_ms | 5.466 | 5.469 | 1.00x |
| ships.collide_far_us | 0.214 | 0.234 | 1.09x |
| ships.collide_us | 1.047 | 9.353 | 8.93x ⚠️ worse |
| ships.dock_ms | 12.056 | 11.155 | 0.93x |
| ships.dock_remesh_s | 0.036 | 0.092 | 2.56x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.541 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.262 | 0.52x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.673 | 1.01x |
| ships.frame_encode_ms | 0.023 | 0.965 | 41.96x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.41 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.23 | 0.73x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.149 | 0.90x |
| ships.physics_ms_p95 | 0.213 | 0.178 | 0.84x |
| ships.spawn_frigate_ms | 2.358 | 2.105 | 0.89x |
| ships.tick_ms_max | 0.522 | 4.957 | 9.50x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.327 | 1.49x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.862 | 2.85x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.415 | 1.02x |
| startup.first_load_ms | 206.958 | 224.506 | 1.08x |
| startup.renderer_init_again_ms | 27.582 | 891.469 | 32.32x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1819.39 | 2.23x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.246 | 0.71x ✅ better |
| startup.since_launch_s | 5.923 | 9.614 | 1.62x ⚠️ worse |
| startup.textures_ms | 26.537 | 589.704 | 22.22x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.942 | 6.80x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.597 | 0.19x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.926 | 0.32x ✅ better |
| tnt.remesh_s | 0.087 | 0.061 | 0.70x ✅ better |
| tnt.tick_ms_max | 5.414 | 1.094 | 0.20x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.742 | 0.16x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.094 | 0.20x ✅ better |
### Smoke test
```
smoke rd 8 mob drawing: mobs 38 (0 within 32), 7812 vertices written, 7812 drawn via Fancy buffer, 45 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 439, loaded 439; stashed mobs 1; map cells 2511; block entities 39; gravity queue 0; fluid pending 129; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4724.1 122.0 1673.8 ground yes water yes menu none
smoke rd 8 Fancy: 40 s, frame 14.2 ms, resident 388 MB, Metal 277 MB, mobs 27, coverage 99%
smoke rd 8 mob drawing: mobs 27 (0 within 32), 4896 vertices written, 4896 drawn via Fancy buffer, 17 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 668, loaded 668; stashed mobs 34; map cells 13738; block entities 148; gravity queue 0; fluid pending 329; jobs 2; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4737.6 119.6 1657.2 ground no water yes menu none
smoke rd 8 Fancy: 50 s, frame 9.3 ms, resident 397 MB, Metal 281 MB, mobs 34, coverage 93%
smoke rd 8 mob drawing: mobs 34 (0 within 32), 6480 vertices written, 6480 drawn via Fancy buffer, 21 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 670, loaded 670; stashed mobs 150; map cells 25162; block entities 302; gravity queue 0; fluid pending 390; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4750.9 118.0 1640.7 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 9.6 ms, resident 401 MB, Metal 285 MB, mobs 11, coverage 93%
smoke rd 8 mob drawing: mobs 11 (0 within 32), 2160 vertices written, 2160 drawn via Fancy buffer, 6 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 656, loaded 656; stashed mobs 229; map cells 36617; block entities 437; gravity queue 0; fluid pending 65; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 479 ms at 0.0 s (frame 0): Game.tick 4 ms, render + GPU 475 ms; frames over 100 ms: 1
smoke rd 8: 3600 frames in 60.0 s wall, frame p50 9.31 p95 14.06 p99 19.75 max 479.39 ms, coverage min 70%, mobs max 65, travelled 3218 blocks, resident peak 410 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 143 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
INFO iron attempt 1 at 4702 54 1743 (iron_ore, pickaxe held): mined yes, now air, 1 drops near
INFO iron attempt 2 at 4703 55 1742 (iron_ore, pickaxe held): mined yes, now air, 2 drops near
PASS mine: raw iron with a stone pickaxe (3)
INFO coal from ore: 1
INFO bulk: +3 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 100 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (2.0 s wall, 100 s game)
PASS worldgen: diamond ore within 80 blocks of spawn
PASS rules: stone pickaxe can't harvest diamond ore
INFO titanium attempt 1 at 4696 -63 1754: mined yes, now lava, 0 drops near
PASS mine: raw titanium with an iron pickaxe at y -63 (1, 2 ores)
INFO bulk: +5 diamond (more diamonds)
INFO bulk: +3 string (spiders)
INFO bulk: +4 flint (gravel)
INFO bulk: +4 feather (chickens)
PASS craft: diamond pickaxe, sword, bow, 16 arrows
INFO bulk: +19 diamond (more diamonds)
INFO bulk: +5 gold_ingot (gold ore)
PASS armour: 19 armour points worn
---- obsidian + portal (2.4 s wall, 103 s game)
INFO fell into deep while mining; back to the surface
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (3.2 s wall, 120 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 337 blocks from the portal
PASS fortress: 2 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 13 cinderwisps in 412 s
INFO cinder rod rate 0.54 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.54 per kill is plausible (reference 0.5)
---- void pearls (8.0 s wall, 535 s game)
INFO bag full: dropped 21 netherrack, 2 quartz, 2 warped_fungus, 2 gold_nugget, 3 rotten_flesh
PASS voidwalkers: 12 void pearls from 15 kills
---- back to the surface (13.3 s wall, 969 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (13.6 s wall, 974 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (13.6 s wall, 978 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 0 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (13.8 s wall, 980 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (14.0 s wall, 991 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 653 health so far (topped up)
---- hollow wyrm fight (14.2 s wall, 1013 s game)
PASS wyrm: defeated in 80 s (3 perches, 23 sword hits, 14 arrows for 43 damage, health left 1)
INFO wyrm fight: player took 48 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 13 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (14.8 s wall, 1106 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (14.8 s wall, 1112 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (14.9 s wall, 1115 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (15.0 s wall, 1123 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (15.1 s wall, 1123 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (15.3 s wall, 1179 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (17.6 s wall, 1192 s game)
INFO bulk: Smite V on the sword, Power V on the bow
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
FAIL blight: defeated in 601 s (388 arrows for 30 damage, 0 sword hits)
INFO blight sight: player sees it true, player SIMD3<Float>(4722.5, 127.0, 1784.8337), blight SIMD3<Float>(4722.5, 131.98885, 1783.6143), phase 0, arena floor y 127
PASS blight: arrows bounce off its armour below half health (0 damage from 0)
INFO blight fight: player took 2159 damage (healed by the test); 0 of 0 sword hits landed for 0
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 4722 132 1784, still listed yes, stars on the ground []
INFO star lost: player at 4722.4 127.0 1785.0, alive yes, 7 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (24.6 s wall, 1796 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 23 advancements earned: adventure/ash_vault, adventure/deep, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, follow_ender_eye, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (24.6 s wall, 1797 s game)
INFO deaths: 0, damage healed by the test: 2923 half-hearts
playthrough: 2 failed checks, 1797 s of game time in 24.6 s wall
```
### Synthesized sounds
- [bell.wav](sounds/bell.wav)
- [birdCall.wav](sounds/birdCall.wav)
- [break_glass.wav](sounds/break_glass.wav)
- [break_wood.wav](sounds/break_wood.wav)
- [bulletWhizz.wav](sounds/bulletWhizz.wav)
- [bullet_impact_metal.wav](sounds/bullet_impact_metal.wav)
- [carriageTreadLoop.wav](sounds/carriageTreadLoop.wav)
- [chestOpen.wav](sounds/chestOpen.wav)
- [doorOpen.wav](sounds/doorOpen.wav)
- [dragonGrowl.wav](sounds/dragonGrowl.wav)
- [engineFullLoop.wav](sounds/engineFullLoop.wav)
- [explode.wav](sounds/explode.wav)
- [frigateDroneLoop.wav](sounds/frigateDroneLoop.wav)
- [gun_0.wav](sounds/gun_0.wav)
- [gun_1.wav](sounds/gun_1.wav)
- [gun_10.wav](sounds/gun_10.wav)
- [gun_2.wav](sounds/gun_2.wav)
- [gun_3.wav](sounds/gun_3.wav)
- [gun_4.wav](sounds/gun_4.wav)
- [gun_5.wav](sounds/gun_5.wav)
- [gun_9.wav](sounds/gun_9.wav)
- [gun_distant_0.wav](sounds/gun_distant_0.wav)
- [gun_reload_0.wav](sounds/gun_reload_0.wav)
- [hullCreak.wav](sounds/hullCreak.wav)
- [levelUp.wav](sounds/levelUp.wav)
- [lever.wav](sounds/lever.wav)
- [mob_cow_ambient.wav](sounds/mob_cow_ambient.wav)
- [mob_enderman_ambient.wav](sounds/mob_enderman_ambient.wav)
- [mob_ghast_ambient.wav](sounds/mob_ghast_ambient.wav)
- [mob_skeleton_hurt.wav](sounds/mob_skeleton_hurt.wav)
- [mob_villager_ambient.wav](sounds/mob_villager_ambient.wav)
- [mob_warden_death.wav](sounds/mob_warden_death.wav)
- [mob_zombie_ambient.wav](sounds/mob_zombie_ambient.wav)
- [mountainWindLoop.wav](sounds/mountainWindLoop.wav)
- [note_0_12.wav](sounds/note_0_12.wav)
- [owlHoot.wav](sounds/owlHoot.wav)
- [pistonExtend.wav](sounds/pistonExtend.wav)
- [place_metal.wav](sounds/place_metal.wav)
- [propFastLoop.wav](sounds/propFastLoop.wav)
- [riverLoop.wav](sounds/riverLoop.wav)
- [shipCollideHard.wav](sounds/shipCollideHard.wav)
- [soldier_1_alert.wav](sounds/soldier_1_alert.wav)
- [soldier_3_death.wav](sounds/soldier_3_death.wav)
- [step_gravel.wav](sounds/step_gravel.wav)
- [step_stone.wav](sounds/step_stone.wav)
- [step_wood.wav](sounds/step_wood.wav)
- [thunder.wav](sounds/thunder.wav)
- [thunderFar.wav](sounds/thunderFar.wav)
- [villager_work_0.wav](sounds/villager_work_0.wav)
- [wardenRoar.wav](sounds/wardenRoar.wav)
- [waterfallLoop.wav](sounds/waterfallLoop.wav)
- [wingRushLoop.wav](sounds/wingRushLoop.wav)
- [witherSpawn.wav](sounds/witherSpawn.wav)
### advancements
![advancements.png](advancements.png)
### aerial
![aerial.png](aerial.png)
### aerial16
![aerial16.png](aerial16.png)
### aerial16_424242
![aerial16_424242.png](aerial16_424242.png)
### aerial16_777
![aerial16_777.png](aerial16_777.png)
### aerial16_fast
![aerial16_fast.png](aerial16_fast.png)
### aerial24
![aerial24.png](aerial24.png)
### agent_door_777
![agent_door_777.png](agent_door_777.png)
### ancient_city
![ancient_city.png](ancient_city.png)
### animals1
![animals1.png](animals1.png)
### animals2
![animals2.png](animals2.png)
### animals3
![animals3.png](animals3.png)
### anvil
![anvil.png](anvil.png)
### aquatic
![aquatic.png](aquatic.png)
### armor
![armor.png](armor.png)
### ashen_grove
![ashen_grove.png](ashen_grove.png)
### ashen_inside
![ashen_inside.png](ashen_inside.png)
### ashen_night
![ashen_night.png](ashen_night.png)
### atlas_0
![atlas_0.png](atlas_0.png)
### atlas_1
![atlas_1.png](atlas_1.png)
### atlas_2
![atlas_2.png](atlas_2.png)
### atlas_3
![atlas_3.png](atlas_3.png)
### audiotest
![audiotest.png](audiotest.png)
### banners
![banners.png](banners.png)
### base_air
![base_air.png](base_air.png)
### base_crawler
![base_crawler.png](base_crawler.png)
### base_lockdown
![base_lockdown.png](base_lockdown.png)
### base_patrol
![base_patrol.png](base_patrol.png)
### base_rebuild
![base_rebuild.png](base_rebuild.png)
### basetest_air
![basetest_air.png](basetest_air.png)
### basetest_crawler
![basetest_crawler.png](basetest_crawler.png)
### basetest_lockdown
![basetest_lockdown.png](basetest_lockdown.png)
### basetest_patrol
![basetest_patrol.png](basetest_patrol.png)
### basetest_rebuild
![basetest_rebuild.png](basetest_rebuild.png)
### bastion
![bastion.png](bastion.png)
### bastion_far
![bastion_far.png](bastion_far.png)
### beacon
![beacon.png](beacon.png)
### biome_badlands
![biome_badlands.png](biome_badlands.png)
### biome_birch_forest
![biome_birch_forest.png](biome_birch_forest.png)
### biome_cherry_grove
![biome_cherry_grove.png](biome_cherry_grove.png)
### biome_dark_forest
![biome_dark_forest.png](biome_dark_forest.png)
### biome_desert
![biome_desert.png](biome_desert.png)
### biome_jagged_peaks
![biome_jagged_peaks.png](biome_jagged_peaks.png)
### biome_jungle
![biome_jungle.png](biome_jungle.png)
### biome_mangrove_swamp
![biome_mangrove_swamp.png](biome_mangrove_swamp.png)
### biome_savanna
![biome_savanna.png](biome_savanna.png)
### biome_swamp
![biome_swamp.png](biome_swamp.png)
### biome_taiga
![biome_taiga.png](biome_taiga.png)
### biome_warm_ocean
![biome_warm_ocean.png](biome_warm_ocean.png)
### boats
![boats.png](boats.png)
### book
![book.png](book.png)
### boom_night
![boom_night.png](boom_night.png)
### brewing
![brewing.png](brewing.png)
### bugnotes
![bugnotes.png](bugnotes.png)
### cactus_far
![cactus_far.png](cactus_far.png)
### cactus_far_nolod
![cactus_far_nolod.png](cactus_far_nolod.png)
### cactus_mid
![cactus_mid.png](cactus_mid.png)
### cactus_mid_fast
![cactus_mid_fast.png](cactus_mid_fast.png)
### camp_abandoned
![camp_abandoned.png](camp_abandoned.png)
### camp_hunters
![camp_hunters.png](camp_hunters.png)
### camp_outlaws
![camp_outlaws.png](camp_outlaws.png)
### camp_prospectors
![camp_prospectors.png](camp_prospectors.png)
### camp_traders
![camp_traders.png](camp_traders.png)
### canyon
![canyon.png](canyon.png)
### canyon_floor
![canyon_floor.png](canyon_floor.png)
### capitaltest
![capitaltest.png](capitaltest.png)
### captains
![captains.png](captains.png)
### cave_dark
![cave_dark.png](cave_dark.png)
### cave_dark_bright
![cave_dark_bright.png](cave_dark_bright.png)
### cave_dark_fast
![cave_dark_fast.png](cave_dark_fast.png)
### cave_dark_mobs
![cave_dark_mobs.png](cave_dark_mobs.png)
### cave_dark_moody
![cave_dark_moody.png](cave_dark_moody.png)
### cave_torches
![cave_torches.png](cave_torches.png)
### chips
![chips.png](chips.png)
### citadel_far
![citadel_far.png](citadel_far.png)
### citadel_gate
![citadel_gate.png](citadel_gate.png)
### citadel_plaza
![citadel_plaza.png](citadel_plaza.png)
### citadel_top
![citadel_top.png](citadel_top.png)
### citadel_turret
![citadel_turret.png](citadel_turret.png)
### climate_1
![climate_1.png](climate_1.png)
### climate_12345
![climate_12345.png](climate_12345.png)
### climate_424242
![climate_424242.png](climate_424242.png)
### climate_777
![climate_777.png](climate_777.png)
### climate_98765
![climate_98765.png](climate_98765.png)
### clouds
![clouds.png](clouds.png)
### commands
![commands.png](commands.png)
### controls_ref
![controls_ref.png](controls_ref.png)
### coop
![coop.png](coop.png)
### copper
![copper.png](copper.png)
### copper_golems
![copper_golems.png](copper_golems.png)
### coppertest
![coppertest.png](coppertest.png)
### crack
![crack.png](crack.png)
### craftbook
![craftbook.png](craftbook.png)
### crafting
![crafting.png](crafting.png)
### create
![create.png](create.png)
### creative
![creative.png](creative.png)
### credits
![credits.png](credits.png)
### dark_forest
![dark_forest.png](dark_forest.png)
### death
![death.png](death.png)
### deck_gun
![deck_gun.png](deck_gun.png)
### decor
![decor.png](decor.png)
### deep_dark
![deep_dark.png](deep_dark.png)
### desert_temple
![desert_temple.png](desert_temple.png)
### desert_temple_inside
![desert_temple_inside.png](desert_temple_inside.png)
### desert_well
![desert_well.png](desert_well.png)
### down
![down.png](down.png)
### dripstone_caves
![dripstone_caves.png](dripstone_caves.png)
### drops
![drops.png](drops.png)
### effects
![effects.png](effects.png)
### ember_basalt
![ember_basalt.png](ember_basalt.png)
### ember_crimson
![ember_crimson.png](ember_crimson.png)
### ember_soul
![ember_soul.png](ember_soul.png)
### ember_warped
![ember_warped.png](ember_warped.png)
### enchant
![enchant.png](enchant.png)
### end
![end.png](end.png)
### end_city
![end_city.png](end_city.png)
### end_outer
![end_outer.png](end_outer.png)
### end_top
![end_top.png](end_top.png)
### farm_variants
![farm_variants.png](farm_variants.png)
### firefight
![firefight.png](firefight.png)
### fireworks
![fireworks.png](fireworks.png)
### flicker_build
![flicker_build.png](flicker_build.png)
### flicker_forest
![flicker_forest.png](flicker_forest.png)
### flicker_village
![flicker_village.png](flicker_village.png)
### flight_heli
![flight_heli.png](flight_heli.png)
### flight_plane
![flight_plane.png](flight_plane.png)
### flighttest
![flighttest.png](flighttest.png)
### forest
![forest.png](forest.png)
### forest_fast
![forest_fast.png](forest_fast.png)
### forest_in
![forest_in.png](forest_in.png)
### forest_nobase
![forest_nobase.png](forest_nobase.png)
### forest_nocull
![forest_nocull.png](forest_nocull.png)
### forest_verify
![forest_verify.png](forest_verify.png)
### fortress
![fortress.png](fortress.png)
### fortress_far
![fortress_far.png](fortress_far.png)
### furnace
![furnace.png](furnace.png)
### gallery_build
![gallery_build.png](gallery_build.png)
### gallery_build_night
![gallery_build_night.png](gallery_build_night.png)
### gallery_color
![gallery_color.png](gallery_color.png)
### gallery_copper
![gallery_copper.png](gallery_copper.png)
### gallery_copper_night
![gallery_copper_night.png](gallery_copper_night.png)
### gallery_earth
![gallery_earth.png](gallery_earth.png)
### gallery_ember
![gallery_ember.png](gallery_ember.png)
### gallery_hollow
![gallery_hollow.png](gallery_hollow.png)
### gallery_ores
![gallery_ores.png](gallery_ores.png)
### gallery_plants
![gallery_plants.png](gallery_plants.png)
### gallery_stone
![gallery_stone.png](gallery_stone.png)
### gallery_wood
![gallery_wood.png](gallery_wood.png)
### gencheck_leak_1
![gencheck_leak_1.png](gencheck_leak_1.png)
### gencheck_leak_2
![gencheck_leak_2.png](gencheck_leak_2.png)
### ground16
![ground16.png](ground16.png)
### ground16_fast
![ground16_fast.png](ground16_fast.png)
### gun_aim
![gun_aim.png](gun_aim.png)
### gun_hip
![gun_hip.png](gun_hip.png)
### gun_scope
![gun_scope.png](gun_scope.png)
### hdatlas
![hdatlas.png](hdatlas.png)
### heads
![heads.png](heads.png)
### hisser
![hisser.png](hisser.png)
### horizon_ring
![horizon_ring.png](horizon_ring.png)
### horizon_ring_evening
![horizon_ring_evening.png](horizon_ring_evening.png)
### hostile
![hostile.png](hostile.png)
### in_lava
![in_lava.png](in_lava.png)
### inventory
![inventory.png](inventory.png)
### inventory_pad
![inventory_pad.png](inventory_pad.png)
### issue_1
![issue_1.png](issue_1.png)
### issue_2
![issue_2.png](issue_2.png)
### jungle_temple
![jungle_temple.png](jungle_temple.png)
### lake
![lake.png](lake.png)
### lake_glint
![lake_glint.png](lake_glint.png)
### leak_12345
![leak_12345.png](leak_12345.png)
### loom
![loom.png](loom.png)
### lush_caves
![lush_caves.png](lush_caves.png)
### magic_blocks
![magic_blocks.png](magic_blocks.png)
### mansion
![mansion.png](mansion.png)
### mansion_inside
![mansion_inside.png](mansion_inside.png)
### map
![map.png](map.png)
### meadow
![meadow.png](meadow.png)
### mineshaft
![mineshaft.png](mineshaft.png)
### mineshaft_torches
![mineshaft_torches.png](mineshaft_torches.png)
### mob_shadows
![mob_shadows.png](mob_shadows.png)
### mobcheck
![mobcheck.png](mobcheck.png)
### mobs
![mobs.png](mobs.png)
### mobs_g
![mobs_g.png](mobs_g.png)
### mobs_new
![mobs_new.png](mobs_new.png)
### monument
![monument.png](monument.png)
### musiccheck
![musiccheck.png](musiccheck.png)
### nether
![nether.png](nether.png)
### nether_mobs
![nether_mobs.png](nether_mobs.png)
### nether_wide
![nether_wide.png](nether_wide.png)
### night
![night.png](night.png)
### ocean_night_777
![ocean_night_777.png](ocean_night_777.png)
### ocean_night_777_fast
![ocean_night_777_fast.png](ocean_night_777_fast.png)
### ocean_ruin
![ocean_ruin.png](ocean_ruin.png)
### options
![options.png](options.png)
### outpost
![outpost.png](outpost.png)
### outpost_close
![outpost_close.png](outpost_close.png)
### padmap
![padmap.png](padmap.png)
### padtest
![padtest.png](padtest.png)
### pathtest
![pathtest.png](pathtest.png)
### pause
![pause.png](pause.png)
### photo_dof
![photo_dof.png](photo_dof.png)
### photo_dof_far
![photo_dof_far.png](photo_dof_far.png)
### physicstest
![physicstest.png](physicstest.png)
### plantcheck
![plantcheck.png](plantcheck.png)
### portal
![portal.png](portal.png)
### rain
![rain.png](rain.png)
### recipes
![recipes.png](recipes.png)
### redstone
![redstone.png](redstone.png)
### relief_1
![relief_1.png](relief_1.png)
### relief_12345
![relief_12345.png](relief_12345.png)
### relief_424242
![relief_424242.png](relief_424242.png)
### relief_777
![relief_777.png](relief_777.png)
### relief_98765
![relief_98765.png](relief_98765.png)
### rulescheck
![rulescheck.png](rulescheck.png)
### seabed_deep
![seabed_deep.png](seabed_deep.png)
### seabed_deep_far
![seabed_deep_far.png](seabed_deep_far.png)
### seabed_warm
![seabed_warm.png](seabed_warm.png)
### selftest
![selftest.png](selftest.png)
### ship_airship
![ship_airship.png](ship_airship.png)
### ship_battle
![ship_battle.png](ship_battle.png)
### ship_boat
![ship_boat.png](ship_boat.png)
### ship_capitalbattle
![ship_capitalbattle.png](ship_capitalbattle.png)
### ship_car
![ship_car.png](ship_car.png)
### ship_carriage
![ship_carriage.png](ship_carriage.png)
### ship_crawler
![ship_crawler.png](ship_crawler.png)
### ship_deck
![ship_deck.png](ship_deck.png)
### ship_frigate
![ship_frigate.png](ship_frigate.png)
### ship_frigate_bow
![ship_frigate_bow.png](ship_frigate_bow.png)
### ship_frigate_deck
![ship_frigate_deck.png](ship_frigate_deck.png)
### ship_frigate_side
![ship_frigate_side.png](ship_frigate_side.png)
### ship_frigate_top
![ship_frigate_top.png](ship_frigate_top.png)
### ship_gunboat
![ship_gunboat.png](ship_gunboat.png)
### ship_plane
![ship_plane.png](ship_plane.png)
### ship_warfrigate
![ship_warfrigate.png](ship_warfrigate.png)
### shipwreck
![shipwreck.png](shipwreck.png)
### shore
![shore.png](shore.png)
### sim
![sim.png](sim.png)
### smoke_rd16
![smoke_rd16.png](smoke_rd16.png)
### smoke_rd24
![smoke_rd24.png](smoke_rd24.png)
### smoke_rd8
![smoke_rd8.png](smoke_rd8.png)
### snowfall
![snowfall.png](snowfall.png)
### snowslope
![snowslope.png](snowslope.png)
### snowy
![snowy.png](snowy.png)
### soldier_actions
![soldier_actions.png](soldier_actions.png)
### soldier_actions_heavy
![soldier_actions_heavy.png](soldier_actions_heavy.png)
### soldier_closeup
![soldier_closeup.png](soldier_closeup.png)
### soldier_ranks_aim
![soldier_ranks_aim.png](soldier_ranks_aim.png)
### soldier_ranks_back
![soldier_ranks_back.png](soldier_ranks_back.png)
### soldier_ranks_front
![soldier_ranks_front.png](soldier_ranks_front.png)
### soldier_ranks_night_back
![soldier_ranks_night_back.png](soldier_ranks_night_back.png)
### soldier_ranks_night_front
![soldier_ranks_night_front.png](soldier_ranks_night_front.png)
### soldier_ranks_night_side
![soldier_ranks_night_side.png](soldier_ranks_night_side.png)
### soldier_ranks_side
![soldier_ranks_side.png](soldier_ranks_side.png)
### soldier_squad
![soldier_squad.png](soldier_squad.png)
### soldier_squad_night
![soldier_squad_night.png](soldier_squad_night.png)
### soldier_stations
![soldier_stations.png](soldier_stations.png)
### soldiers
![soldiers.png](soldiers.png)
### spawn
![spawn.png](spawn.png)
### spawn_portal_check
![spawn_portal_check.png](spawn_portal_check.png)
### spear_hold
![spear_hold.png](spear_hold.png)
### spire
![spire.png](spire.png)
### spire_horizon
![spire_horizon.png](spire_horizon.png)
### spire_inside
![spire_inside.png](spire_inside.png)
### stars
![stars.png](stars.png)
### steelhold
![steelhold.png](steelhold.png)
### steelhold_armory
![steelhold_armory.png](steelhold_armory.png)
### steelhold_armory_close
![steelhold_armory_close.png](steelhold_armory_close.png)
### steelhold_armory_fast
![steelhold_armory_fast.png](steelhold_armory_fast.png)
### steelhold_armory_swords
![steelhold_armory_swords.png](steelhold_armory_swords.png)
### steelhold_command
![steelhold_command.png](steelhold_command.png)
### steelhold_fight
![steelhold_fight.png](steelhold_fight.png)
### steelhold_gate
![steelhold_gate.png](steelhold_gate.png)
### stronghold
![stronghold.png](stronghold.png)
### subtitles
![subtitles.png](subtitles.png)
### sunset
![sunset.png](sunset.png)
### sunset_fast
![sunset_fast.png](sunset_fast.png)
### sunset_sun
![sunset_sun.png](sunset_sun.png)
### survival
![survival.png](survival.png)
### temple
![temple.png](temple.png)
### temple2
![temple2.png](temple2.png)
### terrain_1
![terrain_1.png](terrain_1.png)
### terrain_12345
![terrain_12345.png](terrain_12345.png)
### terrain_424242
![terrain_424242.png](terrain_424242.png)
### terrain_777
![terrain_777.png](terrain_777.png)
### terrain_98765
![terrain_98765.png](terrain_98765.png)
### texsrc_cc0_cliff
![texsrc_cc0_cliff.png](texsrc_cc0_cliff.png)
### texsrc_cc0_forest
![texsrc_cc0_forest.png](texsrc_cc0_forest.png)
### texsrc_cc0_village
![texsrc_cc0_village.png](texsrc_cc0_village.png)
### texsrc_gemini_cliff
![texsrc_gemini_cliff.png](texsrc_gemini_cliff.png)
### texsrc_gemini_forest
![texsrc_gemini_forest.png](texsrc_gemini_forest.png)
### texsrc_gemini_village
![texsrc_gemini_village.png](texsrc_gemini_village.png)
### texsrc_procedural_cliff
![texsrc_procedural_cliff.png](texsrc_procedural_cliff.png)
### texsrc_procedural_forest
![texsrc_procedural_forest.png](texsrc_procedural_forest.png)
### texsrc_procedural_village
![texsrc_procedural_village.png](texsrc_procedural_village.png)
### third_back
![third_back.png](third_back.png)
### third_front
![third_front.png](third_front.png)
### third_swim
![third_swim.png](third_swim.png)
### thunder
![thunder.png](thunder.png)
### title
![title.png](title.png)
### torches
![torches.png](torches.png)
### torches_day
![torches_day.png](torches_day.png)
### torches_near
![torches_near.png](torches_near.png)
### tour_12345_aerial
![tour_12345_aerial.png](tour_12345_aerial.png)
### tour_12345_low
![tour_12345_low.png](tour_12345_low.png)
### tour_1_aerial
![tour_1_aerial.png](tour_1_aerial.png)
### tour_1_low
![tour_1_low.png](tour_1_low.png)
### tour_424242_aerial
![tour_424242_aerial.png](tour_424242_aerial.png)
### tour_424242_low
![tour_424242_low.png](tour_424242_low.png)
### tour_777_aerial
![tour_777_aerial.png](tour_777_aerial.png)
### tour_777_aerial_fast
![tour_777_aerial_fast.png](tour_777_aerial_fast.png)
### tour_777_aerial_nocull
![tour_777_aerial_nocull.png](tour_777_aerial_nocull.png)
### tour_777_low
![tour_777_low.png](tour_777_low.png)
### tour_98765_aerial
![tour_98765_aerial.png](tour_98765_aerial.png)
### tour_98765_low
![tour_98765_low.png](tour_98765_low.png)
### tour_coast
![tour_coast.png](tour_coast.png)
### tour_delta
![tour_delta.png](tour_delta.png)
### tour_delta_777
![tour_delta_777.png](tour_delta_777.png)
### tour_desert
![tour_desert.png](tour_desert.png)
### tour_forest_floor
![tour_forest_floor.png](tour_forest_floor.png)
### tour_jungle
![tour_jungle.png](tour_jungle.png)
### tour_lake
![tour_lake.png](tour_lake.png)
### tour_lake_424242
![tour_lake_424242.png](tour_lake_424242.png)
### tour_mesa
![tour_mesa.png](tour_mesa.png)
### tour_peaks
![tour_peaks.png](tour_peaks.png)
### tour_river
![tour_river.png](tour_river.png)
### tour_river_777
![tour_river_777.png](tour_river_777.png)
### tour_snowline
![tour_snowline.png](tour_snowline.png)
### trade
![trade.png](trade.png)
### trail_ruins
![trail_ruins.png](trail_ruins.png)
### trial_chambers
![trial_chambers.png](trial_chambers.png)
### tv_combat
![tv_combat.png](tv_combat.png)
### tv_confirm
![tv_confirm.png](tv_confirm.png)
### tv_coop
![tv_coop.png](tv_coop.png)
### tv_coop_side
![tv_coop_side.png](tv_coop_side.png)
### tv_craftbook
![tv_craftbook.png](tv_craftbook.png)
### tv_craftbook2
![tv_craftbook2.png](tv_craftbook2.png)
### tv_craftbook_all
![tv_craftbook_all.png](tv_craftbook_all.png)
### tv_hud
![tv_hud.png](tv_hud.png)
### tv_keyboard
![tv_keyboard.png](tv_keyboard.png)
### tv_map
![tv_map.png](tv_map.png)
### tv_options
![tv_options.png](tv_options.png)
### tv_title
![tv_title.png](tv_title.png)
### tv_worlds
![tv_worlds.png](tv_worlds.png)
### underwater
![underwater.png](underwater.png)
### underwater_up
![underwater_up.png](underwater_up.png)
### vehicle_hud
![vehicle_hud.png](vehicle_hud.png)
### village
![village.png](village.png)
### village2
![village2.png](village2.png)
### village3
![village3.png](village3.png)
### village_street
![village_street.png](village_street.png)
### village_top
![village_top.png](village_top.png)
### villager_jobs
![villager_jobs.png](villager_jobs.png)
### villagers
![villagers.png](villagers.png)
### volcano_crater
![volcano_crater.png](volcano_crater.png)
### volcano_dusk
![volcano_dusk.png](volcano_dusk.png)
### volcano_far
![volcano_far.png](volcano_far.png)
### volcano_horizon
![volcano_horizon.png](volcano_horizon.png)
### volcano_horizon_night
![volcano_horizon_night.png](volcano_horizon_night.png)
### water_flow
![water_flow.png](water_flow.png)
