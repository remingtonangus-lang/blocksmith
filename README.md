# Blocksmith CI snapshots (heavy lane)

Commit `fa80a8e975d2751159fc87643ec9cb405df0191c` on `claude/happy-brown-vxalk8`: build **success**, heavy jobs **success**
- checks: success
- perf: success
- play: success
- shots: success
- smoke: success

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37048828104

```
textures without a painter: missing
textures: 1665 layers at 128 px, BC3, 34.7 MB with mips (build 760 ms, upload 286 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 69) sky 15 block 8 in bush, daylight 1.0
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=48.8 hash=ce0b3dcbd9631eee
imagecheck agent_door_777.png magenta=0.00000 black=0.0000 white=0.0008 std=48.8 hash=ce0b3dcbd9631eee
seed 777  pos 959.5 138.0 272.5  rd 8  chunks 297  (drawn 82)
gen 257 ms  mesh(all, parallel) 230 ms  mesh(1 section) 0.78 ms  quads 765073 opaque / 11714 water
frame (encode+GPU, offscreen, median of 30) 4.49 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 210 MB
memory: resident 266 MB  (section meshes 24 MB)
wrote snaps/agent_door_777.png
naming audit: 5898 names, 0 flagged
selftest: 982 blocks, 97 mob kinds, 4/4 special recipes, bundle fill 32/64, 83 advancements
selftest ok: 188 mobs after 3 s
textures without a painter: missing
textures: 1665 layers at 128 px, BC3, 34.7 MB with mips (build 988 ms, upload 324 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck selftest.png magenta=0.00000 black=0.0002 white=0.0090 std=51.6 hash=fbcb5eea2c38246c
imagecheck selftest.png magenta=0.00000 black=0.0002 white=0.0090 std=51.6 hash=fbcb5eea2c38246c
seed 12345  pos -87.5 135.0 104.5  rd 8  chunks 297  (drawn 78)
gen 256 ms  mesh(all, parallel) 211 ms  mesh(1 section) 0.31 ms  quads 793167 opaque / 16522 water
frame (encode+GPU, offscreen, median of 30) 5.52 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 210 MB
memory: resident 261 MB  (section meshes 25 MB)
wrote snaps/selftest.png
structure village at 14 129 -322 (38 pieces, framed)
textures without a painter: missing
textures: 1665 layers at 128 px, BC3, 34.7 MB with mips (build 932 ms, upload 286 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 136) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=51.9 hash=c35a08f292608e7d flicker=0.00087
imagecheck flicker_village.png magenta=0.00000 black=0.0000 white=0.0008 std=51.9 hash=c35a08f292608e7d flicker=0.00087
seed 12345  pos -24.8 218.4 -355.8  rd 8  chunks 297  (drawn 80)
gen 220 ms  mesh(all, parallel) 455 ms  mesh(1 section) 1.10 ms  quads 1583161 opaque / 12820 water
frame (encode+GPU, offscreen, median of 30) 5.35 ms  biome taiga
mesh slabs 56 MB, chunks 297 (block+light arrays 37 MB), Metal allocated 238 MB
memory: resident 319 MB  (section meshes 49 MB)
wrote snaps/flicker_village.png
textures without a painter: missing
textures: 1665 layers at 128 px, BC3, 34.7 MB with mips (build 873 ms, upload 310 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 87) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=52.9 hash=f138fea781c509df flicker=0.00038
imagecheck flicker_forest.png magenta=0.00000 black=0.0000 white=0.0008 std=52.9 hash=f138fea781c509df flicker=0.00038
seed 12345  pos -135.5 173.0 -39.5  rd 8  chunks 297  (drawn 79)
gen 228 ms  mesh(all, parallel) 385 ms  mesh(1 section) 1.26 ms  quads 1123696 opaque / 9408 water
frame (encode+GPU, offscreen, median of 30) 5.30 ms  biome forest
mesh slabs 40 MB, chunks 297 (block+light arrays 29 MB), Metal allocated 210 MB
memory: resident 278 MB  (section meshes 35 MB)
wrote snaps/flicker_forest.png
textures without a painter: missing
textures: 1665 layers at 128 px, BC3, 34.7 MB with mips (build 691 ms, upload 238 ms)
light probe: eye sky 15 block 6 in air; floor+1 (y 70) sky 15 block 0 in air, daylight 1.0
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0015 std=43.0 hash=c2a236da3c96aa85 flicker=0.00099
imagecheck flicker_build.png magenta=0.00000 black=0.0000 white=0.0015 std=43.0 hash=c2a236da3c96aa85 flicker=0.00099
seed 12345  pos -87.5 140.0 104.5  rd 8  chunks 297  (drawn 75)
gen 214 ms  mesh(all, parallel) 179 ms  mesh(1 section) 0.29 ms  quads 793380 opaque / 16522 water
frame (encode+GPU, offscreen, median of 30) 4.43 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 198 MB
memory: resident 257 MB  (section meshes 25 MB)
wrote snaps/flicker_build.png
imagecheck: 133 frames, black_frame 1, missing_texture 2
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 2.03 ms (min 1.41, max 3.83) [0]
bench: gen starts
bench gen phases (ms/chunk): columns 0.29, stone 0.16, surface 0.03, caves 1.12, ores 0.33, trees 0.06, plants 0.22, starts 0.36, structures 0.04
bench gen structure starts (ms over 24 chunks): village 3.7, pillager_outpost 2.1, mineshaft 1.4, fossil 0.6, shipwreck 0.6, desert_well 0.4, ocean_ruin 0.4, ruined_portal 0.2
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 2.71 ms/chunk (p95 4.83, max 7.21) single-thread | 1215 chunks/s parallel
bench: gen took 0.6 s (live worlds 0, games 0)
bench: mesh starts
bench mesh: 2.18 ms/chunk (24 sections, 91 non-empty), section mean 91 us p95 448 us max 622 us, 4640 quads/chunk
bench mesh_lod1: 2.06 ms/chunk (24 sections, 47 non-empty), section mean 86 us p95 422 us max 518 us, 1247 quads/chunk
bench: mesh took 0.5 s (live worlds 0, games 0)
bench: startup starts
bench startup: world+game init 4 ms, first load (r 4) 218 ms, renderer 2510 ms (textures 790 ms, shaders 0 ms), fill rd 12 3.15 s
bench: startup took 8.2 s (live worlds 0, games 0)
bench: frame starts
bench frame 800p rd 16: encode p50 1.27 ms, GPU p50 3.67 ms (max 6.07), 260 chunks drawn
bench frame 1080p rd 16: encode p50 0.89 ms, GPU p50 4.27 ms (max 6.08), 277 chunks drawn
bench frame 4k rd 16: encode p50 1.24 ms, GPU p50 6.20 ms (max 6.73), 277 chunks drawn
bench frame: 574 visible sections, 948 draw calls, 187k quads
bench: frame took 4.4 s (live worlds 0, games 0)
bench: edit starts
bench edit: break mean 0.78 ms max 1.66 ms, place mean 0.80 ms max 1.91 ms (synchronous remesh)
bench: edit took 0.8 s (live worlds 0, games 0)
bench: mobs starts
bench mobs: tick 0.48 ms empty, 1.23 ms with 150 mobs (p95 3.25, max 5.66), 205 alive
bench: mobs took 1.0 s (live worlds 0, games 0)
bench: save starts
bench save: 145 chunks, save 1.30 ms/chunk (main thread 3.0 ms total, unchanged re-save 1.0 ms), load 0.21 ms/chunk (145 ok), 5.0 KB/chunk
bench: save took 0.8 s (live worlds 0, games 0)
bench: tnt starts
bench tnt: blast mean 1.57 ms max 1.69 ms (main thread) | re-mesh done in 0.05 s, tick p95 7.57 max 7.57 ms
bench: tnt took 0.7 s (live worlds 0, games 0)
bench: fluids starts
bench fluids: tick p50 0.35 p95 1.66 max 4.07 ms, 3621 sections re-meshed in 6 s, 1330 cells still pending
bench: fluids took 6.7 s (live worlds 0, games 0)
bench: ships starts
bench ships: edit remesh 2.58 ms, blast 1.80 ms + remesh 4.09 ms (3031 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.04 ms encode, 0.18 ms GPU (66 draw calls)
bench ships: docked 3071 blocks in 12.24 ms (world remesh 0.01 s), assembled 3031 in 21.57 ms
bench ships: frigate 3031 blocks spawn 2.34 ms, mesh 5.08 ms; tick 0.48 ms (p95 1.37), physics 0.15 ms; collide 0.98 us near ships, 0.24 us far; 13 ships
bench: ships took 2.3 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 104 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight8 starts
bench flight8: frame p50 2.56 p95 4.32 p99 6.92 max 13.65 ms, 0 hitches >25 ms | tick p95 2.19 (update p95 0.59, max 3.63) encode p95 2.11 GPU p95 3.52 ms
bench flight8: coverage min 93% mean 100% | gen 24 chunks/s (2.6 ms each on a worker) mesh 598 sections/s (172 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 34 MB, meshes 35 MB (slabs 48 MB), resident peak 228 MB, preload 440 ms
bench: flight8 took 14.2 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight16 starts
bench flight16: frame p50 4.34 p95 6.58 p99 8.79 max 27.77 ms, 1 hitches >25 ms | tick p95 2.95 (update p95 1.05, max 2.16) encode p95 3.41 GPU p95 5.26 ms
bench flight16: coverage min 96% mean 99% | gen 44 chunks/s (2.4 ms each on a worker) mesh 2395 sections/s (159 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 113 MB, meshes 75 MB (slabs 92 MB), resident peak 361 MB, preload 1675 ms
bench: flight16 took 15.6 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: flight24 starts
bench flight24: frame p50 7.35 p95 11.17 p99 15.62 max 21.59 ms, 0 hitches >25 ms | tick p95 5.31 (update p95 1.85, max 4.29) encode p95 6.04 GPU p95 8.89 ms
bench flight24: coverage min 95% mean 99% | gen 64 chunks/s (2.5 ms each on a worker) mesh 3827 sections/s (193 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 239 MB, meshes 127 MB (slabs 148 MB), resident peak 707 MB, preload 3828 ms
bench: flight24 took 17.9 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 206 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.658 | 2.76x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.785 | 1.76x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.6 | 1.01x |
| edit.place_ms_max | 0.732 | 1.907 | 2.61x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.797 | 1.75x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.604 | 1.02x |
| flight16.arena_free_mb | 0.864 | 3.847 | 4.45x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.113 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.304 | 0.43x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.777 | 0.67x ✅ better |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1214 | 0.85x |
| flight16.drawn_kquads | 475.516 | 294.988 | 0.62x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.354 | 0.91x |
| flight16.encode_ms_p95 | 2.361 | 3.414 | 1.45x ⚠️ worse |
| flight16.frame_ms_max | 12.652 | 27.766 | 2.19x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.336 | 0.90x |
| flight16.frame_ms_p95 | 5.8 | 6.58 | 1.13x |
| flight16.frame_ms_p99 | 7.443 | 8.791 | 1.18x |
| flight16.gen_chunks_per_s | 43.68 | 43.709 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.233 | 0.88x |
| flight16.gpu_ms_p95 | 5.71 | 5.265 | 0.92x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 74.914 | 0.92x |
| flight16.mesh_sections_per_s | 1972.83 | 2394.6 | 0.82x |
| flight16.preload_ms | 1871.23 | 1674.82 | 0.90x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 361.487 | 1.26x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 19.064 | 2.23x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.974 | 2.51x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.953 | 1.42x ⚠️ worse |
| flight16.update_ms_max | 8.289 | 2.16 | 0.26x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.286 | 16.82x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.049 | 0.60x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.362 | 1.17x |
| flight16.worker_mesh_us | 177.949 | 158.829 | 0.89x |
| flight24.arena_free_mb | 0.427 | 3.988 | 9.34x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.262 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.985 | 1.01x |
| flight24.coverage_min | 0.974 | 0.947 | 1.03x |
| flight24.cull_ms_p50 | 1.198 | 0.795 | 0.66x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.207 | 0.80x |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3024 | 0.95x |
| flight24.drawn_kquads | 821.704 | 583.424 | 0.71x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.437 | 0.99x |
| flight24.encode_ms_p95 | 5.237 | 6.042 | 1.15x |
| flight24.frame_ms_max | 13.319 | 21.594 | 1.62x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 7.346 | 0.95x |
| flight24.frame_ms_p95 | 9.472 | 11.168 | 1.18x |
| flight24.frame_ms_p99 | 10.337 | 15.62 | 1.51x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.715 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.947 | 0.90x |
| flight24.gpu_ms_p95 | 9.428 | 8.889 | 0.94x |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 127.299 | 0.97x |
| flight24.mesh_sections_per_s | 2455.22 | 3826.64 | 0.64x ✅ better |
| flight24.preload_ms | 4742.83 | 3827.59 | 0.81x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 707.394 | 1.38x ⚠️ worse |
| flight24.slab_mb | 148 | 148 | 1.00x |
| flight24.tick_ms_max | 11.61 | 16.8 | 1.45x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.658 | 4.13x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 5.307 | 1.80x ⚠️ worse |
| flight24.update_ms_max | 4.586 | 4.29 | 0.94x |
| flight24.update_ms_p50 | 0.015 | 0.764 | 50.93x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.849 | 0.73x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.517 | 1.07x |
| flight24.worker_mesh_us | 177.947 | 192.978 | 1.08x |
| flight8.arena_free_mb | 2.438 | 5.051 | 2.07x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.996 | 0.99x |
| flight8.coverage_min | 0.924 | 0.933 | 0.99x |
| flight8.cull_ms_p50 | 0.204 | 0.079 | 0.39x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.213 | 0.70x ✅ better |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 257 | 0.56x ✅ better |
| flight8.drawn_kquads | 211.463 | 96.234 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.761 | 1.35x ⚠️ worse |
| flight8.encode_ms_p95 | 0.832 | 2.111 | 2.54x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 13.652 | 1.03x |
| flight8.frame_ms_p50 | 2.588 | 2.559 | 0.99x |
| flight8.frame_ms_p95 | 3.197 | 4.317 | 1.35x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 6.924 | 1.57x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.724 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.517 | 0.98x |
| flight8.gpu_ms_p95 | 3.081 | 3.521 | 1.14x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 34.754 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 597.833 | 0.85x |
| flight8.preload_ms | 1398.04 | 440.39 | 0.32x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 227.908 | 1.83x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 8.021 | 0.64x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.529 | 3.35x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 2.186 | 1.79x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 3.625 | 0.29x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.01 | 1.00x |
| flight8.update_ms_p95 | 0.869 | 0.593 | 0.68x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.611 | 0.81x |
| flight8.worker_mesh_us | 181.115 | 172.031 | 0.95x |
| fluids.pending | 240 | 1330 | 5.54x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3621 | 1.39x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 4.068 | 1.19x |
| fluids.tick_ms_p50 | 0.226 | 0.348 | 1.54x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.664 | 0.89x |
| frame.draw_calls | 1076 | 948 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 187.394 | 1.05x |
| frame.mesh_mb | 57.324 | 65.246 | 1.14x |
| frame.visible_sections | 686 | 574 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 3.618 | 3.22x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.894 | 1.43x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 6.081 | 2.31x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.27 | 1.85x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 3.173 | 1.98x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.237 | 1.79x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 6.728 | 1.65x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.2 | 1.76x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.298 | 4.37x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.268 | 2.09x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 6.067 | 2.52x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.665 | 1.77x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 7.208 | 2.13x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.714 | 1.30x ⚠️ worse |
| gen.chunk_ms_p95 | 3.325 | 4.829 | 1.45x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1215.16 | 1.39x ⚠️ worse |
| gen.terrain_hash | 1238443285367868 | 402044516665604 | ⚠️ changed |
| genphase.caves_ms | – | 1.122 | new |
| genphase.columns_ms | – | 0.289 | new |
| genphase.ores_ms | – | 0.33 | new |
| genphase.plants_ms | – | 0.22 | new |
| genphase.starts_ms | – | 0.357 | new |
| genphase.stone_ms | – | 0.165 | new |
| genphase.structures_ms | – | 0.045 | new |
| genphase.surface_ms | – | 0.033 | new |
| genphase.trees_ms | – | 0.058 | new |
| mesh.chunk_ms_max | 5.758 | 2.523 | 0.44x ✅ better |
| mesh.chunk_ms_mean | 3.347 | 2.18 | 0.65x ✅ better |
| mesh.quads_per_chunk | 3763.89 | 4640.22 | 1.23x |
| mesh.section_us_max | 1621.01 | 621.915 | 0.38x ✅ better |
| mesh.section_us_mean | 139.451 | 90.833 | 0.65x ✅ better |
| mesh.section_us_p95 | 686.049 | 447.989 | 0.65x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 2.5 | 0.46x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.056 | 0.68x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1247.44 | 1.59x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 517.964 | 0.35x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 85.678 | 0.68x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 422.001 | 0.74x ✅ better |
| mobs.per_mob_us | 1.608 | 5.011 | 3.12x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 5.664 | 4.53x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 1.235 | 4.54x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 3.252 | 7.41x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.483 | 15.58x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 2.159 | 26.33x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.013 | 1.12x |
| save.chunk_ms | 2.896 | 1.297 | 0.45x ✅ better |
| save.load_chunk_ms | 0.587 | 0.211 | 0.36x ✅ better |
| save.main_thread_ms | 5.206 | 2.978 | 0.57x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.05 | 0.41x ✅ better |
| ships.assemble_ms | 19.313 | 21.573 | 1.12x |
| ships.assemble_remesh_s | 0.027 | 0.007 | 0.26x ✅ better |
| ships.blast_ms | 2.675 | 1.797 | 0.67x ✅ better |
| ships.blast_remesh_ms | 5.466 | 4.094 | 0.75x ✅ better |
| ships.collide_far_us | 0.214 | 0.239 | 1.12x |
| ships.collide_us | 1.047 | 0.977 | 0.93x |
| ships.dock_ms | 12.056 | 12.243 | 1.02x |
| ships.dock_remesh_s | 0.036 | 0.011 | 0.31x ✅ better |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.55 | 0.62x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.267 | 0.53x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.581 | 0.71x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.038 | 1.65x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.179 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 5.077 | 1.66x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.152 | 0.92x |
| ships.physics_ms_p95 | 0.213 | 0.351 | 1.65x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 2.337 | 0.99x |
| ships.tick_ms_max | 0.522 | 3.542 | 6.79x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.482 | 2.20x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.366 | 4.52x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.148 | 0.73x ✅ better |
| startup.first_load_ms | 206.958 | 218.192 | 1.05x |
| startup.renderer_init_again_ms | 27.582 | 1124.68 | 40.78x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2509.67 | 3.07x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.245 | 0.71x ✅ better |
| startup.since_launch_s | 5.923 | 8.963 | 1.51x ⚠️ worse |
| startup.textures_ms | 26.537 | 790.338 | 29.78x ⚠️ worse |
| startup.world_init_ms | 2.198 | 3.663 | 1.67x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.687 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.566 | 0.54x ✅ better |
| tnt.remesh_s | 0.087 | 0.055 | 0.63x ✅ better |
| tnt.tick_ms_max | 5.414 | 7.572 | 1.40x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 2.151 | 0.47x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.572 | 1.40x ⚠️ worse |
### Smoke test
```
smoke rd 24: menu tour: no help line for vol:4
smoke rd 24: menu tour: no help line for vol:5
smoke rd 24: menu tour: no help line for vol:6
smoke rd 24: menu tour: no help line for vol:7
smoke rd 24: menu tour: no help line for vol:8
smoke rd 24: menu tour: no help line for vol:2
smoke rd 24: menu tour: no help line for vol:3
smoke rd 24: menu tour: no help line for vol:4
smoke rd 24: menu tour: no help line for vol:5
smoke rd 24: menu tour: no help line for vol:6
smoke rd 24: menu tour: no help line for vol:7
smoke rd 24: menu tour: no help line for vol:8
smoke rd 24: menu tour: 20 screens, 187 rows hovered; 20 block screens opened
smoke rd 24 Fast: 30 s, frame 13.5 ms, resident 731 MB, Metal 285 MB, mobs 600, coverage 100%
smoke rd 24 Fast: 40 s, frame 19.3 ms, resident 968 MB, Metal 333 MB, mobs 534, coverage 96%
smoke rd 24 Fast: 50 s, frame 15.2 ms, resident 1208 MB, Metal 357 MB, mobs 437, coverage 98%
smoke rd 24 Fast: 60 s, frame 22.4 ms, resident 1477 MB, Metal 417 MB, mobs 388, coverage 96%
smoke rd 24: 3600 frames in 62.0 s wall, frame p50 14.06 p95 23.03 p99 30.94 max 247.35 ms, coverage min 30%, mobs max 613, travelled 1230 blocks, resident peak 1464 MB, menu closed
smoke rd 24 Fast: PASS
smoke: PASS at render distance 8 16 24 24f
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
PASS mine: 3 cobblestone with a wooden pickaxe (3 mined; bare hand would take 7.5 s and drop nothing)
INFO bulk: +8 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.6 s wall, 19 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 1
INFO bulk: +5 raw_iron (more iron ore)
PASS place: furnace placed with a right click (furnace[south])
PASS smelt: 6 iron ingots after 82 s
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (2.0 s wall, 83 s game)
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
---- obsidian + portal (2.1 s wall, 85 s game)
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (2.9 s wall, 103 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 138 blocks from the portal
PASS fortress: 4 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 8 cinder rods from 17 cinderwisps in 226 s
INFO cinder rod rate 0.47 per kill (reference 0.5 without looting)
PASS fortress: cinder rod rate 0.47 per kill is plausible (reference 0.5)
---- void pearls (5.9 s wall, 331 s game)
PASS voidwalkers: 12 void pearls from 22 kills
---- back to the surface (15.6 s wall, 769 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (15.9 s wall, 774 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
---- stronghold (15.9 s wall, 778 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 3 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (16.2 s wall, 779 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (16.4 s wall, 790 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 447 health so far (topped up)
---- hollow wyrm fight (16.7 s wall, 812 s game)
PASS wyrm: defeated in 199 s (3 perches, 21 sword hits, 28 arrows for 50 damage, health left 1)
INFO wyrm fight: player took 136 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (12000 points, level 14 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (19.0 s wall, 1025 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (19.1 s wall, 1031 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (19.2 s wall, 1034 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
PASS rift: the return rift leads back to the central island (90 blocks out)
---- save + reload (19.4 s wall, 1042 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (19.5 s wall, 1042 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (19.7 s wall, 1098 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (26.5 s wall, 1111 s game)
INFO bulk: Smite V on the sword, Power V on the bow
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
PASS blight: defeated in 37 s (15 arrows for 169 damage, 8 sword hits)
PASS blight: arrows bounce off its armour below half health (0 damage from 3)
INFO blight fight: player took 108 damage (healed by the test); 8 of 8 sword hits landed for 155
PASS blight: the Blight Star drops and is picked up (1)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (27.8 s wall, 1170 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 20 advancements earned: adventure/kill_a_mob, adventure/root, adventure/shoot_arrow, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (27.8 s wall, 1171 s game)
INFO deaths: 0, damage healed by the test: 738 half-hearts
playthrough: 0 failed checks, 1171 s of game time in 27.8 s wall
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
### captains
![captains.png](captains.png)
### cave_torches
![cave_torches.png](cave_torches.png)
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
### copper
![copper.png](copper.png)
### copper_golems
![copper_golems.png](copper_golems.png)
### crack
![crack.png](crack.png)
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
### issue_2
![issue_2.png](issue_2.png)
### issue_3
![issue_3.png](issue_3.png)
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
### ship_car
![ship_car.png](ship_car.png)
### ship_carriage
![ship_carriage.png](ship_carriage.png)
### ship_deck
![ship_deck.png](ship_deck.png)
### ship_frigate
![ship_frigate.png](ship_frigate.png)
### ship_gunboat
![ship_gunboat.png](ship_gunboat.png)
### ship_plane
![ship_plane.png](ship_plane.png)
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
### soldiers
![soldiers.png](soldiers.png)
### spawn
![spawn.png](spawn.png)
### spawn_portal_check
![spawn_portal_check.png](spawn_portal_check.png)
### spear_hold
![spear_hold.png](spear_hold.png)
### stars
![stars.png](stars.png)
### steelhold
![steelhold.png](steelhold.png)
### steelhold_armory
![steelhold_armory.png](steelhold_armory.png)
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
### texsrc_procedural_cliff
![texsrc_procedural_cliff.png](texsrc_procedural_cliff.png)
### texsrc_procedural_forest
![texsrc_procedural_forest.png](texsrc_procedural_forest.png)
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
### trial_chambers
![trial_chambers.png](trial_chambers.png)
### tv_combat
![tv_combat.png](tv_combat.png)
### tv_confirm
![tv_confirm.png](tv_confirm.png)
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
### water_flow
![water_flow.png](water_flow.png)
