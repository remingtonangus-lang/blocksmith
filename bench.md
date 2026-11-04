| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.353 | 3.92x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.06 | 2.37x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 1.055 | 1.77x ⚠️ worse |
| edit.place_ms_max | 0.732 | 2.257 | 3.08x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.056 | 2.32x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 1.029 | 1.73x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 11.654 | 13.49x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 62.586 | 0.60x ✅ better |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.988 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.46 | 0.65x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 1.128 | 0.98x |
| flight16.cull_walked_sections | 2817 | 1836 | 0.65x ✅ better |
| flight16.draw_calls | 1434 | 989 | 0.69x ✅ better |
| flight16.drawn_kquads | 475.516 | 119.771 | 0.25x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.078 | 0.72x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.641 | 1.12x |
| flight16.frame_ms_max | 12.652 | 60.997 | 4.82x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.566 | 0.74x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 4.326 | 0.75x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 5.679 | 0.76x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 81.582 | 0.54x ✅ better |
| flight16.gpu_ms_p50 | 4.804 | 3.549 | 0.74x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.215 | 0.74x ✅ better |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 34.843 | 0.43x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 2108.57 | 0.94x |
| flight16.preload_ms | 1871.23 | 2947.32 | 1.58x ⚠️ worse |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 320.112 | 1.12x |
| flight16.slab_mb | 96 | 52 | 0.54x ✅ better |
| flight16.tick_ms_max | 8.551 | 58.954 | 6.89x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.407 | 1.05x |
| flight16.tick_ms_p95 | 2.08 | 1.63 | 0.78x |
| flight16.update_ms_max | 8.289 | 13.703 | 1.65x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.157 | 9.24x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.232 | 0.71x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.604 | 1.29x |
| flight16.worker_mesh_us | 177.949 | 201.901 | 1.13x |
| flight24.arena_free_mb | 0.427 | 4.419 | 10.35x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 72.898 | 0.33x ✅ better |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.991 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 1.351 | 1.13x |
| flight24.cull_ms_p95 | 2.767 | 3.207 | 1.16x |
| flight24.cull_walked_sections | 7607 | 5485 | 0.72x ✅ better |
| flight24.draw_calls | 3175 | 2559 | 0.81x |
| flight24.drawn_kquads | 821.704 | 264.131 | 0.32x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.503 | 1.01x |
| flight24.encode_ms_p95 | 5.237 | 6.003 | 1.15x |
| flight24.frame_ms_max | 13.319 | 80.488 | 6.04x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 5.695 | 0.74x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 8.337 | 0.88x |
| flight24.frame_ms_p99 | 10.337 | 12.313 | 1.19x |
| flight24.gen_chunks_per_s | 63.73 | 108.955 | 0.58x ✅ better |
| flight24.gpu_ms_p50 | 7.718 | 5.292 | 0.69x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.734 | 0.71x ✅ better |
| flight24.hitches | 0 | 2 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 62.116 | 0.47x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 2551.84 | 0.96x |
| flight24.preload_ms | 4742.83 | 5866.59 | 1.24x |
| flight24.realtime | 1 | 0.996 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 519.409 | 1.01x |
| flight24.slab_mb | 148 | 76 | 0.51x ✅ better |
| flight24.tick_ms_max | 11.61 | 62.131 | 5.35x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.623 | 1.55x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.073 | 0.70x ✅ better |
| flight24.update_ms_max | 4.586 | 52.052 | 11.35x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.317 | 21.13x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.634 | 0.64x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.831 | 1.20x |
| flight24.worker_mesh_us | 177.947 | 215.177 | 1.21x |
| flight8.arena_free_mb | 2.438 | 7.324 | 3.00x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.992 | 0.86x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.087 | 0.43x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.169 | 0.55x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 335 | 0.72x ✅ better |
| flight8.drawn_kquads | 211.463 | 78.865 | 0.37x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.497 | 0.88x |
| flight8.encode_ms_p95 | 0.832 | 0.836 | 1.00x |
| flight8.frame_ms_max | 13.232 | 14.307 | 1.08x |
| flight8.frame_ms_p50 | 2.588 | 2.243 | 0.87x |
| flight8.frame_ms_p95 | 3.197 | 2.986 | 0.93x |
| flight8.frame_ms_p99 | 4.401 | 5.696 | 1.29x |
| flight8.gen_chunks_per_s | 23.603 | 23.679 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.242 | 0.87x |
| flight8.gpu_ms_p95 | 3.081 | 2.935 | 0.95x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 20.229 | 0.49x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 615.401 | 0.82x |
| flight8.preload_ms | 1398.04 | 1096.18 | 0.78x |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 224.752 | 1.80x ⚠️ worse |
| flight8.slab_mb | 52 | 32 | 0.62x ✅ better |
| flight8.tick_ms_max | 12.539 | 9.096 | 0.73x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.3 | 1.90x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.016 | 0.83x |
| flight8.update_ms_max | 12.421 | 2.131 | 0.17x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.016 | 1.60x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.5 | 0.58x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.361 | 0.73x ✅ better |
| flight8.worker_mesh_us | 181.115 | 251.747 | 1.39x ⚠️ worse |
| fluids.pending | 240 | 26 | 0.11x ✅ better |
| fluids.remeshed_sections | 2605 | 1892 | 0.73x ✅ better |
| fluids.tick_ms_max | 3.42 | 2.754 | 0.81x |
| fluids.tick_ms_p50 | 0.226 | 0.206 | 0.91x |
| fluids.tick_ms_p95 | 1.872 | 0.723 | 0.39x ✅ better |
| frame.draw_calls | 1076 | 1316 | 1.22x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 207.513 | 1.16x |
| frame.mesh_mb | 57.324 | 43.345 | 0.76x ✅ better |
| frame.visible_sections | 686 | 719 | 1.05x |
| frame_1080p.encode_ms_max | 1.123 | 3.078 | 2.74x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.146 | 1.83x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.237 | 1.99x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 5.027 | 2.18x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.987 | 1.86x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.191 | 1.72x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 12.246 | 3.00x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.953 | 1.97x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.87 | 5.13x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.248 | 2.05x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 7.268 | 3.02x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.762 | 1.82x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 1272.63 | 376.30x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 68.878 | 33.08x ❌ regression |
| gen.chunk_ms_p95 | 3.325 | 261.24 | 78.57x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 161.639 | 10.41x ⚠️ worse |
| gen.starts_cold_ms | – | 0.864 | new |
| gen.terrain_hash | 1238443285367868 | 163195936105986 | ⚠️ changed |
| genphase.caves_ms | – | 0.932 | new |
| genphase.columns_ms | – | 0.254 | new |
| genphase.ores_ms | – | 0.35 | new |
| genphase.plants_ms | – | 0.231 | new |
| genphase.starts_ms | – | 0.604 | new |
| genphase.stone_ms | – | 0.244 | new |
| genphase.structures_ms | – | 63.674 | new |
| genphase.surface_ms | – | 0.03 | new |
| genphase.trees_ms | – | 2.467 | new |
| mesh.chunk_ms_max | 5.758 | 8.775 | 1.52x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 6.323 | 1.44x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4430.11 | 0.89x |
| mesh.section_us_max | 1621.01 | 2341.03 | 1.44x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 263.441 | 1.89x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1028.06 | 1.50x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 7.602 | 1.40x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.625 | 1.37x ⚠️ worse |
| mesh_lod1.quads_per_chunk | 2535 | 2359.33 | 0.93x |
| mesh_lod1.section_us_max | 1477.96 | 1290.08 | 0.87x |
| mesh_lod1.section_us_mean | 126.754 | 234.388 | 1.85x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 908.017 | 1.60x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 3.98 | 2.48x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.751 | 2.20x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.694 | 2.55x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.729 | 3.94x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.097 | 3.13x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.186 | 2.27x ⚠️ worse |
| save.chunk_kb | 4.471 | 7.015 | 1.57x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.864 | 0.64x ✅ better |
| save.load_chunk_ms | 0.587 | 0.196 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 6.042 | 1.16x |
| save.unchanged_resave_ms | 2.544 | 2.147 | 0.84x |
| ships.assemble_ms | 19.313 | 64.637 | 3.35x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.04 | 1.48x ⚠️ worse |
| ships.blast_ms | 2.675 | 5.068 | 1.89x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 7.433 | 1.36x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.252 | 1.18x |
| ships.collide_us | 1.047 | 1.107 | 1.06x |
| ships.dock_ms | 12.056 | 26.48 | 2.20x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.144 | 4.00x ⚠️ worse |
| ships.draw_calls | 66 | 68 | 1.03x |
| ships.edit_ms_max | 0.887 | 1.006 | 1.13x |
| ships.edit_ms_mean | 0.505 | 0.384 | 0.76x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.731 | 1.02x |
| ships.frame_encode_ms | 0.023 | 0.053 | 2.30x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.158 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.935 | 0.96x |
| ships.physics_ms_mean | 0.165 | 0.236 | 1.43x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.604 | 2.84x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.372 | 0.58x ✅ better |
| ships.tick_ms_max | 0.522 | 3.844 | 7.36x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.413 | 1.89x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.008 | 3.34x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 5.16 | 1.19x |
| startup.first_load_ms | 206.958 | 667.063 | 3.22x ⚠️ worse |
| startup.renderer_init_again_ms | 27.582 | 1151.7 | 41.76x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2434.82 | 2.98x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.334 | 0.96x |
| startup.since_launch_s | 5.923 | 15.637 | 2.64x ⚠️ worse |
| startup.textures_ms | 26.537 | 808.66 | 30.47x ⚠️ worse |
| startup.world_init_ms | 2.198 | 60.597 | 27.57x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.388 | 0.39x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.134 | 0.39x ✅ better |
| tnt.remesh_s | 0.087 | 0.368 | 4.23x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 1.19 | 0.22x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.537 | 0.12x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.187 | 0.22x ✅ better |

**Regressions past the CI gate:**

- gen.chunk_ms_mean: 2.082 -> 68.878 (33.08x worse, 33.08x for runner speed, gate 1.6x)
