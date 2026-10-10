# Blocksmith CI snapshots (heavy lane)

Commit `d93af332c3d7659ccc9ce60c6151ad165b81c39c` on `claude/project-thread-dkuflx`: build **success**, heavy jobs **failure**
- checks: failure
- perf: failure
- play: failure
- shots: failure
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38090345636

```
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 171 MB
memory: resident 242 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1722 layers at 128 px, BC3, 35.9 MB with mips (build 608 ms, upload 273 ms)
target: spruce_planks at 959 139 274, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(959.5, 138.0, 272.5)
light probe: eye sky 15 block 1 in air; floor+1 (y 69) sky 15 block 5 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
imagecheck agent_door_777.png magenta=0.00000 black=0.0001 white=0.0008 std=16.1 hash=7a651d5e1919e4dc
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 289 ms  mesh(all, parallel) 282 ms  mesh(1 section) 1.32 ms  quads 753963 opaque / 417 water
frame (encode+GPU, offscreen, median of 30) 4.34 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 256 MB  (section meshes 23 MB)
wrote snaps/agent_door_777.png
naming audit: 6746 names, 0 flagged
selftest: 1206 blocks, 104 mob kinds, 4/4 special recipes, bundle fill 32/64, 89 advancements
selftest ok: 108 mobs after 3 s
textures: 1722 layers at 128 px, BC3, 35.9 MB with mips (build 537 ms, upload 262 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0008 std=29.0 hash=0f066f61027b3e82
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0008 std=29.0 hash=0f066f61027b3e82
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 303 ms  mesh(all, parallel) 220 ms  mesh(1 section) 0.22 ms  quads 800253 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 5.03 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 179 MB
memory: resident 254 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (35 pieces, framed)
textures: 1722 layers at 128 px, BC3, 35.9 MB with mips (build 515 ms, upload 249 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=59.0 hash=10dc683227825c37 flicker=0.00015
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=59.0 hash=10dc683227825c37 flicker=0.00015
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 330 ms  mesh(all, parallel) 402 ms  mesh(1 section) 0.76 ms  quads 1644210 opaque / 70 water
frame (encode+GPU, offscreen, median of 30) 4.12 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 38 MB), Metal allocated 207 MB
memory: resident 295 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1722 layers at 128 px, BC3, 35.9 MB with mips (build 678 ms, upload 313 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=54.6 hash=0794fbd1a2a2e9d2 flicker=0.00003
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 264 ms  mesh(all, parallel) 268 ms  mesh(1 section) 0.90 ms  quads 1169814 opaque / 73 water
frame (encode+GPU, offscreen, median of 30) 5.02 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 30 MB), Metal allocated 179 MB
memory: resident 257 MB  (section meshes 36 MB)
wrote snaps/flicker_forest.png
textures: 1722 layers at 128 px, BC3, 35.9 MB with mips (build 607 ms, upload 279 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=41.2 hash=38a7bb975c4d4979 flicker=0.00007
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 295 ms  mesh(all, parallel) 272 ms  mesh(1 section) 0.36 ms  quads 800454 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 4.07 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 167 MB
memory: resident 241 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 202 frames, no flags
snap.sh: 1 failing line(s): 424
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.01 ms (min 1.39, max 2.13) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 3.09 ms/chunk
bench gen slow chunk -59,14: 8.0 ms (caves 0.9, ores 0.3, columns 0.2; starts 0.0, place 6.2)
bench gen slow chunk -24,-21: 5.3 ms (caves 2.5, ores 0.9, columns 0.5; starts 0.0, place 0.4)
bench gen slow chunk -17,-8: 5.1 ms (caves 2.7, columns 0.6, ores 0.5; starts 0.0, place 0.3)
bench gen phases (ms/chunk): columns 0.33, stone 0.22, surface 0.04, caves 1.22, ores 0.31, trees 0.06, plants 0.25, starts 0.01, structures 0.30
bench gen structure starts (ms over 24 chunks): capital_city 61.7, boreal_station 49.8, wild_camp 44.3, military_base 43.2, village 17.1, mansion 6.3, temple 4.7, trail_ruins 2.6
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 2.86 ms/chunk (p95 5.30, max 8.04) single-thread | 996 chunks/s parallel
bench: gen took 0.9 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 4.55 ms/chunk (24 sections, 81 non-empty), section mean 190 us p95 772 us max 1901 us, 4942 quads/chunk
bench mesh_lod1: 4.70 ms/chunk (24 sections, 81 non-empty), section mean 196 us p95 779 us max 1574 us, 2498 quads/chunk
bench: mesh took 0.8 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 15 ms, first load (r 4) 181 ms, renderer 2605 ms (textures 582 ms, shaders 0 ms), fill rd 12 4.47 s
bench: startup took 9.4 s (live worlds 1, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 0.84 ms, GPU p50 4.29 ms (max 5.61), 258 chunks drawn
bench frame 1080p rd 16: encode p50 0.91 ms, GPU p50 5.00 ms (max 9.61), 270 chunks drawn
bench frame 4k rd 16: encode p50 1.41 ms, GPU p50 7.41 ms (max 9.42), 270 chunks drawn
bench frame: 697 visible sections, 1216 draw calls, 235k quads
bench: frame took 5.1 s (live worlds 1, games 0)
bench: edit starts
bench edit: break mean 1.05 ms max 1.88 ms, place mean 1.04 ms max 1.84 ms (synchronous remesh)
bench: edit took 1.0 s (live worlds 1, games 0)
bench: mobs starts
bench mobs: tick 0.40 ms empty, 0.55 ms with 150 mobs (p95 1.40, max 2.92), 159 alive
bench: mobs took 1.1 s (live worlds 1, games 0)
bench: save starts
bench save: 145 chunks, save 1.96 ms/chunk (main thread 3.9 ms total, unchanged re-save 1.9 ms), load 0.28 ms/chunk (145 ok), 6.2 KB/chunk
bench: save took 1.1 s (live worlds 1, games 0)
bench: tnt starts
bench tnt: blast mean 1.61 ms max 3.39 ms (main thread) | re-mesh done in 0.09 s, tick p95 1.54 max 1.54 ms
bench: tnt took 1.0 s (live worlds 2, games 0)
bench: fluids starts
bench fluids: tick p50 0.40 p95 2.24 max 19.84 ms, 6448 sections re-meshed in 6 s, 1283 cells still pending
bench: fluids took 6.9 s (live worlds 2, games 0)
bench: ships starts
bench ships: edit remesh 3.72 ms, blast 5.35 ms + remesh 4.15 ms (3033 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.23 ms encode, 0.15 ms GPU (66 draw calls)
bench ships: docked 3073 blocks in 14.94 ms (world remesh 0.10 s), assembled 3053 in 44.35 ms
bench ships: frigate 3033 blocks spawn 4.53 ms, mesh 4.58 ms; tick 0.92 ms (p95 2.75), physics 0.36 ms; collide 0.96 us near ships, 0.24 us far; 13 ships
bench: ships took 3.4 s (live worlds 2, games 0)
bench: worlds still alive after the scenes: 2
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 593
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 193
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.61 p95 3.56 p99 5.88 max 11.90 ms, 0 hitches >25 ms | tick p95 1.61 (update p95 0.63, max 6.18) encode p95 1.66 GPU p95 3.43 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.9 ms each on a worker) mesh 940 sections/s (305 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 25 MB, meshes 24 MB (slabs 40 MB), resident peak 208 MB, preload 696 ms
bench: flight8 took 14.8 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 2.93 p95 3.62 p99 4.22 max 8.42 ms, 0 hitches >25 ms | tick p95 1.39 (update p95 0.58, max 1.35) encode p95 1.22 GPU p95 3.59 ms
bench flight16: coverage min 73% mean 85% | gen 43 chunks/s (1.9 ms each on a worker) mesh 3189 sections/s (219 us each) | realtime 1.00x
bench flight16: 1052 chunks, chunk data 86 MB, meshes 46 MB (slabs 68 MB), resident peak 350 MB, preload 1995 ms
bench: flight16 took 15.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 4.27 p95 5.75 p99 6.84 max 10.82 ms, 0 hitches >25 ms | tick p95 2.23 (update p95 1.01, max 3.24) encode p95 3.03 GPU p95 5.26 ms
bench flight24: coverage min 73% mean 83% | gen 23 chunks/s (2.1 ms each on a worker) mesh 3315 sections/s (281 us each) | realtime 1.00x
bench flight24: 1684 chunks, chunk data 144 MB, meshes 67 MB (slabs 96 MB), resident peak 536 MB, preload 3366 ms
bench: flight24 took 17.1 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.876 | 3.13x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.05 | 2.35x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.825 | 1.39x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.844 | 2.52x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.035 | 2.27x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.786 | 1.32x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 14.755 | 17.08x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.852 | 1.16x |
| flight16.coverage_min | 0.962 | 0.731 | 1.32x ⚠️ worse |
| flight16.cull_ms_p50 | 0.708 | 0.287 | 0.41x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.468 | 0.41x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.7 | 0.47x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.223 | 0.52x ✅ better |
| flight16.frame_ms_max | 12.652 | 8.421 | 0.67x ✅ better |
| flight16.frame_ms_p50 | 4.807 | 2.929 | 0.61x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 3.62 | 0.62x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 4.218 | 0.57x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 43.222 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 2.927 | 0.61x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 3.59 | 0.63x ✅ better |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.421 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3188.89 | 0.62x ✅ better |
| flight16.preload_ms | 1871.23 | 1995.06 | 1.07x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 349.971 | 1.22x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 7.551 | 0.88x |
| flight16.tick_ms_p50 | 0.388 | 0.452 | 1.16x |
| flight16.tick_ms_p95 | 2.08 | 1.393 | 0.67x ✅ better |
| flight16.update_ms_max | 8.289 | 1.353 | 0.16x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.165 | 9.71x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.58 | 0.33x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.892 | 0.94x |
| flight16.worker_mesh_us | 177.949 | 218.81 | 1.23x |
| flight24.arena_free_mb | 0.427 | 20.323 | 47.59x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 143.955 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1684 | 0.77x |
| flight24.coverage_mean | 0.994 | 0.831 | 1.20x |
| flight24.coverage_min | 0.974 | 0.73 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.624 | 0.52x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.548 | 0.56x ✅ better |
| flight24.cull_walked_sections | 7607 | 3786 | 0.50x ✅ better |
| flight24.draw_calls | 3175 | 1158 | 0.36x ✅ better |
| flight24.drawn_kquads | 821.704 | 215.935 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.235 | 0.50x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 3.032 | 0.58x ✅ better |
| flight24.frame_ms_max | 13.319 | 10.821 | 0.81x |
| flight24.frame_ms_p50 | 7.72 | 4.274 | 0.55x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.752 | 0.61x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 6.842 | 0.66x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 23.411 | 2.72x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.231 | 0.55x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.259 | 0.56x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 66.797 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3315.07 | 0.74x ✅ better |
| flight24.preload_ms | 4742.83 | 3366.07 | 0.71x ✅ better |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 536.003 | 1.05x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 8.932 | 0.77x ✅ better |
| flight24.tick_ms_p50 | 0.401 | 0.625 | 1.56x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.226 | 0.76x ✅ better |
| flight24.update_ms_max | 4.586 | 3.242 | 0.71x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.281 | 18.73x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.008 | 0.40x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.108 | 0.90x |
| flight24.worker_mesh_us | 177.947 | 280.621 | 1.58x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.958 | 4.49x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.167 | 0.82x |
| flight8.cull_ms_p95 | 0.305 | 0.332 | 1.09x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.828 | 1.47x ⚠️ worse |
| flight8.encode_ms_p95 | 0.832 | 1.663 | 2.00x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 11.896 | 0.90x |
| flight8.frame_ms_p50 | 2.588 | 2.607 | 1.01x |
| flight8.frame_ms_p95 | 3.197 | 3.559 | 1.11x |
| flight8.frame_ms_p99 | 4.401 | 5.879 | 1.34x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.686 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.592 | 1.01x |
| flight8.gpu_ms_p95 | 3.081 | 3.429 | 1.11x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 940.377 | 0.54x ✅ better |
| flight8.preload_ms | 1398.04 | 695.762 | 0.50x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 207.94 | 1.67x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 11.523 | 0.92x |
| flight8.tick_ms_p50 | 0.158 | 0.484 | 3.06x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.607 | 1.31x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 6.183 | 0.50x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.043 | 4.30x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.625 | 0.72x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.888 | 0.89x |
| flight8.worker_mesh_us | 181.115 | 305.398 | 1.69x ⚠️ worse |
| fluids.pending | 240 | 1283 | 5.35x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6448 | 2.48x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 19.842 | 5.80x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.402 | 1.78x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.239 | 1.20x |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 4.042 | 3.60x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.908 | 1.45x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 9.607 | 3.65x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.996 | 2.16x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.33 | 1.45x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.414 | 2.05x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 9.416 | 2.31x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.407 | 2.10x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.624 | 3.48x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.839 | 1.38x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 5.61 | 2.33x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.287 | 2.07x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 8.038 | 2.38x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.857 | 1.37x ⚠️ worse |
| gen.chunk_ms_p95 | 3.325 | 5.304 | 1.60x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 996.418 | 1.69x ⚠️ worse |
| gen.starts_cold_ms | – | 3.089 | new |
| gen.terrain_hash | 1238443285367868 | 2072315357721602 | ⚠️ changed |
| genphase.caves_ms | – | 1.222 | new |
| genphase.columns_ms | – | 0.331 | new |
| genphase.ores_ms | – | 0.314 | new |
| genphase.plants_ms | – | 0.254 | new |
| genphase.starts_ms | – | 0.012 | new |
| genphase.stone_ms | – | 0.217 | new |
| genphase.structures_ms | – | 0.302 | new |
| genphase.surface_ms | – | 0.035 | new |
| genphase.trees_ms | – | 0.062 | new |
| mesh.chunk_ms_max | 5.758 | 6.953 | 1.21x |
| mesh.chunk_ms_mean | 4.38 | 4.551 | 1.04x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1901.03 | 1.17x |
| mesh.section_us_mean | 139.451 | 189.611 | 1.36x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 771.999 | 1.13x |
| mesh_lod1.chunk_ms_max | 5.44 | 7.248 | 1.33x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.704 | 1.15x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1574.04 | 1.07x |
| mesh_lod1.section_us_mean | 126.754 | 196.003 | 1.55x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 778.913 | 1.37x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.029 | 0.64x ✅ better |
| mobs.tick_150_ms_max | 1.25 | 2.916 | 2.33x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.553 | 2.03x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.398 | 3.18x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.398 | 12.84x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.087 | 13.26x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.957 | 0.68x ✅ better |
| save.load_chunk_ms | 0.587 | 0.277 | 0.47x ✅ better |
| save.main_thread_ms | 5.206 | 3.946 | 0.76x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.92 | 0.75x ✅ better |
| ships.assemble_ms | 19.313 | 44.352 | 2.30x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.046 | 1.70x ⚠️ worse |
| ships.blast_ms | 2.675 | 5.353 | 2.00x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 4.147 | 0.76x ✅ better |
| ships.collide_far_us | 0.214 | 0.236 | 1.10x |
| ships.collide_us | 1.047 | 0.965 | 0.92x |
| ships.dock_ms | 12.056 | 14.935 | 1.24x |
| ships.dock_remesh_s | 0.036 | 0.1 | 2.78x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 1.316 | 1.48x ⚠️ worse |
| ships.edit_ms_mean | 0.505 | 0.47 | 0.93x |
| ships.edit_remesh_ms | 3.642 | 3.723 | 1.02x |
| ships.frame_encode_ms | 0.023 | 0.233 | 10.13x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.152 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.579 | 1.49x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.36 | 2.18x ❌ regression |
| ships.physics_ms_p95 | 0.213 | 1.04 | 4.88x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 4.533 | 1.92x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 10.972 | 21.02x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.919 | 4.20x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 2.752 | 9.11x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.469 | 1.03x |
| startup.first_load_ms | 206.958 | 180.883 | 0.87x |
| startup.renderer_init_again_ms | 27.582 | 1151.27 | 41.74x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2604.8 | 3.19x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.271 | 0.78x |
| startup.since_launch_s | 5.923 | 10.812 | 1.83x ⚠️ worse |
| startup.textures_ms | 26.537 | 582.241 | 21.94x ⚠️ worse |
| startup.world_init_ms | 2.198 | 15.381 | 7.00x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.394 | 0.40x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.61 | 0.55x ✅ better |
| tnt.remesh_s | 0.087 | 0.093 | 1.07x |
| tnt.tick_ms_max | 5.414 | 1.539 | 0.28x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.898 | 0.20x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.539 | 0.28x ✅ better |

**Regressions past the CI gate:**

- ships.physics_ms_mean: 0.165 -> 0.36 (2.18x worse, 2.18x for runner speed, gate 2.0x)
### Smoke test
```
smoke rd 8 mob drawing: mobs 38 (11 within 32), 7200 vertices written, 7200 drawn via Fancy buffer, 43 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 439, loaded 439; stashed mobs 1; map cells 2511; block entities 39; gravity queue 0; fluid pending 123; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4724.1 122.0 1673.8 ground yes water yes menu none
smoke rd 8 Fancy: 40 s, frame 14.8 ms, resident 378 MB, Metal 273 MB, mobs 35, coverage 96%
smoke rd 8 mob drawing: mobs 35 (0 within 32), 6696 vertices written, 6696 drawn via Fancy buffer, 16 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 666, loaded 666; stashed mobs 30; map cells 13738; block entities 136; gravity queue 0; fluid pending 336; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4737.6 119.6 1657.2 ground no water yes menu none
smoke rd 8 Fancy: 50 s, frame 12.2 ms, resident 397 MB, Metal 281 MB, mobs 43, coverage 93%
smoke rd 8 mob drawing: mobs 43 (0 within 32), 7452 vertices written, 7452 drawn via Fancy buffer, 23 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 669, loaded 669; stashed mobs 153; map cells 25162; block entities 298; gravity queue 0; fluid pending 330; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4750.9 118.0 1640.7 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 16.4 ms, resident 397 MB, Metal 281 MB, mobs 17, coverage 93%
smoke rd 8 mob drawing: mobs 17 (0 within 32), 3240 vertices written, 3240 drawn via Fancy buffer, 7 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 652, loaded 652; stashed mobs 233; map cells 36617; block entities 433; gravity queue 0; fluid pending 52; jobs 16; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 721 ms at 0.0 s (frame 0): Game.tick 4 ms, render + GPU 717 ms; frames over 100 ms: 1
smoke rd 8: 3600 frames in 60.0 s wall, frame p50 12.82 p95 19.96 p99 47.44 max 721.01 ms, coverage min 66%, mobs max 75, travelled 3218 blocks, resident peak 402 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 143 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
---- iron age (0.5 s wall, 19 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 82 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (1.6 s wall, 83 s game)
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
---- obsidian + portal (2.1 s wall, 85 s game)
INFO fell into deep while mining; back to the surface
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (2.8 s wall, 102 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 337 blocks from the portal
PASS fortress: 2 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 14 cinderwisps in 330 s
INFO cinder rod rate 0.50 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.50 per kill is plausible (reference 0.5)
---- void pearls (6.0 s wall, 435 s game)
PASS voidwalkers: 12 void pearls from 25 kills
---- back to the surface (11.8 s wall, 1005 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (12.1 s wall, 1010 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
INFO bulk: +1 ender_eye (eye shattered)
---- stronghold (12.1 s wall, 1014 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 0 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (12.4 s wall, 1015 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (12.5 s wall, 1026 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 911 health so far (topped up)
---- hollow wyrm fight (12.7 s wall, 1049 s game)
PASS wyrm: defeated in 70 s (3 perches, 20 sword hits, 15 arrows for 64 damage, health left 1)
INFO wyrm fight: player took 30 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 13 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (13.2 s wall, 1132 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (13.3 s wall, 1138 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (13.3 s wall, 1142 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (13.5 s wall, 1150 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (13.6 s wall, 1150 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (13.7 s wall, 1206 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (15.7 s wall, 1219 s game)
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
FAIL blight: defeated in 601 s (388 arrows for 39 damage, 0 sword hits)
INFO blight sight: player sees it true, player SIMD3<Float>(4722.5, 127.0, 1784.8337), blight SIMD3<Float>(4722.5, 131.98885, 1783.6143), phase 0, arena floor y 127
PASS blight: arrows bounce off its armour below half health (0 damage from 0)
INFO blight fight: player took 2150 damage (healed by the test); 0 of 0 sword hits landed for 0
INFO bag full: dropped 14 slime_ball, 1 lily_pad, 2 feather, 1 chicken, 8 sand, 4 string, 10 dirt, 19 netherrack, 1 warped_stem, 2 rotten_flesh
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 4702 133 1795, still listed yes, stars on the ground []
INFO star lost: player at 4700.1 127.8 1794.2, alive yes, 7 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (22.7 s wall, 1843 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 23 advancements earned: adventure/ash_vault, adventure/deep, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, follow_ender_eye, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (22.7 s wall, 1844 s game)
INFO deaths: 0, damage healed by the test: 3200 half-hearts
playthrough: 2 failed checks, 1844 s of game time in 22.7 s wall
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
