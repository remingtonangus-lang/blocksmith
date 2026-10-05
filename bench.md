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
