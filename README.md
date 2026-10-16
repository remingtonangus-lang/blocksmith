# Blocksmith CI snapshots (heavy lane)

Commit `34e73de7f33d7f04118746a1e252490e5307819e` on `claude/bs-world-fx`: build **success**, heavy jobs **failure**
- checks: failure
- perf: success
- play: failure
- shots: success
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38855915298

```
gen 293 ms  mesh(all, parallel) 283 ms  mesh(1 section) 0.41 ms  quads 835232 opaque / 19278 water
frame (encode+GPU, offscreen, median of 30) 6.02 ms  biome beach
mesh slabs 32 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 173 MB
memory: resident 239 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1821 layers at 128 px, BC3, 38.0 MB with mips (build 1195 ms, upload 311 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 69) sky 15 block 8 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=52.3 hash=043bcce9ab8d04e0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=52.3 hash=043bcce9ab8d04e0
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 84)
gen 312 ms  mesh(all, parallel) 318 ms  mesh(1 section) 0.87 ms  quads 752386 opaque / 422 water
frame (encode+GPU, offscreen, median of 30) 4.70 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 181 MB
memory: resident 251 MB  (section meshes 23 MB)
wrote snaps/agent_door_777.png
naming audit: 6691 names, 0 flagged
selftest: 1199 blocks, 104 mob kinds, 4/4 special recipes, bundle fill 32/64, 87 advancements
selftest ok: 109 mobs after 3 s
textures: 1821 layers at 128 px, BC3, 38.0 MB with mips (build 1047 ms, upload 274 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0063 std=46.2 hash=d6641dfccf7da6ff
imagecheck selftest.png magenta=0.00000 black=0.0000 white=0.0063 std=46.2 hash=d6641dfccf7da6ff
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 342 ms  mesh(all, parallel) 307 ms  mesh(1 section) 0.24 ms  quads 800253 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 4.85 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 181 MB
memory: resident 257 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (38 pieces, framed)
textures: 1821 layers at 128 px, BC3, 38.0 MB with mips (build 1017 ms, upload 278 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=55.6 hash=12e598bb8d18b6fd flicker=0.00012
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=55.6 hash=12e598bb8d18b6fd flicker=0.00012
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 241 ms  mesh(all, parallel) 493 ms  mesh(1 section) 1.07 ms  quads 1643475 opaque / 75 water
frame (encode+GPU, offscreen, median of 30) 4.68 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 38 MB), Metal allocated 209 MB
memory: resident 293 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1821 layers at 128 px, BC3, 38.0 MB with mips (build 1211 ms, upload 309 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=51.7 hash=d8b4a475fff1291c flicker=0.00001
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=51.7 hash=d8b4a475fff1291c flicker=0.00001
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 273 ms  mesh(all, parallel) 359 ms  mesh(1 section) 0.93 ms  quads 1169814 opaque / 73 water
frame (encode+GPU, offscreen, median of 30) 6.79 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 30 MB), Metal allocated 181 MB
memory: resident 250 MB  (section meshes 36 MB)
wrote snaps/flicker_forest.png
textures: 1821 layers at 128 px, BC3, 38.0 MB with mips (build 1330 ms, upload 332 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=38.6 hash=85a3a640bf9cf273 flicker=0.00006
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=38.6 hash=85a3a640bf9cf273 flicker=0.00006
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 251 ms  mesh(all, parallel) 282 ms  mesh(1 section) 0.36 ms  quads 800454 opaque / 6822 water
frame (encode+GPU, offscreen, median of 30) 5.73 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 169 MB
memory: resident 236 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 200 frames, no flags
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 1.79 ms (min 1.38, max 4.91) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 1.29 ms/chunk
bench gen slow chunk -59,14: 4.9 ms (caves 0.7, ores 0.3, columns 0.2; starts 0.0, place 3.4)
bench gen slow chunk -80,-25: 3.8 ms (plants 2.0, caves 0.8, ores 0.3; starts 0.0, place 0.2)
bench gen slow chunk 53,22: 2.3 ms (caves 1.3, ores 0.3, columns 0.3; starts 0.0, place 0.1)
bench gen phases (ms/chunk): columns 0.21, stone 0.16, surface 0.02, caves 0.83, ores 0.22, trees 0.03, plants 0.20, starts 0.00, structures 0.18
bench gen structure starts (ms over 24 chunks): military_base 22.5, capital_city 19.1, village 11.5, temple 4.3, pillager_outpost 3.9, mansion 1.2, mineshaft 0.8, trail_ruins 0.7
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.92 ms/chunk (p95 3.79, max 4.85) single-thread | 1156 chunks/s parallel
bench: gen took 0.7 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 5.54 ms/chunk (24 sections, 81 non-empty), section mean 231 us p95 906 us max 1933 us, 4942 quads/chunk
bench mesh_lod1: 5.60 ms/chunk (24 sections, 81 non-empty), section mean 234 us p95 972 us max 2091 us, 2515 quads/chunk
bench: mesh took 0.7 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 15 ms, first load (r 4) 183 ms, renderer 2996 ms (textures 1083 ms, shaders 1 ms), fill rd 12 3.08 s
bench: startup took 9.5 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 1.42 ms, GPU p50 4.45 ms (max 5.17), 258 chunks drawn
bench frame 1080p rd 16: encode p50 1.03 ms, GPU p50 4.62 ms (max 7.67), 270 chunks drawn
bench frame 4k rd 16: encode p50 0.92 ms, GPU p50 7.10 ms (max 10.50), 270 chunks drawn
bench frame: 697 visible sections, 1221 draw calls, 253k quads
bench: frame took 5.8 s (live worlds 1, games 0)
bench: edit starts
bench edit: break mean 0.80 ms max 1.31 ms, place mean 0.79 ms max 1.24 ms (synchronous remesh)
bench: edit took 0.8 s (live worlds 1, games 0)
bench: mobs starts
bench mobs: tick 0.25 ms empty, 0.56 ms with 150 mobs (p95 1.43, max 4.23), 159 alive
bench: mobs took 0.9 s (live worlds 1, games 0)
bench: save starts
bench save: 145 chunks, save 1.48 ms/chunk (main thread 3.6 ms total, unchanged re-save 1.4 ms), load 0.20 ms/chunk (145 ok), 6.2 KB/chunk
bench: save took 0.9 s (live worlds 1, games 0)
bench: tnt starts
bench tnt: blast mean 1.00 ms max 1.76 ms (main thread) | re-mesh done in 0.09 s, tick p95 4.52 max 4.52 ms
bench: tnt took 0.8 s (live worlds 1, games 0)
bench: fluids starts
bench fluids: tick p50 0.37 p95 1.56 max 5.09 ms, 6702 sections re-meshed in 6 s, 1271 cells still pending
bench: fluids took 6.7 s (live worlds 1, games 0)
bench: weather starts
bench weather: tick p50 0.35 p95 1.41 max 15.13 ms, fire tick worst 0.78 ms (peak 96 burning), flood step worst 1.74 ms, 74 decal quads
bench: weather took 8.9 s (live worlds 1, games 0)
bench: ships starts
bench ships: edit remesh 2.29 ms, blast 2.31 ms + remesh 5.36 ms (3036 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds -0.09 ms encode, -0.02 ms GPU (66 draw calls)
bench ships: docked 3076 blocks in 11.90 ms (world remesh 0.07 s), assembled 3056 in 11.96 ms
bench ships: frigate 3036 blocks spawn 2.38 ms, mesh 4.29 ms; tick 0.64 ms (p95 2.00), physics 0.28 ms; collide 0.92 us near ships, 0.23 us far; 13 ships
bench: ships took 3.2 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 997
bench: wrote 113 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: resident 18 MB at start, 106 after loading, 191 after the renderer
bench flight8: frame p50 2.52 p95 4.03 p99 8.07 max 16.89 ms, 0 hitches >25 ms | tick p95 1.38 (update p95 0.63, max 4.93) encode p95 1.12 GPU p95 3.75 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.6 ms each on a worker) mesh 955 sections/s (310 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 25 MB, meshes 24 MB (slabs 40 MB), resident peak 213 MB, preload 495 ms
bench: flight8 took 14.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 38 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: resident 18 MB at start, 245 after loading, 321 after the renderer
bench flight16: frame p50 3.80 p95 6.62 p99 11.18 max 25.13 ms, 1 hitches >25 ms | tick p95 2.34 (update p95 1.20, max 4.17) encode p95 2.30 GPU p95 5.81 ms
bench flight16: coverage min 77% mean 88% | gen 43 chunks/s (2.3 ms each on a worker) mesh 3453 sections/s (296 us each) | realtime 1.00x
bench flight16: 1054 chunks, chunk data 86 MB, meshes 46 MB (slabs 72 MB), resident peak 339 MB, preload 2147 ms
bench: flight16 took 16.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 38 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: resident 17 MB at start, 444 after loading, 485 after the renderer
bench flight24: frame p50 4.62 p95 8.43 p99 14.69 max 17.81 ms, 0 hitches >25 ms | tick p95 3.42 (update p95 1.76, max 15.59) encode p95 4.02 GPU p95 6.59 ms
bench flight24: coverage min 73% mean 83% | gen 23 chunks/s (2.3 ms each on a worker) mesh 3471 sections/s (340 us each) | realtime 1.00x
bench flight24: 1687 chunks, chunk data 144 MB, meshes 68 MB (slabs 100 MB), resident peak 504 MB, preload 5139 ms
bench: flight24 took 20.4 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 38 metrics to snaps/bench_part_flight24.json
bench: merged 221 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.309 | 2.18x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.799 | 1.79x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.784 | 1.32x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.242 | 1.70x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.792 | 1.74x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.761 | 1.28x |
| flight16.arena_free_mb | 0.864 | 16.312 | 18.88x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.688 | 0.82x |
| flight16.chunks | 1056 | 1054 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.877 | 1.13x |
| flight16.coverage_min | 0.962 | 0.774 | 1.24x |
| flight16.cull_ms_p50 | 0.708 | 0.342 | 0.48x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.983 | 0.85x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.878 | 0.59x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.301 | 0.97x |
| flight16.frame_ms_max | 12.652 | 25.134 | 1.99x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.804 | 0.79x |
| flight16.frame_ms_p95 | 5.8 | 6.622 | 1.14x |
| flight16.frame_ms_p99 | 7.443 | 11.179 | 1.50x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.391 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.774 | 0.79x |
| flight16.gpu_ms_p95 | 5.71 | 5.807 | 1.02x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.334 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3453.32 | 0.57x ✅ better |
| flight16.preload_ms | 1871.23 | 2147.37 | 1.15x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_after_load_mb | – | 245.033 | new |
| flight16.resident_after_renderer_mb | – | 320.534 | new |
| flight16.resident_peak_mb | 285.862 | 338.955 | 1.19x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 10.257 | 1.20x |
| flight16.tick_ms_p50 | 0.388 | 0.664 | 1.71x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.344 | 1.13x |
| flight16.update_ms_max | 8.289 | 4.169 | 0.50x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.3 | 17.65x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.195 | 0.69x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.313 | 1.14x |
| flight16.worker_mesh_us | 177.949 | 296.229 | 1.66x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.412 | 54.83x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 144.184 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1687 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.832 | 1.19x |
| flight24.coverage_min | 0.974 | 0.731 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.724 | 0.60x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.205 | 0.80x |
| flight24.cull_walked_sections | 7607 | 3698 | 0.49x ✅ better |
| flight24.draw_calls | 3175 | 1124 | 0.35x ✅ better |
| flight24.drawn_kquads | 821.704 | 211.166 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.441 | 0.58x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.021 | 0.77x ✅ better |
| flight24.frame_ms_max | 13.319 | 17.808 | 1.34x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.617 | 0.60x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 8.428 | 0.89x |
| flight24.frame_ms_p99 | 10.337 | 14.693 | 1.42x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 22.985 | 2.77x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.583 | 0.59x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.586 | 0.70x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 68.459 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3470.51 | 0.71x ✅ better |
| flight24.preload_ms | 4742.83 | 5138.65 | 1.08x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_after_load_mb | – | 444.206 | new |
| flight24.resident_after_renderer_mb | – | 485.237 | new |
| flight24.resident_peak_mb | 512.018 | 504.206 | 0.98x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 15.766 | 1.36x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.814 | 2.03x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.423 | 1.16x |
| flight24.update_ms_max | 4.586 | 15.586 | 3.40x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.391 | 26.07x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.763 | 0.70x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.269 | 0.96x |
| flight24.worker_mesh_us | 177.947 | 340.075 | 1.91x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.71 | 4.39x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.08 | 0.39x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.224 | 0.73x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.435 | 0.77x |
| flight8.encode_ms_p95 | 0.832 | 1.124 | 1.35x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 16.887 | 1.28x |
| flight8.frame_ms_p50 | 2.588 | 2.523 | 0.97x |
| flight8.frame_ms_p95 | 3.197 | 4.033 | 1.26x |
| flight8.frame_ms_p99 | 4.401 | 8.071 | 1.83x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.712 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.515 | 0.98x |
| flight8.gpu_ms_p95 | 3.081 | 3.748 | 1.22x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 954.956 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 494.856 | 0.35x ✅ better |
| flight8.realtime | 0.994 | 0.998 | 1.00x |
| flight8.resident_after_load_mb | – | 106.33 | new |
| flight8.resident_after_renderer_mb | – | 190.752 | new |
| flight8.resident_peak_mb | 124.705 | 213.018 | 1.71x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 15.74 | 1.26x |
| flight8.tick_ms_p50 | 0.158 | 0.389 | 2.46x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.378 | 1.13x |
| flight8.update_ms_max | 12.421 | 4.926 | 0.40x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.004 | 0.40x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.628 | 0.72x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.588 | 0.80x |
| flight8.worker_mesh_us | 181.115 | 309.507 | 1.71x ⚠️ worse |
| fluids.pending | 240 | 1271 | 5.30x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6702 | 2.57x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.091 | 1.49x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.372 | 1.65x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.558 | 0.83x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.805 | 2.50x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.028 | 1.64x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 7.672 | 2.91x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.615 | 2.00x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.55 | 1.59x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.919 | 1.33x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 10.498 | 2.57x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.095 | 2.02x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.293 | 4.36x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.418 | 2.33x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 5.173 | 2.15x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.448 | 2.15x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.854 | 1.44x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.921 | 0.92x |
| gen.chunk_ms_p95 | 3.325 | 3.787 | 1.14x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1155.53 | 1.46x ⚠️ worse |
| gen.starts_cold_ms | – | 1.286 | new |
| gen.terrain_hash | 1238443285367868 | 1538201698069241 | ⚠️ changed |
| genphase.caves_ms | – | 0.828 | new |
| genphase.columns_ms | – | 0.207 | new |
| genphase.ores_ms | – | 0.216 | new |
| genphase.plants_ms | – | 0.197 | new |
| genphase.starts_ms | – | 0.005 | new |
| genphase.stone_ms | – | 0.164 | new |
| genphase.structures_ms | – | 0.182 | new |
| genphase.surface_ms | – | 0.023 | new |
| genphase.trees_ms | – | 0.035 | new |
| mesh.chunk_ms_max | 5.758 | 6.969 | 1.21x |
| mesh.chunk_ms_mean | 4.38 | 5.54 | 1.26x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1932.98 | 1.19x |
| mesh.section_us_mean | 139.451 | 230.85 | 1.66x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 905.991 | 1.32x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 9.379 | 1.72x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.604 | 1.37x ⚠️ worse |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 2091.05 | 1.41x ⚠️ worse |
| mesh_lod1.section_us_mean | 126.754 | 233.502 | 1.84x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 972.033 | 1.71x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 2.055 | 1.28x |
| mobs.tick_150_ms_max | 1.25 | 4.225 | 3.38x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.559 | 2.06x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.427 | 3.25x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.251 | 8.10x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.915 | 11.16x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.48 | 0.51x ✅ better |
| save.load_chunk_ms | 0.587 | 0.196 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 3.626 | 0.70x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.382 | 0.54x ✅ better |
| ships.assemble_ms | 19.313 | 11.964 | 0.62x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.021 | 0.78x |
| ships.blast_ms | 2.675 | 2.308 | 0.86x |
| ships.blast_remesh_ms | 5.466 | 5.358 | 0.98x |
| ships.collide_far_us | 0.214 | 0.232 | 1.08x |
| ships.collide_us | 1.047 | 0.917 | 0.88x |
| ships.dock_ms | 12.056 | 11.897 | 0.99x |
| ships.dock_remesh_s | 0.036 | 0.07 | 1.94x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.649 | 0.73x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.29 | 0.57x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.285 | 0.63x ✅ better |
| ships.frame_encode_ms | 0.023 | -0.092 | -4.00x ✅ better |
| ships.frame_gpu_ms | -0.228 | -0.023 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.285 | 1.40x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.281 | 1.70x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.763 | 3.58x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 2.38 | 1.01x |
| ships.tick_ms_max | 0.522 | 7.964 | 15.26x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.64 | 2.92x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.999 | 6.62x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.08 | 0.71x ✅ better |
| startup.first_load_ms | 206.958 | 182.859 | 0.88x |
| startup.renderer_init_again_ms | 27.582 | 1717.44 | 62.27x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2995.89 | 3.66x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.699 | 2.01x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.633 | 1.80x ⚠️ worse |
| startup.textures_ms | 26.537 | 1083.17 | 40.82x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.892 | 6.78x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.757 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1 | 0.34x ✅ better |
| tnt.remesh_s | 0.087 | 0.087 | 1.00x |
| tnt.tick_ms_max | 5.414 | 4.525 | 0.84x |
| tnt.tick_ms_p50 | 4.529 | 0.412 | 0.09x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 4.525 | 0.84x |
| weather.decal_quads | – | 74 | new |
| weather.fire_burning_peak | – | 96 | new |
| weather.fire_tick_ms_worst | – | 0.783 | new |
| weather.flood_step_ms_worst | – | 1.736 | new |
| weather.storm_ms_worst | – | 1.739 | new |
| weather.tick_ms_max | – | 15.132 | new |
| weather.tick_ms_p50 | – | 0.353 | new |
| weather.tick_ms_p95 | – | 1.406 | new |
### Smoke test
```
smoke rd 8 mob drawing: mobs 21 (0 within 32), 2664 vertices written, 2664 drawn via Fancy buffer, 31 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 439, loaded 439; stashed mobs 1; map cells 2511; block entities 39; gravity queue 0; fluid pending 128; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 4724.1 122.0 1673.8 ground yes water yes menu none
smoke rd 8 Fancy: 40 s, frame 14.8 ms, resident 369 MB, Metal 271 MB, mobs 18, coverage 96%
smoke rd 8 mob drawing: mobs 18 (0 within 32), 1980 vertices written, 1980 drawn via Fancy buffer, 15 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 658, loaded 658; stashed mobs 28; map cells 13738; block entities 127; gravity queue 0; fluid pending 364; jobs 12; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 4737.6 119.6 1657.2 ground no water yes menu none
smoke rd 8 Fancy: 50 s, frame 20.1 ms, resident 395 MB, Metal 279 MB, mobs 47, coverage 90%
smoke rd 8 mob drawing: mobs 47 (0 within 32), 8964 vertices written, 8964 drawn via Fancy buffer, 35 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 669, loaded 669; stashed mobs 132; map cells 25162; block entities 292; gravity queue 0; fluid pending 416; jobs 6; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 4750.9 118.0 1640.7 ground yes water yes menu none
smoke rd 8 Fancy: 60 s, frame 10.6 ms, resident 393 MB, Metal 283 MB, mobs 7, coverage 93%
smoke rd 8 mob drawing: mobs 7 (0 within 32), 1368 vertices written, 1368 drawn via Fancy buffer, 5 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 654, loaded 654; stashed mobs 226; map cells 36617; block entities 432; gravity queue 0; fluid pending 64; jobs 15; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 684 ms at 0.0 s (frame 0): Game.tick 5 ms, render + GPU 679 ms; frames over 100 ms: 1
smoke rd 8: 3600 frames in 60.0 s wall, frame p50 12.68 p95 25.83 p99 60.27 max 684.15 ms, coverage min 56%, mobs max 61, travelled 3218 blocks, resident peak 401 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 143 blocks
smoke rd 8 split screen: PASS
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
INFO bulk: +10 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.7 s wall, 34 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 106 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (2.5 s wall, 106 s game)
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
---- obsidian + portal (3.1 s wall, 109 s game)
INFO fell into deep while mining; back to the surface
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (4.0 s wall, 130 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 337 blocks from the portal
PASS fortress: 2 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 12 cinderwisps in 163 s
INFO cinder rod rate 0.58 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.58 per kill is plausible (reference 0.5)
---- void pearls (6.1 s wall, 296 s game)
PASS voidwalkers: 12 void pearls from 20 kills
---- back to the surface (8.1 s wall, 456 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (8.4 s wall, 461 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (8.5 s wall, 469 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 0 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (8.8 s wall, 470 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (9.0 s wall, 481 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 57 health so far (topped up)
---- hollow wyrm fight (9.2 s wall, 504 s game)
PASS wyrm: defeated in 102 s (3 perches, 20 sword hits, 21 arrows for 60 damage, health left 1)
INFO wyrm fight: player took 45 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 12 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (10.0 s wall, 619 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (10.1 s wall, 629 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (10.2 s wall, 633 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (10.4 s wall, 640 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (10.4 s wall, 640 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (10.7 s wall, 696 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (13.4 s wall, 710 s game)
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
INFO blight fight: player took 2141 damage (healed by the test); 0 of 0 sword hits landed for 0
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 4722 132 1784, still listed yes, stars on the ground []
INFO star lost: player at 4722.5 127.0 1785.1, alive yes, 12 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (21.2 s wall, 1313 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 24 advancements earned: adventure/ash_vault, adventure/deep, adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, follow_ender_eye, form_obsidian, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (21.2 s wall, 1314 s game)
INFO deaths: 0, damage healed by the test: 2304 half-hearts
playthrough: 3 failed checks, 1314 s of game time in 21.2 s wall
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
### dropgrid
![dropgrid.png](dropgrid.png)
### drops
![drops.png](drops.png)
### drops_cave
![drops_cave.png](drops_cave.png)
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
### fx_blast
![fx_blast.png](fx_blast.png)
### fx_cracks
![fx_cracks.png](fx_cracks.png)
### fx_end
![fx_end.png](fx_end.png)
### fx_fire_0
![fx_fire_0.png](fx_fire_0.png)
### fx_fire_1
![fx_fire_1.png](fx_fire_1.png)
### fx_fire_2
![fx_fire_2.png](fx_fire_2.png)
### fx_fire_3
![fx_fire_3.png](fx_fire_3.png)
### fx_flood_0
![fx_flood_0.png](fx_flood_0.png)
### fx_flood_1
![fx_flood_1.png](fx_flood_1.png)
### fx_flood_2
![fx_flood_2.png](fx_flood_2.png)
### fx_flood_3
![fx_flood_3.png](fx_flood_3.png)
### fx_shallows
![fx_shallows.png](fx_shallows.png)
### fx_shatter
![fx_shatter.png](fx_shatter.png)
### fx_snow_0
![fx_snow_0.png](fx_snow_0.png)
### fx_snow_1
![fx_snow_1.png](fx_snow_1.png)
### fx_snow_2
![fx_snow_2.png](fx_snow_2.png)
### fx_storm_ship
![fx_storm_ship.png](fx_storm_ship.png)
### fx_wildfire
![fx_wildfire.png](fx_wildfire.png)
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
### held_apple
![held_apple.png](held_apple.png)
### held_bow
![held_bow.png](held_bow.png)
### held_pickaxe_ench
![held_pickaxe_ench.png](held_pickaxe_ench.png)
### held_sword
![held_sword.png](held_sword.png)
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
### itemsheet_blocks
![itemsheet_blocks.png](itemsheet_blocks.png)
### itemsheet_enchanted_tv
![itemsheet_enchanted_tv.png](itemsheet_enchanted_tv.png)
### itemsheet_items
![itemsheet_items.png](itemsheet_items.png)
### itemsheet_items_tv_0
![itemsheet_items_tv_0.png](itemsheet_items_tv_0.png)
### itemsheet_items_tv_1
![itemsheet_items_tv_1.png](itemsheet_items_tv_1.png)
### itemsheet_tools
![itemsheet_tools.png](itemsheet_tools.png)
### itemsheet_tools_tv
![itemsheet_tools_tv.png](itemsheet_tools_tv.png)
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
### storm_sea
![storm_sea.png](storm_sea.png)
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
