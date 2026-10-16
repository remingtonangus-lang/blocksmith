| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.014 | 3.36x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.023 | 2.29x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.837 | 1.41x ⚠️ worse |
| edit.place_ms_max | 0.732 | 2.005 | 2.74x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.966 | 2.12x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.826 | 1.39x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 16.14 | 18.68x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.858 | 1.16x |
| flight16.coverage_min | 0.962 | 0.747 | 1.29x |
| flight16.cull_ms_p50 | 0.708 | 0.326 | 0.46x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.903 | 0.78x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.819 | 0.55x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.119 | 0.90x |
| flight16.frame_ms_max | 12.652 | 30.055 | 2.38x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.374 | 0.70x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.6 | 0.97x |
| flight16.frame_ms_p99 | 7.443 | 10.824 | 1.45x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.149 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.358 | 0.70x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.875 | 0.85x |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.429 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3218.77 | 0.61x ✅ better |
| flight16.preload_ms | 1871.23 | 2017.77 | 1.08x |
| flight16.realtime | 0.998 | 0.998 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 325.987 | 1.14x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 24.622 | 2.88x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.638 | 1.64x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.081 | 1.00x |
| flight16.update_ms_max | 8.289 | 7.344 | 0.89x |
| flight16.update_ms_p50 | 0.017 | 0.274 | 16.12x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.961 | 0.55x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.392 | 1.18x |
| flight16.worker_mesh_us | 177.949 | 287.311 | 1.61x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.685 | 55.47x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 141.851 | 0.64x ✅ better |
| flight24.chunks | 2176 | 1658 | 0.76x ✅ better |
| flight24.coverage_mean | 0.994 | 0.829 | 1.20x |
| flight24.coverage_min | 0.974 | 0.715 | 1.36x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.608 | 0.51x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.257 | 0.45x ✅ better |
| flight24.cull_walked_sections | 7607 | 3518 | 0.46x ✅ better |
| flight24.draw_calls | 3175 | 1075 | 0.34x ✅ better |
| flight24.drawn_kquads | 821.704 | 204.292 | 0.25x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.242 | 0.50x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.427 | 0.46x ✅ better |
| flight24.frame_ms_max | 13.319 | 19.612 | 1.47x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 3.874 | 0.50x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.864 | 0.62x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 6.675 | 0.65x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 20.507 | 3.11x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 3.868 | 0.50x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.719 | 0.61x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 67.897 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3277.09 | 0.75x ✅ better |
| flight24.preload_ms | 4742.83 | 3999.71 | 0.84x |
| flight24.realtime | 1 | 0.996 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 485.191 | 0.95x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 9.388 | 0.81x |
| flight24.tick_ms_p50 | 0.401 | 0.547 | 1.36x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.689 | 0.57x ✅ better |
| flight24.update_ms_max | 4.586 | 2.351 | 0.51x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.253 | 16.87x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.651 | 0.26x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.884 | 0.80x |
| flight24.worker_mesh_us | 177.947 | 285.837 | 1.61x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.824 | 4.44x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.088 | 0.43x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.273 | 0.90x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.476 | 0.85x |
| flight8.encode_ms_p95 | 0.832 | 1.322 | 1.59x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 24.387 | 1.84x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.652 | 1.02x |
| flight8.frame_ms_p95 | 3.197 | 5.903 | 1.85x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 10.513 | 2.39x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.704 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.642 | 1.02x |
| flight8.gpu_ms_p95 | 3.081 | 5.672 | 1.84x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 944.983 | 0.54x ✅ better |
| flight8.preload_ms | 1398.04 | 608.775 | 0.44x ✅ better |
| flight8.realtime | 0.994 | 0.998 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 196.658 | 1.58x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 23.934 | 1.91x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.425 | 2.69x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.699 | 1.39x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 9.403 | 0.76x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.007 | 0.70x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.684 | 0.79x |
| flight8.worker_gen_ms | 3.236 | 2.765 | 0.85x |
| flight8.worker_mesh_us | 181.115 | 338.521 | 1.87x ⚠️ worse |
| fluids.pending | 240 | 1146 | 4.78x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6559 | 2.52x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 9.722 | 2.84x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.468 | 2.07x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.231 | 1.19x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.579 | 2.30x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.901 | 1.44x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.426 | 2.06x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.212 | 1.82x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 27.716 | 17.29x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.365 | 1.98x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 8.913 | 2.18x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.617 | 2.16x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.751 | 3.64x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.426 | 2.35x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 7.928 | 3.30x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.215 | 2.04x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 6.299 | 1.86x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.442 | 1.17x |
| gen.chunk_ms_p95 | 3.325 | 5.574 | 1.68x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 791.426 | 2.13x ⚠️ worse |
| gen.starts_cold_ms | – | 1.921 | new |
| gen.terrain_hash | 1238443285367868 | 2875621164255659 | ⚠️ changed |
| genphase.caves_ms | – | 0.987 | new |
| genphase.columns_ms | – | 0.271 | new |
| genphase.ores_ms | – | 0.258 | new |
| genphase.plants_ms | – | 0.292 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.216 | new |
| genphase.structures_ms | – | 0.218 | new |
| genphase.surface_ms | – | 0.029 | new |
| genphase.trees_ms | – | 0.055 | new |
| mesh.chunk_ms_max | 5.758 | 10.233 | 1.78x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 6.004 | 1.37x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 4799.01 | 2.96x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 250.167 | 1.79x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 963.926 | 1.41x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 7.259 | 1.33x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.884 | 1.44x ⚠️ worse |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1662.97 | 1.13x |
| mesh_lod1.section_us_mean | 126.754 | 245.162 | 1.93x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 1032.95 | 1.82x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 2.443 | 1.52x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 3.38 | 2.70x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.796 | 2.93x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.181 | 4.97x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.43 | 13.87x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.986 | 24.22x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.593 | 0.90x |
| save.load_chunk_ms | 0.587 | 0.399 | 0.68x ✅ better |
| save.main_thread_ms | 5.206 | 4.187 | 0.80x |
| save.unchanged_resave_ms | 2.544 | 3.257 | 1.28x |
| ships.assemble_ms | 19.313 | 17.847 | 0.92x |
| ships.assemble_remesh_s | 0.027 | 0.037 | 1.37x ⚠️ worse |
| ships.blast_ms | 2.675 | 2.481 | 0.93x |
| ships.blast_remesh_ms | 5.466 | 5.605 | 1.03x |
| ships.collide_far_us | 0.214 | 0.261 | 1.22x |
| ships.collide_us | 1.047 | 1.025 | 0.98x |
| ships.dock_ms | 12.056 | 19.459 | 1.61x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.108 | 3.00x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 1.068 | 1.20x |
| ships.edit_ms_mean | 0.505 | 0.589 | 1.17x |
| ships.edit_remesh_ms | 3.642 | 3.832 | 1.05x |
| ships.frame_encode_ms | 0.023 | -0.539 | -23.43x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.227 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 6.71 | 2.19x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.281 | 1.70x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.591 | 2.77x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 5.385 | 2.28x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 8.602 | 16.48x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.626 | 2.86x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.418 | 4.70x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.802 | 1.11x |
| startup.first_load_ms | 206.958 | 226.073 | 1.09x |
| startup.renderer_init_again_ms | 27.582 | 1045.28 | 37.90x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2195.67 | 2.69x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.455 | 1.31x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.967 | 1.85x ⚠️ worse |
| startup.textures_ms | 26.537 | 908.339 | 34.23x ⚠️ worse |
| startup.world_init_ms | 2.198 | 22.614 | 10.29x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 5.169 | 0.60x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.809 | 0.62x ✅ better |
| tnt.remesh_s | 0.087 | 0.128 | 1.47x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 7.49 | 1.38x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 1.828 | 0.40x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.49 | 1.38x ⚠️ worse |
