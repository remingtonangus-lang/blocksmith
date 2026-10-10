# Blocksmith CI snapshots (heavy lane)

Commit `177237a70ad0d4d1216cb721a823cb5b0eb836c9` on `claude/project-thread-j7cbv2`: build **success**, heavy jobs **failure**
- checks: failure
- perf: success
- play: failure
- shots: failure
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38089113969

```
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 171 MB
memory: resident 249 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 529 ms, upload 248 ms)
target: spruce_planks at 959 139 274, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(959.5, 138.0, 272.5)
light probe: eye sky 15 block 1 in air; floor+1 (y 69) sky 15 block 5 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 220 ms  mesh(all, parallel) 227 ms  mesh(1 section) 0.79 ms  quads 752871 opaque / 417 water
frame (encode+GPU, offscreen, median of 30) 3.81 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 252 MB  (section meshes 23 MB)
wrote snaps/agent_door_777.png
naming audit: 6745 names, 0 flagged
selftest: 1206 blocks, 104 mob kinds, 4/4 special recipes, bundle fill 32/64, 89 advancements
selftest ok: 111 mobs after 3 s
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 515 ms, upload 243 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0008 std=16.9 hash=6ec292dcbe0e136b
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0008 std=16.9 hash=6ec292dcbe0e136b
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 260 ms  mesh(all, parallel) 198 ms  mesh(1 section) 0.21 ms  quads 800253 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 4.88 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 266 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (35 pieces, framed)
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 510 ms, upload 242 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=59.0 hash=10dc683227825c37 flicker=0.00015
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=59.0 hash=10dc683227825c37 flicker=0.00015
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 286 ms  mesh(all, parallel) 372 ms  mesh(1 section) 0.64 ms  quads 1643402 opaque / 70 water
frame (encode+GPU, offscreen, median of 30) 3.67 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 38 MB), Metal allocated 207 MB
memory: resident 300 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 514 ms, upload 244 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 250 ms  mesh(all, parallel) 247 ms  mesh(1 section) 0.72 ms  quads 1169814 opaque / 73 water
frame (encode+GPU, offscreen, median of 30) 4.42 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 30 MB), Metal allocated 179 MB
memory: resident 253 MB  (section meshes 36 MB)
wrote snaps/flicker_forest.png
textures: 1721 layers at 128 px, BC3, 35.9 MB with mips (build 514 ms, upload 245 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 254 ms  mesh(all, parallel) 194 ms  mesh(1 section) 0.26 ms  quads 800454 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 4.03 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 167 MB
memory: resident 242 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 201 frames, no flags
snap.sh: 2 failing line(s): 424 424
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.29 ms (min 1.37, max 4.28) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 2.66 ms/chunk
bench gen slow chunk -80,-25: 5.1 ms (plants 2.4, caves 1.3, stone 0.4; starts 0.0, place 0.4)
bench gen slow chunk -59,14: 4.8 ms (caves 0.7, ores 0.4, columns 0.2; starts 0.0, place 3.2)
bench gen slow chunk 81,24: 3.3 ms (caves 1.2, columns 0.9, stone 0.7; starts 0.0, place 0.1)
bench gen phases (ms/chunk): columns 0.26, stone 0.19, surface 0.03, caves 0.83, ores 0.22, trees 0.04, plants 0.22, starts 0.01, structures 0.18
bench gen structure starts (ms over 24 chunks): capital_city 52.8, wild_camp 41.8, military_base 39.2, boreal_station 32.9, village 17.5, temple 5.2, mansion 4.5, trail_ruins 2.1
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 2.05 ms/chunk (p95 4.84, max 5.12) single-thread | 936 chunks/s parallel
bench: gen took 0.8 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 4.97 ms/chunk (24 sections, 81 non-empty), section mean 207 us p95 871 us max 1195 us, 4942 quads/chunk
bench mesh_lod1: 4.49 ms/chunk (24 sections, 81 non-empty), section mean 187 us p95 768 us max 1504 us, 2498 quads/chunk
bench: mesh took 0.7 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 22 ms, first load (r 4) 230 ms, renderer 2404 ms (textures 605 ms, shaders 0 ms), fill rd 12 2.81 s
bench: startup took 7.4 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 0.90 ms, GPU p50 4.47 ms (max 4.74), 258 chunks drawn
bench frame 1080p rd 16: encode p50 1.12 ms, GPU p50 5.21 ms (max 6.42), 270 chunks drawn
bench frame 4k rd 16: encode p50 1.59 ms, GPU p50 8.03 ms (max 11.48), 270 chunks drawn
bench frame: 697 visible sections, 1216 draw calls, 235k quads
bench: frame took 5.0 s (live worlds 0, games 0)
bench: edit starts
bench edit: break mean 1.02 ms max 2.20 ms, place mean 1.00 ms max 1.89 ms (synchronous remesh)
bench: edit took 0.9 s (live worlds 0, games 0)
bench: mobs starts
bench mobs: tick 0.27 ms empty, 0.70 ms with 150 mobs (p95 1.81, max 3.11), 158 alive
bench: mobs took 1.0 s (live worlds 0, games 0)
bench: save starts
bench save: 145 chunks, save 2.66 ms/chunk (main thread 32.2 ms total, unchanged re-save 1.9 ms), load 0.30 ms/chunk (145 ok), 6.2 KB/chunk
bench: save took 1.1 s (live worlds 0, games 0)
bench: tnt starts
bench tnt: blast mean 1.51 ms max 3.76 ms (main thread) | re-mesh done in 0.06 s, tick p95 7.99 max 7.99 ms
bench: tnt took 0.9 s (live worlds 0, games 0)
bench: fluids starts
bench fluids: tick p50 0.44 p95 1.84 max 11.46 ms, 6753 sections re-meshed in 6 s, 1284 cells still pending
bench: fluids took 6.7 s (live worlds 0, games 0)
bench: ships starts
bench ships: edit remesh 3.08 ms, blast 2.27 ms + remesh 10.23 ms (3037 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds -0.79 ms encode, -0.01 ms GPU (66 draw calls)
bench ships: docked 3077 blocks in 18.78 ms (world remesh 0.06 s), assembled 3057 in 12.72 ms
bench ships: frigate 3037 blocks spawn 11.15 ms, mesh 5.94 ms; tick 0.51 ms (p95 1.24), physics 0.21 ms; collide 1.38 us near ships, 0.72 us far; 13 ships
bench: ships took 3.0 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.55 p95 4.38 p99 7.79 max 10.76 ms, 0 hitches >25 ms | tick p95 1.26 (update p95 0.59, max 2.24) encode p95 1.11 GPU p95 4.15 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.3 ms each on a worker) mesh 958 sections/s (274 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 25 MB, meshes 24 MB (slabs 40 MB), resident peak 198 MB, preload 661 ms
bench: flight8 took 14.8 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 3.60 p95 5.05 p99 8.09 max 15.14 ms, 0 hitches >25 ms | tick p95 2.02 (update p95 0.98, max 2.24) encode p95 2.33 GPU p95 4.86 ms
bench flight16: coverage min 79% mean 89% | gen 44 chunks/s (2.3 ms each on a worker) mesh 3503 sections/s (261 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 86 MB, meshes 46 MB (slabs 68 MB), resident peak 321 MB, preload 1903 ms
bench: flight16 took 15.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 4.59 p95 7.83 p99 13.40 max 40.40 ms, 3 hitches >25 ms | tick p95 3.04 (update p95 1.29, max 8.20) encode p95 4.55 GPU p95 6.58 ms
bench flight24: coverage min 74% mean 83% | gen 23 chunks/s (2.5 ms each on a worker) mesh 3501 sections/s (339 us each) | realtime 1.00x
bench flight24: 1691 chunks, chunk data 145 MB, meshes 67 MB (slabs 96 MB), resident peak 492 MB, preload 4284 ms
bench: flight24 took 18.4 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.204 | 3.67x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.021 | 2.28x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.727 | 1.22x |
| edit.place_ms_max | 0.732 | 1.889 | 2.58x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.998 | 2.19x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.71 | 1.19x |
| flight16.arena_free_mb | 0.864 | 15.052 | 17.42x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.855 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.895 | 1.11x |
| flight16.coverage_min | 0.962 | 0.786 | 1.22x |
| flight16.cull_ms_p50 | 0.708 | 0.347 | 0.49x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.98 | 0.85x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.86 | 0.58x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.327 | 0.99x |
| flight16.frame_ms_max | 12.652 | 15.143 | 1.20x |
| flight16.frame_ms_p50 | 4.807 | 3.602 | 0.75x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.048 | 0.87x |
| flight16.frame_ms_p99 | 7.443 | 8.085 | 1.09x |
| flight16.gen_chunks_per_s | 43.68 | 43.549 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.561 | 0.74x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.856 | 0.85x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.228 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3502.99 | 0.56x ✅ better |
| flight16.preload_ms | 1871.23 | 1902.98 | 1.02x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 320.893 | 1.12x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 9.192 | 1.07x |
| flight16.tick_ms_p50 | 0.388 | 0.627 | 1.62x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.023 | 0.97x |
| flight16.update_ms_max | 8.289 | 2.241 | 0.27x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.298 | 17.53x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.979 | 0.56x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.28 | 1.13x |
| flight16.worker_mesh_us | 177.949 | 261.421 | 1.47x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 20.429 | 47.84x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 144.502 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1691 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.834 | 1.19x |
| flight24.coverage_min | 0.974 | 0.738 | 1.32x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.818 | 0.68x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.264 | 0.82x |
| flight24.cull_walked_sections | 7607 | 3786 | 0.50x ✅ better |
| flight24.draw_calls | 3175 | 1158 | 0.36x ✅ better |
| flight24.drawn_kquads | 821.704 | 215.935 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.673 | 0.68x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.551 | 0.87x |
| flight24.frame_ms_max | 13.319 | 40.4 | 3.03x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.591 | 0.59x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 7.825 | 0.83x |
| flight24.frame_ms_p99 | 10.337 | 13.399 | 1.30x |
| flight24.gen_chunks_per_s | 63.73 | 23.332 | 2.73x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.504 | 0.58x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.58 | 0.70x ✅ better |
| flight24.hitches | 0 | 3 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 66.909 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3500.58 | 0.70x ✅ better |
| flight24.preload_ms | 4742.83 | 4283.54 | 0.90x |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 491.831 | 0.96x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 17.494 | 1.51x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.83 | 2.07x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.041 | 1.03x |
| flight24.update_ms_max | 4.586 | 8.203 | 1.79x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.4 | 26.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.294 | 0.51x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.465 | 1.05x |
| flight24.worker_mesh_us | 177.947 | 339.287 | 1.91x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.761 | 4.41x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.083 | 0.41x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.252 | 0.83x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.419 | 0.75x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 1.113 | 1.34x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 10.756 | 0.81x |
| flight8.frame_ms_p50 | 2.588 | 2.549 | 0.98x |
| flight8.frame_ms_p95 | 3.197 | 4.377 | 1.37x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 7.791 | 1.77x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.741 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.532 | 0.98x |
| flight8.gpu_ms_p95 | 3.081 | 4.149 | 1.35x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 957.642 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 660.532 | 0.47x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 198.049 | 1.59x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 8.544 | 0.68x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.39 | 2.47x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.258 | 1.03x |
| flight8.update_ms_max | 12.421 | 2.236 | 0.18x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.005 | 0.50x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.59 | 0.68x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.296 | 0.71x ✅ better |
| flight8.worker_mesh_us | 181.115 | 274.24 | 1.51x ⚠️ worse |
| fluids.pending | 240 | 1284 | 5.35x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6753 | 2.59x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 11.457 | 3.35x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.436 | 1.93x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.841 | 0.98x |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.313 | 2.06x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.125 | 1.80x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 6.421 | 2.44x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 5.212 | 2.26x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 4.305 | 2.69x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.588 | 2.30x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 11.482 | 2.81x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 8.033 | 2.28x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.134 | 2.83x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.9 | 1.48x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.743 | 1.97x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.475 | 2.16x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 5.123 | 1.51x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.052 | 0.99x |
| gen.chunk_ms_p95 | 3.325 | 4.84 | 1.46x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 936.431 | 1.80x ⚠️ worse |
| gen.starts_cold_ms | – | 2.661 | new |
| gen.terrain_hash | 1238443285367868 | 2072315357721602 | ⚠️ changed |
| genphase.caves_ms | – | 0.827 | new |
| genphase.columns_ms | – | 0.264 | new |
| genphase.ores_ms | – | 0.217 | new |
| genphase.plants_ms | – | 0.218 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.189 | new |
| genphase.structures_ms | – | 0.18 | new |
| genphase.surface_ms | – | 0.026 | new |
| genphase.trees_ms | – | 0.043 | new |
| mesh.chunk_ms_max | 5.758 | 6.631 | 1.15x |
| mesh.chunk_ms_mean | 4.38 | 4.974 | 1.14x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1194.95 | 0.74x ✅ better |
| mesh.section_us_mean | 139.451 | 207.254 | 1.49x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 870.943 | 1.27x |
| mesh_lod1.chunk_ms_max | 5.44 | 5.442 | 1.00x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.494 | 1.10x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1503.94 | 1.02x |
| mesh_lod1.section_us_mean | 126.754 | 187.266 | 1.48x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 768.065 | 1.35x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 2.867 | 1.78x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 3.11 | 2.49x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.7 | 2.57x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.805 | 4.11x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.27 | 8.71x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.091 | 13.30x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.659 | 0.92x |
| save.load_chunk_ms | 0.587 | 0.304 | 0.52x ✅ better |
| save.main_thread_ms | 5.206 | 32.222 | 6.19x ⚠️ worse |
| save.unchanged_resave_ms | 2.544 | 1.89 | 0.74x ✅ better |
| ships.assemble_ms | 19.313 | 12.724 | 0.66x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.017 | 0.63x ✅ better |
| ships.blast_ms | 2.675 | 2.272 | 0.85x |
| ships.blast_remesh_ms | 5.466 | 10.23 | 1.87x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.72 | 3.36x ⚠️ worse |
| ships.collide_us | 1.047 | 1.375 | 1.31x ⚠️ worse |
| ships.dock_ms | 12.056 | 18.784 | 1.56x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.062 | 1.72x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.539 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.291 | 0.58x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.085 | 0.85x |
| ships.frame_encode_ms | 0.023 | -0.787 | -34.22x ✅ better |
| ships.frame_gpu_ms | -0.228 | -0.011 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 5.937 | 1.94x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.213 | 1.29x |
| ships.physics_ms_p95 | 0.213 | 0.501 | 2.35x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 11.153 | 4.73x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 14.402 | 27.59x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.511 | 2.33x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.242 | 4.11x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.813 | 0.65x ✅ better |
| startup.first_load_ms | 206.958 | 230.422 | 1.11x |
| startup.renderer_init_again_ms | 27.582 | 1038.04 | 37.63x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2404.37 | 2.94x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.407 | 1.17x |
| startup.since_launch_s | 5.923 | 8.74 | 1.48x ⚠️ worse |
| startup.textures_ms | 26.537 | 605.25 | 22.81x ⚠️ worse |
| startup.world_init_ms | 2.198 | 21.721 | 9.88x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.762 | 0.44x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.509 | 0.52x ✅ better |
| tnt.remesh_s | 0.087 | 0.06 | 0.69x ✅ better |
| tnt.tick_ms_max | 5.414 | 7.99 | 1.48x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 2.605 | 0.58x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.99 | 1.48x ⚠️ worse |
### Smoke test
```
smoke rd 8 mob drawing: mobs 15 (0 within 32), 2484 vertices written, 2484 drawn via Fancy buffer, 20 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 439, loaded 439; stashed mobs 1; map cells 2511; block entities 39; gravity queue 0; fluid pending 135; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4724.1 122.0 1673.8 ground yes water yes menu none
smoke rd 8 Fancy: 40 s, frame 17.0 ms, resident 370 MB, Metal 273 MB, mobs 21, coverage 95%
smoke rd 8 mob drawing: mobs 21 (0 within 32), 4284 vertices written, 4284 drawn via Fancy buffer, 13 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 658, loaded 658; stashed mobs 25; map cells 13738; block entities 138; gravity queue 0; fluid pending 319; jobs 14; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4737.6 119.6 1657.2 ground no water yes menu none
smoke rd 8 Fancy: 50 s, frame 11.2 ms, resident 395 MB, Metal 281 MB, mobs 35, coverage 93%
smoke rd 8 mob drawing: mobs 35 (0 within 32), 8568 vertices written, 8568 drawn via Fancy buffer, 22 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 669, loaded 669; stashed mobs 136; map cells 25162; block entities 291; gravity queue 0; fluid pending 401; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4750.9 118.0 1640.7 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 44.3 ms, resident 383 MB, Metal 281 MB, mobs 10, coverage 93%
smoke rd 8 mob drawing: mobs 10 (0 within 32), 1692 vertices written, 1692 drawn via Fancy buffer, 6 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 663, loaded 663; stashed mobs 217; map cells 36617; block entities 426; gravity queue 0; fluid pending 88; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 681 ms at 0.0 s (frame 0): Game.tick 4 ms, render + GPU 677 ms; frames over 100 ms: 2
smoke rd 8: 3600 frames in 60.1 s wall, frame p50 10.79 p95 19.42 p99 34.65 max 681.46 ms, coverage min 68%, mobs max 63, travelled 3218 blocks, resident peak 399 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 143 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
INFO bulk: +9 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.5 s wall, 28 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 100 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (1.4 s wall, 101 s game)
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
---- obsidian + portal (1.9 s wall, 103 s game)
INFO fell into deep while mining; back to the surface
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (2.5 s wall, 125 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 337 blocks from the portal
PASS fortress: 2 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 15 cinderwisps in 294 s
INFO cinder rod rate 0.47 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.47 per kill is plausible (reference 0.5)
---- void pearls (5.0 s wall, 421 s game)
PASS voidwalkers: 12 void pearls from 19 kills
---- back to the surface (5.8 s wall, 514 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (6.0 s wall, 519 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (6.0 s wall, 528 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 0 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (6.3 s wall, 529 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (6.4 s wall, 540 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 211 health so far (topped up)
---- hollow wyrm fight (6.6 s wall, 563 s game)
PASS wyrm: defeated in 148 s (3 perches, 21 sword hits, 22 arrows for 54 damage, health left 1)
INFO wyrm fight: player took 96 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 13 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (7.5 s wall, 724 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (7.5 s wall, 730 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (7.6 s wall, 734 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (7.7 s wall, 741 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (7.8 s wall, 741 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (7.9 s wall, 797 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (9.8 s wall, 811 s game)
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
FAIL blight: defeated in 601 s (388 arrows for 38 damage, 0 sword hits)
INFO blight sight: player sees it true, player SIMD3<Float>(4722.5, 127.0, 1784.8337), blight SIMD3<Float>(4722.5, 131.98885, 1783.6143), phase 0, arena floor y 127
PASS blight: arrows bounce off its armour below half health (0 damage from 0)
INFO blight fight: player took 2160 damage (healed by the test); 0 of 0 sword hits landed for 0
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 4722 132 1784, still listed yes, stars on the ground []
INFO star lost: player at 4722.4 127.0 1785.0, alive yes, 15 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (15.6 s wall, 1414 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 23 advancements earned: adventure/ash_vault, adventure/deep, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, form_obsidian, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (15.6 s wall, 1415 s game)
INFO deaths: 0, damage healed by the test: 2534 half-hearts
playthrough: 2 failed checks, 1415 s of game time in 15.6 s wall
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
