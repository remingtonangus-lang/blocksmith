# Blocksmith CI snapshots (heavy lane)

Commit `594cb12de385c68453753fb60909849fa8786782` on `claude/bs-capital-soldiers`: build **success**, heavy jobs **failure**
- checks: failure
- perf: success
- play: failure
- shots: failure
- smoke: success
- tours: failure

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37309530495

```
frame (encode+GPU, offscreen, median of 30) 6.71 ms  biome beach
mesh slabs 32 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 170 MB
memory: resident 227 MB  (section meshes 26 MB)
wrote snaps/leak_12345.png
textures: 1679 layers at 128 px, BC3, 35.0 MB with mips (build 912 ms, upload 288 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 69) sky 15 block 8 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=48.9 hash=37da6e2bf39a6da5
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=48.9 hash=37da6e2bf39a6da5
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 82)
gen 255 ms  mesh(all, parallel) 275 ms  mesh(1 section) 0.85 ms  quads 780831 opaque / 12019 water
frame (encode+GPU, offscreen, median of 30) 6.86 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 178 MB
memory: resident 240 MB  (section meshes 24 MB)
wrote snaps/agent_door_777.png
naming audit: 5945 names, 0 flagged
selftest: 999 blocks, 99 mob kinds, 4/4 special recipes, bundle fill 32/64, 83 advancements
selftest ok: 160 mobs after 3 s
textures: 1679 layers at 128 px, BC3, 35.0 MB with mips (build 689 ms, upload 248 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0188 white=0.0243 std=48.7 hash=8872ae6e2c44fa30
imagecheck selftest.png magenta=0.00000 black=0.0188 white=0.0243 std=48.7 hash=8872ae6e2c44fa30
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 238 ms  mesh(all, parallel) 209 ms  mesh(1 section) 0.31 ms  quads 794763 opaque / 16866 water
frame (encode+GPU, offscreen, median of 30) 5.69 ms  biome plains
mesh slabs 32 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 182 MB
memory: resident 243 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (38 pieces, framed)
textures: 1679 layers at 128 px, BC3, 35.0 MB with mips (build 777 ms, upload 272 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=56.3 hash=bb95016e74aca586 flicker=0.00021
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=56.3 hash=bb95016e74aca586 flicker=0.00021
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 238 ms  mesh(all, parallel) 391 ms  mesh(1 section) 1.27 ms  quads 1633449 opaque / 12883 water
frame (encode+GPU, offscreen, median of 30) 3.80 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 37 MB), Metal allocated 206 MB
memory: resident 281 MB  (section meshes 50 MB)
wrote snaps/flicker_village.png
textures: 1679 layers at 128 px, BC3, 35.0 MB with mips (build 925 ms, upload 306 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=53.1 hash=d22bfd38a7d832e7 flicker=0.00002
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=53.1 hash=d22bfd38a7d832e7 flicker=0.00002
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 202 ms  mesh(all, parallel) 240 ms  mesh(1 section) 0.97 ms  quads 1136737 opaque / 9486 water
frame (encode+GPU, offscreen, median of 30) 7.19 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 29 MB), Metal allocated 178 MB
memory: resident 250 MB  (section meshes 35 MB)
wrote snaps/flicker_forest.png
textures: 1679 layers at 128 px, BC3, 35.0 MB with mips (build 1007 ms, upload 321 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=40.0 hash=c13f54a8dbf88b03 flicker=0.00020
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0012 std=40.0 hash=c13f54a8dbf88b03 flicker=0.00020
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 279 ms  mesh(all, parallel) 236 ms  mesh(1 section) 0.42 ms  quads 794976 opaque / 16866 water
frame (encode+GPU, offscreen, median of 30) 8.85 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 166 MB
memory: resident 232 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 199 frames, no flags
snap.sh: 1 failing line(s): 414
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.46 ms (min 1.93, max 5.30) [0]
bench: gen starts
bench gen: structure starts for the sample (cold) 0.37 ms/chunk
bench gen slow chunk -80,-25: 3.8 ms (plants 1.6, caves 1.1, ores 0.3; starts 0.0, place 0.2)
bench gen slow chunk -66,1: 2.7 ms (caves 1.1, ores 0.5, plants 0.3; starts 0.0, place 0.3)
bench gen slow chunk 46,9: 2.3 ms (caves 0.9, columns 0.2, ores 0.2; starts 0.0, place 0.7)
bench gen phases (ms/chunk): columns 0.22, stone 0.15, surface 0.02, caves 0.81, ores 0.24, trees 0.04, plants 0.14, starts 0.01, structures 0.04
bench gen structure starts (ms over 24 chunks): village 4.1, pillager_outpost 2.3, mineshaft 1.0, fossil 0.6, military_base 0.5, mansion 0.4, ocean_ruin 0.4, shipwreck 0.3
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.75 ms/chunk (p95 2.70, max 3.78) single-thread | 1547 chunks/s parallel
bench: gen took 0.6 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 3.00 ms/chunk (24 sections, 91 non-empty), section mean 125 us p95 562 us max 1434 us, 4652 quads/chunk
bench mesh_lod1: 1.95 ms/chunk (24 sections, 47 non-empty), section mean 81 us p95 407 us max 482 us, 1251 quads/chunk
bench: mesh took 0.6 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 4 ms, first load (r 4) 190 ms, renderer 2451 ms (textures 1018 ms, shaders 0 ms), fill rd 12 4.15 s
bench: startup took 9.5 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 1.80 ms, GPU p50 3.62 ms (max 3.75), 260 chunks drawn
bench frame 1080p rd 16: encode p50 0.82 ms, GPU p50 4.28 ms (max 6.88), 277 chunks drawn
bench frame 4k rd 16: encode p50 0.87 ms, GPU p50 6.37 ms (max 12.57), 277 chunks drawn
bench frame: 575 visible sections, 951 draw calls, 188k quads
bench: frame took 5.0 s (live worlds 0, games 0)
bench: edit starts
bench edit: break mean 0.84 ms max 2.81 ms, place mean 0.82 ms max 2.30 ms (synchronous remesh)
bench: edit took 0.8 s (live worlds 0, games 0)
bench: mobs starts
bench mobs: tick 0.36 ms empty, 0.88 ms with 150 mobs (p95 2.51, max 4.22), 200 alive
bench: mobs took 1.0 s (live worlds 0, games 0)
bench: save starts
bench save: 145 chunks, save 1.79 ms/chunk (main thread 3.3 ms total, unchanged re-save 1.2 ms), load 0.27 ms/chunk (145 ok), 5.0 KB/chunk
bench: save took 0.9 s (live worlds 0, games 0)
bench: tnt starts
bench tnt: blast mean 1.77 ms max 2.60 ms (main thread) | re-mesh done in 0.14 s, tick p95 11.24 max 11.24 ms
bench: tnt took 0.9 s (live worlds 0, games 0)
bench: fluids starts
bench fluids: tick p50 0.52 p95 2.89 max 12.78 ms, 3552 sections re-meshed in 6 s, 1439 cells still pending
bench: fluids took 6.9 s (live worlds 0, games 0)
bench: ships starts
bench ships: edit remesh 5.57 ms, blast 4.75 ms + remesh 10.08 ms (3036 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.13 ms encode, 0.38 ms GPU (66 draw calls)
bench ships: docked 3076 blocks in 29.76 ms (world remesh 0.04 s), assembled 3036 in 20.36 ms
bench ships: frigate 3036 blocks spawn 1.12 ms, mesh 3.04 ms; tick 0.60 ms (p95 1.44), physics 0.23 ms; collide 0.98 us near ships, 0.21 us far; 13 ships
bench: ships took 3.0 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 105 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 3.03 p95 6.99 p99 11.67 max 24.53 ms, 0 hitches >25 ms | tick p95 2.03 (update p95 0.57, max 4.16) encode p95 1.81 GPU p95 6.67 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (3.2 ms each on a worker) mesh 576 sections/s (222 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 34 MB, meshes 35 MB (slabs 48 MB), resident peak 204 MB, preload 677 ms
bench: flight8 took 15.0 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 5.01 p95 10.05 p99 17.81 max 40.95 ms, 3 hitches >25 ms | tick p95 3.20 (update p95 1.44, max 20.92) encode p95 3.77 GPU p95 8.75 ms
bench flight16: coverage min 96% mean 99% | gen 44 chunks/s (3.1 ms each on a worker) mesh 2301 sections/s (201 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 113 MB, meshes 75 MB (slabs 92 MB), resident peak 347 MB, preload 2055 ms
bench: flight16 took 16.6 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 8.20 p95 13.44 p99 19.32 max 37.98 ms, 3 hitches >25 ms | tick p95 5.01 (update p95 1.89, max 7.50) encode p95 6.43 GPU p95 12.34 ms
bench flight24: coverage min 97% mean 99% | gen 64 chunks/s (2.9 ms each on a worker) mesh 2920 sections/s (205 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 239 MB, meshes 128 MB (slabs 152 MB), resident peak 597 MB, preload 4956 ms
bench: flight24 took 19.4 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 207 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.814 | 4.69x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.843 | 1.89x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.651 | 1.09x |
| edit.place_ms_max | 0.732 | 2.298 | 3.14x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.817 | 1.80x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.648 | 1.09x |
| flight16.arena_free_mb | 0.864 | 3.955 | 4.58x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.133 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.991 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.417 | 0.59x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 1.129 | 0.98x |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1209 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.011 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.37 | 0.92x |
| flight16.encode_ms_p95 | 2.361 | 3.771 | 1.60x ⚠️ worse |
| flight16.frame_ms_max | 12.652 | 40.946 | 3.24x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 5.014 | 1.04x |
| flight16.frame_ms_p95 | 5.8 | 10.051 | 1.73x ⚠️ worse |
| flight16.frame_ms_p99 | 7.443 | 17.811 | 2.39x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.631 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.801 | 1.00x |
| flight16.gpu_ms_p95 | 5.71 | 8.746 | 1.53x ⚠️ worse |
| flight16.hitches | 0 | 3 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 75.234 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2300.57 | 0.86x |
| flight16.preload_ms | 1871.23 | 2054.82 | 1.10x |
| flight16.realtime | 0.998 | 0.997 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 347.081 | 1.21x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 21.964 | 2.57x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 1.097 | 2.83x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 3.198 | 1.54x ⚠️ worse |
| flight16.update_ms_max | 8.289 | 20.922 | 2.52x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.138 | 8.12x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.442 | 0.83x |
| flight16.worker_gen_ms | 2.022 | 3.083 | 1.52x ⚠️ worse |
| flight16.worker_mesh_us | 177.949 | 200.501 | 1.13x |
| flight24.arena_free_mb | 0.427 | 4.319 | 10.11x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.273 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.993 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 1.027 | 0.86x |
| flight24.cull_ms_p95 | 2.767 | 3.09 | 1.12x |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3016 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.372 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.501 | 1.01x |
| flight24.encode_ms_p95 | 5.237 | 6.426 | 1.23x |
| flight24.frame_ms_max | 13.319 | 37.978 | 2.85x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 8.199 | 1.06x |
| flight24.frame_ms_p95 | 9.472 | 13.435 | 1.42x ⚠️ worse |
| flight24.frame_ms_p99 | 10.337 | 19.324 | 1.87x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.671 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 8.069 | 1.05x |
| flight24.gpu_ms_p95 | 9.428 | 12.34 | 1.31x ⚠️ worse |
| flight24.hitches | 0 | 3 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 128.152 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 2920.29 | 0.84x |
| flight24.preload_ms | 4742.83 | 4955.63 | 1.04x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 597.05 | 1.17x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 20.332 | 1.75x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.405 | 3.50x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 5.011 | 1.70x ⚠️ worse |
| flight24.update_ms_max | 4.586 | 7.503 | 1.64x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.294 | 19.60x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.892 | 0.75x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.904 | 1.23x |
| flight24.worker_mesh_us | 177.947 | 204.61 | 1.15x |
| flight8.arena_free_mb | 2.438 | 5.069 | 2.08x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.992 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.106 | 0.52x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.293 | 0.96x |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.137 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.716 | 1.27x |
| flight8.encode_ms_p95 | 0.832 | 1.807 | 2.17x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 24.534 | 1.85x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 3.032 | 1.17x |
| flight8.frame_ms_p95 | 3.197 | 6.986 | 2.19x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 11.67 | 2.65x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.749 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.978 | 1.15x |
| flight8.gpu_ms_p95 | 3.081 | 6.669 | 2.16x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 34.839 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 576.233 | 0.88x |
| flight8.preload_ms | 1398.04 | 677.108 | 0.48x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 203.565 | 1.63x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 13.464 | 1.07x |
| flight8.tick_ms_p50 | 0.158 | 0.668 | 4.23x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 2.029 | 1.66x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 4.164 | 0.34x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.003 | 0.30x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.565 | 0.65x ✅ better |
| flight8.worker_gen_ms | 3.236 | 3.214 | 0.99x |
| flight8.worker_mesh_us | 181.115 | 222.194 | 1.23x |
| fluids.pending | 240 | 1439 | 6.00x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3552 | 1.36x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 12.776 | 3.74x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.517 | 2.29x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.894 | 1.55x ⚠️ worse |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.48 | 1.05x |
| frame.mesh_mb | 57.324 | 65.841 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 2.216 | 1.97x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.818 | 1.31x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 6.876 | 2.61x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.284 | 1.86x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.495 | 1.56x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.874 | 1.26x |
| frame_4k.gpu_ms_max | 4.083 | 12.57 | 3.08x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.372 | 1.81x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.319 | 3.07x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.801 | 2.96x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 3.752 | 1.56x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.622 | 1.75x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 3.775 | 1.12x |
| gen.chunk_ms_mean | 2.082 | 1.747 | 0.84x |
| gen.chunk_ms_p95 | 3.325 | 2.705 | 0.81x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1547.19 | 1.09x |
| gen.starts_cold_ms | – | 0.366 | new |
| gen.terrain_hash | 1238443285367868 | 3438778483796502 | ⚠️ changed |
| genphase.caves_ms | – | 0.807 | new |
| genphase.columns_ms | – | 0.22 | new |
| genphase.ores_ms | – | 0.238 | new |
| genphase.plants_ms | – | 0.142 | new |
| genphase.starts_ms | – | 0.006 | new |
| genphase.stone_ms | – | 0.149 | new |
| genphase.structures_ms | – | 0.043 | new |
| genphase.surface_ms | – | 0.024 | new |
| genphase.trees_ms | – | 0.04 | new |
| mesh.chunk_ms_max | 5.758 | 4.737 | 0.82x |
| mesh.chunk_ms_mean | 3.347 | 2.999 | 0.90x |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 1433.97 | 0.88x |
| mesh.section_us_mean | 139.451 | 124.939 | 0.90x |
| mesh.section_us_p95 | 686.049 | 562.072 | 0.82x |
| mesh_lod1.chunk_ms_max | 5.44 | 2.34 | 0.43x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 1.949 | 0.64x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 482.082 | 0.33x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 81.219 | 0.64x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 407.1 | 0.72x ✅ better |
| mobs.per_mob_us | 1.608 | 3.429 | 2.13x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 4.216 | 3.37x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.878 | 3.23x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.513 | 5.72x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.363 | 11.71x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.468 | 17.90x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.015 | 1.12x |
| save.chunk_ms | 2.896 | 1.786 | 0.62x ✅ better |
| save.load_chunk_ms | 0.587 | 0.273 | 0.47x ✅ better |
| save.main_thread_ms | 5.206 | 3.342 | 0.64x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.202 | 0.47x ✅ better |
| ships.assemble_ms | 19.313 | 20.365 | 1.05x |
| ships.assemble_remesh_s | 0.027 | 0.016 | 0.59x ✅ better |
| ships.blast_ms | 2.675 | 4.755 | 1.78x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 10.083 | 1.84x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.212 | 0.99x |
| ships.collide_us | 1.047 | 0.979 | 0.94x |
| ships.dock_ms | 12.056 | 29.759 | 2.47x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.037 | 1.03x |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 1.588 | 1.79x ⚠️ worse |
| ships.edit_ms_mean | 0.505 | 0.561 | 1.11x |
| ships.edit_remesh_ms | 3.642 | 5.571 | 1.53x ⚠️ worse |
| ships.frame_encode_ms | 0.023 | 0.128 | 5.57x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.377 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 3.044 | 0.99x |
| ships.physics_ms_mean | 0.165 | 0.227 | 1.38x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.507 | 2.38x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.124 | 0.48x ✅ better |
| ships.tick_ms_max | 0.522 | 3.021 | 5.79x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.596 | 2.72x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.439 | 4.76x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.148 | 0.96x |
| startup.first_load_ms | 206.958 | 189.813 | 0.92x |
| startup.renderer_init_again_ms | 27.582 | 1227.18 | 44.49x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2451.12 | 3.00x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.483 | 1.39x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.401 | 1.76x ⚠️ worse |
| startup.textures_ms | 26.537 | 1018.08 | 38.36x ⚠️ worse |
| startup.world_init_ms | 2.198 | 3.795 | 1.73x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 2.598 | 0.30x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.77 | 0.61x ✅ better |
| tnt.remesh_s | 0.087 | 0.143 | 1.64x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 11.236 | 2.08x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 3.328 | 0.73x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 11.236 | 2.08x ⚠️ worse |
### Smoke test
```
smoke rd 8 mob drawing: mobs 81 (1 within 32), 33660 vertices written, 33660 drawn via Fancy buffer, 52 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 331, loaded 331; stashed mobs 9; map cells 1216; block entities 30; gravity queue 0; fluid pending 0; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 30 s player 2 at 14.7 150.0 3.3 ground yes water no menu none
smoke rd 8 Fancy: 40 s, frame 16.8 ms, resident 334 MB, Metal 252 MB, mobs 105, coverage 94%
smoke rd 8 mob drawing: mobs 105 (0 within 32), 16524 vertices written, 16524 drawn via Fancy buffer, 42 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 659, loaded 659; stashed mobs 41; map cells 10643; block entities 154; gravity queue 0; fluid pending 699; jobs 16; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 40 s player 2 at 14.3 152.0 -1.7 ground yes water no menu none
smoke rd 8 Fancy: 50 s, frame 12.9 ms, resident 374 MB, Metal 280 MB, mobs 173, coverage 98%
smoke rd 8 mob drawing: mobs 173 (1 within 32), 25380 vertices written, 25380 drawn via Fancy buffer, 84 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 673, loaded 673; stashed mobs 320; map cells 20320; block entities 265; gravity queue 0; fluid pending 203; jobs 4; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8 split: t 50 s player 2 at 14.3 152.0 -1.7 ground yes water no menu none
smoke rd 8 Fancy: 60 s, frame 14.8 ms, resident 384 MB, Metal 284 MB, mobs 110, coverage 100%
smoke rd 8 mob drawing: mobs 110 (0 within 32), 19584 vertices written, 19584 drawn via Fancy buffer, 47 culled, 0 dropped (buffer full)
smoke rd 8 memory: chunks alive 676, loaded 676; stashed mobs 688; map cells 30001; block entities 416; gravity queue 0; fluid pending 7; jobs 0; NaN quarantined: player 0, mobs 0, ships 0
smoke rd 8: worst frame 600 ms at 0.0 s (frame 0): Game.tick 9 ms, render + GPU 591 ms; frames over 100 ms: 1
smoke rd 8: 3600 frames in 60.3 s wall, frame p50 12.41 p95 23.20 p99 43.85 max 600.36 ms, coverage min 86%, mobs max 207, travelled 3187 blocks, resident peak 385 MB, menu closed
smoke rd 8: mobs dropped for a full mob buffer: at most 0 in a frame (the farthest first)
smoke rd 8 split screen: player 2 moved 12 blocks
smoke rd 8: FAIL player 2 barely moved
smoke: PASS at render distance 8 16 24 24f 8c
```
### Playthrough
```
INFO bulk: +4 feather (chickens)
PASS craft: diamond pickaxe, sword, bow, 16 arrows
INFO bulk: +19 diamond (more diamonds)
INFO bulk: +5 gold_ingot (gold ore)
PASS armour: 19 armour points worn
---- obsidian + portal (2.5 s wall, 112 s game)
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (3.5 s wall, 134 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 138 blocks from the portal
PASS fortress: 4 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 8 cinder rods from 22 cinderwisps in 899 s
INFO cinder rod rate 0.36 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.36 per kill is plausible (reference 0.5)
---- void pearls (17.2 s wall, 1036 s game)
INFO bag full: dropped 11 netherrack, 64 netherrack, 1 rotten_flesh, 64 netherrack, 2 leather
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO bag full: dropped 64 netherrack, 64 netherrack, 64 netherrack, 64 netherrack, 64 netherrack, 64 netherrack, 8 porkchop, 2 rotten_flesh
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 37 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 34 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO bag full: dropped 14 netherrack, 1 magma_block, 1 crimson_roots, 64 netherrack, 64 netherrack, 64 netherrack, 11 crimson_nylium
INFO bulk: +1 golden_helmet (armour)
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 169 39 35 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 36 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 37 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 36 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_leggings (armour)
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 169 39 37 in nether
PASS armour: 19 armour points worn
INFO died (Player fell from a high place) at 169 39 37 in nether
INFO bag full: dropped 28 netherrack, 7 rotten_flesh, 64 netherrack, 34 gold_nugget, 64 netherrack, 15 porkchop, 7 leather
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO died (Player fell from a high place) at 170 39 36 in nether
INFO died (Player fell from a high place) at 170 39 36 in nether
PASS voidwalkers: 12 void pearls from 26 kills
---- back to the surface (52.9 s wall, 2642 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (53.3 s wall, 2647 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (53.4 s wall, 2656 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 3 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (53.7 s wall, 2657 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (53.8 s wall, 2668 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 6513 health so far (topped up)
---- hollow wyrm fight (54.1 s wall, 2690 s game)
PASS wyrm: defeated in 167 s (3 perches, 39 sword hits, 24 arrows for 45 damage, health left 1)
INFO wyrm fight: player took 702 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 2 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (55.5 s wall, 2870 s game)
INFO bag full: dropped 2 rotten_flesh, 8 crimson_nylium, 7 netherrack, 6 leather, 64 netherrack, 64 netherrack, 64 netherrack, 64 netherrack
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (55.5 s wall, 2876 s game)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (55.6 s wall, 2879 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (55.8 s wall, 2887 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (55.9 s wall, 2887 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (56.1 s wall, 2943 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (61.9 s wall, 2957 s game)
INFO bulk: Smite V on the sword, Power V on the bow
INFO bulk: +1 diamond_chestplate (armour)
PASS armour: 19 armour points worn
INFO bulk: +1 bow (a new bow)
FAIL blight: defeated in 601 s (388 arrows for 0 damage, 0 sword hits)
PASS blight: arrows bounce off its armour below half health (0 damage from 0)
INFO blight fight: player took 0 damage (healed by the test); 0 of 0 sword hits landed for 0
FAIL blight: the Blight Star drops and is picked up (0)
INFO star lost: Blight health 300 at 32 132 45, still listed yes, stars on the ground []
INFO star lost: player at 29.1 128.2 53.9, alive yes, 12 free slots
INFO bulk: +1 nether_star (star lost)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (73.0 s wall, 3560 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 22 advancements earned: adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, form_obsidian, iron_tools, mine_diamond, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (73.0 s wall, 3561 s game)
INFO deaths: 15, damage healed by the test: 7246 half-hearts
playthrough: 2 failed checks, 3561 s of game time in 73.0 s wall
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
