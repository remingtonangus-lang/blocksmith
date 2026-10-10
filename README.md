# Blocksmith CI snapshots (heavy lane)

Commit `579a1622ed376b1d164ceed6476985cc1a7602e3` on `claude/project-thread-27glmf`: build **success**, heavy jobs **failure**
- checks: failure
- perf: success
- play: failure
- shots: success
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38054178466

```
gen 248 ms  mesh(all, parallel) 256 ms  mesh(1 section) 0.45 ms  quads 835232 opaque / 19278 water
frame (encode+GPU, offscreen, median of 30) 5.29 ms  biome beach
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 171 MB
memory: resident 241 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 614 ms, upload 245 ms)
light probe: eye sky 15 block 1 in air; floor+1 (y 69) sky 15 block 5 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0007 white=0.0008 std=18.2 hash=759d34606798badd
imagecheck agent_door_777.png magenta=0.00000 black=0.0007 white=0.0008 std=18.2 hash=759d34606798badd
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 244 ms  mesh(all, parallel) 268 ms  mesh(1 section) 0.95 ms  quads 752871 opaque / 417 water
frame (encode+GPU, offscreen, median of 30) 4.55 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 238 MB  (section meshes 23 MB)
wrote snaps/agent_door_777.png
naming audit: 6745 names, 0 flagged
selftest: 1206 blocks, 104 mob kinds, 4/4 special recipes, bundle fill 32/64, 89 advancements
selftest ok: 107 mobs after 3 s
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 583 ms, upload 242 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0008 white=0.0063 std=48.6 hash=79b316c9eabd79e7
imagecheck selftest.png magenta=0.00000 black=0.0008 white=0.0063 std=48.6 hash=79b316c9eabd79e7
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 254 ms  mesh(all, parallel) 241 ms  mesh(1 section) 0.23 ms  quads 800253 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 5.71 ms  biome plains
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 183 MB
memory: resident 259 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (35 pieces, framed)
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 605 ms, upload 246 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=60.9 hash=055072ad6849de33 flicker=0.00017
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=60.9 hash=055072ad6849de33 flicker=0.00017
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 259 ms  mesh(all, parallel) 437 ms  mesh(1 section) 0.79 ms  quads 1647813 opaque / 70 water
frame (encode+GPU, offscreen, median of 30) 4.35 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 38 MB), Metal allocated 207 MB
memory: resident 287 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 647 ms, upload 263 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=55.3 hash=a9507ccd7c8eebad flicker=0.00003
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=55.3 hash=a9507ccd7c8eebad flicker=0.00003
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 241 ms  mesh(all, parallel) 310 ms  mesh(1 section) 1.20 ms  quads 1169814 opaque / 73 water
frame (encode+GPU, offscreen, median of 30) 5.71 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 30 MB), Metal allocated 179 MB
memory: resident 247 MB  (section meshes 36 MB)
wrote snaps/flicker_forest.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 667 ms, upload 265 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=43.3 hash=b7cc3381e88c9e80 flicker=0.00010
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=43.3 hash=b7cc3381e88c9e80 flicker=0.00010
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 257 ms  mesh(all, parallel) 246 ms  mesh(1 section) 0.32 ms  quads 800454 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 4.26 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 167 MB
memory: resident 225 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 199 frames, no flags
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 1.97 ms (min 1.41, max 2.54) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 1.95 ms/chunk
bench gen slow chunk -59,14: 4.5 ms (caves 0.6, ores 0.3, columns 0.1; starts 0.0, place 3.1)
bench gen slow chunk -80,-25: 3.7 ms (plants 2.0, caves 0.8, ores 0.3; starts 0.0, place 0.1)
bench gen slow chunk 53,22: 2.0 ms (caves 1.1, ores 0.3, columns 0.2; starts 0.0, place 0.0)
bench gen phases (ms/chunk): columns 0.18, stone 0.15, surface 0.02, caves 0.73, ores 0.19, trees 0.03, plants 0.18, starts 0.00, structures 0.16
bench gen structure starts (ms over 24 chunks): capital_city 35.7, boreal_station 33.4, military_base 26.7, village 11.3, temple 3.0, mansion 2.9, pillager_outpost 2.6, trail_ruins 1.2
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.71 ms/chunk (p95 3.71, max 4.49) single-thread | 1359 chunks/s parallel
bench: gen took 0.7 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 4.30 ms/chunk (24 sections, 81 non-empty), section mean 179 us p95 771 us max 974 us, 4942 quads/chunk
bench mesh_lod1: 3.96 ms/chunk (24 sections, 81 non-empty), section mean 165 us p95 685 us max 885 us, 2515 quads/chunk
bench: mesh took 0.7 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 19 ms, first load (r 4) 172 ms, renderer 2200 ms (textures 695 ms, shaders 1 ms), fill rd 12 5.12 s
bench: startup took 9.8 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 0.94 ms, GPU p50 3.88 ms (max 4.86), 258 chunks drawn
bench frame 1080p rd 16: encode p50 0.92 ms, GPU p50 4.39 ms (max 5.17), 270 chunks drawn
bench frame 4k rd 16: encode p50 0.92 ms, GPU p50 7.12 ms (max 8.66), 270 chunks drawn
bench frame: 697 visible sections, 1221 draw calls, 253k quads
bench: frame took 4.8 s (live worlds 0, games 0)
bench: edit starts
bench edit: break mean 0.84 ms max 1.33 ms, place mean 0.80 ms max 1.17 ms (synchronous remesh)
bench: edit took 0.8 s (live worlds 1, games 0)
bench: mobs starts
bench mobs: tick 0.21 ms empty, 0.55 ms with 150 mobs (p95 1.60, max 2.56), 158 alive
bench: mobs took 1.0 s (live worlds 1, games 0)
bench: save starts
bench save: 145 chunks, save 2.00 ms/chunk (main thread 5.9 ms total, unchanged re-save 2.1 ms), load 0.28 ms/chunk (145 ok), 6.2 KB/chunk
bench: save took 1.1 s (live worlds 1, games 0)
bench: tnt starts
bench tnt: blast mean 1.35 ms max 3.21 ms (main thread) | re-mesh done in 0.13 s, tick p95 2.41 max 2.41 ms
bench: tnt took 0.9 s (live worlds 1, games 0)
bench: fluids starts
bench fluids: tick p50 0.31 p95 1.77 max 7.89 ms, 6284 sections re-meshed in 6 s, 1260 cells still pending
bench: fluids took 6.8 s (live worlds 1, games 0)
bench: ships starts
bench ships: edit remesh 3.68 ms, blast 1.95 ms + remesh 10.66 ms (3034 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds -0.03 ms encode, 0.09 ms GPU (66 draw calls)
bench ships: docked 3074 blocks in 16.69 ms (world remesh 0.09 s), assembled 3054 in 19.31 ms
bench ships: frigate 3034 blocks spawn 2.30 ms, mesh 3.34 ms; tick 0.37 ms (p95 0.92), physics 0.17 ms; collide 0.92 us near ships, 0.23 us far; 13 ships
bench: ships took 2.6 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 193
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.56 p95 4.87 p99 9.24 max 20.85 ms, 0 hitches >25 ms | tick p95 1.38 (update p95 0.60, max 20.26) encode p95 1.14 GPU p95 4.18 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.4 ms each on a worker) mesh 955 sections/s (318 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 25 MB, meshes 24 MB (slabs 40 MB), resident peak 210 MB, preload 620 ms
bench: flight8 took 14.8 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 3.43 p95 5.53 p99 12.36 max 25.03 ms, 1 hitches >25 ms | tick p95 1.93 (update p95 0.97, max 12.58) encode p95 2.09 GPU p95 4.57 ms
bench flight16: coverage min 75% mean 86% | gen 43 chunks/s (2.2 ms each on a worker) mesh 3318 sections/s (263 us each) | realtime 1.00x
bench flight16: 1052 chunks, chunk data 86 MB, meshes 46 MB (slabs 68 MB), resident peak 314 MB, preload 2093 ms
bench: flight16 took 16.2 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 4.49 p95 6.43 p99 9.98 max 15.65 ms, 0 hitches >25 ms | tick p95 2.02 (update p95 0.98, max 3.36) encode p95 3.33 GPU p95 6.27 ms
bench flight24: coverage min 72% mean 83% | gen 21 chunks/s (2.3 ms each on a worker) mesh 3346 sections/s (304 us each) | realtime 1.00x
bench flight24: 1664 chunks, chunk data 142 MB, meshes 68 MB (slabs 100 MB), resident peak 497 MB, preload 3939 ms
bench: flight24 took 18.4 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.33 | 2.22x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.835 | 1.87x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.792 | 1.33x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.17 | 1.60x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.8 | 1.76x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.779 | 1.31x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 16.153 | 18.70x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.862 | 1.15x |
| flight16.coverage_min | 0.962 | 0.75 | 1.28x |
| flight16.cull_ms_p50 | 0.708 | 0.309 | 0.44x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.894 | 0.78x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.801 | 0.54x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.087 | 0.88x |
| flight16.frame_ms_max | 12.652 | 25.034 | 1.98x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.434 | 0.71x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.535 | 0.95x |
| flight16.frame_ms_p99 | 7.443 | 12.356 | 1.66x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.193 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.408 | 0.71x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.575 | 0.80x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.296 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3317.59 | 0.59x ✅ better |
| flight16.preload_ms | 1871.23 | 2092.57 | 1.12x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 313.831 | 1.10x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 14.796 | 1.73x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.574 | 1.48x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 1.927 | 0.93x |
| flight16.update_ms_max | 8.289 | 12.58 | 1.52x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.251 | 14.76x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.969 | 0.56x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.168 | 1.07x |
| flight16.worker_mesh_us | 177.949 | 263.225 | 1.48x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.81 | 55.76x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 142.289 | 0.64x ✅ better |
| flight24.chunks | 2176 | 1664 | 0.76x ✅ better |
| flight24.coverage_mean | 0.994 | 0.829 | 1.20x |
| flight24.coverage_min | 0.974 | 0.717 | 1.36x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.633 | 0.53x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.694 | 0.61x ✅ better |
| flight24.cull_walked_sections | 7607 | 3538 | 0.47x ✅ better |
| flight24.draw_calls | 3175 | 1081 | 0.34x ✅ better |
| flight24.drawn_kquads | 821.704 | 204.952 | 0.25x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.29 | 0.52x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 3.33 | 0.64x ✅ better |
| flight24.frame_ms_max | 13.319 | 15.653 | 1.18x |
| flight24.frame_ms_p50 | 7.72 | 4.487 | 0.58x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.427 | 0.68x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 9.984 | 0.97x |
| flight24.gen_chunks_per_s | 63.73 | 21.154 | 3.01x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.475 | 0.58x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.275 | 0.67x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 67.947 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3346.22 | 0.73x ✅ better |
| flight24.preload_ms | 4742.83 | 3939.35 | 0.83x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 497.394 | 0.97x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 12.822 | 1.10x |
| flight24.tick_ms_p50 | 0.401 | 0.619 | 1.54x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.016 | 0.69x ✅ better |
| flight24.update_ms_max | 4.586 | 3.361 | 0.73x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.295 | 19.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.98 | 0.39x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.267 | 0.96x |
| flight24.worker_mesh_us | 177.947 | 303.826 | 1.71x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.64 | 4.36x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.989 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.086 | 0.42x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.233 | 0.76x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.45 | 0.80x |
| flight8.encode_ms_p95 | 0.832 | 1.141 | 1.37x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 20.847 | 1.58x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.561 | 0.99x |
| flight8.frame_ms_p95 | 3.197 | 4.868 | 1.52x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 9.241 | 2.10x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.732 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.553 | 0.99x |
| flight8.gpu_ms_p95 | 3.081 | 4.176 | 1.36x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 954.795 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 619.753 | 0.44x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 209.705 | 1.68x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 20.42 | 1.63x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.404 | 2.56x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.377 | 1.13x |
| flight8.update_ms_max | 12.421 | 20.264 | 1.63x ⚠️ worse |
| flight8.update_ms_p50 | 0.01 | 0.007 | 0.70x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.601 | 0.69x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.404 | 0.74x ✅ better |
| flight8.worker_mesh_us | 181.115 | 318.275 | 1.76x ⚠️ worse |
| fluids.pending | 240 | 1260 | 5.25x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6284 | 2.41x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 7.889 | 2.31x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.306 | 1.35x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.766 | 0.94x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.173 | 1.93x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.922 | 1.48x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.173 | 1.97x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.393 | 1.90x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.559 | 1.60x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.919 | 1.33x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 8.657 | 2.12x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.124 | 2.02x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.329 | 3.08x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.939 | 1.54x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.86 | 2.02x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.878 | 1.88x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.493 | 1.33x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.709 | 0.82x |
| gen.chunk_ms_p95 | 3.325 | 3.706 | 1.11x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1358.77 | 1.24x |
| gen.starts_cold_ms | – | 1.951 | new |
| gen.terrain_hash | 1238443285367868 | 1188771535852922 | ⚠️ changed |
| genphase.caves_ms | – | 0.73 | new |
| genphase.columns_ms | – | 0.183 | new |
| genphase.ores_ms | – | 0.189 | new |
| genphase.plants_ms | – | 0.184 | new |
| genphase.starts_ms | – | 0.004 | new |
| genphase.stone_ms | – | 0.146 | new |
| genphase.structures_ms | – | 0.164 | new |
| genphase.surface_ms | – | 0.02 | new |
| genphase.trees_ms | – | 0.029 | new |
| mesh.chunk_ms_max | 5.758 | 5.152 | 0.89x |
| mesh.chunk_ms_mean | 4.38 | 4.303 | 0.98x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 973.94 | 0.60x ✅ better |
| mesh.section_us_mean | 139.451 | 179.294 | 1.29x |
| mesh.section_us_p95 | 686.049 | 770.926 | 1.12x |
| mesh_lod1.chunk_ms_max | 5.44 | 4.678 | 0.86x |
| mesh_lod1.chunk_ms_mean | 4.1 | 3.961 | 0.97x |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 885.01 | 0.60x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 165.041 | 1.30x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 684.977 | 1.21x |
| mobs.per_mob_us | 1.608 | 2.283 | 1.42x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.556 | 2.04x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.554 | 2.04x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.597 | 3.64x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.212 | 6.84x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.847 | 10.33x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.005 | 0.69x ✅ better |
| save.load_chunk_ms | 0.587 | 0.279 | 0.48x ✅ better |
| save.main_thread_ms | 5.206 | 5.925 | 1.14x |
| save.unchanged_resave_ms | 2.544 | 2.084 | 0.82x |
| ships.assemble_ms | 19.313 | 19.313 | 1.00x |
| ships.assemble_remesh_s | 0.027 | 0.017 | 0.63x ✅ better |
| ships.blast_ms | 2.675 | 1.954 | 0.73x ✅ better |
| ships.blast_remesh_ms | 5.466 | 10.662 | 1.95x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.234 | 1.09x |
| ships.collide_us | 1.047 | 0.919 | 0.88x |
| ships.dock_ms | 12.056 | 16.688 | 1.38x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.089 | 2.47x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.84 | 0.95x |
| ships.edit_ms_mean | 0.505 | 0.337 | 0.67x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.682 | 1.01x |
| ships.frame_encode_ms | 0.023 | -0.027 | -1.17x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.086 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 3.342 | 1.09x |
| ships.physics_ms_mean | 0.165 | 0.166 | 1.01x |
| ships.physics_ms_p95 | 0.213 | 0.269 | 1.26x |
| ships.spawn_frigate_ms | 2.358 | 2.299 | 0.97x |
| ships.tick_ms_max | 0.522 | 5.233 | 10.02x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.37 | 1.69x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.918 | 3.04x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 5.115 | 1.18x |
| startup.first_load_ms | 206.958 | 172.236 | 0.83x |
| startup.renderer_init_again_ms | 27.582 | 1138.37 | 41.27x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2199.79 | 2.69x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.661 | 1.90x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.855 | 1.83x ⚠️ worse |
| startup.textures_ms | 26.537 | 695.087 | 26.19x ⚠️ worse |
| startup.world_init_ms | 2.198 | 19.323 | 8.79x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.211 | 0.37x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.349 | 0.46x ✅ better |
| tnt.remesh_s | 0.087 | 0.126 | 1.45x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 2.414 | 0.45x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.962 | 0.21x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 2.414 | 0.45x ✅ better |
### Smoke test
```
smoke rd 8 mob drawing: mobs 16 (0 within 32), 3672 vertices written, 3672 drawn via Fancy buffer, 21 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 439, loaded 439; stashed mobs 1; map cells 2511; block entities 39; gravity queue 0; fluid pending 154; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4724.1 122.0 1673.8 ground yes water yes menu none
smoke rd 8 Fancy: 40 s, frame 15.3 ms, resident 366 MB, Metal 269 MB, mobs 17, coverage 96%
smoke rd 8 mob drawing: mobs 17 (0 within 32), 2952 vertices written, 2952 drawn via Fancy buffer, 9 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 662, loaded 662; stashed mobs 20; map cells 13738; block entities 132; gravity queue 0; fluid pending 386; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4737.6 119.6 1657.2 ground no water yes menu none
smoke rd 8 Fancy: 50 s, frame 15.6 ms, resident 381 MB, Metal 277 MB, mobs 36, coverage 89%
smoke rd 8 mob drawing: mobs 36 (0 within 32), 8352 vertices written, 8352 drawn via Fancy buffer, 23 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 668, loaded 668; stashed mobs 121; map cells 25162; block entities 294; gravity queue 0; fluid pending 408; jobs 9; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4750.9 118.0 1640.7 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 12.3 ms, resident 377 MB, Metal 281 MB, mobs 12, coverage 93%
smoke rd 8 mob drawing: mobs 12 (0 within 32), 2232 vertices written, 2232 drawn via Fancy buffer, 7 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 663, loaded 663; stashed mobs 202; map cells 36617; block entities 435; gravity queue 0; fluid pending 65; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 468 ms at 0.0 s (frame 0): Game.tick 4 ms, render + GPU 464 ms; frames over 100 ms: 1
smoke rd 8: 3600 frames in 60.0 s wall, frame p50 11.84 p95 20.37 p99 39.83 max 468.12 ms, coverage min 64%, mobs max 60, travelled 3218 blocks, resident peak 395 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 143 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
INFO bulk: +9 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.8 s wall, 55 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 137 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (2.1 s wall, 137 s game)
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
---- obsidian + portal (2.7 s wall, 139 s game)
INFO fell into deep while mining; back to the surface
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (3.4 s wall, 166 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 337 blocks from the portal
PASS fortress: 2 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 8 cinder rods from 12 cinderwisps in 133 s
INFO cinder rod rate 0.67 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.67 per kill is plausible (reference 0.5)
---- void pearls (4.7 s wall, 301 s game)
PASS voidwalkers: 12 void pearls from 18 kills
---- back to the surface (6.5 s wall, 481 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (6.9 s wall, 486 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (7.1 s wall, 499 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 0 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (7.4 s wall, 501 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (7.6 s wall, 512 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 20 health so far (topped up)
---- hollow wyrm fight (7.8 s wall, 534 s game)
PASS wyrm: defeated in 69 s (3 perches, 20 sword hits, 15 arrows for 55 damage, health left 1)
INFO wyrm fight: player took 41 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 12 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (8.4 s wall, 616 s game)
PASS egg: hitting the egg makes it teleport (2 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (8.6 s wall, 636 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (8.7 s wall, 640 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (8.8 s wall, 648 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (8.9 s wall, 648 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (9.1 s wall, 704 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (11.6 s wall, 717 s game)
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
FAIL blight: defeated in 601 s (388 arrows for 37 damage, 0 sword hits)
INFO blight sight: player sees it true, player SIMD3<Float>(4722.5, 127.0, 1784.8337), blight SIMD3<Float>(4722.5, 131.98885, 1783.6143), phase 0, arena floor y 127
PASS blight: arrows bounce off its armour below half health (0 damage from 0)
INFO blight fight: player took 2120 damage (healed by the test); 0 of 0 sword hits landed for 0
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 4696 134 1775, still listed yes, stars on the ground []
INFO star lost: player at 4698.9 128.4 1773.4, alive yes, 12 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (18.8 s wall, 1352 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 24 advancements earned: adventure/ash_vault, adventure/deep, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, follow_ender_eye, form_obsidian, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (18.8 s wall, 1353 s game)
INFO deaths: 0, damage healed by the test: 2292 half-hearts
playthrough: 2 failed checks, 1353 s of game time in 18.8 s wall
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
### mobtests
![mobtests.png](mobtests.png)
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
### ruined_portal
![ruined_portal.png](ruined_portal.png)
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
