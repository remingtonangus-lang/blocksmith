# Blocksmith CI snapshots

Commit `a0ad380c20a29f86d74767b94951fcf987d1aad3` on `claude/free-physics` — build: **success**, benchmarks: **success**, snapshots: **failure**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/36923469922

```
physicstest PASS: boat has helm, propeller and engine
physicstest boat: mass 68.0 t, submerged 0.0, draft 1.88, vy 0.000, up 1.000
physicstest PASS: boat floats upright at rest
physicstest boat: 10 s at full throttle: 40.8 blocks, speed 4.81 b/s, rider at 2.50 1.00 5.70 (deck 2.5 1.0 5.5)
physicstest PASS: boat sails under propeller power
physicstest PASS: player stays on the moving deck
physicstest boat: turned -91 degrees in 5 s
physicstest PASS: boat turns right under helm
physicstest boat: 6 sails, wind 5.0 b/s: drifted 10.2 blocks in 8 s
physicstest PASS: sails carry the boat with the wind
physicstest PASS: ship saves and loads (624 bytes)
physicstest gunboat: Assembled 135 blocks (94.1 t, 1 turret)
physicstest PASS: turret carries its cannons
physicstest gunboat: turret yaw 1.57 (wanted 1.57), bearing gap 0.000
physicstest PASS: turret turns on its ring and stays mounted
physicstest PASS: turret link saves and loads
physicstest gunboat: fired 3 shells, 20 of 20 wall blocks destroyed, 0 in flight
physicstest PASS: cannon shells fly and explode on impact
physicstest gunboat: blast removed 10 hull blocks
physicstest PASS: explosions break ship blocks
physicstest gunboat: sawn through 4 blocks: 1 new ship(s), 70 + 45 blocks
physicstest PASS: a hull cut in two becomes two ships
physicstest ramming: struck boat moved 16.7 blocks, closest centres 11.9 (hull length 12)
physicstest PASS: ships collide with each other
physicstest airship: Assembled 236 blocks (46.3 t)
physicstest airship: mass 46.3 t, 154 balloons, lift 0.15, drift -0.00 in 4 s
physicstest PASS: airship hovers
physicstest airship: climbed 11.5 in 3 s
physicstest PASS: airship climbs
physicstest airship: flew 95.2 blocks in 6 s, altitude change -0.07
physicstest PASS: airship flies level under propellers
physicstest plane: Assembled 78 blocks (25.7 t)
physicstest plane: mass 25.7 t, 38 airfoils, 6 s: 149.7 blocks, altitude change -4.9, speed 27.5, up 1.00
physicstest PASS: aircraft flies under power
physicstest plane: climb input 2 s: altitude change 11.2
physicstest PASS: aircraft climbs when pulled up
physicstest takeoff: Assembled 81 blocks (27.5 t)
physicstest takeoff: rolled 49.7 blocks in 4 s (12.0 b/s), then 3 s pulled up: climbed 11.2, up 0.72
physicstest PASS: aircraft takes off from a runway
physicstest car: Assembled 48 blocks (28.5 t)
physicstest car: mass 28.5 t, grounded yes, up 1.000, vy -0.000
physicstest PASS: car rests on its wheels
physicstest car: drove 41.1 blocks in 6 s, speed 8.42, up 1.000
physicstest PASS: car drives
physicstest car: docked 48 of 48 blocks back into the world
physicstest PASS: car docks back into the world
physicstest frigate: 3151 blocks 826 t, 1716 balloons, lift 0.24, 10 s patrol: 23.9 blocks, altitude change -6.00, up 1.000
physicstest FAIL: frigate patrols at its altitude
physicstest frigate: turret aim error 0.000 rad
physicstest PASS: frigate turret tracks a target
physicstest frigate: guns engage a player 40 blocks off: true, one on the deck: false
physicstest PASS: vessel guns engage outsiders, not boarders
physicstest frigate: captain's chest holds 3 stacks, 0 of 4 crew aboard
physicstest PASS: frigate carries loot
physicstest frigate: captured yes, piloted 3 s: 18.9 blocks
physicstest PASS: a vessel can be captured and steered
physicstest PASS: capturing a vessel earns Prize Crew
physicstest frigate: throttle held at 1.00 after letting go, 0.00 after S for 1.5 s, 0.00 after 0.3 s more
physicstest PASS: ship throttle holds and stops at zero
physicstest carriage: 1037 blocks 1925 t, grounded yes, up 1.000, 6 s: 22.3 blocks
physicstest PASS: siege carriage rolls on six wheels
physicstest PASS: siege carriage's giant gun fires
physicstest encounters: 34 frigates, 21 siege carriages in 441 regions of 2048 blocks
physicstest PASS: vessel encounters are rare
physicstest encounters: nearest frigate home at 592, 909: 1 appeared
physicstest PASS: a vessel appears when the player nears its home
physicstest sleep: 600 blocks away asleep+released true, back near awake true meshed true
physicstest PASS: far ships sleep and wake
physicstest wreck: helm gone -> wrecked yes, sank 5.4 blocks in 4 s, autopilot off
physicstest PASS: a vessel without its helm founders and sinks
physicstest: 1 checks failed, 2.4 s, ships 18
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 33) sky 0 block 0 in water, daylight 1.0
seed 12345  pos -386.2 131.4 -75.7  rd 8  chunks 1601  (drawn 74)
gen 219 ms  mesh(all, parallel) 196 ms  mesh(1 section) 0.57 ms  quads 827022 opaque / 53722 water
frame (encode+GPU, offscreen, median of 30) 1.99 ms  biome ocean
mesh slabs 156 MB, chunks 1601 (block+light arrays 142 MB), Metal allocated 187 MB
memory: resident 323 MB  (section meshes 140 MB)
wrote snaps/physicstest.png
snap.sh: line 22: exit 1
```
### Benchmarks (vs perf/baseline.json)
```
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench: calibration 1.88 ms (min 1.56, max 3.34) [0]
bench gen: stone-fill interpolation vs Lattice.sample: 0 mismatching samples (must be 0)
bench gen: 1.81 ms/chunk (p95 3.38, max 3.40) single-thread | 2121 chunks/s parallel
bench: gen took 0.6 s (live worlds 0, games 0)
bench mesh: 2.86 ms/chunk (24 sections, 85 non-empty), section mean 119 us p95 472 us max 1513 us, 3955 quads/chunk
bench mesh_lod1: 2.56 ms/chunk (24 sections, 36 non-empty), section mean 107 us p95 524 us max 1400 us, 809 quads/chunk
bench: mesh took 0.5 s (live worlds 0, games 0)
bench startup: world+game init 2 ms, first load (r 4) 171 ms, renderer 798 ms (textures 20 ms, shaders 1 ms), fill rd 12 5.00 s
bench: startup took 6.3 s (live worlds 0, games 0)
bench frame 800p rd 16: encode p50 0.72 ms, GPU p50 2.73 ms (max 5.87), 260 chunks drawn
bench frame 1080p rd 16: encode p50 0.74 ms, GPU p50 2.59 ms (max 8.84), 272 chunks drawn
bench frame 4k rd 16: encode p50 0.78 ms, GPU p50 4.19 ms (max 5.58), 272 chunks drawn
bench frame: 686 visible sections, 1078 draw calls, 180k quads
bench: frame took 3.6 s (live worlds 1, games 0)
bench edit: break mean 0.82 ms max 2.48 ms, place mean 0.84 ms max 1.97 ms (synchronous remesh)
bench: edit took 0.9 s (live worlds 1, games 0)
bench mobs: tick 0.07 ms empty, 0.30 ms with 150 mobs (p95 0.40, max 4.99), 153 alive
bench: mobs took 0.8 s (live worlds 1, games 0)
bench save: 145 chunks, save 1.31 ms/chunk (main thread 4.0 ms total, unchanged re-save 1.1 ms), load 0.32 ms/chunk (145 ok), 4.5 KB/chunk
bench: save took 0.9 s (live worlds 1, games 0)
bench tnt: blast mean 1.19 ms max 1.42 ms (main thread) | re-mesh done in 0.10 s, tick p95 1.98 max 1.98 ms
bench: tnt took 0.7 s (live worlds 1, games 0)
bench fluids: tick p50 0.16 p95 1.58 max 3.14 ms, 3011 sections re-meshed in 6 s, 318 cells still pending
bench: fluids took 6.8 s (live worlds 1, games 0)
bench ships: edit remesh 3.66 ms, blast 2.84 ms + remesh 5.51 ms (3031 blocks left, 1 pieces split off)
bench ships: drawing two vessels at 1080p adds 0.11 ms encode, 0.44 ms GPU (66 draw calls)
bench ships: docked 3071 blocks in 11.75 ms (world remesh 0.04 s), assembled 3031 in 22.69 ms
bench ships: frigate 3031 blocks spawn 2.83 ms, mesh 2.69 ms; tick 0.18 ms (p95 0.33), physics 0.11 ms; collide 2.42 us near ships, 0.59 us far; 13 ships
bench: ships took 1.3 s (live worlds 1, games 0)
bench: worlds still alive after the scenes: 1
bench: live world: jobs 0, queue ops 0, gen in flight 0, results 0/0, chunks 997
bench: wrote 95 metrics to snaps/bench_part_0.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight8: frame p50 2.29 p95 2.98 p99 4.09 max 10.95 ms, 0 hitches >25 ms | tick p95 0.81 (update p95 0.46, max 2.54) encode p95 0.61 GPU p95 2.95 ms
bench flight8: coverage min 92% mean 99% | gen 24 chunks/s (2.4 ms each on a worker) mesh 509 sections/s (131 us each) | realtime 1.00x
bench flight8: 328 chunks, chunk data 30 MB, meshes 39 MB (slabs 48 MB), resident peak 138 MB, preload 535 ms
bench: flight8 took 13.2 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight8.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight16: frame p50 4.46 p95 5.84 p99 7.86 max 13.30 ms, 0 hitches >25 ms | tick p95 1.41 (update p95 1.17, max 2.60) encode p95 1.84 GPU p95 5.82 ms
bench flight16: coverage min 96% mean 99% | gen 44 chunks/s (2.0 ms each on a worker) mesh 1977 sections/s (135 us each) | realtime 1.00x
bench flight16: 1056 chunks, chunk data 104 MB, meshes 77 MB (slabs 88 MB), resident peak 273 MB, preload 1460 ms
bench: flight16 took 14.2 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight16.json
bench: device Apple Paravirtual device, 3 cores, seed 12345
bench flight24: frame p50 9.46 p95 10.89 p99 15.72 max 25.72 ms, 1 hitches >25 ms | tick p95 2.47 (update p95 2.00, max 8.15) encode p95 5.03 GPU p95 10.75 ms
bench flight24: coverage min 97% mean 100% | gen 64 chunks/s (2.5 ms each on a worker) mesh 2456 sections/s (150 us each) | realtime 1.00x
bench flight24: 2176 chunks, chunk data 222 MB, meshes 127 MB (slabs 144 MB), resident peak 416 MB, preload 3970 ms
bench: flight24 took 16.7 s (live worlds 0, games 0)
bench: worlds still alive after the scenes: 0
bench: wrote 36 metrics to snaps/bench_part_flight24.json
bench: merged 197 metrics into snaps/bench.json
```
| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.478 | 4.13x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.816 | 1.83x ⚠️ worse |
| edit.break_ms_p50 | – | 0.685 | new |
| edit.place_ms_max | 0.732 | 1.971 | 2.69x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.836 | 1.84x ⚠️ worse |
| edit.place_ms_p50 | – | 0.686 | new |
| flight16.arena_free_mb | 0.864 | 0.707 | 0.82x |
| flight16.chunk_mb | 103.906 | 103.82 | 1.00x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.356 | 0.50x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.917 | 0.80x |
| flight16.cull_walked_sections | 2817 | 2709 | 0.96x |
| flight16.draw_calls | 1434 | 1440 | 1.00x |
| flight16.drawn_kquads | 475.516 | 456.556 | 0.96x |
| flight16.encode_ms_p50 | 1.494 | 0.807 | 0.54x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.841 | 0.78x |
| flight16.frame_ms_max | 12.652 | 13.296 | 1.05x |
| flight16.frame_ms_p50 | 4.807 | 4.457 | 0.93x |
| flight16.frame_ms_p95 | 5.8 | 5.835 | 1.01x |
| flight16.frame_ms_p99 | 7.443 | 7.855 | 1.06x |
| flight16.gen_chunks_per_s | 43.68 | 43.701 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.456 | 0.93x |
| flight16.gpu_ms_p95 | 5.71 | 5.822 | 1.02x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 77.012 | 0.95x |
| flight16.mesh_sections_per_s | 1972.83 | 1976.7 | 1.00x |
| flight16.preload_ms | 1871.23 | 1459.65 | 0.78x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 273.237 | 0.96x |
| flight16.slab_mb | 96 | 88 | 0.92x |
| flight16.tick_ms_max | 8.551 | 10.14 | 1.19x |
| flight16.tick_ms_p50 | 0.388 | 0.284 | 0.73x ✅ better |
| flight16.tick_ms_p95 | 2.08 | 1.412 | 0.68x ✅ better |
| flight16.update_ms_max | 8.289 | 2.604 | 0.31x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.009 | 0.53x ✅ better |
| flight16.update_ms_p95 | 1.74 | 1.174 | 0.67x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.038 | 1.01x |
| flight16.worker_mesh_us | 177.949 | 135.196 | 0.76x ✅ better |
| flight24.arena_free_mb | 0.427 | 0.341 | 0.80x |
| flight24.chunk_mb | 222.438 | 222.352 | 1.00x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.995 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 0.965 | 0.81x |
| flight24.cull_ms_p95 | 2.767 | 2.537 | 0.92x |
| flight24.cull_walked_sections | 7607 | 7006 | 0.92x |
| flight24.draw_calls | 3175 | 3181 | 1.00x |
| flight24.drawn_kquads | 821.704 | 802.74 | 0.98x |
| flight24.encode_ms_p50 | 2.473 | 2.012 | 0.81x |
| flight24.encode_ms_p95 | 5.237 | 5.026 | 0.96x |
| flight24.frame_ms_max | 13.319 | 25.716 | 1.93x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 9.463 | 1.23x |
| flight24.frame_ms_p95 | 9.472 | 10.887 | 1.15x |
| flight24.frame_ms_p99 | 10.337 | 15.719 | 1.52x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.684 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 9.456 | 1.23x |
| flight24.gpu_ms_p95 | 9.428 | 10.752 | 1.14x |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 126.87 | 0.97x |
| flight24.mesh_sections_per_s | 2455.22 | 2456.12 | 1.00x |
| flight24.preload_ms | 4742.83 | 3969.75 | 0.84x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 416.393 | 0.81x |
| flight24.slab_mb | 148 | 144 | 0.97x |
| flight24.tick_ms_max | 11.61 | 13.816 | 1.19x |
| flight24.tick_ms_p50 | 0.401 | 0.339 | 0.85x |
| flight24.tick_ms_p95 | 2.942 | 2.467 | 0.84x |
| flight24.update_ms_max | 4.586 | 8.148 | 1.78x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.009 | 0.60x ✅ better |
| flight24.update_ms_p95 | 2.535 | 2 | 0.79x |
| flight24.worker_gen_ms | 2.355 | 2.533 | 1.08x |
| flight24.worker_mesh_us | 177.947 | 150.15 | 0.84x |
| flight8.arena_free_mb | 2.438 | 2.625 | 1.08x |
| flight8.chunk_mb | 30.25 | 30.188 | 1.00x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.994 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.08 | 0.39x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.211 | 0.69x ✅ better |
| flight8.cull_walked_sections | 517 | 434 | 0.84x |
| flight8.draw_calls | 463 | 463 | 1.00x |
| flight8.drawn_kquads | 211.463 | 211.409 | 1.00x |
| flight8.encode_ms_p50 | 0.562 | 0.266 | 0.47x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.612 | 0.74x ✅ better |
| flight8.frame_ms_max | 13.232 | 10.952 | 0.83x |
| flight8.frame_ms_p50 | 2.588 | 2.292 | 0.89x |
| flight8.frame_ms_p95 | 3.197 | 2.982 | 0.93x |
| flight8.frame_ms_p99 | 4.401 | 4.087 | 0.93x |
| flight8.gen_chunks_per_s | 23.603 | 23.725 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.29 | 0.89x |
| flight8.gpu_ms_p95 | 3.081 | 2.954 | 0.96x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 38.624 | 0.94x |
| flight8.mesh_sections_per_s | 506.848 | 509.46 | 0.99x |
| flight8.preload_ms | 1398.04 | 535.219 | 0.38x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 138.267 | 1.11x |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 10.383 | 0.83x |
| flight8.tick_ms_p50 | 0.158 | 0.112 | 0.71x ✅ better |
| flight8.tick_ms_p95 | 1.223 | 0.809 | 0.66x ✅ better |
| flight8.update_ms_max | 12.421 | 2.545 | 0.20x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.007 | 0.70x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.465 | 0.54x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.374 | 0.73x ✅ better |
| flight8.worker_mesh_us | 181.115 | 130.969 | 0.72x ✅ better |
| fluids.pending | 240 | 318 | 1.32x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3011 | 1.16x |
| fluids.tick_ms_max | 3.42 | 3.142 | 0.92x |
| fluids.tick_ms_p50 | 0.226 | 0.16 | 0.71x ✅ better |
| fluids.tick_ms_p95 | 1.872 | 1.581 | 0.84x |
| frame.draw_calls | 1076 | 1078 | 1.00x |
| frame.drawn_chunks | 272 | 272 | 1.00x |
| frame.drawn_kquads | 178.99 | 180.53 | 1.01x |
| frame.mesh_mb | 57.324 | 55.351 | 0.97x |
| frame.visible_sections | 686 | 686 | 1.00x |
| frame_1080p.encode_ms_max | 1.123 | 2.14 | 1.91x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.737 | 1.18x |
| frame_1080p.gpu_ms_max | 2.632 | 8.84 | 3.36x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 2.595 | 1.12x |
| frame_4k.encode_ms_max | 1.603 | 1.529 | 0.95x |
| frame_4k.encode_ms_p50 | 0.691 | 0.783 | 1.13x |
| frame_4k.gpu_ms_max | 4.083 | 5.578 | 1.37x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 4.19 | 1.19x |
| frame_800p.encode_ms_max | 0.755 | 2.331 | 3.09x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.717 | 1.18x |
| frame_800p.gpu_ms_max | 2.405 | 5.873 | 2.44x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 2.73 | 1.32x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 3.401 | 1.01x |
| gen.chunk_ms_mean | 2.082 | 1.813 | 0.87x |
| gen.chunk_ms_p95 | 3.325 | 3.38 | 1.02x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 2121.12 | 0.79x |
| gen.terrain_hash | 1238443285367868 | 2107617729993301 | ⚠️ changed |
| mesh.chunk_ms_max | 5.758 | 5.043 | 0.88x |
| mesh.chunk_ms_mean | 3.347 | 2.857 | 0.85x |
| mesh.quads_per_chunk | 3763.89 | 3955.44 | 1.05x |
| mesh.section_us_max | 1621.01 | 1513 | 0.93x |
| mesh.section_us_mean | 139.451 | 119.034 | 0.85x |
| mesh.section_us_p95 | 686.049 | 472.069 | 0.69x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 4.712 | 0.87x |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.558 | 0.84x |
| mesh_lod1.quads_per_chunk | 783.333 | 809 | 1.03x |
| mesh_lod1.section_us_max | 1477.96 | 1399.99 | 0.95x |
| mesh_lod1.section_us_mean | 126.754 | 106.564 | 0.84x |
| mesh_lod1.section_us_p95 | 568.032 | 524.044 | 0.92x |
| mobs.per_mob_us | 1.608 | 1.502 | 0.93x |
| mobs.tick_150_ms_max | 1.25 | 4.989 | 3.99x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.298 | 1.10x |
| mobs.tick_150_ms_p95 | 0.439 | 0.397 | 0.90x |
| mobs.tick_base_ms_mean | 0.031 | 0.073 | 2.35x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.282 | 3.44x ⚠️ worse |
| save.chunk_kb | 4.471 | 4.459 | 1.00x |
| save.chunk_ms | 2.896 | 1.308 | 0.45x ✅ better |
| save.load_chunk_ms | 0.587 | 0.323 | 0.55x ✅ better |
| save.main_thread_ms | 5.206 | 3.959 | 0.76x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.122 | 0.44x ✅ better |
| ships.assemble_ms | – | 22.691 | new |
| ships.assemble_remesh_s | – | 0.036 | new |
| ships.blast_ms | – | 2.841 | new |
| ships.blast_remesh_ms | – | 5.513 | new |
| ships.collide_far_us | 0.214 | 0.593 | 2.77x ⚠️ worse |
| ships.collide_us | 1.047 | 2.42 | 2.31x ⚠️ worse |
| ships.dock_ms | – | 11.747 | new |
| ships.dock_remesh_s | – | 0.036 | new |
| ships.draw_calls | – | 66 | new |
| ships.edit_ms_max | 0.887 | 0.647 | 0.73x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.313 | 0.62x ✅ better |
| ships.edit_remesh_ms | – | 3.66 | new |
| ships.frame_encode_ms | – | 0.11 | new |
| ships.frame_gpu_ms | – | 0.436 | new |
| ships.mesh_frigate_ms | 3.066 | 2.687 | 0.88x |
| ships.physics_ms_mean | 0.165 | 0.114 | 0.69x ✅ better |
| ships.physics_ms_p95 | 0.213 | 0.217 | 1.02x |
| ships.spawn_frigate_ms | 2.358 | 2.835 | 1.20x |
| ships.tick_ms_max | 0.522 | 0.685 | 1.31x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.178 | 0.81x |
| ships.tick_ms_p95 | 0.302 | 0.326 | 1.08x |
| startup.fill_rd12_s | 4.324 | 4.995 | 1.16x |
| startup.first_load_ms | 206.958 | 171.283 | 0.83x |
| startup.renderer_init_again_ms | 27.582 | 17.658 | 0.64x ✅ better |
| startup.renderer_init_ms | 817.522 | 797.957 | 0.98x |
| startup.shader_compile_ms | 0.347 | 0.602 | 1.73x ⚠️ worse |
| startup.since_launch_s | 5.923 | 7.196 | 1.21x |
| startup.textures_ms | 26.537 | 20.264 | 0.76x ✅ better |
| startup.world_init_ms | 2.198 | 2.3 | 1.05x |
| tnt.blast_ms_max | 8.579 | 1.421 | 0.17x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.191 | 0.41x ✅ better |
| tnt.remesh_s | 0.087 | 0.103 | 1.18x |
| tnt.tick_ms_max | 5.414 | 1.983 | 0.37x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.517 | 0.11x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.983 | 0.37x ✅ better |
### physicstest
![physicstest.png](physicstest.png)
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
### spawn
![spawn.png](spawn.png)
