| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.553 | 2.59x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.66 | 1.48x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.584 | 0.98x |
| edit.place_ms_max | 0.732 | 1.573 | 2.15x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.634 | 1.39x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.581 | 0.98x |
| flight16.arena_free_mb | 0.864 | 3.805 | 4.40x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.141 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.991 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.383 | 0.54x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.993 | 0.86x |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1210 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.238 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.187 | 0.79x |
| flight16.encode_ms_p95 | 2.361 | 2.949 | 1.25x |
| flight16.frame_ms_max | 12.652 | 28.109 | 2.22x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.548 | 0.95x |
| flight16.frame_ms_p95 | 5.8 | 6.613 | 1.14x |
| flight16.frame_ms_p99 | 7.443 | 9.705 | 1.30x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.635 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.407 | 0.92x |
| flight16.gpu_ms_p95 | 5.71 | 6.001 | 1.05x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 75.216 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2400.74 | 0.82x |
| flight16.preload_ms | 1871.23 | 1869.71 | 1.00x |
| flight16.realtime | 0.998 | 0.997 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 365.612 | 1.28x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 10.025 | 1.17x |
| flight16.tick_ms_p50 | 0.388 | 1.186 | 3.06x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.961 | 1.42x ⚠️ worse |
| flight16.update_ms_max | 8.289 | 3.161 | 0.38x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.279 | 16.41x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.337 | 0.77x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.711 | 1.34x ⚠️ worse |
| flight16.worker_mesh_us | 177.949 | 186.876 | 1.05x |
| flight24.arena_free_mb | 0.427 | 4.53 | 10.61x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.281 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.988 | 1.01x |
| flight24.coverage_min | 0.974 | 0.959 | 1.02x |
| flight24.cull_ms_p50 | 1.198 | 0.949 | 0.79x |
| flight24.cull_ms_p95 | 2.767 | 2.833 | 1.02x |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3021 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.235 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.266 | 0.92x |
| flight24.encode_ms_p95 | 5.237 | 5.853 | 1.12x |
| flight24.frame_ms_max | 13.319 | 30.524 | 2.29x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 7.649 | 0.99x |
| flight24.frame_ms_p95 | 9.472 | 10.202 | 1.08x |
| flight24.frame_ms_p99 | 10.337 | 14.657 | 1.42x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.612 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 7.124 | 0.92x |
| flight24.gpu_ms_p95 | 9.428 | 9.107 | 0.97x |
| flight24.hitches | 0 | 2 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 128.116 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 3770.33 | 0.65x ✅ better |
| flight24.preload_ms | 4742.83 | 4087.06 | 0.86x |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 614.128 | 1.20x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 17.683 | 1.52x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.863 | 4.65x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 4.931 | 1.68x ⚠️ worse |
| flight24.update_ms_max | 4.586 | 6.082 | 1.33x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.881 | 58.73x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.882 | 0.74x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.733 | 1.16x |
| flight24.worker_mesh_us | 177.947 | 208.547 | 1.17x |
| flight8.arena_free_mb | 2.438 | 5.342 | 2.19x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.995 | 0.99x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.084 | 0.41x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.228 | 0.75x ✅ better |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.138 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.481 | 0.86x |
| flight8.encode_ms_p95 | 0.832 | 1.233 | 1.48x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 33.785 | 2.55x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.65 | 1.02x |
| flight8.frame_ms_p95 | 3.197 | 3.923 | 1.23x |
| flight8.frame_ms_p99 | 4.401 | 9.875 | 2.24x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.621 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.631 | 1.02x |
| flight8.gpu_ms_p95 | 3.081 | 3.552 | 1.15x |
| flight8.hitches | 0 | 3 | infx ⚠️ worse |
| flight8.mesh_mb | 40.975 | 34.838 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 595.258 | 0.85x |
| flight8.preload_ms | 1398.04 | 499.588 | 0.36x ✅ better |
| flight8.realtime | 0.994 | 0.995 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 246.19 | 1.97x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 29.121 | 2.32x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.54 | 3.42x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.461 | 1.19x |
| flight8.update_ms_max | 12.421 | 2.197 | 0.18x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.009 | 0.90x |
| flight8.update_ms_p95 | 0.869 | 0.429 | 0.49x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.594 | 0.80x |
| flight8.worker_mesh_us | 181.115 | 209.765 | 1.16x |
| fluids.pending | 240 | 1550 | 6.46x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3685 | 1.41x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 10.435 | 3.05x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.459 | 2.03x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.658 | 1.42x ⚠️ worse |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.48 | 1.05x |
| frame.mesh_mb | 57.324 | 65.782 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 3.341 | 2.98x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.828 | 1.32x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 4.841 | 1.84x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.208 | 1.82x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.787 | 1.74x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.565 | 2.26x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 10.479 | 2.57x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.296 | 1.79x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.739 | 2.30x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.598 | 0.98x |
| frame_800p.gpu_ms_max | 2.405 | 3.613 | 1.50x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 2.497 | 1.21x |
| gen.chunk_ms_max | 3.382 | 6.334 | 1.87x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.044 | 0.98x |
| gen.chunk_ms_p95 | 3.325 | 5.518 | 1.66x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1490.47 | 1.13x |
| gen.starts_cold_ms | – | 0.372 | new |
| gen.terrain_hash | 1238443285367868 | 2389122056781389 | ⚠️ changed |
| genphase.caves_ms | – | 0.931 | new |
| genphase.columns_ms | – | 0.28 | new |
| genphase.ores_ms | – | 0.235 | new |
| genphase.plants_ms | – | 0.234 | new |
| genphase.starts_ms | – | 0.008 | new |
| genphase.stone_ms | – | 0.158 | new |
| genphase.structures_ms | – | 0.046 | new |
| genphase.surface_ms | – | 0.029 | new |
| genphase.trees_ms | – | 0.044 | new |
| mesh.chunk_ms_max | 5.758 | 4.948 | 0.86x |
| mesh.chunk_ms_mean | 3.347 | 2.733 | 0.82x |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 1577.97 | 0.97x |
| mesh.section_us_mean | 139.451 | 113.881 | 0.82x |
| mesh.section_us_p95 | 686.049 | 519.991 | 0.76x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 3.091 | 0.57x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.356 | 0.77x |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 931.978 | 0.63x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 98.186 | 0.77x |
| mesh_lod1.section_us_p95 | 568.032 | 442.982 | 0.78x |
| mobs.per_mob_us | 1.608 | 6.583 | 4.09x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 8.543 | 6.83x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 1.321 | 4.86x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 3.54 | 8.06x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.333 | 10.74x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.999 | 12.18x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.015 | 1.12x |
| save.chunk_ms | 2.896 | 1.95 | 0.67x ✅ better |
| save.load_chunk_ms | 0.587 | 0.364 | 0.62x ✅ better |
| save.main_thread_ms | 5.206 | 5.418 | 1.04x |
| save.unchanged_resave_ms | 2.544 | 2.948 | 1.16x |
| ships.assemble_ms | 19.313 | 37.411 | 1.94x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.015 | 0.56x ✅ better |
| ships.blast_ms | 2.675 | 7.222 | 2.70x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 4.624 | 0.85x |
| ships.collide_far_us | 0.214 | 0.273 | 1.28x |
| ships.collide_us | 1.047 | 1.038 | 0.99x |
| ships.dock_ms | 12.056 | 21.743 | 1.80x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.019 | 0.53x ✅ better |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.632 | 0.71x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.34 | 0.67x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.592 | 0.71x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.249 | 10.83x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.563 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 3.011 | 0.98x |
| ships.physics_ms_mean | 0.165 | 0.167 | 1.01x |
| ships.physics_ms_p95 | 0.213 | 0.402 | 1.89x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.755 | 0.74x ✅ better |
| ships.tick_ms_max | 0.522 | 1.292 | 2.48x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.408 | 1.86x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.926 | 3.07x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.972 | 0.69x ✅ better |
| startup.first_load_ms | 206.958 | 179.826 | 0.87x |
| startup.renderer_init_again_ms | 27.582 | 1411.47 | 51.17x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2421.66 | 2.96x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.218 | 0.63x ✅ better |
| startup.since_launch_s | 5.923 | 8.972 | 1.51x ⚠️ worse |
| startup.textures_ms | 26.537 | 828.92 | 31.24x ⚠️ worse |
| startup.world_init_ms | 2.198 | 6.345 | 2.89x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 2.488 | 0.29x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.641 | 0.57x ✅ better |
| tnt.remesh_s | 0.087 | 0.114 | 1.31x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 15.324 | 2.83x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 7.194 | 1.59x ⚠️ worse |
| tnt.tick_ms_p95 | 5.414 | 15.324 | 2.83x ⚠️ worse |
