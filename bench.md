| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.831 | 1.39x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.717 | 1.60x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.71 | 1.19x |
| edit.place_ms_max | 0.732 | 0.769 | 1.05x |
| edit.place_ms_mean | 0.455 | 0.708 | 1.56x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.701 | 1.18x |
| flight16.arena_free_mb | 0.864 | 16.481 | 19.08x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.587 | 0.82x |
| flight16.chunks | 1056 | 1053 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.869 | 1.14x |
| flight16.coverage_min | 0.962 | 0.769 | 1.25x |
| flight16.cull_ms_p50 | 0.708 | 0.298 | 0.42x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.707 | 0.61x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.751 | 0.50x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.721 | 0.73x ✅ better |
| flight16.frame_ms_max | 12.652 | 14.944 | 1.18x |
| flight16.frame_ms_p50 | 4.807 | 3.474 | 0.72x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.044 | 0.87x |
| flight16.frame_ms_p99 | 7.443 | 8.243 | 1.11x |
| flight16.gen_chunks_per_s | 43.68 | 43.327 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.459 | 0.72x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.705 | 0.82x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.299 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3319.61 | 0.59x ✅ better |
| flight16.preload_ms | 1871.23 | 1885.45 | 1.01x |
| flight16.realtime | 0.998 | 1 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 342.549 | 1.20x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 13.759 | 1.61x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.537 | 1.38x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 1.789 | 0.86x |
| flight16.update_ms_max | 8.289 | 10.78 | 1.30x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.222 | 13.06x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.876 | 0.50x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.16 | 1.07x |
| flight16.worker_mesh_us | 177.949 | 253.221 | 1.42x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.213 | 54.36x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 143.804 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1682 | 0.77x |
| flight24.coverage_mean | 0.994 | 0.83 | 1.20x |
| flight24.coverage_min | 0.974 | 0.719 | 1.35x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.566 | 0.47x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.294 | 0.47x ✅ better |
| flight24.cull_walked_sections | 7607 | 3774 | 0.50x ✅ better |
| flight24.draw_calls | 3175 | 1152 | 0.36x ✅ better |
| flight24.drawn_kquads | 821.704 | 215.197 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.156 | 0.47x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.586 | 0.49x ✅ better |
| flight24.frame_ms_max | 13.319 | 11.848 | 0.89x |
| flight24.frame_ms_p50 | 7.72 | 4.49 | 0.58x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.211 | 0.66x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 7.996 | 0.77x |
| flight24.gen_chunks_per_s | 63.73 | 22.578 | 2.82x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.488 | 0.58x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.152 | 0.65x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 68.449 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3386.16 | 0.73x ✅ better |
| flight24.preload_ms | 4742.83 | 3648.24 | 0.77x ✅ better |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 514.534 | 1.00x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 8.475 | 0.73x ✅ better |
| flight24.tick_ms_p50 | 0.401 | 0.568 | 1.42x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.81 | 0.62x ✅ better |
| flight24.update_ms_max | 4.586 | 2.394 | 0.52x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.25 | 16.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.71 | 0.28x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.036 | 0.86x |
| flight24.worker_mesh_us | 177.947 | 274.743 | 1.54x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.734 | 4.40x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.989 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.078 | 0.38x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.196 | 0.64x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.406 | 0.72x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.983 | 1.18x |
| flight8.frame_ms_max | 13.232 | 20.087 | 1.52x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.493 | 0.96x |
| flight8.frame_ms_p95 | 3.197 | 2.957 | 0.92x |
| flight8.frame_ms_p99 | 4.401 | 5.128 | 1.17x |
| flight8.gen_chunks_per_s | 23.603 | 23.732 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.489 | 0.97x |
| flight8.gpu_ms_p95 | 3.081 | 2.933 | 0.95x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 954.009 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 579.016 | 0.41x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 209.439 | 1.68x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 7.167 | 0.57x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.339 | 2.15x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 0.941 | 0.77x ✅ better |
| flight8.update_ms_max | 12.421 | 3.873 | 0.31x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.024 | 2.40x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.433 | 0.50x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.12 | 0.66x ✅ better |
| flight8.worker_mesh_us | 181.115 | 257.034 | 1.42x ⚠️ worse |
| fluids.pending | 240 | 1249 | 5.20x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6300 | 2.42x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 14.917 | 4.36x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.287 | 1.27x |
| fluids.tick_ms_p95 | 1.872 | 1.366 | 0.73x ✅ better |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 6.364 | 5.67x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.873 | 1.40x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 16.654 | 6.33x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.018 | 1.74x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.678 | 1.67x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.007 | 1.46x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 7.992 | 1.96x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.458 | 2.12x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.329 | 1.76x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.809 | 1.33x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.291 | 1.78x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.328 | 1.61x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 8.143 | 2.41x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.571 | 1.23x |
| gen.chunk_ms_p95 | 3.325 | 7.99 | 2.40x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1065.28 | 1.58x ⚠️ worse |
| gen.starts_cold_ms | – | 2.028 | new |
| gen.terrain_hash | 1238443285367868 | 670778666217496 | ⚠️ changed |
| genphase.caves_ms | – | 1.057 | new |
| genphase.columns_ms | – | 0.289 | new |
| genphase.ores_ms | – | 0.268 | new |
| genphase.plants_ms | – | 0.264 | new |
| genphase.starts_ms | – | 0.008 | new |
| genphase.stone_ms | – | 0.24 | new |
| genphase.structures_ms | – | 0.269 | new |
| genphase.surface_ms | – | 0.031 | new |
| genphase.trees_ms | – | 0.052 | new |
| mesh.chunk_ms_max | 5.758 | 9.041 | 1.57x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 6.494 | 1.48x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1834.04 | 1.13x |
| mesh.section_us_mean | 139.451 | 270.593 | 1.94x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1090.05 | 1.59x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 5.443 | 1.00x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.53 | 1.10x |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 941.038 | 0.64x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 188.73 | 1.49x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 793.934 | 1.40x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.909 | 1.19x |
| mobs.tick_150_ms_max | 1.25 | 2.173 | 1.74x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.484 | 1.78x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.371 | 3.12x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.198 | 6.39x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.854 | 10.41x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.309 | 0.45x ✅ better |
| save.load_chunk_ms | 0.587 | 0.209 | 0.36x ✅ better |
| save.main_thread_ms | 5.206 | 7.766 | 1.49x ⚠️ worse |
| save.unchanged_resave_ms | 2.544 | 1.948 | 0.77x ✅ better |
| ships.assemble_ms | 19.313 | 13.309 | 0.69x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.022 | 0.81x |
| ships.blast_ms | 2.675 | 6.644 | 2.48x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 2.416 | 0.44x ✅ better |
| ships.collide_far_us | 0.214 | 0.246 | 1.15x |
| ships.collide_us | 1.047 | 0.902 | 0.86x |
| ships.dock_ms | 12.056 | 11.306 | 0.94x |
| ships.dock_remesh_s | 0.036 | 0.057 | 1.58x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.75 | 0.85x |
| ships.edit_ms_mean | 0.505 | 0.286 | 0.57x ✅ better |
| ships.edit_remesh_ms | 3.642 | 4.414 | 1.21x |
| ships.frame_encode_ms | 0.023 | 0.114 | 4.96x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.554 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.38 | 0.78x |
| ships.physics_ms_mean | 0.165 | 0.154 | 0.93x |
| ships.physics_ms_p95 | 0.213 | 0.175 | 0.82x |
| ships.spawn_frigate_ms | 2.358 | 2.284 | 0.97x |
| ships.tick_ms_max | 0.522 | 4.79 | 9.18x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.334 | 1.53x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.823 | 2.73x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.458 | 1.03x |
| startup.first_load_ms | 206.958 | 199.967 | 0.97x |
| startup.renderer_init_again_ms | 27.582 | 990.836 | 35.92x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2331.06 | 2.85x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.264 | 0.76x ✅ better |
| startup.since_launch_s | 5.923 | 10.485 | 1.77x ⚠️ worse |
| startup.textures_ms | 26.537 | 681.938 | 25.70x ⚠️ worse |
| startup.world_init_ms | 2.198 | 33.783 | 15.37x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.68 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.953 | 0.33x ✅ better |
| tnt.remesh_s | 0.087 | 0.175 | 2.01x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 12.652 | 2.34x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 0.671 | 0.15x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 12.652 | 2.34x ⚠️ worse |
