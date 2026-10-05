# Blocksmith CI snapshots (heavy lane)

Commit `c1810866835b606b9ea91ba1b566dd553c3d7c9f` on `claude/bs-vehicle-riding`: build **success**, heavy jobs **failure**
- checks: success
- perf: success
- play: failure
- shots: success
- smoke: success
- tours: success

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37245491537

```
textures without a painter: missing
textures: 1677 layers at 128 px, BC3, 35.0 MB with mips (build 875 ms, upload 297 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 69) sky 15 block 8 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=54.2 hash=11b19720764ac356
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=54.2 hash=11b19720764ac356
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 82)
gen 269 ms  mesh(all, parallel) 257 ms  mesh(1 section) 0.95 ms  quads 780530 opaque / 11893 water
frame (encode+GPU, offscreen, median of 30) 4.79 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 211 MB
memory: resident 276 MB  (section meshes 24 MB)
wrote snaps/agent_door_777.png
naming audit: 5938 names, 0 flagged
selftest: 995 blocks, 99 mob kinds, 4/4 special recipes, bundle fill 32/64, 83 advancements
selftest ok: 168 mobs after 3 s
textures without a painter: missing
textures: 1677 layers at 128 px, BC3, 35.0 MB with mips (build 882 ms, upload 288 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0003 white=0.0029 std=39.1 hash=40ded84637c6663e
imagecheck selftest.png magenta=0.00000 black=0.0003 white=0.0029 std=39.1 hash=40ded84637c6663e
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 290 ms  mesh(all, parallel) 227 ms  mesh(1 section) 0.34 ms  quads 794813 opaque / 16522 water
frame (encode+GPU, offscreen, median of 30) 6.30 ms  biome plains
mesh slabs 32 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 215 MB
memory: resident 283 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (38 pieces, framed)
textures without a painter: missing
textures: 1677 layers at 128 px, BC3, 35.0 MB with mips (build 849 ms, upload 288 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=54.1 hash=61c29076313ea951 flicker=0.00040
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=54.1 hash=61c29076313ea951 flicker=0.00040
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 300 ms  mesh(all, parallel) 444 ms  mesh(1 section) 1.26 ms  quads 1632579 opaque / 12810 water
frame (encode+GPU, offscreen, median of 30) 5.42 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 37 MB), Metal allocated 239 MB
memory: resident 311 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures without a painter: missing
textures: 1677 layers at 128 px, BC3, 35.0 MB with mips (build 904 ms, upload 295 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=50.9 hash=1de47a58863ff706 flicker=0.00010
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=50.9 hash=1de47a58863ff706 flicker=0.00010
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 329 ms  mesh(all, parallel) 325 ms  mesh(1 section) 1.34 ms  quads 1136052 opaque / 9408 water
frame (encode+GPU, offscreen, median of 30) 6.22 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 29 MB), Metal allocated 211 MB
memory: resident 285 MB  (section meshes 35 MB)
wrote snaps/flicker_forest.png
textures without a painter: missing
textures: 1677 layers at 128 px, BC3, 35.0 MB with mips (build 869 ms, upload 302 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0015 std=41.7 hash=f815321fcb21f643 flicker=0.00067
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0015 std=41.7 hash=f815321fcb21f643 flicker=0.00067
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 270 ms  mesh(all, parallel) 217 ms  mesh(1 section) 0.30 ms  quads 795026 opaque / 16522 water
frame (encode+GPU, offscreen, median of 30) 4.78 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 199 MB
memory: resident 268 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 180 frames, no flags
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 1.45 ms (min 1.36, max 1.56) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 0.29 ms/chunk
bench gen slow chunk -80,-25: 3.5 ms (plants 1.5, caves 1.0, ores 0.3; starts 0.0, place 0.1)
bench gen slow chunk 46,9: 2.0 ms (caves 0.8, columns 0.2, ores 0.2; starts 0.0, place 0.6)
bench gen slow chunk -52,-23: 1.9 ms (caves 1.0, ores 0.3, columns 0.2; starts 0.0, place 0.1)
bench gen phases (ms/chunk): columns 0.19, stone 0.14, surface 0.02, caves 0.80, ores 0.21, trees 0.03, plants 0.12, starts 0.00, structures 0.03
bench gen structure starts (ms over 24 chunks): village 3.5, pillager_outpost 2.1, mineshaft 0.8, fossil 0.4, military_base 0.4, shipwreck 0.3, ocean_ruin 0.3, desert_well 0.2
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.62 ms/chunk (p95 2.02, max 3.49) single-thread | 2182 chunks/s parallel
bench: gen took 0.5 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 2.20 ms/chunk (24 sections, 91 non-empty), section mean 92 us p95 472 us max 618 us, 4652 quads/chunk
bench mesh_lod1: 1.95 ms/chunk (24 sections, 47 non-empty), section mean 81 us p95 409 us max 713 us, 1251 quads/chunk
bench: mesh took 0.5 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 3 ms, first load (r 4) 151 ms, renderer 1777 ms (textures 647 ms, shaders 0 ms), fill rd 12 2.95 s
bench: startup took 6.7 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 0.64 ms, GPU p50 2.59 ms (max 2.71), 260 chunks drawn
bench frame 1080p rd 16: encode p50 0.68 ms, GPU p50 3.19 ms (max 4.17), 277 chunks drawn
bench frame 4k rd 16: encode p50 0.59 ms, GPU p50 4.52 ms (max 5.24), 277 chunks drawn
bench frame: 575 visible sections, 951 draw calls, 188k quads
bench: frame took 3.4 s (live worlds 1, games 0)
bench: edit starts
bench edit: break mean 0.57 ms max 0.67 ms, place mean 0.57 ms max 0.68 ms (synchronous remesh)
bench: edit took 0.7 s (live worlds 1, games 0)
bench: mobs starts
bench mobs: tick 0.23 ms empty, 0.91 ms with 150 mobs (p95 2.54, max 5.24), 208 alive
bench: mobs took 0.8 s (live worlds 1, games 0)
bench: save starts
bench save: 145 chunks, save 1.28 ms/chunk (main thread 2.7 ms total, unchanged re-save 0.9 ms), load 0.20 ms/chunk (145 ok), 5.0 KB/chunk
bench: save took 0.8 s (live worlds 1, games 0)
bench: tnt starts
bench tnt: blast mean 1.59 ms max 1.69 ms (main thread) | re-mesh done in 0.06 s, tick p95 7.45 max 7.45 ms
bench: tnt took 0.7 s (live worlds 1, games 0)
bench: fluids starts
bench fluids: tick p50 0.45 p95 2.09 max 8.40 ms, 3512 sections re-meshed in 6 s, 1316 cells still pending
bench: fluids took 6.6 s (live worlds 1, games 0)
bench: ships starts
bench ships: edit remesh 2.57 ms, blast 1.56 ms + remesh 4.38 ms (3031 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds -0.02 ms encode, 0.04 ms GPU (66 draw calls)
bench ships: docked 3070 blocks in 12.93 ms (world remesh 0.03 s), assembled 3031 in 20.09 ms
bench ships: frigate 3031 blocks spawn 1.12 ms, mesh 2.10 ms; tick 0.35 ms (p95 0.47), physics 0.13 ms; collide 0.96 us near ships, 0.23 us far; 13 ships
bench: ships took 2.0 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 997
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.28 p95 3.00 p99 4.77 max 19.49 ms, 0 hitches >25 ms | tick p95 1.25 (update p95 0.38, max 0.95) encode p95 1.25 GPU p95 2.93 ms
bench flight8: coverage min 92% mean 100% | gen 24 chunks/s (2.5 ms each on a worker) mesh 602 sections/s (149 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 34 MB, meshes 35 MB (slabs 48 MB), resident peak 236 MB, preload 383 ms
bench: flight8 took 13.8 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 3.80 p95 5.10 p99 10.79 max 19.09 ms, 0 hitches >25 ms | tick p95 2.04 (update p95 0.74, max 15.86) encode p95 2.26 GPU p95 4.64 ms
bench flight16: coverage min 96% mean 99% | gen 44 chunks/s (1.9 ms each on a worker) mesh 2377 sections/s (142 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 113 MB, meshes 75 MB (slabs 92 MB), resident peak 376 MB, preload 1445 ms
bench: flight16 took 14.9 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 6.04 p95 6.60 p99 7.18 max 20.57 ms, 0 hitches >25 ms | tick p95 3.00 (update p95 1.07, max 14.09) encode p95 2.32 GPU p95 6.58 ms
bench flight24: coverage min 95% mean 99% | gen 64 chunks/s (1.9 ms each on a worker) mesh 3769 sections/s (147 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 239 MB, meshes 128 MB (slabs 152 MB), resident peak 604 MB, preload 3023 ms
bench: flight24 took 16.6 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.669 | 1.12x |
| edit.break_ms_mean | 0.447 | 0.574 | 1.28x |
| edit.break_ms_p50 | 0.595 | 0.567 | 0.95x |
| edit.place_ms_max | 0.732 | 0.676 | 0.92x |
| edit.place_ms_mean | 0.455 | 0.573 | 1.26x |
| edit.place_ms_p50 | 0.595 | 0.567 | 0.95x |
| flight16.arena_free_mb | 0.864 | 3.762 | 4.35x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.141 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.993 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.315 | 0.44x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.71 | 0.62x ✅ better |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1210 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.232 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.913 | 0.61x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.261 | 0.96x |
| flight16.frame_ms_max | 12.652 | 19.09 | 1.51x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.799 | 0.79x |
| flight16.frame_ms_p95 | 5.8 | 5.098 | 0.88x |
| flight16.frame_ms_p99 | 7.443 | 10.79 | 1.45x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.682 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.777 | 0.79x |
| flight16.gpu_ms_p95 | 5.71 | 4.641 | 0.81x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 75.217 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2377.27 | 0.83x |
| flight16.preload_ms | 1871.23 | 1444.65 | 0.77x |
| flight16.realtime | 0.998 | 0.998 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 375.581 | 1.31x ⚠️ worse |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 16.532 | 1.93x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.834 | 2.15x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.041 | 0.98x |
| flight16.update_ms_max | 8.289 | 15.859 | 1.91x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.1 | 5.88x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.735 | 0.42x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.872 | 0.93x |
| flight16.worker_mesh_us | 177.949 | 141.768 | 0.80x |
| flight24.arena_free_mb | 0.427 | 4.387 | 10.27x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.281 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.987 | 1.01x |
| flight24.coverage_min | 0.974 | 0.953 | 1.02x |
| flight24.cull_ms_p50 | 1.198 | 0.771 | 0.64x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.075 | 0.39x ✅ better |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3021 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.202 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.699 | 0.69x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.32 | 0.44x ✅ better |
| flight24.frame_ms_max | 13.319 | 20.568 | 1.54x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.044 | 0.78x |
| flight24.frame_ms_p95 | 9.472 | 6.598 | 0.70x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 7.183 | 0.69x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 63.61 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.038 | 0.78x |
| flight24.gpu_ms_p95 | 9.428 | 6.584 | 0.70x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 128.114 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 3769.43 | 0.65x ✅ better |
| flight24.preload_ms | 4742.83 | 3022.63 | 0.64x ✅ better |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 603.597 | 1.18x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 14.585 | 1.26x |
| flight24.tick_ms_p50 | 0.401 | 1.311 | 3.27x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.995 | 1.02x |
| flight24.update_ms_max | 4.586 | 14.089 | 3.07x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.669 | 44.60x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.074 | 0.42x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.944 | 0.83x |
| flight24.worker_mesh_us | 177.947 | 147.481 | 0.83x |
| flight8.arena_free_mb | 2.438 | 5.297 | 2.17x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.995 | 0.99x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.081 | 0.40x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.216 | 0.71x ✅ better |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.137 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.453 | 0.81x |
| flight8.encode_ms_p95 | 0.832 | 1.251 | 1.50x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 19.491 | 1.47x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.281 | 0.88x |
| flight8.frame_ms_p95 | 3.197 | 3.003 | 0.94x |
| flight8.frame_ms_p99 | 4.401 | 4.771 | 1.08x |
| flight8.gen_chunks_per_s | 23.603 | 23.737 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.28 | 0.88x |
| flight8.gpu_ms_p95 | 3.081 | 2.925 | 0.95x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 34.85 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 601.514 | 0.84x |
| flight8.preload_ms | 1398.04 | 383.119 | 0.27x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 235.861 | 1.89x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 19.074 | 1.52x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.484 | 3.06x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.246 | 1.02x |
| flight8.update_ms_max | 12.421 | 0.947 | 0.08x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.006 | 0.60x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.381 | 0.44x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.469 | 0.76x ✅ better |
| flight8.worker_mesh_us | 181.115 | 148.842 | 0.82x |
| fluids.pending | 240 | 1316 | 5.48x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3512 | 1.35x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 8.401 | 2.46x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.446 | 1.97x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.093 | 1.12x |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.604 | 1.05x |
| frame.mesh_mb | 57.324 | 65.787 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 0.768 | 0.68x ✅ better |
| frame_1080p.encode_ms_p50 | 0.625 | 0.682 | 1.09x |
| frame_1080p.gpu_ms_max | 2.632 | 4.169 | 1.58x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.19 | 1.38x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 0.771 | 0.48x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.591 | 0.86x |
| frame_4k.gpu_ms_max | 4.083 | 5.238 | 1.28x |
| frame_4k.gpu_ms_p50 | 3.521 | 4.524 | 1.28x |
| frame_800p.encode_ms_max | 0.755 | 0.695 | 0.92x |
| frame_800p.encode_ms_p50 | 0.608 | 0.639 | 1.05x |
| frame_800p.gpu_ms_max | 2.405 | 2.71 | 1.13x |
| frame_800p.gpu_ms_p50 | 2.068 | 2.586 | 1.25x |
| gen.chunk_ms_max | 3.382 | 3.49 | 1.03x |
| gen.chunk_ms_mean | 2.082 | 1.619 | 0.78x |
| gen.chunk_ms_p95 | 3.325 | 2.017 | 0.61x ✅ better |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 2182.12 | 0.77x |
| gen.starts_cold_ms | – | 0.291 | new |
| gen.terrain_hash | 1238443285367868 | 4216460180825950 | ⚠️ changed |
| genphase.caves_ms | – | 0.803 | new |
| genphase.columns_ms | – | 0.188 | new |
| genphase.ores_ms | – | 0.211 | new |
| genphase.plants_ms | – | 0.121 | new |
| genphase.starts_ms | – | 0.003 | new |
| genphase.stone_ms | – | 0.144 | new |
| genphase.structures_ms | – | 0.034 | new |
| genphase.surface_ms | – | 0.023 | new |
| genphase.trees_ms | – | 0.027 | new |
| mesh.chunk_ms_max | 5.758 | 2.482 | 0.43x ✅ better |
| mesh.chunk_ms_mean | 3.347 | 2.201 | 0.66x ✅ better |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 617.981 | 0.38x ✅ better |
| mesh.section_us_mean | 139.451 | 91.696 | 0.66x ✅ better |
| mesh.section_us_p95 | 686.049 | 471.95 | 0.69x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 2.298 | 0.42x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 1.949 | 0.64x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 712.991 | 0.48x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 81.215 | 0.64x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 409.007 | 0.72x ✅ better |
| mobs.per_mob_us | 1.608 | 4.513 | 2.81x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 5.244 | 4.20x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.91 | 3.35x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.545 | 5.80x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.233 | 7.52x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.441 | 5.38x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.016 | 1.12x |
| save.chunk_ms | 2.896 | 1.282 | 0.44x ✅ better |
| save.load_chunk_ms | 0.587 | 0.202 | 0.34x ✅ better |
| save.main_thread_ms | 5.206 | 2.662 | 0.51x ✅ better |
| save.unchanged_resave_ms | 2.544 | 0.932 | 0.37x ✅ better |
| ships.assemble_ms | 19.313 | 20.093 | 1.04x |
| ships.assemble_remesh_s | 0.027 | 0.03 | 1.11x |
| ships.blast_ms | 2.675 | 1.556 | 0.58x ✅ better |
| ships.blast_remesh_ms | 5.466 | 4.382 | 0.80x |
| ships.collide_far_us | 0.214 | 0.23 | 1.07x |
| ships.collide_us | 1.047 | 0.957 | 0.91x |
| ships.dock_ms | 12.056 | 12.925 | 1.07x |
| ships.dock_remesh_s | 0.036 | 0.027 | 0.75x ✅ better |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.505 | 0.57x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.242 | 0.48x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.568 | 0.71x ✅ better |
| ships.frame_encode_ms | 0.023 | -0.025 | -1.09x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.036 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.095 | 0.68x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.132 | 0.80x |
| ships.physics_ms_p95 | 0.213 | 0.152 | 0.71x ✅ better |
| ships.spawn_frigate_ms | 2.358 | 1.12 | 0.47x ✅ better |
| ships.tick_ms_max | 0.522 | 1.841 | 3.53x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.346 | 1.58x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.47 | 1.56x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.95 | 0.68x ✅ better |
| startup.first_load_ms | 206.958 | 150.987 | 0.73x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 871.163 | 31.58x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1776.56 | 2.17x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.189 | 0.54x ✅ better |
| startup.since_launch_s | 5.923 | 7.453 | 1.26x |
| startup.textures_ms | 26.537 | 646.869 | 24.38x ⚠️ worse |
| startup.world_init_ms | 2.198 | 2.809 | 1.28x |
| tnt.blast_ms_max | 8.579 | 1.691 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.594 | 0.55x ✅ better |
| tnt.remesh_s | 0.087 | 0.06 | 0.69x ✅ better |
| tnt.tick_ms_max | 5.414 | 7.454 | 1.38x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 2.126 | 0.47x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.454 | 1.38x ⚠️ worse |
### Smoke test
```
smoke rd 8: menu tour: no help line for vol:5
smoke rd 8: menu tour: no help line for vol:6
smoke rd 8: menu tour: no help line for vol:7
smoke rd 8: menu tour: no help line for vol:8
smoke rd 8: menu tour: no help line for vol:2
smoke rd 8: menu tour: no help line for vol:3
smoke rd 8: menu tour: no help line for vol:4
smoke rd 8: menu tour: no help line for vol:5
smoke rd 8: menu tour: no help line for vol:6
smoke rd 8: menu tour: no help line for vol:7
smoke rd 8: menu tour: no help line for vol:8
smoke rd 8: menu tour: 21 screens, 197 rows hovered; 20 block screens opened
smoke rd 8 Fancy: 30 s, frame 42.4 ms, resident 304 MB, Metal 249 MB, mobs 77, coverage 100%
smoke rd 8 Fancy: 40 s, frame 20.6 ms, resident 492 MB, Metal 289 MB, mobs 121, coverage 100%
smoke rd 8 Fancy: 50 s, frame 12.2 ms, resident 726 MB, Metal 317 MB, mobs 191, coverage 94%
smoke rd 8 Fancy: 60 s, frame 23.9 ms, resident 925 MB, Metal 325 MB, mobs 99, coverage 100%
smoke rd 8: 3600 frames in 63.1 s wall, frame p50 14.28 p95 32.50 p99 63.32 max 811.60 ms, coverage min 83%, mobs max 215, travelled 3186 blocks, resident peak 916 MB, menu closed
smoke rd 8 split screen: player 2 moved 12 blocks
smoke rd 8: FAIL player 2 barely moved
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
playthrough: seed 12345
---- spawn (0.0 s wall, 0 s game)
PASS spawn: standing on solid ground (oak_leaves at y 90)
PASS spawn: not in water or lava
PASS spawn: alive and healthy
---- gather + craft (0.2 s wall, 3 s game)
PASS gather: logs mined by hand (3)
INFO bulk: +3 oak_log (more trees)
PASS craft: 24 oak_planks
PASS craft: crafting table + wooden pickaxe
---- stone age (0.4 s wall, 14 s game)
PASS hold wooden pickaxe
FAIL mine: 0 cobblestone with a wooden pickaxe (3 mined; bare hand would take 7.5 s and drop nothing)
INFO stone at 7 84 5, now air; around (up down +x -x +z -z): dirt air air stone dirt stone; drops within 24: cobblestone at 7.2 82.0 5.7
INFO cobblestone close up: delay -17.45 age 18.0 ground yes; stood at 0.00 above it, after a tick the player is 0.00 10.00 0.00 from it; alive yes, 32 free slots, picked no, menu none
INFO bulk: +11 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.7 s wall, 33 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 105 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (2.1 s wall, 105 s game)
PASS worldgen: diamond ore within 80 blocks of spawn
PASS rules: stone pickaxe can't harvest diamond ore
PASS mine: diamond with an iron pickaxe at y -59 (1, 1 ore)
INFO bulk: +4 diamond (more diamonds)
INFO bulk: +3 string (spiders)
INFO bulk: +4 flint (gravel)
INFO bulk: +4 feather (chickens)
PASS craft: diamond pickaxe, sword, bow, 16 arrows
INFO bulk: +19 diamond (more diamonds)
INFO bulk: +5 gold_ingot (gold ore)
PASS armour: 19 armour points worn
---- obsidian + portal (2.2 s wall, 107 s game)
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (3.0 s wall, 130 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 138 blocks from the portal
PASS fortress: 4 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 11 cinderwisps in 207 s
INFO cinder rod rate 0.64 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.64 per kill is plausible (reference 0.5)
---- void pearls (5.3 s wall, 339 s game)
PASS voidwalkers: 12 void pearls from 18 kills
---- back to the surface (6.9 s wall, 435 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (7.1 s wall, 440 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (7.2 s wall, 448 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 3 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (7.4 s wall, 449 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (7.6 s wall, 460 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 105 health so far (topped up)
---- hollow wyrm fight (7.8 s wall, 483 s game)
PASS wyrm: defeated in 177 s (3 perches, 53 sword hits, 19 arrows for 39 damage, health left 1)
INFO wyrm fight: player took 207 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 13 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (9.4 s wall, 673 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (9.4 s wall, 679 s game)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (9.5 s wall, 683 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (9.6 s wall, 690 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (9.7 s wall, 690 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (9.8 s wall, 746 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (15.1 s wall, 760 s game)
INFO bulk: Smite V on the sword, Power V on the bow
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
PASS blight: defeated in 33 s (14 arrows for 158 damage, 8 sword hits)
PASS blight: arrows bounce off its armour below half health (0 damage from 3)
INFO blight fight: player took 91 damage (healed by the test); 8 of 8 sword hits landed for 154
PASS blight: the Blight Star drops and is picked up (1)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (16.0 s wall, 814 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 21 advancements earned: adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, form_obsidian, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (16.0 s wall, 815 s game)
INFO deaths: 0, damage healed by the test: 436 half-hearts
playthrough: 1 failed checks, 815 s of game time in 16.0 s wall
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
### volcano_far_nolod
![volcano_far_nolod.png](volcano_far_nolod.png)
### volcano_horizon
![volcano_horizon.png](volcano_horizon.png)
### volcano_horizon_night
![volcano_horizon_night.png](volcano_horizon_night.png)
### water_flow
![water_flow.png](water_flow.png)
