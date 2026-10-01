# Blocksmith CI snapshots

Commit `dadc2dc49da576576cc883f16171c32144f0b2d1` on `claude/youthful-knuth-5m8qqp` — build: **success**, benchmarks: **failure**, snapshots: **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/36794248164

```
textures without a painter: missing
swim pose: prone true eye 0.40000153
seed 12345  pos -407.5 127.0 -23.5  rd 8  chunks 297  (drawn 83)
gen 167 ms  mesh(all, parallel) 198 ms  mesh(1 section) 1.32 ms  quads 627169 opaque / 95272 water
frame (encode+GPU, offscreen, median of 30) 2.55 ms  biome ocean
mesh slabs 28 MB, chunks 297 (block+light arrays 23 MB), Metal allocated 56 MB
memory: resident 112 MB  (section meshes 22 MB)
wrote snaps/third_swim.png
textures without a painter: missing
seed 12345  pos -311.5 146.0 72.5  rd 8  chunks 297  (drawn 65)
gen 175 ms  mesh(all, parallel) 226 ms  mesh(1 section) 0.20 ms  quads 714357 opaque / 65674 water
frame (encode+GPU, offscreen, median of 30) 2.14 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 25 MB), Metal allocated 56 MB
memory: resident 114 MB  (section meshes 24 MB)
wrote snaps/third_front.png
path: 24 nodes, ends 0,0,5
pathtest: zombie start 10.0 from player, end 0.0, reached after 9.5 s
textures without a painter: missing
seed 12345  pos -311.5 159.0 72.5  rd 8  chunks 297  (drawn 86)
gen 222 ms  mesh(all, parallel) 269 ms  mesh(1 section) 0.34 ms  quads 714357 opaque / 65674 water
frame (encode+GPU, offscreen, median of 30) 1.56 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 25 MB), Metal allocated 56 MB
memory: resident 110 MB  (section meshes 24 MB)
wrote snaps/pathtest.png
textures without a painter: missing
seed 12345  pos 72.5 145.0 -39.5  rd 8  chunks 297  (drawn 73)
gen 173 ms  mesh(all, parallel) 277 ms  mesh(1 section) 0.95 ms  quads 1011085 opaque / 59264 water
frame (encode+GPU, offscreen, median of 30) 1.80 ms  biome paleGarden
mesh slabs 40 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 68 MB
memory: resident 114 MB  (section meshes 33 MB)
wrote snaps/ashen_grove.png
after 4.0 s: 26 mobs, villagers 
textures without a painter: missing
seed 12345  pos 72.5 143.0 -39.5  rd 8  chunks 297  (drawn 81)
gen 163 ms  mesh(all, parallel) 244 ms  mesh(1 section) 0.86 ms  quads 1011103 opaque / 59264 water
frame (encode+GPU, offscreen, median of 30) 1.93 ms  biome paleGarden
mesh slabs 40 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 68 MB
memory: resident 133 MB  (section meshes 33 MB)
wrote snaps/ashen_night.png
cave pocket at y -50
textures without a painter: missing
seed 12345  pos 40.5 14.0 -71.5  rd 8  chunks 297  (drawn 41)
gen 151 ms  mesh(all, parallel) 273 ms  mesh(1 section) 0.86 ms  quads 936527 opaque / 69951 water
frame (encode+GPU, offscreen, median of 30) 1.11 ms  biome ocean
mesh slabs 36 MB, chunks 297 (block+light arrays 26 MB), Metal allocated 64 MB
memory: resident 126 MB  (section meshes 31 MB)
wrote snaps/lush_caves.png
cave pocket at y -56
textures without a painter: missing
seed 12345  pos 72.5 8.0 184.5  rd 8  chunks 297  (drawn 46)
gen 189 ms  mesh(all, parallel) 181 ms  mesh(1 section) 0.25 ms  quads 629916 opaque / 40823 water
frame (encode+GPU, offscreen, median of 30) 0.82 ms  biome windsweptSavanna
mesh slabs 24 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 52 MB
memory: resident 112 MB  (section meshes 20 MB)
wrote snaps/dripstone_caves.png
cave pocket at y -19
textures without a painter: missing
seed 12345  pos 152.5 45.0 -311.5  rd 8  chunks 297  (drawn 48)
gen 159 ms  mesh(all, parallel) 311 ms  mesh(1 section) 0.62 ms  quads 992785 opaque / 79554 water
frame (encode+GPU, offscreen, median of 30) 1.12 ms  biome coldOcean
mesh slabs 36 MB, chunks 297 (block+light arrays 27 MB), Metal allocated 64 MB
memory: resident 133 MB  (section meshes 33 MB)
wrote snaps/deep_dark.png
textures without a painter: missing
seed 12345  pos 280.5 154.0 -103.5  rd 8  chunks 297  (drawn 58)
gen 177 ms  mesh(all, parallel) 398 ms  mesh(1 section) 0.94 ms  quads 1683150 opaque / 44984 water
frame (encode+GPU, offscreen, median of 30) 2.75 ms  biome darkForest
mesh slabs 60 MB, chunks 297 (block+light arrays 32 MB), Metal allocated 88 MB
memory: resident 140 MB  (section meshes 53 MB)
wrote snaps/dark_forest.png
naming audit: 5165 names, 0 flagged
selftest: 887 blocks, 84 mob kinds, 4/4 special recipes, bundle fill 32/64, 76 advancements
selftest ok: 82 mobs after 3 s
textures without a painter: missing
seed 12345  pos -311.5 146.0 72.5  rd 8  chunks 297  (drawn 73)
gen 236 ms  mesh(all, parallel) 235 ms  mesh(1 section) 0.19 ms  quads 714357 opaque / 65674 water
frame (encode+GPU, offscreen, median of 30) 1.76 ms  biome plains
mesh slabs 28 MB, chunks 297 (block+light arrays 25 MB), Metal allocated 56 MB
memory: resident 105 MB  (section meshes 24 MB)
wrote snaps/selftest.png
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.98 ms/chunk (p95 4.41, max 5.56) single-thread | 2076 chunks/s parallel
bench: gen took 0.4 s (live worlds 0, games 0)
bench mesh: 7.95 ms/chunk (24 sections, 85 non-empty), section mean 331 us p95 1215 us max 8035 us, 3763 quads/chunk
bench mesh_lod1: 2.88 ms/chunk (24 sections, 36 non-empty), section mean 120 us p95 563 us max 1695 us, 783 quads/chunk
bench: mesh took 0.5 s (live worlds 0, games 0)
bench startup: world+game init 2 ms, first load (r 4) 126 ms, renderer 523 ms (textures 20 ms, shaders 0 ms), fill rd 12 4.56 s
bench: startup took 5.6 s (live worlds 1, games 0)
bench frame 800p rd 16: encode p50 0.56 ms, GPU p50 1.95 ms (max 2.62), 260 chunks drawn
bench frame 1080p rd 16: encode p50 0.55 ms, GPU p50 2.20 ms (max 2.97), 272 chunks drawn
bench frame 4k rd 16: encode p50 0.56 ms, GPU p50 2.80 ms (max 4.37), 272 chunks drawn
bench frame: 686 visible sections, 1076 draw calls, 178k quads
bench: frame took 2.5 s (live worlds 2, games 0)
bench edit: break mean 0.51 ms max 1.05 ms, place mean 0.51 ms max 1.09 ms (synchronous remesh)
bench: edit took 0.6 s (live worlds 2, games 0)
bench mobs: tick 0.03 ms empty, 0.27 ms with 150 mobs (p95 0.40, max 2.10), 154 alive
bench: mobs took 0.6 s (live worlds 2, games 0)
bench save: 145 chunks, save 1.92 ms/chunk (main thread 3.5 ms total, unchanged re-save 1.4 ms), load 0.26 ms/chunk (145 ok), 4.5 KB/chunk
bench: save took 0.8 s (live worlds 2, games 0)
bench tnt: blast mean 1.83 ms max 2.88 ms (main thread) | re-mesh done in 0.04 s, tick p95 2.42 max 2.42 ms
bench: tnt took 0.8 s (live worlds 3, games 0)
bench fluids: tick p50 0.13 p95 0.92 max 2.18 ms, 2543 sections re-meshed in 6 s, 190 cells still pending
bench: fluids took 6.8 s (live worlds 4, games 0)
bench: worlds still alive after the scenes: 4
bench: live world: jobs 2, queue ops 0, gen in flight 0, results 0/2, chunks 193
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 193
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 997
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 593
bench: wrote 71 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight8: frame p50 2.18 p95 3.44 p99 8.17 max 22.21 ms, 0 hitches >25 ms | tick p95 0.87 (update p95 0.44, max 2.04) encode p95 0.63 GPU p95 3.11 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (1.5 ms each on a worker) mesh 511 sections/s (149 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 30 MB, meshes 41 MB (slabs 52 MB), resident peak 145 MB, preload 385 ms
bench: flight8 took 13.0 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 328
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight16: frame p50 4.76 p95 6.49 p99 15.13 max 24.32 ms, 0 hitches >25 ms | tick p95 1.56 (update p95 1.33, max 23.34) encode p95 1.98 GPU p95 6.28 ms
bench flight16: coverage min 96% mean 99% | gen 44 chunks/s (2.0 ms each on a worker) mesh 1970 sections/s (154 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 104 MB, meshes 81 MB (slabs 96 MB), resident peak 211 MB, preload 1459 ms
bench: flight16 took 14.3 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 1056
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight24: frame p50 7.79 p95 9.77 p99 13.74 max 22.93 ms, 0 hitches >25 ms | tick p95 2.15 (update p95 1.89, max 5.68) encode p95 4.47 GPU p95 9.77 ms
bench flight24: coverage min 97% mean 100% | gen 64 chunks/s (1.8 ms each on a worker) mesh 2451 sections/s (144 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 222 MB, meshes 131 MB (slabs 148 MB), resident peak 414 MB, preload 3202 ms
bench: flight24 took 16.1 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 2176
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 173 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.053 | 1.75x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.513 | 1.15x |
| edit.place_ms_max | 0.732 | 1.086 | 1.48x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.514 | 1.13x |
| flight16.arena_free_mb | 0.864 | 0.813 | 0.94x |
| flight16.chunk_mb | 103.906 | 103.906 | 1.00x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.39 | 0.55x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.993 | 0.86x |
| flight16.cull_walked_sections | 2817 | 2817 | 1.00x |
| flight16.draw_calls | 1434 | 1434 | 1.00x |
| flight16.drawn_kquads | 475.516 | 475.516 | 1.00x |
| flight16.encode_ms_p50 | 1.494 | 0.832 | 0.56x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.983 | 0.84x |
| flight16.frame_ms_max | 12.652 | 24.324 | 1.92x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.759 | 0.99x |
| flight16.frame_ms_p95 | 5.8 | 6.489 | 1.12x |
| flight16.frame_ms_p99 | 7.443 | 15.132 | 2.03x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.618 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.755 | 0.99x |
| flight16.gpu_ms_p95 | 5.71 | 6.28 | 1.10x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 81.28 | 1.00x |
| flight16.mesh_sections_per_s | 1972.83 | 1970.04 | 1.00x |
| flight16.preload_ms | 1871.23 | 1458.66 | 0.78x |
| flight16.realtime | 0.998 | 0.997 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 210.612 | 0.74x ✅ better |
| flight16.slab_mb | 96 | 96 | 1.00x |
| flight16.tick_ms_max | 8.551 | 23.425 | 2.74x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.317 | 0.82x |
| flight16.tick_ms_p95 | 2.08 | 1.557 | 0.75x ✅ better |
| flight16.update_ms_max | 8.289 | 23.343 | 2.82x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.01 | 0.59x ✅ better |
| flight16.update_ms_p95 | 1.74 | 1.333 | 0.77x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.02 | 1.00x |
| flight16.worker_mesh_us | 177.949 | 154.245 | 0.87x |
| flight24.arena_free_mb | 0.427 | 0.395 | 0.93x |
| flight24.chunk_mb | 222.438 | 222.438 | 1.00x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.995 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 0.965 | 0.81x |
| flight24.cull_ms_p95 | 2.767 | 2.333 | 0.84x |
| flight24.cull_walked_sections | 7607 | 7607 | 1.00x |
| flight24.draw_calls | 3175 | 3175 | 1.00x |
| flight24.drawn_kquads | 821.704 | 821.704 | 1.00x |
| flight24.encode_ms_p50 | 2.473 | 1.928 | 0.78x |
| flight24.encode_ms_p95 | 5.237 | 4.469 | 0.85x |
| flight24.frame_ms_max | 13.319 | 22.93 | 1.72x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 7.792 | 1.01x |
| flight24.frame_ms_p95 | 9.472 | 9.774 | 1.03x |
| flight24.frame_ms_p99 | 10.337 | 13.743 | 1.33x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.63 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 7.788 | 1.01x |
| flight24.gpu_ms_p95 | 9.428 | 9.772 | 1.04x |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 131.138 | 1.00x |
| flight24.mesh_sections_per_s | 2455.22 | 2451.36 | 1.00x |
| flight24.preload_ms | 4742.83 | 3201.7 | 0.68x ✅ better |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 413.565 | 0.81x |
| flight24.slab_mb | 148 | 148 | 1.00x |
| flight24.tick_ms_max | 11.61 | 7.091 | 0.61x ✅ better |
| flight24.tick_ms_p50 | 0.401 | 0.326 | 0.81x |
| flight24.tick_ms_p95 | 2.942 | 2.147 | 0.73x ✅ better |
| flight24.update_ms_max | 4.586 | 5.68 | 1.24x |
| flight24.update_ms_p50 | 0.015 | 0.009 | 0.60x ✅ better |
| flight24.update_ms_p95 | 2.535 | 1.894 | 0.75x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.83 | 0.78x |
| flight24.worker_mesh_us | 177.947 | 144.392 | 0.81x |
| flight8.arena_free_mb | 2.438 | 2.463 | 1.01x |
| flight8.chunk_mb | 30.25 | 30.25 | 1.00x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.081 | 0.40x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.211 | 0.69x ✅ better |
| flight8.cull_walked_sections | 517 | 517 | 1.00x |
| flight8.draw_calls | 463 | 463 | 1.00x |
| flight8.drawn_kquads | 211.463 | 211.463 | 1.00x |
| flight8.encode_ms_p50 | 0.562 | 0.25 | 0.44x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.631 | 0.76x ✅ better |
| flight8.frame_ms_max | 13.232 | 22.213 | 1.68x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.181 | 0.84x |
| flight8.frame_ms_p95 | 3.197 | 3.437 | 1.08x |
| flight8.frame_ms_p99 | 4.401 | 8.168 | 1.86x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.662 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.181 | 0.85x |
| flight8.gpu_ms_p95 | 3.081 | 3.111 | 1.01x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 40.975 | 1.00x |
| flight8.mesh_sections_per_s | 506.848 | 510.928 | 0.99x |
| flight8.preload_ms | 1398.04 | 385.416 | 0.28x ✅ better |
| flight8.realtime | 0.994 | 0.996 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 144.611 | 1.16x |
| flight8.slab_mb | 52 | 52 | 1.00x |
| flight8.tick_ms_max | 12.539 | 7.837 | 0.63x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.117 | 0.74x ✅ better |
| flight8.tick_ms_p95 | 1.223 | 0.871 | 0.71x ✅ better |
| flight8.update_ms_max | 12.421 | 2.042 | 0.16x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.005 | 0.50x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.443 | 0.51x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.495 | 0.46x ✅ better |
| flight8.worker_mesh_us | 181.115 | 148.585 | 0.82x |
| fluids.pending | 240 | 190 | 0.79x |
| fluids.remeshed_sections | 2605 | 2543 | 0.98x |
| fluids.tick_ms_max | 3.42 | 2.183 | 0.64x ✅ better |
| fluids.tick_ms_p50 | 0.226 | 0.125 | 0.55x ✅ better |
| fluids.tick_ms_p95 | 1.872 | 0.919 | 0.49x ✅ better |
| frame.draw_calls | 1076 | 1076 | 1.00x |
| frame.drawn_chunks | 272 | 272 | 1.00x |
| frame.drawn_kquads | 178.99 | 178.99 | 1.00x |
| frame.mesh_mb | 57.324 | 57.324 | 1.00x |
| frame.visible_sections | 686 | 686 | 1.00x |
| frame_1080p.encode_ms_max | 1.123 | 0.746 | 0.66x ✅ better |
| frame_1080p.encode_ms_p50 | 0.625 | 0.553 | 0.88x |
| frame_1080p.gpu_ms_max | 2.632 | 2.971 | 1.13x |
| frame_1080p.gpu_ms_p50 | 2.308 | 2.2 | 0.95x |
| frame_4k.encode_ms_max | 1.603 | 1.462 | 0.91x |
| frame_4k.encode_ms_p50 | 0.691 | 0.557 | 0.81x |
| frame_4k.gpu_ms_max | 4.083 | 4.374 | 1.07x |
| frame_4k.gpu_ms_p50 | 3.521 | 2.801 | 0.80x |
| frame_800p.encode_ms_max | 0.755 | 0.756 | 1.00x |
| frame_800p.encode_ms_p50 | 0.608 | 0.562 | 0.92x |
| frame_800p.gpu_ms_max | 2.405 | 2.624 | 1.09x |
| frame_800p.gpu_ms_p50 | 2.068 | 1.946 | 0.94x |
| gen.chunk_ms_max | 3.382 | 5.561 | 1.64x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.984 | 0.95x |
| gen.chunk_ms_p95 | 3.325 | 4.41 | 1.33x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 2075.99 | 0.81x |
| gen.terrain_hash | 1238443285367868 | 1238443285367868 | same |
| mesh.chunk_ms_max | 5.758 | 23.002 | 3.99x ⚠️ worse |
| mesh.chunk_ms_mean | 3.347 | 7.945 | 2.37x ❌ regression |
| mesh.quads_per_chunk | 3763.89 | 3763.89 | 1.00x |
| mesh.section_us_max | 1621.01 | 8034.94 | 4.96x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 331.049 | 2.37x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1214.98 | 1.77x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 6.153 | 1.13x |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.876 | 0.95x |
| mesh_lod1.quads_per_chunk | 783.333 | 783.333 | 1.00x |
| mesh_lod1.section_us_max | 1477.96 | 1695.04 | 1.15x |
| mesh_lod1.section_us_mean | 126.754 | 119.839 | 0.95x |
| mesh_lod1.section_us_p95 | 568.032 | 563.025 | 0.99x |
| mobs.per_mob_us | 1.608 | 1.614 | 1.00x |
| mobs.tick_150_ms_max | 1.25 | 2.102 | 1.68x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.268 | 0.99x |
| mobs.tick_150_ms_p95 | 0.439 | 0.401 | 0.91x |
| mobs.tick_base_ms_mean | 0.031 | 0.026 | 0.84x |
| mobs.tick_base_ms_p95 | 0.082 | 0.071 | 0.87x |
| save.chunk_kb | 4.471 | 4.471 | 1.00x |
| save.chunk_ms | 2.896 | 1.918 | 0.66x ✅ better |
| save.load_chunk_ms | 0.587 | 0.258 | 0.44x ✅ better |
| save.main_thread_ms | 5.206 | 3.507 | 0.67x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.386 | 0.54x ✅ better |
| startup.fill_rd12_s | 4.324 | 4.565 | 1.06x |
| startup.first_load_ms | 206.958 | 125.921 | 0.61x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 13.93 | 0.51x ✅ better |
| startup.renderer_init_ms | 817.522 | 522.791 | 0.64x ✅ better |
| startup.shader_compile_ms | 0.347 | 0.452 | 1.30x ⚠️ worse |
| startup.since_launch_s | 5.923 | 6.358 | 1.07x |
| startup.textures_ms | 26.537 | 20.125 | 0.76x ✅ better |
| startup.world_init_ms | 2.198 | 1.862 | 0.85x |
| tnt.blast_ms_max | 8.579 | 2.878 | 0.34x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.827 | 0.63x ✅ better |
| tnt.remesh_s | 0.087 | 0.04 | 0.46x ✅ better |
| tnt.tick_ms_max | 5.414 | 2.419 | 0.45x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 1.649 | 0.36x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 2.419 | 0.45x ✅ better |

**Regressions past the CI gate:**

- mesh.chunk_ms_mean: 3.347 -> 7.945 (2.37x worse, gate 1.6x)
### Synthesized sounds
- [anvil.wav](sounds/anvil.wav)
- [arrowHit.wav](sounds/arrowHit.wav)
- [attack.wav](sounds/attack.wav)
- [bell.wav](sounds/bell.wav)
- [bow.wav](sounds/bow.wav)
- [breakBlock_dirt_.wav](sounds/breakBlock_dirt_.wav)
- [breakBlock_glass_.wav](sounds/breakBlock_glass_.wav)
- [breakBlock_plant_.wav](sounds/breakBlock_plant_.wav)
- [breakBlock_sand_.wav](sounds/breakBlock_sand_.wav)
- [breakBlock_snow_.wav](sounds/breakBlock_snow_.wav)
- [breakBlock_stone_.wav](sounds/breakBlock_stone_.wav)
- [breakBlock_wood_.wav](sounds/breakBlock_wood_.wav)
- [brew.wav](sounds/brew.wav)
- [burp.wav](sounds/burp.wav)
- [caveAmbience.wav](sounds/caveAmbience.wav)
- [click.wav](sounds/click.wav)
- [creeperHiss.wav](sounds/creeperHiss.wav)
- [dig.wav](sounds/dig.wav)
- [drink.wav](sounds/drink.wav)
- [eat.wav](sounds/eat.wav)
- [enchant.wav](sounds/enchant.wav)
- [evokerCast.wav](sounds/evokerCast.wav)
- [explode.wav](sounds/explode.wav)
- [fangs.wav](sounds/fangs.wav)
- [fireball.wav](sounds/fireball.wav)
- [fireworkBlast.wav](sounds/fireworkBlast.wav)
- [fireworkBlastLarge.wav](sounds/fireworkBlastLarge.wav)
- [fireworkLaunch.wav](sounds/fireworkLaunch.wav)
- [fireworkTwinkle.wav](sounds/fireworkTwinkle.wav)
- [fizz.wav](sounds/fizz.wav)
- [glassBreak.wav](sounds/glassBreak.wav)
- [goatHorn.wav](sounds/goatHorn.wav)
- [hurt.wav](sounds/hurt.wav)
- [land.wav](sounds/land.wav)
- [levelUp.wav](sounds/levelUp.wav)
- [mobBee.wav](sounds/mobBee.wav)
- [mobBlight.wav](sounds/mobBlight.wav)
- [mobBoarling.wav](sounds/mobBoarling.wav)
- [mobCat.wav](sounds/mobCat.wav)
- [mobChicken.wav](sounds/mobChicken.wav)
- [mobCinderwisp.wav](sounds/mobCinderwisp.wav)
- [mobCow.wav](sounds/mobCow.wav)
- [mobGolem.wav](sounds/mobGolem.wav)
- [mobHorse.wav](sounds/mobHorse.wav)
- [mobLlama.wav](sounds/mobLlama.wav)
- [mobPig.wav](sounds/mobPig.wav)
- [mobRavager.wav](sounds/mobRavager.wav)
- [mobSheep.wav](sounds/mobSheep.wav)
- [mobSkeleton.wav](sounds/mobSkeleton.wav)
- [mobSlime.wav](sounds/mobSlime.wav)
- [mobSpider.wav](sounds/mobSpider.wav)
- [mobUndeadBoarling.wav](sounds/mobUndeadBoarling.wav)
- [mobVex.wav](sounds/mobVex.wav)
- [mobVillager.wav](sounds/mobVillager.wav)
- [mobVoidwalker.wav](sounds/mobVoidwalker.wav)
- [mobWailer.wav](sounds/mobWailer.wav)
- [mobWarden.wav](sounds/mobWarden.wav)
- [mobWolf.wav](sounds/mobWolf.wav)
- [mobZombie.wav](sounds/mobZombie.wav)
- [open.wav](sounds/open.wav)
- [pickup.wav](sounds/pickup.wav)
- [place_dirt_.wav](sounds/place_dirt_.wav)
- [place_glass_.wav](sounds/place_glass_.wav)
- [place_plant_.wav](sounds/place_plant_.wav)
- [place_sand_.wav](sounds/place_sand_.wav)
- [place_snow_.wav](sounds/place_snow_.wav)
- [place_stone_.wav](sounds/place_stone_.wav)
- [place_wood_.wav](sounds/place_wood_.wav)
- [raidHorn.wav](sounds/raidHorn.wav)
- [rain.wav](sounds/rain.wav)
- [splash.wav](sounds/splash.wav)
- [step_dirt_.wav](sounds/step_dirt_.wav)
- [step_glass_.wav](sounds/step_glass_.wav)
- [step_plant_.wav](sounds/step_plant_.wav)
- [step_sand_.wav](sounds/step_sand_.wav)
- [step_snow_.wav](sounds/step_snow_.wav)
- [step_stone_.wav](sounds/step_stone_.wav)
- [step_wood_.wav](sounds/step_wood_.wav)
- [thunder.wav](sounds/thunder.wav)
- [witherShoot.wav](sounds/witherShoot.wav)
- [witherSpawn.wav](sounds/witherSpawn.wav)
- [xp.wav](sounds/xp.wav)
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
### aerial24
![aerial24.png](aerial24.png)
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
### ashen_night
![ashen_night.png](ashen_night.png)
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
### brewing
![brewing.png](brewing.png)
### clouds
![clouds.png](clouds.png)
### commands
![commands.png](commands.png)
### copper
![copper.png](copper.png)
### crafting
![crafting.png](crafting.png)
### create
![create.png](create.png)
### creative
![creative.png](creative.png)
### dark_forest
![dark_forest.png](dark_forest.png)
### death
![death.png](death.png)
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
### fireworks
![fireworks.png](fireworks.png)
### forest
![forest.png](forest.png)
### forest_in
![forest_in.png](forest_in.png)
### fortress
![fortress.png](fortress.png)
### fortress_far
![fortress_far.png](fortress_far.png)
### furnace
![furnace.png](furnace.png)
### heads
![heads.png](heads.png)
### hostile
![hostile.png](hostile.png)
### inventory
![inventory.png](inventory.png)
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
### mobs
![mobs.png](mobs.png)
### mobs_g
![mobs_g.png](mobs_g.png)
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
### options
![options.png](options.png)
### outpost
![outpost.png](outpost.png)
### outpost_close
![outpost_close.png](outpost_close.png)
### pathtest
![pathtest.png](pathtest.png)
### pause
![pause.png](pause.png)
### portal
![portal.png](portal.png)
### rain
![rain.png](rain.png)
### recipes
![recipes.png](recipes.png)
### redstone
![redstone.png](redstone.png)
### ruined_portal
![ruined_portal.png](ruined_portal.png)
### selftest
![selftest.png](selftest.png)
### shipwreck
![shipwreck.png](shipwreck.png)
### sim
![sim.png](sim.png)
### snowfall
![snowfall.png](snowfall.png)
### snowslope
![snowslope.png](snowslope.png)
### snowy
![snowy.png](snowy.png)
### spawn
![spawn.png](spawn.png)
### stars
![stars.png](stars.png)
### stronghold
![stronghold.png](stronghold.png)
### sunset
![sunset.png](sunset.png)
### survival
![survival.png](survival.png)
### temple
![temple.png](temple.png)
### temple2
![temple2.png](temple2.png)
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
### trade
![trade.png](trade.png)
### trial_chambers
![trial_chambers.png](trial_chambers.png)
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
