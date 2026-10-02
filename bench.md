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
