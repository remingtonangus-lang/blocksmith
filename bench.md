| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.84 | 1.40x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.603 | 1.35x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.636 | 1.07x |
| edit.place_ms_max | 0.732 | 0.695 | 0.95x |
| edit.place_ms_mean | 0.455 | 0.597 | 1.31x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.651 | 1.09x |
| flight16.arena_free_mb | 0.864 | 14.727 | 17.05x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.996 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.359 | 0.51x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.579 | 0.50x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.439 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.85 | 0.57x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.58 | 0.67x ✅ better |
| flight16.frame_ms_max | 12.652 | 23.203 | 1.83x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.842 | 0.80x |
| flight16.frame_ms_p95 | 5.8 | 4.925 | 0.85x |
| flight16.frame_ms_p99 | 7.443 | 8.921 | 1.20x |
| flight16.gen_chunks_per_s | 43.68 | 43.711 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.837 | 0.80x |
| flight16.gpu_ms_p95 | 5.71 | 4.784 | 0.84x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.839 | 0.58x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 2671.84 | 0.74x ✅ better |
| flight16.preload_ms | 1871.23 | 1603.11 | 0.86x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 322.799 | 1.13x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 22.315 | 2.61x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.454 | 1.17x |
| flight16.tick_ms_p95 | 2.08 | 1.306 | 0.63x ✅ better |
| flight16.update_ms_max | 8.289 | 22.101 | 2.67x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.136 | 8.00x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.742 | 0.43x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.93 | 0.95x |
| flight16.worker_mesh_us | 177.949 | 181.704 | 1.02x |
| flight24.arena_free_mb | 0.427 | 10.515 | 24.63x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 187 | 0.84x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.993 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 0.982 | 0.82x |
| flight24.cull_ms_p95 | 2.767 | 2.344 | 0.85x |
| flight24.cull_walked_sections | 7607 | 5570 | 0.73x ✅ better |
| flight24.draw_calls | 3175 | 2525 | 0.80x |
| flight24.drawn_kquads | 821.704 | 461.822 | 0.56x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.895 | 0.77x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.466 | 0.85x |
| flight24.frame_ms_max | 13.319 | 26.234 | 1.97x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.179 | 0.80x |
| flight24.frame_ms_p95 | 9.472 | 7.841 | 0.83x |
| flight24.frame_ms_p99 | 10.337 | 11.484 | 1.11x |
| flight24.gen_chunks_per_s | 63.73 | 63.712 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.131 | 0.79x |
| flight24.gpu_ms_p95 | 9.428 | 7.578 | 0.80x |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 84.526 | 0.64x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3560.04 | 0.69x ✅ better |
| flight24.preload_ms | 4742.83 | 3416.28 | 0.72x ✅ better |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 522.644 | 1.02x |
| flight24.slab_mb | 148 | 108 | 0.73x ✅ better |
| flight24.tick_ms_max | 11.61 | 20.093 | 1.73x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.64 | 1.60x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.868 | 0.63x ✅ better |
| flight24.update_ms_max | 4.586 | 14.51 | 3.16x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.304 | 20.27x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.279 | 0.50x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.123 | 0.90x |
| flight24.worker_mesh_us | 177.947 | 207.018 | 1.16x |
| flight8.arena_free_mb | 2.438 | 10.217 | 4.19x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.996 | 0.99x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.074 | 0.36x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.201 | 0.66x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.297 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.367 | 0.65x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.982 | 1.18x |
| flight8.frame_ms_max | 13.232 | 20.682 | 1.56x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.388 | 0.92x |
| flight8.frame_ms_p95 | 3.197 | 3.049 | 0.95x |
| flight8.frame_ms_p99 | 4.401 | 4.471 | 1.02x |
| flight8.gen_chunks_per_s | 23.603 | 23.676 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.386 | 0.93x |
| flight8.gpu_ms_p95 | 3.081 | 2.974 | 0.97x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.353 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 653.468 | 0.78x |
| flight8.preload_ms | 1398.04 | 477.877 | 0.34x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 218.44 | 1.75x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 20.277 | 1.62x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.293 | 1.85x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 0.914 | 0.75x ✅ better |
| flight8.update_ms_max | 12.421 | 1.72 | 0.14x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.003 | 0.30x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.335 | 0.39x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.917 | 0.59x ✅ better |
| flight8.worker_mesh_us | 181.115 | 172.913 | 0.95x |
| fluids.pending | 240 | 31 | 0.13x ✅ better |
| fluids.remeshed_sections | 2605 | 3269 | 1.25x |
| fluids.tick_ms_max | 3.42 | 21.764 | 6.36x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.268 | 1.19x |
| fluids.tick_ms_p95 | 1.872 | 0.767 | 0.41x ✅ better |
| frame.draw_calls | 1076 | 1272 | 1.18x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 241.388 | 1.35x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.592 | 0.92x |
| frame.visible_sections | 686 | 704 | 1.03x |
| frame_1080p.encode_ms_max | 1.123 | 1.348 | 1.20x |
| frame_1080p.encode_ms_p50 | 0.625 | 0.82 | 1.31x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.16 | 1.96x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.933 | 1.70x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 1.241 | 0.77x |
| frame_4k.encode_ms_p50 | 0.691 | 0.826 | 1.20x |
| frame_4k.gpu_ms_max | 4.083 | 7.98 | 1.95x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.778 | 1.93x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.509 | 2.00x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.764 | 1.26x |
| frame_800p.gpu_ms_max | 2.405 | 4.438 | 1.85x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.28 | 1.59x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.814 | 1.42x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.937 | 0.93x |
| gen.chunk_ms_p95 | 3.325 | 3.735 | 1.12x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1257.91 | 1.34x ⚠️ worse |
| gen.starts_cold_ms | – | 0.881 | new |
| gen.terrain_hash | 1238443285367868 | 3899601491877530 | ⚠️ changed |
| genphase.caves_ms | – | 0.78 | new |
| genphase.columns_ms | – | 0.215 | new |
| genphase.ores_ms | – | 0.22 | new |
| genphase.plants_ms | – | 0.194 | new |
| genphase.starts_ms | – | 0.008 | new |
| genphase.stone_ms | – | 0.214 | new |
| genphase.structures_ms | – | 0.171 | new |
| genphase.surface_ms | – | 0.024 | new |
| genphase.trees_ms | – | 0.046 | new |
| mesh.chunk_ms_max | 5.758 | 4.717 | 0.82x |
| mesh.chunk_ms_mean | 4.38 | 4.029 | 0.92x |
| mesh.quads_per_chunk | 4996 | 4946.78 | 0.99x |
| mesh.section_us_max | 1621.01 | 916.004 | 0.57x ✅ better |
| mesh.section_us_mean | 139.451 | 167.892 | 1.20x |
| mesh.section_us_p95 | 686.049 | 699.043 | 1.02x |
| mesh_lod1.chunk_ms_max | 5.44 | 4.483 | 0.82x |
| mesh_lod1.chunk_ms_mean | 4.1 | 3.919 | 0.96x |
| mesh_lod1.quads_per_chunk | 2535 | 2626.89 | 1.04x |
| mesh_lod1.section_us_max | 1477.96 | 890.97 | 0.60x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 163.296 | 1.29x |
| mesh_lod1.section_us_p95 | 568.032 | 689.983 | 1.21x |
| mobs.per_mob_us | 1.608 | 2.603 | 1.62x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.522 | 2.02x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.729 | 2.68x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.932 | 4.40x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.338 | 10.90x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.32 | 3.90x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.464 | 1.45x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.307 | 0.45x ✅ better |
| save.load_chunk_ms | 0.587 | 0.213 | 0.36x ✅ better |
| save.main_thread_ms | 5.206 | 3.124 | 0.60x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.252 | 0.49x ✅ better |
| ships.assemble_ms | 19.313 | 11.817 | 0.61x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.016 | 0.59x ✅ better |
| ships.blast_ms | 2.675 | 2.012 | 0.75x ✅ better |
| ships.blast_remesh_ms | 5.466 | 4.594 | 0.84x |
| ships.collide_far_us | 0.214 | 0.207 | 0.97x |
| ships.collide_us | 1.047 | 0.897 | 0.86x |
| ships.dock_ms | 12.056 | 10.537 | 0.87x |
| ships.dock_remesh_s | 0.036 | 0.049 | 1.36x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.552 | 0.62x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.261 | 0.52x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.584 | 0.71x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.044 | 1.91x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.03 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.199 | 0.72x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.143 | 0.87x |
| ships.physics_ms_p95 | 0.213 | 0.165 | 0.77x |
| ships.spawn_frigate_ms | 2.358 | 2.255 | 0.96x |
| ships.tick_ms_max | 0.522 | 17.028 | 32.62x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.313 | 1.43x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.332 | 1.10x |
| startup.fill_rd12_s | 4.324 | 3.504 | 0.81x |
| startup.first_load_ms | 206.958 | 166.013 | 0.80x |
| startup.renderer_init_again_ms | 27.582 | 812.526 | 29.46x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1753.58 | 2.14x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.495 | 1.43x ⚠️ worse |
| startup.since_launch_s | 5.923 | 8.366 | 1.41x ⚠️ worse |
| startup.textures_ms | 26.537 | 682.039 | 25.70x ⚠️ worse |
| startup.world_init_ms | 2.198 | 15.169 | 6.90x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 2.916 | 0.34x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.065 | 0.37x ✅ better |
| tnt.remesh_s | 0.087 | 0.057 | 0.66x ✅ better |
| tnt.tick_ms_max | 5.414 | 0.951 | 0.18x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.772 | 0.17x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 0.951 | 0.18x ✅ better |
