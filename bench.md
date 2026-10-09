| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.157 | 3.60x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.169 | 2.62x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 1.052 | 1.77x ⚠️ worse |
| edit.place_ms_max | 0.732 | 2.104 | 2.87x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.15 | 2.53x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 1.028 | 1.73x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 16.558 | 19.16x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.883 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.898 | 1.10x |
| flight16.coverage_min | 0.962 | 0.774 | 1.24x |
| flight16.cull_ms_p50 | 0.708 | 0.358 | 0.51x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 1.034 | 0.90x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.901 | 0.60x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.389 | 1.01x |
| flight16.frame_ms_max | 12.652 | 28.016 | 2.21x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.662 | 0.76x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 7.614 | 1.31x ⚠️ worse |
| flight16.frame_ms_p99 | 7.443 | 12.425 | 1.67x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.684 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.59 | 0.75x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 5.867 | 1.03x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.425 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3272.76 | 0.60x ✅ better |
| flight16.preload_ms | 1871.23 | 2371.27 | 1.27x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 327.096 | 1.14x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 14.349 | 1.68x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.606 | 1.56x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 3.839 | 1.85x ⚠️ worse |
| flight16.update_ms_max | 8.289 | 6.785 | 0.82x |
| flight16.update_ms_p50 | 0.017 | 0.272 | 16.00x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.871 | 0.50x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.366 | 1.17x |
| flight16.worker_mesh_us | 177.949 | 286.942 | 1.61x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 21.41 | 50.14x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 156.752 | 0.70x ✅ better |
| flight24.chunks | 2176 | 1836 | 0.84x |
| flight24.coverage_mean | 0.994 | 0.876 | 1.13x |
| flight24.coverage_min | 0.974 | 0.818 | 1.19x |
| flight24.cull_ms_p50 | 1.198 | 0.888 | 0.74x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.464 | 0.89x |
| flight24.cull_walked_sections | 7607 | 5028 | 0.66x ✅ better |
| flight24.draw_calls | 3175 | 1474 | 0.46x ✅ better |
| flight24.drawn_kquads | 821.704 | 263.95 | 0.32x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.784 | 0.72x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.482 | 0.86x |
| flight24.frame_ms_max | 13.319 | 27.207 | 2.04x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.899 | 0.63x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 9.301 | 0.98x |
| flight24.frame_ms_p99 | 10.337 | 20.163 | 1.95x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 35.368 | 1.80x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.736 | 0.61x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 7.081 | 0.75x ✅ better |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 72.446 | 0.55x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3643.4 | 0.67x ✅ better |
| flight24.preload_ms | 4742.83 | 5038.1 | 1.06x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 498.706 | 0.97x |
| flight24.slab_mb | 148 | 104 | 0.70x ✅ better |
| flight24.tick_ms_max | 11.61 | 24.656 | 2.12x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.771 | 1.92x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.114 | 1.06x |
| flight24.update_ms_max | 4.586 | 5.434 | 1.18x |
| flight24.update_ms_p50 | 0.015 | 0.394 | 26.27x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.249 | 0.49x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.389 | 1.01x |
| flight24.worker_mesh_us | 177.947 | 338.747 | 1.90x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.754 | 4.41x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.992 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.087 | 0.43x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.255 | 0.84x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.485 | 0.86x |
| flight8.encode_ms_p95 | 0.832 | 1.221 | 1.47x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 21.035 | 1.59x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.59 | 1.00x |
| flight8.frame_ms_p95 | 3.197 | 5.421 | 1.70x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 9.337 | 2.12x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.748 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.58 | 1.00x |
| flight8.gpu_ms_p95 | 3.081 | 5.085 | 1.65x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 982.094 | 0.52x ✅ better |
| flight8.preload_ms | 1398.04 | 709.768 | 0.51x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 203.002 | 1.63x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 11.329 | 0.90x |
| flight8.tick_ms_p50 | 0.158 | 0.417 | 2.64x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.364 | 1.12x |
| flight8.update_ms_max | 12.421 | 2.958 | 0.24x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.004 | 0.40x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.583 | 0.67x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.667 | 0.82x |
| flight8.worker_mesh_us | 181.115 | 317.931 | 1.76x ⚠️ worse |
| fluids.pending | 240 | 1170 | 4.88x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6547 | 2.51x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 10.758 | 3.15x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.42 | 1.86x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.399 | 1.28x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 1.352 | 1.20x |
| frame_1080p.encode_ms_p50 | 0.625 | 0.936 | 1.50x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 19.245 | 7.31x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.272 | 1.85x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.132 | 1.33x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.105 | 1.60x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 8.057 | 1.97x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.882 | 2.24x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.462 | 1.94x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.857 | 1.41x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.614 | 1.92x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.422 | 1.65x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.854 | 1.44x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.336 | 1.12x |
| gen.chunk_ms_p95 | 3.325 | 4.507 | 1.36x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1063.22 | 1.58x ⚠️ worse |
| gen.starts_cold_ms | – | 1.257 | new |
| gen.terrain_hash | 1238443285367868 | 670778666217496 | ⚠️ changed |
| genphase.caves_ms | – | 1.01 | new |
| genphase.columns_ms | – | 0.266 | new |
| genphase.ores_ms | – | 0.263 | new |
| genphase.plants_ms | – | 0.256 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.182 | new |
| genphase.structures_ms | – | 0.178 | new |
| genphase.surface_ms | – | 0.026 | new |
| genphase.trees_ms | – | 0.048 | new |
| mesh.chunk_ms_max | 5.758 | 7.284 | 1.27x |
| mesh.chunk_ms_mean | 4.38 | 5.761 | 1.32x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1954.08 | 1.21x |
| mesh.section_us_mean | 139.451 | 240.057 | 1.72x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 998.974 | 1.46x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 5.838 | 1.07x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.716 | 1.15x |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1379.97 | 0.93x |
| mesh_lod1.section_us_mean | 126.754 | 196.519 | 1.55x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 790 | 1.39x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 0.963 | 0.60x ✅ better |
| mobs.tick_150_ms_max | 1.25 | 2.516 | 2.01x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.525 | 1.93x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.33 | 3.03x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.381 | 12.29x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.208 | 14.73x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.465 | 0.85x |
| save.load_chunk_ms | 0.587 | 0.395 | 0.67x ✅ better |
| save.main_thread_ms | 5.206 | 4.413 | 0.85x |
| save.unchanged_resave_ms | 2.544 | 1.929 | 0.76x ✅ better |
| ships.assemble_ms | 19.313 | 29.103 | 1.51x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.018 | 0.67x ✅ better |
| ships.blast_ms | 2.675 | 1.753 | 0.66x ✅ better |
| ships.blast_remesh_ms | 5.466 | 4.565 | 0.84x |
| ships.collide_far_us | 0.214 | 0.243 | 1.14x |
| ships.collide_us | 1.047 | 2.855 | 2.73x ⚠️ worse |
| ships.dock_ms | 12.056 | 18.539 | 1.54x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.083 | 2.31x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.541 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.269 | 0.53x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.112 | 0.85x |
| ships.frame_encode_ms | 0.023 | 0.017 | 0.74x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.178 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.453 | 0.80x |
| ships.physics_ms_mean | 0.165 | 0.22 | 1.33x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.522 | 2.45x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 2.215 | 0.94x |
| ships.tick_ms_max | 0.522 | 4.91 | 9.41x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.497 | 2.27x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.302 | 4.31x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.169 | 0.73x ✅ better |
| startup.first_load_ms | 206.958 | 242.614 | 1.17x |
| startup.renderer_init_again_ms | 27.582 | 1211.9 | 43.94x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2784.84 | 3.41x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.42 | 1.21x |
| startup.since_launch_s | 5.923 | 9.941 | 1.68x ⚠️ worse |
| startup.textures_ms | 26.537 | 958.94 | 36.14x ⚠️ worse |
| startup.world_init_ms | 2.198 | 20.172 | 9.18x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.044 | 0.35x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.272 | 0.44x ✅ better |
| tnt.remesh_s | 0.087 | 0.079 | 0.91x |
| tnt.tick_ms_max | 5.414 | 10.316 | 1.91x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 0.782 | 0.17x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 10.316 | 1.91x ⚠️ worse |
