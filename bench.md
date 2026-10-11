| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 3.383 | 5.64x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.002 | 2.24x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.792 | 1.33x ⚠️ worse |
| edit.place_ms_max | 0.732 | 13.534 | 18.49x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.344 | 2.95x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.835 | 1.40x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 14.963 | 17.32x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.867 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.886 | 1.12x |
| flight16.coverage_min | 0.962 | 0.786 | 1.22x |
| flight16.cull_ms_p50 | 0.708 | 0.323 | 0.46x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.883 | 0.77x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.439 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.8 | 0.54x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.986 | 0.84x |
| flight16.frame_ms_max | 12.652 | 22.213 | 1.76x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.428 | 0.71x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 4.66 | 0.80x |
| flight16.frame_ms_p99 | 7.443 | 7.314 | 0.98x |
| flight16.gen_chunks_per_s | 43.68 | 43.582 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.416 | 0.71x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.545 | 0.80x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.248 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3474.03 | 0.57x ✅ better |
| flight16.preload_ms | 1871.23 | 1766.28 | 0.94x |
| flight16.realtime | 0.998 | 1 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 335.424 | 1.17x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 9.688 | 1.13x |
| flight16.tick_ms_p50 | 0.388 | 0.58 | 1.49x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 1.713 | 0.82x |
| flight16.update_ms_max | 8.289 | 2.674 | 0.32x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.257 | 15.12x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.766 | 0.44x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.129 | 1.05x |
| flight16.worker_mesh_us | 177.949 | 248.693 | 1.40x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 19.741 | 46.23x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 146.868 | 0.66x ✅ better |
| flight24.chunks | 2176 | 1718 | 0.79x |
| flight24.coverage_mean | 0.994 | 0.834 | 1.19x |
| flight24.coverage_min | 0.974 | 0.738 | 1.32x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.664 | 0.55x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.178 | 0.79x |
| flight24.cull_walked_sections | 7607 | 4125 | 0.54x ✅ better |
| flight24.draw_calls | 3175 | 1244 | 0.39x ✅ better |
| flight24.drawn_kquads | 821.704 | 227.672 | 0.28x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.371 | 0.55x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 3.937 | 0.75x ✅ better |
| flight24.frame_ms_max | 13.319 | 15.431 | 1.16x |
| flight24.frame_ms_p50 | 7.72 | 4.508 | 0.58x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.312 | 0.67x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 10.466 | 1.01x |
| flight24.gen_chunks_per_s | 63.73 | 25.547 | 2.49x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.434 | 0.57x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.018 | 0.64x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 67.834 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3555.23 | 0.69x ✅ better |
| flight24.preload_ms | 4742.83 | 3790.84 | 0.80x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 460.222 | 0.90x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 12.761 | 1.10x |
| flight24.tick_ms_p50 | 0.401 | 0.694 | 1.73x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.212 | 0.75x ✅ better |
| flight24.update_ms_max | 4.586 | 8.547 | 1.86x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.338 | 22.53x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.048 | 0.41x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.172 | 0.92x |
| flight24.worker_mesh_us | 177.947 | 303.075 | 1.70x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.564 | 4.33x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.083 | 0.41x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.228 | 0.75x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.297 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.439 | 0.78x |
| flight8.encode_ms_p95 | 0.832 | 1.116 | 1.34x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 28.755 | 2.17x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.572 | 0.99x |
| flight8.frame_ms_p95 | 3.197 | 4.784 | 1.50x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 9.681 | 2.20x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.721 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.555 | 0.99x |
| flight8.gpu_ms_p95 | 3.081 | 3.6 | 1.17x |
| flight8.hitches | 0 | 1 | infx ⚠️ worse |
| flight8.mesh_mb | 40.975 | 24.353 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 950.907 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 634.379 | 0.45x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 214.096 | 1.72x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 12.971 | 1.03x |
| flight8.tick_ms_p50 | 0.158 | 0.399 | 2.53x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.314 | 1.07x |
| flight8.update_ms_max | 12.421 | 1.949 | 0.16x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.005 | 0.50x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.569 | 0.65x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.335 | 0.72x ✅ better |
| flight8.worker_mesh_us | 181.115 | 279.42 | 1.54x ⚠️ worse |
| fluids.pending | 240 | 1191 | 4.96x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6953 | 2.67x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 7.159 | 2.09x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.376 | 1.66x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.357 | 0.72x ✅ better |
| frame.draw_calls | 1076 | 1218 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.522 | 1.32x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.334 | 0.91x |
| frame.visible_sections | 686 | 699 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.209 | 1.97x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.174 | 1.88x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.202 | 1.98x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.483 | 1.94x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.238 | 1.40x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.548 | 2.24x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 8.003 | 1.96x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.397 | 2.10x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.106 | 2.79x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.881 | 1.45x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.779 | 1.99x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.371 | 2.11x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 5.943 | 1.76x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.336 | 1.12x |
| gen.chunk_ms_p95 | 3.325 | 5.673 | 1.71x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 985.04 | 1.71x ⚠️ worse |
| gen.starts_cold_ms | – | 2.264 | new |
| gen.terrain_hash | 1238443285367868 | 1954612902641660 | ⚠️ changed |
| genphase.caves_ms | – | 1.071 | new |
| genphase.columns_ms | – | 0.243 | new |
| genphase.ores_ms | – | 0.256 | new |
| genphase.plants_ms | – | 0.219 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.194 | new |
| genphase.structures_ms | – | 0.184 | new |
| genphase.surface_ms | – | 0.026 | new |
| genphase.trees_ms | – | 0.052 | new |
| mesh.chunk_ms_max | 5.758 | 7.717 | 1.34x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 5.307 | 1.21x |
| mesh.quads_per_chunk | 4996 | 4972.22 | 1.00x |
| mesh.section_us_max | 1621.01 | 2117.04 | 1.31x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 221.125 | 1.59x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 843.048 | 1.23x |
| mesh_lod1.chunk_ms_max | 5.44 | 7.091 | 1.30x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.026 | 1.23x |
| mesh_lod1.quads_per_chunk | 2535 | 2502.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1798.03 | 1.22x |
| mesh_lod1.section_us_mean | 126.754 | 209.399 | 1.65x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 859.022 | 1.51x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 4.24 | 2.64x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 5.441 | 4.35x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.904 | 3.32x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.834 | 6.46x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.268 | 8.65x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.098 | 13.39x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.493 | 1.45x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.508 | 0.87x |
| save.load_chunk_ms | 0.587 | 0.315 | 0.54x ✅ better |
| save.main_thread_ms | 5.206 | 4.232 | 0.81x |
| save.unchanged_resave_ms | 2.544 | 1.161 | 0.46x ✅ better |
| ships.assemble_ms | 19.313 | 21.11 | 1.09x |
| ships.assemble_remesh_s | 0.027 | 0.019 | 0.70x ✅ better |
| ships.blast_ms | 2.675 | 2.162 | 0.81x |
| ships.blast_remesh_ms | 5.466 | 4.085 | 0.75x ✅ better |
| ships.collide_far_us | 0.214 | 0.335 | 1.57x ⚠️ worse |
| ships.collide_us | 1.047 | 1.994 | 1.90x ⚠️ worse |
| ships.dock_ms | 12.056 | 12.58 | 1.04x |
| ships.dock_remesh_s | 0.036 | 0.07 | 1.94x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.547 | 0.62x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.283 | 0.56x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.051 | 0.84x |
| ships.frame_encode_ms | 0.023 | 0.085 | 3.70x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.399 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 3.924 | 1.28x |
| ships.physics_ms_mean | 0.165 | 0.155 | 0.94x |
| ships.physics_ms_p95 | 0.213 | 0.201 | 0.94x |
| ships.spawn_frigate_ms | 2.358 | 2.09 | 0.89x |
| ships.tick_ms_max | 0.522 | 5.728 | 10.97x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.343 | 1.57x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.896 | 2.97x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.67 | 0.85x |
| startup.first_load_ms | 206.958 | 209.265 | 1.01x |
| startup.renderer_init_again_ms | 27.582 | 1144.99 | 41.51x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2435.66 | 2.98x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.273 | 0.79x |
| startup.since_launch_s | 5.923 | 9.734 | 1.64x ⚠️ worse |
| startup.textures_ms | 26.537 | 720.74 | 27.16x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.917 | 6.79x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.71 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.973 | 0.34x ✅ better |
| tnt.remesh_s | 0.087 | 0.063 | 0.72x ✅ better |
| tnt.tick_ms_max | 5.414 | 2.445 | 0.45x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.848 | 0.19x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 2.445 | 0.45x ✅ better |
