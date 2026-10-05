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
