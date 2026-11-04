# Blocksmith CI snapshots (heavy lane)

Commit `b0a2f516a54a706e71e8495dfa1a5f62787747c2` on `claude/project-thread-ddeimn`: build **success**, heavy jobs **failure**
- checks: failure
- perf: failure
- play: failure
- shots: failure
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41755745269

```
mesh slabs 28 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 174 MB
memory: resident 258 MB  (section meshes 23 MB)
wrote snaps/leak_12345.png
textures: 2032 layers at 128 px, BC3, 42.4 MB with mips (build 619 ms, upload 289 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 69) sky 15 block 0 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=46.1 hash=0fa1dac7c631ce30
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=46.1 hash=0fa1dac7c631ce30
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 1851 ms  mesh(all, parallel) 288 ms  mesh(1 section) 0.24 ms  quads 638278 opaque / 1596 water
frame (encode+GPU, offscreen, median of 30) 3.78 ms  biome plains
mesh slabs 24 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 182 MB
memory: resident 256 MB  (section meshes 20 MB)
wrote snaps/agent_door_777.png
naming audit: 7927 names, 0 flagged
selftest: 1397 blocks, 123 mob kinds, 4/4 special recipes, bundle fill 32/64, 105 advancements
selftest ok: 121 mobs after 3 s
textures: 2032 layers at 128 px, BC3, 42.4 MB with mips (build 613 ms, upload 286 ms)
target: tall_grass[upper] at -88 136 103, boxes [(SIMD3<Float>(0.125, 0.0, 0.125), SIMD3<Float>(0.875, 0.8125, 0.875))], feet SIMD3<Float>(-87.5, 135.0, 104.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in short_grass, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0003 white=0.0356 std=55.7 hash=a134934bf41a09b5
imagecheck selftest.png magenta=0.00000 black=0.0004 white=0.0356 std=55.7 hash=a134934bf41a09b5
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 322  (drawn 78)
gen 4206 ms  mesh(all, parallel) 288 ms  mesh(1 section) 0.27 ms  quads 708590 opaque / 7118 water
frame (encode+GPU, offscreen, median of 30) 6.67 ms  biome plains
mesh slabs 28 MB, chunks 322 (block+light arrays 30 MB), Metal allocated 202 MB
memory: resident 328 MB  (section meshes 23 MB)
wrote snaps/selftest.png
structure village at -274 71 -1042 (35 pieces, framed)
textures: 2032 layers at 128 px, BC3, 42.4 MB with mips (build 716 ms, upload 327 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 71) sky 15 block 0 in snow, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=70.9 hash=9b3735f323a1e8b4 flicker=0.00071
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=70.9 hash=9b3735f323a1e8b4 flicker=0.00071
seed 12345  pos -326.5 166.0 -1088.5  rd 8  chunks 297  (drawn 72)
gen 4677 ms  mesh(all, parallel) 454 ms  mesh(1 section) 0.95 ms  quads 1159839 opaque / 1245 water
frame (encode+GPU, offscreen, median of 30) 5.02 ms  biome taiga
mesh slabs 40 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 198 MB
memory: resident 288 MB  (section meshes 35 MB)
wrote snaps/flicker_village.png
textures: 2032 layers at 128 px, BC3, 42.4 MB with mips (build 617 ms, upload 290 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 90) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=59.2 hash=10f4054dbf4dad59 flicker=0.00007
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=59.2 hash=10f4054dbf4dad59 flicker=0.00007
seed 12345  pos -135.5 176.0 -39.5  rd 8  chunks 297  (drawn 81)
gen 5665 ms  mesh(all, parallel) 366 ms  mesh(1 section) 1.16 ms  quads 1088514 opaque / 280 water
frame (encode+GPU, offscreen, median of 30) 6.51 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 31 MB), Metal allocated 186 MB
memory: resident 272 MB  (section meshes 33 MB)
wrote snaps/flicker_forest.png
textures: 2032 layers at 128 px, BC3, 42.4 MB with mips (build 616 ms, upload 286 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in short_grass, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0014 std=46.4 hash=4c530026b5f24dd9 flicker=0.00020
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0014 std=46.4 hash=4c530026b5f24dd9 flicker=0.00020
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 4318 ms  mesh(all, parallel) 292 ms  mesh(1 section) 0.34 ms  quads 708795 opaque / 7124 water
frame (encode+GPU, offscreen, median of 30) 4.72 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 186 MB
memory: resident 253 MB  (section meshes 22 MB)
wrote snaps/flicker_build.png
imagecheck: 200 frames, no flags
snap.sh: 5 failing line(s): 379 382 383 385 393
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.02 ms (min 1.48, max 2.94) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 0.86 ms/chunk
bench gen slow chunk -80,-25: 1272.6 ms (trees 30.8, caves 0.8, ores 0.6; starts 2533.0, place 1239.8)
bench gen slow chunk -24,-21: 261.2 ms (caves 0.8, trees 0.6, ores 0.4; starts 783.0, place 258.7)
bench gen slow chunk -73,-12: 36.9 ms (starts 9.5, plants 2.5, caves 2.1; starts 42.5, place 20.6)
bench gen phases (ms/chunk): columns 0.25, stone 0.24, surface 0.03, caves 0.93, ores 0.35, trees 2.47, plants 0.23, starts 0.60, structures 63.67
bench gen structure starts (ms over 24 chunks): military_base 962.2, capital_city 788.1, village 693.1, greywall_base 211.5, wild_camp 193.8, pillager_outpost 152.1, frontier_site 129.8, temple 126.2
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 68.88 ms/chunk (p95 261.24, max 1272.63) single-thread | 162 chunks/s parallel
bench: gen took 2.9 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 6.32 ms/chunk (24 sections, 81 non-empty), section mean 263 us p95 1028 us max 2341 us, 4430 quads/chunk
bench mesh_lod1: 5.63 ms/chunk (24 sections, 80 non-empty), section mean 234 us p95 908 us max 1290 us, 2359 quads/chunk
bench: mesh took 2.3 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 61 ms, first load (r 4) 667 ms, renderer 2435 ms (textures 809 ms, shaders 0 ms), fill rd 12 5.16 s
bench: startup took 10.7 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 1.25 ms, GPU p50 3.76 ms (max 7.27), 260 chunks drawn
bench frame 1080p rd 16: encode p50 1.15 ms, GPU p50 5.03 ms (max 5.24), 270 chunks drawn
bench frame 4k rd 16: encode p50 1.19 ms, GPU p50 6.95 ms (max 12.25), 270 chunks drawn
bench frame: 719 visible sections, 1316 draw calls, 207k quads
bench: frame took 5.5 s (live worlds 1, games 0)
bench: edit starts
bench edit: break mean 1.06 ms max 2.35 ms, place mean 1.06 ms max 2.26 ms (synchronous remesh)
bench: edit took 1.4 s (live worlds 1, games 0)
bench: mobs starts
bench mobs: tick 0.10 ms empty, 0.69 ms with 150 mobs (p95 1.73, max 2.75), 153 alive
bench: mobs took 1.5 s (live worlds 1, games 0)
bench: save starts
bench save: 145 chunks, save 1.86 ms/chunk (main thread 6.0 ms total, unchanged re-save 2.1 ms), load 0.20 ms/chunk (145 ok), 7.0 KB/chunk
bench: save took 2.9 s (live worlds 1, games 0)
bench: tnt starts
bench tnt: blast mean 1.13 ms max 3.39 ms (main thread) | re-mesh done in 0.37 s, tick p95 1.19 max 1.19 ms
bench: tnt took 1.6 s (live worlds 1, games 0)
bench: fluids starts
bench fluids: tick p50 0.21 p95 0.72 max 2.75 ms, 1892 sections re-meshed in 6 s, 26 cells still pending
bench: fluids took 7.3 s (live worlds 2, games 0)
bench: ships starts
bench ships: edit remesh 3.73 ms, blast 5.07 ms + remesh 7.43 ms (3040 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.05 ms encode, 0.16 ms GPU (68 draw calls)
bench ships: docked 3090 blocks in 26.48 ms (world remesh 0.14 s), assembled 3066 in 64.64 ms
bench ships: frigate 3040 blocks spawn 1.37 ms, mesh 2.94 ms; tick 0.41 ms (p95 1.01), physics 0.24 ms; collide 1.11 us near ships, 0.25 us far; 11 ships
bench: ships took 3.4 s (live worlds 2, games 0)
bench: worlds still alive after the scenes: 2
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 193
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 997
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.24 p95 2.99 p99 5.70 max 14.31 ms, 0 hitches >25 ms | tick p95 1.02 (update p95 0.50, max 2.13) encode p95 0.84 GPU p95 2.93 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.4 ms each on a worker) mesh 615 sections/s (252 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 26 MB, meshes 20 MB (slabs 32 MB), resident peak 225 MB, preload 1096 ms
bench: flight8 took 15.6 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 3.57 p95 4.33 p99 5.68 max 61.00 ms, 2 hitches >25 ms | tick p95 1.63 (update p95 1.23, max 13.70) encode p95 2.64 GPU p95 4.21 ms
bench flight16: coverage min 96% mean 99% | gen 82 chunks/s (2.6 ms each on a worker) mesh 2109 sections/s (202 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 63 MB, meshes 35 MB (slabs 52 MB), resident peak 320 MB, preload 2947 ms
bench: flight16 took 18.0 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 5.69 p95 8.34 p99 12.31 max 80.49 ms, 2 hitches >25 ms | tick p95 2.07 (update p95 1.63, max 52.05) encode p95 6.00 GPU p95 6.73 ms
bench flight24: coverage min 97% mean 99% | gen 109 chunks/s (2.8 ms each on a worker) mesh 2552 sections/s (215 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 73 MB, meshes 62 MB (slabs 76 MB), resident peak 519 MB, preload 5867 ms
bench: flight24 took 21.4 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.353 | 3.92x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.06 | 2.37x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 1.055 | 1.77x ⚠️ worse |
| edit.place_ms_max | 0.732 | 2.257 | 3.08x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.056 | 2.32x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 1.029 | 1.73x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 11.654 | 13.49x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 62.586 | 0.60x ✅ better |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.988 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.46 | 0.65x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 1.128 | 0.98x |
| flight16.cull_walked_sections | 2817 | 1836 | 0.65x ✅ better |
| flight16.draw_calls | 1434 | 989 | 0.69x ✅ better |
| flight16.drawn_kquads | 475.516 | 119.771 | 0.25x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.078 | 0.72x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.641 | 1.12x |
| flight16.frame_ms_max | 12.652 | 60.997 | 4.82x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.566 | 0.74x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 4.326 | 0.75x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 5.679 | 0.76x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 81.582 | 0.54x ✅ better |
| flight16.gpu_ms_p50 | 4.804 | 3.549 | 0.74x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.215 | 0.74x ✅ better |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 34.843 | 0.43x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 2108.57 | 0.94x |
| flight16.preload_ms | 1871.23 | 2947.32 | 1.58x ⚠️ worse |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 320.112 | 1.12x |
| flight16.slab_mb | 96 | 52 | 0.54x ✅ better |
| flight16.tick_ms_max | 8.551 | 58.954 | 6.89x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.407 | 1.05x |
| flight16.tick_ms_p95 | 2.08 | 1.63 | 0.78x |
| flight16.update_ms_max | 8.289 | 13.703 | 1.65x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.157 | 9.24x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.232 | 0.71x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.604 | 1.29x |
| flight16.worker_mesh_us | 177.949 | 201.901 | 1.13x |
| flight24.arena_free_mb | 0.427 | 4.419 | 10.35x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 72.898 | 0.33x ✅ better |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.991 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 1.351 | 1.13x |
| flight24.cull_ms_p95 | 2.767 | 3.207 | 1.16x |
| flight24.cull_walked_sections | 7607 | 5485 | 0.72x ✅ better |
| flight24.draw_calls | 3175 | 2559 | 0.81x |
| flight24.drawn_kquads | 821.704 | 264.131 | 0.32x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.503 | 1.01x |
| flight24.encode_ms_p95 | 5.237 | 6.003 | 1.15x |
| flight24.frame_ms_max | 13.319 | 80.488 | 6.04x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 5.695 | 0.74x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 8.337 | 0.88x |
| flight24.frame_ms_p99 | 10.337 | 12.313 | 1.19x |
| flight24.gen_chunks_per_s | 63.73 | 108.955 | 0.58x ✅ better |
| flight24.gpu_ms_p50 | 7.718 | 5.292 | 0.69x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.734 | 0.71x ✅ better |
| flight24.hitches | 0 | 2 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 62.116 | 0.47x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 2551.84 | 0.96x |
| flight24.preload_ms | 4742.83 | 5866.59 | 1.24x |
| flight24.realtime | 1 | 0.996 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 519.409 | 1.01x |
| flight24.slab_mb | 148 | 76 | 0.51x ✅ better |
| flight24.tick_ms_max | 11.61 | 62.131 | 5.35x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.623 | 1.55x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.073 | 0.70x ✅ better |
| flight24.update_ms_max | 4.586 | 52.052 | 11.35x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.317 | 21.13x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.634 | 0.64x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.831 | 1.20x |
| flight24.worker_mesh_us | 177.947 | 215.177 | 1.21x |
| flight8.arena_free_mb | 2.438 | 7.324 | 3.00x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.992 | 0.86x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.087 | 0.43x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.169 | 0.55x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 335 | 0.72x ✅ better |
| flight8.drawn_kquads | 211.463 | 78.865 | 0.37x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.497 | 0.88x |
| flight8.encode_ms_p95 | 0.832 | 0.836 | 1.00x |
| flight8.frame_ms_max | 13.232 | 14.307 | 1.08x |
| flight8.frame_ms_p50 | 2.588 | 2.243 | 0.87x |
| flight8.frame_ms_p95 | 3.197 | 2.986 | 0.93x |
| flight8.frame_ms_p99 | 4.401 | 5.696 | 1.29x |
| flight8.gen_chunks_per_s | 23.603 | 23.679 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.242 | 0.87x |
| flight8.gpu_ms_p95 | 3.081 | 2.935 | 0.95x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 20.229 | 0.49x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 615.401 | 0.82x |
| flight8.preload_ms | 1398.04 | 1096.18 | 0.78x |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 224.752 | 1.80x ⚠️ worse |
| flight8.slab_mb | 52 | 32 | 0.62x ✅ better |
| flight8.tick_ms_max | 12.539 | 9.096 | 0.73x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.3 | 1.90x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.016 | 0.83x |
| flight8.update_ms_max | 12.421 | 2.131 | 0.17x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.016 | 1.60x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.5 | 0.58x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.361 | 0.73x ✅ better |
| flight8.worker_mesh_us | 181.115 | 251.747 | 1.39x ⚠️ worse |
| fluids.pending | 240 | 26 | 0.11x ✅ better |
| fluids.remeshed_sections | 2605 | 1892 | 0.73x ✅ better |
| fluids.tick_ms_max | 3.42 | 2.754 | 0.81x |
| fluids.tick_ms_p50 | 0.226 | 0.206 | 0.91x |
| fluids.tick_ms_p95 | 1.872 | 0.723 | 0.39x ✅ better |
| frame.draw_calls | 1076 | 1316 | 1.22x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 207.513 | 1.16x |
| frame.mesh_mb | 57.324 | 43.345 | 0.76x ✅ better |
| frame.visible_sections | 686 | 719 | 1.05x |
| frame_1080p.encode_ms_max | 1.123 | 3.078 | 2.74x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.146 | 1.83x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.237 | 1.99x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 5.027 | 2.18x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.987 | 1.86x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.191 | 1.72x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 12.246 | 3.00x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.953 | 1.97x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.87 | 5.13x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.248 | 2.05x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 7.268 | 3.02x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.762 | 1.82x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 1272.63 | 376.30x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 68.878 | 33.08x ❌ regression |
| gen.chunk_ms_p95 | 3.325 | 261.24 | 78.57x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 161.639 | 10.41x ⚠️ worse |
| gen.starts_cold_ms | – | 0.864 | new |
| gen.terrain_hash | 1238443285367868 | 163195936105986 | ⚠️ changed |
| genphase.caves_ms | – | 0.932 | new |
| genphase.columns_ms | – | 0.254 | new |
| genphase.ores_ms | – | 0.35 | new |
| genphase.plants_ms | – | 0.231 | new |
| genphase.starts_ms | – | 0.604 | new |
| genphase.stone_ms | – | 0.244 | new |
| genphase.structures_ms | – | 63.674 | new |
| genphase.surface_ms | – | 0.03 | new |
| genphase.trees_ms | – | 2.467 | new |
| mesh.chunk_ms_max | 5.758 | 8.775 | 1.52x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 6.323 | 1.44x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4430.11 | 0.89x |
| mesh.section_us_max | 1621.01 | 2341.03 | 1.44x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 263.441 | 1.89x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1028.06 | 1.50x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 7.602 | 1.40x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.625 | 1.37x ⚠️ worse |
| mesh_lod1.quads_per_chunk | 2535 | 2359.33 | 0.93x |
| mesh_lod1.section_us_max | 1477.96 | 1290.08 | 0.87x |
| mesh_lod1.section_us_mean | 126.754 | 234.388 | 1.85x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 908.017 | 1.60x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 3.98 | 2.48x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.751 | 2.20x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.694 | 2.55x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.729 | 3.94x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.097 | 3.13x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.186 | 2.27x ⚠️ worse |
| save.chunk_kb | 4.471 | 7.015 | 1.57x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.864 | 0.64x ✅ better |
| save.load_chunk_ms | 0.587 | 0.196 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 6.042 | 1.16x |
| save.unchanged_resave_ms | 2.544 | 2.147 | 0.84x |
| ships.assemble_ms | 19.313 | 64.637 | 3.35x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.04 | 1.48x ⚠️ worse |
| ships.blast_ms | 2.675 | 5.068 | 1.89x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 7.433 | 1.36x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.252 | 1.18x |
| ships.collide_us | 1.047 | 1.107 | 1.06x |
| ships.dock_ms | 12.056 | 26.48 | 2.20x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.144 | 4.00x ⚠️ worse |
| ships.draw_calls | 66 | 68 | 1.03x |
| ships.edit_ms_max | 0.887 | 1.006 | 1.13x |
| ships.edit_ms_mean | 0.505 | 0.384 | 0.76x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.731 | 1.02x |
| ships.frame_encode_ms | 0.023 | 0.053 | 2.30x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.158 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.935 | 0.96x |
| ships.physics_ms_mean | 0.165 | 0.236 | 1.43x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.604 | 2.84x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.372 | 0.58x ✅ better |
| ships.tick_ms_max | 0.522 | 3.844 | 7.36x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.413 | 1.89x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.008 | 3.34x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 5.16 | 1.19x |
| startup.first_load_ms | 206.958 | 667.063 | 3.22x ⚠️ worse |
| startup.renderer_init_again_ms | 27.582 | 1151.7 | 41.76x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2434.82 | 2.98x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.334 | 0.96x |
| startup.since_launch_s | 5.923 | 15.637 | 2.64x ⚠️ worse |
| startup.textures_ms | 26.537 | 808.66 | 30.47x ⚠️ worse |
| startup.world_init_ms | 2.198 | 60.597 | 27.57x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.388 | 0.39x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.134 | 0.39x ✅ better |
| tnt.remesh_s | 0.087 | 0.368 | 4.23x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 1.19 | 0.22x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.537 | 0.12x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.187 | 0.22x ✅ better |

**Regressions past the CI gate:**

- gen.chunk_ms_mean: 2.082 -> 68.878 (33.08x worse, 33.08x for runner speed, gate 1.6x)
### Smoke test
```
smoke rd 8 mob drawing: mobs 38 (8 within 32), 9900 vertices written, 9900 drawn via Fancy buffer, 41 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 412, loaded 412; stashed mobs 0; map cells 2365; block entities 3; gravity queue 0; fluid pending 21; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4721.8 124.6 1685.3 ground no water yes menu none
smoke rd 8 Fancy: 40 s, frame 11.9 ms, resident 389 MB, Metal 272 MB, mobs 21, coverage 93%
smoke rd 8 mob drawing: mobs 21 (0 within 32), 5040 vertices written, 5040 drawn via Fancy buffer, 10 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 664, loaded 662; stashed mobs 39; map cells 13629; block entities 5; gravity queue 0; fluid pending 0; jobs 16; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4735.3 121.0 1668.5 ground yes water yes menu none
smoke rd 8 Fancy: 50 s, frame 13.1 ms, resident 394 MB, Metal 272 MB, mobs 47, coverage 93%
smoke rd 8 mob drawing: mobs 47 (0 within 32), 8388 vertices written, 8388 drawn via Fancy buffer, 28 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 663, loaded 663; stashed mobs 107; map cells 25097; block entities 22; gravity queue 0; fluid pending 0; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4748.7 119.0 1651.9 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 12.6 ms, resident 387 MB, Metal 272 MB, mobs 13, coverage 100%
smoke rd 8 mob drawing: mobs 13 (0 within 32), 5040 vertices written, 5040 drawn via Fancy buffer, 6 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 668, loaded 668; stashed mobs 196; map cells 36524; block entities 37; gravity queue 0; fluid pending 0; jobs 1; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 771 ms at 0.0 s (frame 0): Game.tick 23 ms, render + GPU 748 ms; frames over 100 ms: 2
smoke rd 8: 3600 frames in 60.0 s wall, frame p50 11.36 p95 18.85 p99 35.21 max 770.95 ms, coverage min 85%, mobs max 49, travelled 3222 blocks, resident peak 395 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 133 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (39.7 s wall, 1533 s game)
INFO field aim at 7 123 8 (built layer air, density 5): eye 8.50 123.63 8.50 (field -0.72) meets 7 123 8 (field at 7.56 123.51 8.50, t 0.95)
INFO field aim at 1 123 12 (built layer air, density 5): eye 2.50 123.63 12.50 (field -0.70) meets 1 123 12 (field at 1.56 123.51 12.50, t 0.95)
INFO field aim at -12 123 20 (built layer air, density 5): eye -10.50 123.63 20.50 (field -0.67) meets -12 123 20 (field at -11.90 123.45 20.50, t 1.41)
INFO field aim at 2 123 27 (built layer air, density 5): eye 3.50 123.63 27.50 (field -0.71) meets 2 123 27 (field at 2.56 123.51 27.50, t 0.95)
INFO field aim at 5 123 30 (built layer air, density 5): eye 6.50 123.63 30.50 (field -0.69) meets 5 123 30 (field at 5.56 123.51 30.50, t 0.95)
INFO field aim at 0 123 29 (built layer air, density 5): eye 1.50 123.63 29.50 (field -0.70) meets 0 123 29 (field at 0.56 123.51 29.50, t 0.95)
INFO field aim at -1 122 43 (built layer air, density 4): eye 0.50 122.63 43.50 (field -0.67) meets -1 122 43 (field at -1.00 122.44 43.50, t 1.51)
INFO field aim at 9 122 31 (built layer air, density 5): eye 10.50 122.63 31.50 (field -0.60) meets 9 122 31 (field at 9.57 122.51 31.50, t 0.94)
INFO field aim at 21 123 39 (built layer air, density 2): eye 21.50 123.63 40.50 (field -0.41) meets 21 123 39 (field at 21.50 123.44 39.00, t 1.51)
INFO field aim at 25 123 25 (built layer air, density 5): eye 26.50 123.63 25.50 (field -0.71) meets 25 123 25 (field at 25.56 123.51 25.50, t 0.95)
PASS egg: hitting the egg makes it teleport (20 hops)
FAIL egg: collected by dropping it onto a torch (0)
INFO egg: last attempt: egg at 25 59 25 on torch over end_stone: no torch spot
INFO bulk: +1 dragon_egg (egg)
---- rift (41.9 s wall, 1629 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (42.0 s wall, 1633 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has a jetpack
PASS jetpack: 3 s of jump held lifts the player 19 blocks off the spire
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (43.2 s wall, 1638 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (43.5 s wall, 1638 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (44.6 s wall, 1696 s game)
PASS blight: retired, nothing summons it (P292)
INFO bulk: +1 nether_star (a Brand Commander's star)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Brand Star
---- deep: through the floor (44.6 s wall, 1696 s game)
INFO bulk: +1 netherite_pickaxe (Duskium gear)
INFO bulk: +1 netherite_sword (Duskium gear)
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
INFO bulk: dug a shaft 124 blocks down to the Wardstone floor
PASS deep: the bottom of the surface is Wardstone (wardstone)
INFO field aim at 4709 2 1763 (built layer air, density 8): eye 4710.50 2.63 1763.50 (field -0.48) meets 4709 2 1763 (field at 4709.92 2.55 1763.50, t 0.59)
INFO field mine at 4709 2 1763: on target 80 of 80 ticks, body moved up to 0.00 in a tick, progress 0.00, no other target
PASS deep: a Duskium pickaxe can't break the Wardstone
INFO bulk: +1 ember_charge (a base's command chest)
PASS deep: an Ember Charge blows the floor and the player drops into the Deep (charge set true, Bottom of the World)
---- deep: the hell band (58.9 s wall, 1704 s game)
INFO field aim at 4709 380 1763 (built layer air, density 5): eye 4710.50 380.63 1763.50 (field -0.59) meets 4709 380 1763 (field at 4709.56 380.51 1763.50, t 0.95)
INFO field aim at 4709 379 1763 (built layer air, density 5): eye 4710.50 379.63 1763.50 (field -0.60) meets 4709 379 1763 (field at 4709.56 379.51 1763.50, t 0.95)
INFO field aim at 4709 378 1763 (built layer air, density 5): eye 4710.50 378.63 1763.50 (field -0.62) meets 4709 378 1763 (field at 4709.56 378.51 1763.50, t 0.95)
INFO field aim at 4709 377 1763 (built layer air, density 5): eye 4710.50 377.63 1763.50 (field -0.62) meets 4709 377 1763 (field at 4709.56 377.51 1763.50, t 0.95)
INFO field aim at 4709 376 1763 (built layer air, density 5): eye 4710.50 376.63 1763.50 (field -0.62) meets 4709 376 1763 (field at 4709.56 376.51 1763.50, t 0.95)
INFO dug 5 blocks of crust
PASS deep: in the hell band (Under the Fire Sky)
PASS deep: the compass points to a Brimstone Keep 499 blocks off
INFO bulk: rode 499 blocks across the hell band to the keep
---- deep: the Castellan (59.4 s wall, 1712 s game)
INFO bulk: fought through 16 of the keep's guards to the strongroom
PASS deep: the Castellan falls to the sword (30 swings, 21 s)
PASS deep: Castellan's Fall: the Ember Gate wakes (true) and the Gate Shard is picked up (1)
---- deep: Sunderite (60.7 s wall, 1737 s game)
INFO field aim at 5206 226 1796 (built layer sunderite_ore, density -127): eye 5207.50 226.63 1796.50 (field -3.97) meets 5206 226 1796
INFO field aim at 5212 226 1797 (built layer sunderite_ore, density -127): eye 5213.50 226.63 1797.50 (field -3.97) meets 5212 226 1797
INFO field aim at 5206 229 1794 (built layer sunderite_ore, density -127): eye 5206.50 229.63 1795.50 (field -3.97) meets 5206 229 1794
INFO field aim at 5214 229 1798 (built layer sunderite_ore, density -127): eye 5213.50 229.63 1798.50 (field -3.97) meets 5214 229 1798
PASS deep: Sunderite Ore mined from the strongroom walls (4 ore, 4 Raw Sunderite)
INFO bulk: +4 raw_sunderite (the rest of the strongroom's ore and its chest)
INFO bulk: +2 blaze_rod (cinderwisps)
PASS deep: Raw Sunderite and Cinder Powder make Sunderite Flux (4)
INFO bulk: +1 blast_furnace (iron and smooth stone)
PASS deep: Sunderite Flux smelts only in a blast furnace
INFO bulk: +2 coal (fuel)
PASS deep: the blast furnace makes 4 Sunderite Ingots in 20 s
INFO bulk: +1 tnt (gunpowder and sand)
PASS deep: a Sunderite Pickaxe and a Sunder Charge crafted
---- deep: through the seal (61.6 s wall, 1790 s game)
INFO bulk: dug down to the Sealrock beside the keep, walled off from the lava
PASS deep: the hell band's floor is Sealrock (sealrock)
INFO field aim at 5249 199 1801 (built layer air, density 8): eye 5250.50 199.63 1801.50 (field -0.59) meets 5249 199 1801 (field at 5249.87 199.55 1801.50, t 0.64)
INFO field mine at 5249 199 1801: on target 100 of 100 ticks, body moved up to 0.00 in a tick, progress 0.00, no other target
PASS deep: a Duskium pickaxe can't break Sealrock
PASS deep: the Sunder Charge blows a shaft through the seal and the player drops through (aim sealrock at 5248,199,1800, menu none, held air, toast 'The Ember Gate in the courtyard wakes'; feet at 191, seal 192...199)
INFO field aim at 5248 190 1800 (built layer air, density 5): eye 5249.50 190.63 1800.50 (field -0.60) meets 5248 190 1800 (field at 5248.56 190.51 1800.50, t 0.95)
INFO field aim at 5248 189 1800 (built layer air, density 5): eye 5249.50 189.63 1800.50 (field -0.60) meets 5248 189 1800 (field at 5248.56 189.51 1800.50, t 0.95)
INFO field aim at 5248 188 1800 (built layer air, density 5): eye 5249.50 188.63 1800.50 (field -0.62) meets 5248 188 1800 (field at 5248.56 188.51 1800.50, t 0.95)
INFO field aim at 5248 187 1800 (built layer air, density 5): eye 5249.50 187.63 1800.50 (field -0.62) meets 5248 187 1800 (field at 5248.56 187.51 1800.50, t 0.95)
INFO field aim at 5248 186 1800 (built layer air, density 5): eye 5249.50 186.63 1800.50 (field -0.62) meets 5248 186 1800 (field at 5248.56 186.51 1800.50, t 0.95)
INFO field aim at 5248 185 1800 (built layer air, density 5): eye 5247.50 185.63 1800.50 (field -0.60) meets 5250 185 1800 (field at 5250.25 185.27 1800.50, t 2.77)
INFO field mine at 5248 185 1800: on target 0 of 160 ticks, body moved up to 0.00 in a tick, progress 0.00, other target 5253 184 1800 (air)
INFO dug 5 blocks of the lower crust
INFO bulk: the rest of the lower crust; out under the vault roof
PASS deep: down into the Ash Vault (landed true, 0 damage on the way down)
---- deep: the Marshal (65.1 s wall, 1815 s game)
INFO bulk: crossed 5547 blocks of the vault to the citadel
INFO bulk: fought through the Marshal's Guard (55 units)
PASS deep: the Ash Marshal falls to the sword (51 swings, 36 s)
PASS deep: the Marshal's fall starts the last battle (stage 1)
---- deep: the last battle (67.5 s wall, 1855 s game)
FAIL deep: wave 1, their reserve infantry and half-tracks, comes in (0 units)
INFO bulk: the rest of wave 1 (0 units)
INFO died (You were shot by Ashguard Stormer) at -12 -37 1 in deep; worst frame since the last death -20, armour 0
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
INFO died (You were shot by Ashguard Rifleman) at -12 -37 6 in deep; worst frame since the last death -26, armour 19
FAIL deep: wave 2, their last tank company, comes in (0 units)
INFO bulk: the rest of wave 2 (0 units)
INFO died (You were shot by Ashguard Officer) at -15 -40 9 in deep; worst frame since the last death -20, armour 0
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
PASS deep: wave 3, the Behemoth, comes in (6 units)
INFO bulk: +1 netherite_sword (a spare sword, the last one was lost on a death)
INFO wave 3: an Ashguard soldier fought hand to hand (13 swings, down true, health left -2, 2.0 blocks off)
INFO bulk: the rest of wave 3 (5 units)
FAIL deep: the last army beaten, the blast door in the command bunker opens (0/9)
---- deep: the Chancellor (73.7 s wall, 1961 s game)
INFO bulk: down the bunker stairs
FAIL deep: the Ash Chancellor waits in his study
---- advancements (74.2 s wall, 1966 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
INFO 32 advancements earned: adventure/ash_vault, adventure/brand_parry, adventure/break_seal, adventure/break_ward, adventure/deep, adventure/deep_hell, adventure/keep_warden, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, adventure/steelhold_gun, adventure/sunderite, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, form_obsidian, goal/furnace, goal/wood, iron_tools, nether/find_fortress, nether/obtain_blaze_rod, nether/root, root, shiny_gear, smelt_iron, spine/intro, spine/iron_set, upgrade_tools
INFO goals in order: wood 0s, root 6s, pickaxe 23s, smelt_iron 42s, spine/iron_set 107s, spine/find_town 113s, adventure/deep_hell 135s, adventure/keep_warden 1710s, adventure/break_seal 1736s, adventure/ash_vault 1798s, adventure/ash_victory 1814s
PASS first hour: the next goal only moves forward along the path (11 goals seen, 0 steps back)
FAIL first hour: the run ends with the path walked to the Capital stage (last goal adventure/ash_victory)
---- summary (74.2 s wall, 1967 s game)
INFO deaths: 3, damage healed by the test: 17513 half-hearts
playthrough: 14 failed checks, 1967 s of game time in 74.2 s wall
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
### atlas_4
![atlas_4.png](atlas_4.png)
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
### basetest_lockdown
![basetest_lockdown.png](basetest_lockdown.png)
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
### capital_city
![capital_city.png](capital_city.png)
### capital_street
![capital_street.png](capital_street.png)
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
### issue_10
![issue_10.png](issue_10.png)
### issue_2
![issue_2.png](issue_2.png)
### issue_3
![issue_3.png](issue_3.png)
### issue_4
![issue_4.png](issue_4.png)
### issue_5
![issue_5.png](issue_5.png)
### issue_6
![issue_6.png](issue_6.png)
### issue_7
![issue_7.png](issue_7.png)
### issue_8
![issue_8.png](issue_8.png)
### issue_9
![issue_9.png](issue_9.png)
### jungle_temple
![jungle_temple.png](jungle_temple.png)
### lake
![lake.png](lake.png)
### lake_glint
![lake_glint.png](lake_glint.png)
### leak_12345
![leak_12345.png](leak_12345.png)
### lily_pond
![lily_pond.png](lily_pond.png)
### lily_pond_777
![lily_pond_777.png](lily_pond_777.png)
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
### powderwight
![powderwight.png](powderwight.png)
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
