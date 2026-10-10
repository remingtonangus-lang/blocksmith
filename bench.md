| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.981 | 1.64x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.736 | 1.65x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.718 | 1.21x |
| edit.place_ms_max | 0.732 | 0.852 | 1.16x |
| edit.place_ms_mean | 0.455 | 0.726 | 1.60x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.712 | 1.20x |
| flight16.arena_free_mb | 0.864 | 16.776 | 19.42x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.91 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.909 | 1.09x |
| flight16.coverage_min | 0.962 | 0.767 | 1.25x |
| flight16.cull_ms_p50 | 0.708 | 0.3 | 0.42x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.444 | 0.39x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.751 | 0.50x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.12 | 0.47x ✅ better |
| flight16.frame_ms_max | 12.652 | 39.924 | 3.16x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.021 | 0.63x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 4.561 | 0.79x |
| flight16.frame_ms_p99 | 7.443 | 7.238 | 0.97x |
| flight16.gen_chunks_per_s | 43.68 | 43.693 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.003 | 0.63x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 3.937 | 0.69x ✅ better |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.507 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3249.49 | 0.61x ✅ better |
| flight16.preload_ms | 1871.23 | 1657.94 | 0.89x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 318.502 | 1.11x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 38.379 | 4.49x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.449 | 1.16x |
| flight16.tick_ms_p95 | 2.08 | 2.256 | 1.08x |
| flight16.update_ms_max | 8.289 | 2.099 | 0.25x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.156 | 9.18x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.538 | 0.31x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.829 | 0.90x |
| flight16.worker_mesh_us | 177.949 | 223.17 | 1.25x |
| flight24.arena_free_mb | 0.427 | 20.218 | 47.35x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 163.039 | 0.73x ✅ better |
| flight24.chunks | 2176 | 1904 | 0.88x |
| flight24.coverage_mean | 0.994 | 0.887 | 1.12x |
| flight24.coverage_min | 0.974 | 0.811 | 1.20x |
| flight24.cull_ms_p50 | 1.198 | 0.749 | 0.63x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.061 | 0.38x ✅ better |
| flight24.cull_walked_sections | 7607 | 5509 | 0.72x ✅ better |
| flight24.draw_calls | 3175 | 1648 | 0.52x ✅ better |
| flight24.drawn_kquads | 821.704 | 292.9 | 0.36x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.45 | 0.59x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.051 | 0.39x ✅ better |
| flight24.frame_ms_max | 13.319 | 19.053 | 1.43x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.342 | 0.56x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.21 | 0.66x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 14.111 | 1.37x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 41.552 | 1.53x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.29 | 0.56x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.229 | 0.55x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 75.292 | 0.57x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3897.86 | 0.63x ✅ better |
| flight24.preload_ms | 4742.83 | 3423.52 | 0.72x ✅ better |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 491.441 | 0.96x |
| flight24.slab_mb | 148 | 104 | 0.70x ✅ better |
| flight24.tick_ms_max | 11.61 | 16.789 | 1.45x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.573 | 1.43x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.752 | 0.94x |
| flight24.update_ms_max | 4.586 | 11.274 | 2.46x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.278 | 18.53x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.74 | 0.29x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.816 | 0.77x |
| flight24.worker_mesh_us | 177.947 | 255.673 | 1.44x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.748 | 4.41x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.071 | 0.35x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.191 | 0.63x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.371 | 0.66x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.931 | 1.12x |
| flight8.frame_ms_max | 13.232 | 13.716 | 1.04x |
| flight8.frame_ms_p50 | 2.588 | 2.133 | 0.82x |
| flight8.frame_ms_p95 | 3.197 | 2.678 | 0.84x |
| flight8.frame_ms_p99 | 4.401 | 3.644 | 0.83x |
| flight8.gen_chunks_per_s | 23.603 | 23.749 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.128 | 0.83x |
| flight8.gpu_ms_p95 | 3.081 | 2.628 | 0.85x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 992.453 | 0.51x ✅ better |
| flight8.preload_ms | 1398.04 | 518.866 | 0.37x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 189.924 | 1.52x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 13.393 | 1.07x |
| flight8.tick_ms_p50 | 0.158 | 0.311 | 1.97x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.02 | 0.83x |
| flight8.update_ms_max | 12.421 | 1.574 | 0.13x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.004 | 0.40x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.362 | 0.42x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.933 | 0.60x ✅ better |
| flight8.worker_mesh_us | 181.115 | 249.016 | 1.37x ⚠️ worse |
| fluids.pending | 240 | 1038 | 4.33x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6782 | 2.60x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.132 | 1.50x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.289 | 1.28x |
| fluids.tick_ms_p95 | 1.872 | 1.6 | 0.85x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 1.407 | 1.25x |
| frame_1080p.encode_ms_p50 | 0.625 | 1.01 | 1.62x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.21 | 1.98x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.492 | 1.95x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 1.449 | 0.90x |
| frame_4k.encode_ms_p50 | 0.691 | 0.867 | 1.25x |
| frame_4k.gpu_ms_max | 4.083 | 7.039 | 1.72x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.359 | 1.81x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.303 | 1.73x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.888 | 1.46x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.426 | 1.84x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.684 | 1.78x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 5.314 | 1.57x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.003 | 0.96x |
| gen.chunk_ms_p95 | 3.325 | 5.109 | 1.54x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 891.514 | 1.89x ⚠️ worse |
| gen.starts_cold_ms | – | 2.623 | new |
| gen.terrain_hash | 1238443285367868 | 1188771535852922 | ⚠️ changed |
| genphase.caves_ms | – | 0.844 | new |
| genphase.columns_ms | – | 0.213 | new |
| genphase.ores_ms | – | 0.219 | new |
| genphase.plants_ms | – | 0.237 | new |
| genphase.starts_ms | – | 0.007 | new |
| genphase.stone_ms | – | 0.169 | new |
| genphase.structures_ms | – | 0.183 | new |
| genphase.surface_ms | – | 0.025 | new |
| genphase.trees_ms | – | 0.04 | new |
| mesh.chunk_ms_max | 5.758 | 5.083 | 0.88x |
| mesh.chunk_ms_mean | 4.38 | 4.371 | 1.00x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 927.925 | 0.57x ✅ better |
| mesh.section_us_mean | 139.451 | 182.144 | 1.31x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 753.045 | 1.10x |
| mesh_lod1.chunk_ms_max | 5.44 | 4.932 | 0.91x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.357 | 1.06x |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 924.945 | 0.63x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 181.53 | 1.43x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 766.993 | 1.35x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.568 | 0.98x |
| mobs.tick_150_ms_max | 1.25 | 1.951 | 1.56x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.447 | 1.64x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.208 | 2.75x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.212 | 6.84x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.927 | 11.30x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.425 | 0.49x ✅ better |
| save.load_chunk_ms | 0.587 | 0.235 | 0.40x ✅ better |
| save.main_thread_ms | 5.206 | 2.943 | 0.57x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.228 | 0.48x ✅ better |
| ships.assemble_ms | 19.313 | 18.88 | 0.98x |
| ships.assemble_remesh_s | 0.027 | 0.03 | 1.11x |
| ships.blast_ms | 2.675 | 1.868 | 0.70x ✅ better |
| ships.blast_remesh_ms | 5.466 | 5.086 | 0.93x |
| ships.collide_far_us | 0.214 | 0.247 | 1.15x |
| ships.collide_us | 1.047 | 0.93 | 0.89x |
| ships.dock_ms | 12.056 | 11.196 | 0.93x |
| ships.dock_remesh_s | 0.036 | 0.052 | 1.44x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.545 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.257 | 0.51x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.776 | 0.76x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.042 | 1.83x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.036 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.359 | 0.77x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.216 | 1.31x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.529 | 2.48x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.977 | 0.84x |
| ships.tick_ms_max | 0.522 | 6.533 | 12.52x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.513 | 2.34x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.76 | 5.83x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.863 | 0.66x ✅ better |
| startup.first_load_ms | 206.958 | 165.118 | 0.80x |
| startup.renderer_init_again_ms | 27.582 | 828.941 | 30.05x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1892.93 | 2.32x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.256 | 0.74x ✅ better |
| startup.since_launch_s | 5.923 | 7.853 | 1.33x ⚠️ worse |
| startup.textures_ms | 26.537 | 592.446 | 22.33x ⚠️ worse |
| startup.world_init_ms | 2.198 | 15.18 | 6.91x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.574 | 0.18x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.927 | 0.32x ✅ better |
| tnt.remesh_s | 0.087 | 0.096 | 1.10x |
| tnt.tick_ms_max | 5.414 | 1.22 | 0.23x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.373 | 0.08x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.22 | 0.23x ✅ better |
