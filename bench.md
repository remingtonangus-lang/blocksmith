| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.33 | 2.22x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.835 | 1.87x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.792 | 1.33x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.17 | 1.60x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.8 | 1.76x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.779 | 1.31x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 16.153 | 18.70x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.862 | 1.15x |
| flight16.coverage_min | 0.962 | 0.75 | 1.28x |
| flight16.cull_ms_p50 | 0.708 | 0.309 | 0.44x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.894 | 0.78x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.801 | 0.54x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.087 | 0.88x |
| flight16.frame_ms_max | 12.652 | 25.034 | 1.98x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.434 | 0.71x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.535 | 0.95x |
| flight16.frame_ms_p99 | 7.443 | 12.356 | 1.66x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.193 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.408 | 0.71x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.575 | 0.80x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.296 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3317.59 | 0.59x ✅ better |
| flight16.preload_ms | 1871.23 | 2092.57 | 1.12x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 313.831 | 1.10x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 14.796 | 1.73x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.574 | 1.48x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 1.927 | 0.93x |
| flight16.update_ms_max | 8.289 | 12.58 | 1.52x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.251 | 14.76x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.969 | 0.56x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.168 | 1.07x |
| flight16.worker_mesh_us | 177.949 | 263.225 | 1.48x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.81 | 55.76x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 142.289 | 0.64x ✅ better |
| flight24.chunks | 2176 | 1664 | 0.76x ✅ better |
| flight24.coverage_mean | 0.994 | 0.829 | 1.20x |
| flight24.coverage_min | 0.974 | 0.717 | 1.36x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.633 | 0.53x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.694 | 0.61x ✅ better |
| flight24.cull_walked_sections | 7607 | 3538 | 0.47x ✅ better |
| flight24.draw_calls | 3175 | 1081 | 0.34x ✅ better |
| flight24.drawn_kquads | 821.704 | 204.952 | 0.25x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.29 | 0.52x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 3.33 | 0.64x ✅ better |
| flight24.frame_ms_max | 13.319 | 15.653 | 1.18x |
| flight24.frame_ms_p50 | 7.72 | 4.487 | 0.58x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.427 | 0.68x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 9.984 | 0.97x |
| flight24.gen_chunks_per_s | 63.73 | 21.154 | 3.01x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.475 | 0.58x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.275 | 0.67x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 67.947 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3346.22 | 0.73x ✅ better |
| flight24.preload_ms | 4742.83 | 3939.35 | 0.83x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 497.394 | 0.97x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 12.822 | 1.10x |
| flight24.tick_ms_p50 | 0.401 | 0.619 | 1.54x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.016 | 0.69x ✅ better |
| flight24.update_ms_max | 4.586 | 3.361 | 0.73x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.295 | 19.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.98 | 0.39x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.267 | 0.96x |
| flight24.worker_mesh_us | 177.947 | 303.826 | 1.71x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.64 | 4.36x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.989 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.086 | 0.42x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.233 | 0.76x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.45 | 0.80x |
| flight8.encode_ms_p95 | 0.832 | 1.141 | 1.37x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 20.847 | 1.58x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.561 | 0.99x |
| flight8.frame_ms_p95 | 3.197 | 4.868 | 1.52x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 9.241 | 2.10x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.732 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.553 | 0.99x |
| flight8.gpu_ms_p95 | 3.081 | 4.176 | 1.36x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 954.795 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 619.753 | 0.44x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 209.705 | 1.68x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 20.42 | 1.63x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.404 | 2.56x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.377 | 1.13x |
| flight8.update_ms_max | 12.421 | 20.264 | 1.63x ⚠️ worse |
| flight8.update_ms_p50 | 0.01 | 0.007 | 0.70x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.601 | 0.69x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.404 | 0.74x ✅ better |
| flight8.worker_mesh_us | 181.115 | 318.275 | 1.76x ⚠️ worse |
| fluids.pending | 240 | 1260 | 5.25x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6284 | 2.41x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 7.889 | 2.31x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.306 | 1.35x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.766 | 0.94x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.173 | 1.93x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.922 | 1.48x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.173 | 1.97x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.393 | 1.90x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.559 | 1.60x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.919 | 1.33x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 8.657 | 2.12x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.124 | 2.02x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.329 | 3.08x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.939 | 1.54x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.86 | 2.02x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.878 | 1.88x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.493 | 1.33x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.709 | 0.82x |
| gen.chunk_ms_p95 | 3.325 | 3.706 | 1.11x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1358.77 | 1.24x |
| gen.starts_cold_ms | – | 1.951 | new |
| gen.terrain_hash | 1238443285367868 | 1188771535852922 | ⚠️ changed |
| genphase.caves_ms | – | 0.73 | new |
| genphase.columns_ms | – | 0.183 | new |
| genphase.ores_ms | – | 0.189 | new |
| genphase.plants_ms | – | 0.184 | new |
| genphase.starts_ms | – | 0.004 | new |
| genphase.stone_ms | – | 0.146 | new |
| genphase.structures_ms | – | 0.164 | new |
| genphase.surface_ms | – | 0.02 | new |
| genphase.trees_ms | – | 0.029 | new |
| mesh.chunk_ms_max | 5.758 | 5.152 | 0.89x |
| mesh.chunk_ms_mean | 4.38 | 4.303 | 0.98x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 973.94 | 0.60x ✅ better |
| mesh.section_us_mean | 139.451 | 179.294 | 1.29x |
| mesh.section_us_p95 | 686.049 | 770.926 | 1.12x |
| mesh_lod1.chunk_ms_max | 5.44 | 4.678 | 0.86x |
| mesh_lod1.chunk_ms_mean | 4.1 | 3.961 | 0.97x |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 885.01 | 0.60x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 165.041 | 1.30x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 684.977 | 1.21x |
| mobs.per_mob_us | 1.608 | 2.283 | 1.42x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.556 | 2.04x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.554 | 2.04x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.597 | 3.64x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.212 | 6.84x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.847 | 10.33x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.005 | 0.69x ✅ better |
| save.load_chunk_ms | 0.587 | 0.279 | 0.48x ✅ better |
| save.main_thread_ms | 5.206 | 5.925 | 1.14x |
| save.unchanged_resave_ms | 2.544 | 2.084 | 0.82x |
| ships.assemble_ms | 19.313 | 19.313 | 1.00x |
| ships.assemble_remesh_s | 0.027 | 0.017 | 0.63x ✅ better |
| ships.blast_ms | 2.675 | 1.954 | 0.73x ✅ better |
| ships.blast_remesh_ms | 5.466 | 10.662 | 1.95x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.234 | 1.09x |
| ships.collide_us | 1.047 | 0.919 | 0.88x |
| ships.dock_ms | 12.056 | 16.688 | 1.38x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.089 | 2.47x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.84 | 0.95x |
| ships.edit_ms_mean | 0.505 | 0.337 | 0.67x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.682 | 1.01x |
| ships.frame_encode_ms | 0.023 | -0.027 | -1.17x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.086 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 3.342 | 1.09x |
| ships.physics_ms_mean | 0.165 | 0.166 | 1.01x |
| ships.physics_ms_p95 | 0.213 | 0.269 | 1.26x |
| ships.spawn_frigate_ms | 2.358 | 2.299 | 0.97x |
| ships.tick_ms_max | 0.522 | 5.233 | 10.02x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.37 | 1.69x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.918 | 3.04x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 5.115 | 1.18x |
| startup.first_load_ms | 206.958 | 172.236 | 0.83x |
| startup.renderer_init_again_ms | 27.582 | 1138.37 | 41.27x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2199.79 | 2.69x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.661 | 1.90x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.855 | 1.83x ⚠️ worse |
| startup.textures_ms | 26.537 | 695.087 | 26.19x ⚠️ worse |
| startup.world_init_ms | 2.198 | 19.323 | 8.79x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.211 | 0.37x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.349 | 0.46x ✅ better |
| tnt.remesh_s | 0.087 | 0.126 | 1.45x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 2.414 | 0.45x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.962 | 0.21x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 2.414 | 0.45x ✅ better |
