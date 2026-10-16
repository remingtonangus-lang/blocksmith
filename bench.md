| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 12.564 | 20.94x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.091 | 2.44x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.729 | 1.23x |
| edit.place_ms_max | 0.732 | 15.218 | 20.79x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.165 | 2.56x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.74 | 1.24x |
| flight16.arena_free_mb | 0.864 | 16.184 | 18.73x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.533 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.848 | 1.17x |
| flight16.coverage_min | 0.962 | 0.722 | 1.33x ⚠️ worse |
| flight16.cull_ms_p50 | 0.708 | 0.278 | 0.39x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.769 | 0.67x ✅ better |
| flight16.cull_walked_sections | 2817 | 1557 | 0.55x ✅ better |
| flight16.draw_calls | 1434 | 966 | 0.67x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.143 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.715 | 0.48x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.8 | 0.76x ✅ better |
| flight16.frame_ms_max | 12.652 | 8.855 | 0.70x ✅ better |
| flight16.frame_ms_p50 | 4.807 | 3.208 | 0.67x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 4.267 | 0.74x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 6.033 | 0.81x |
| flight16.gen_chunks_per_s | 43.68 | 43.189 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.203 | 0.67x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.188 | 0.73x ✅ better |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.71 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3186.08 | 0.62x ✅ better |
| flight16.preload_ms | 1871.23 | 1612.84 | 0.86x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 346.831 | 1.21x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 7.768 | 0.91x |
| flight16.tick_ms_p50 | 0.388 | 0.49 | 1.26x |
| flight16.tick_ms_p95 | 2.08 | 1.54 | 0.74x ✅ better |
| flight16.update_ms_max | 8.289 | 1.795 | 0.22x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.185 | 10.88x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.639 | 0.37x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.89 | 0.93x |
| flight16.worker_mesh_us | 177.949 | 249.903 | 1.40x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.657 | 55.40x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 142.305 | 0.64x ✅ better |
| flight24.chunks | 2176 | 1663 | 0.76x ✅ better |
| flight24.coverage_mean | 0.994 | 0.827 | 1.20x |
| flight24.coverage_min | 0.974 | 0.715 | 1.36x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.573 | 0.48x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.277 | 0.46x ✅ better |
| flight24.cull_walked_sections | 7607 | 3568 | 0.47x ✅ better |
| flight24.draw_calls | 3175 | 1087 | 0.34x ✅ better |
| flight24.drawn_kquads | 821.704 | 206.839 | 0.25x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.18 | 0.48x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.634 | 0.50x ✅ better |
| flight24.frame_ms_max | 13.319 | 21.554 | 1.62x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.118 | 0.53x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 6.059 | 0.64x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 6.607 | 0.64x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 21.643 | 2.94x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.109 | 0.53x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.902 | 0.63x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 68.235 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3330.55 | 0.74x ✅ better |
| flight24.preload_ms | 4742.83 | 3527.42 | 0.74x ✅ better |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 495.112 | 0.97x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 14.285 | 1.23x |
| flight24.tick_ms_p50 | 0.401 | 0.532 | 1.33x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.708 | 0.58x ✅ better |
| flight24.update_ms_max | 4.586 | 1.983 | 0.43x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.242 | 16.13x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.742 | 0.29x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.956 | 0.83x |
| flight24.worker_mesh_us | 177.947 | 281.054 | 1.58x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.883 | 4.46x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.324 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.072 | 0.35x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.152 | 0.50x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 335 | 0.72x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.124 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.383 | 0.68x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.785 | 0.94x |
| flight8.frame_ms_max | 13.232 | 15.974 | 1.21x |
| flight8.frame_ms_p50 | 2.588 | 2.116 | 0.82x |
| flight8.frame_ms_p95 | 3.197 | 2.788 | 0.87x |
| flight8.frame_ms_p99 | 4.401 | 4.086 | 0.93x |
| flight8.gen_chunks_per_s | 23.603 | 23.729 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.115 | 0.82x |
| flight8.gpu_ms_p95 | 3.081 | 2.756 | 0.89x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.406 | 0.60x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 968.895 | 0.52x ✅ better |
| flight8.preload_ms | 1398.04 | 515.56 | 0.37x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 208.346 | 1.67x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 6.393 | 0.51x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.294 | 1.86x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 0.909 | 0.74x ✅ better |
| flight8.update_ms_max | 12.421 | 1.017 | 0.08x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.035 | 3.50x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.384 | 0.44x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.948 | 0.60x ✅ better |
| flight8.worker_mesh_us | 181.115 | 238.219 | 1.32x ⚠️ worse |
| fluids.pending | 240 | 1360 | 5.67x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 5880 | 2.26x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 4.584 | 1.34x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.227 | 1.00x |
| fluids.tick_ms_p95 | 1.872 | 1.234 | 0.66x ✅ better |
| frame.draw_calls | 1076 | 1253 | 1.16x |
| frame.drawn_chunks | 272 | 271 | 1.00x |
| frame.drawn_kquads | 178.99 | 258.303 | 1.44x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.628 | 0.94x |
| frame.visible_sections | 686 | 721 | 1.05x |
| frame_1080p.encode_ms_max | 1.123 | 3.447 | 3.07x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.861 | 1.38x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.27 | 2.00x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.969 | 2.15x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.208 | 1.38x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.796 | 1.15x |
| frame_4k.gpu_ms_max | 4.083 | 6.796 | 1.66x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.307 | 1.79x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.907 | 2.53x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.789 | 1.30x |
| frame_800p.gpu_ms_max | 2.405 | 4.497 | 1.87x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.117 | 1.99x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 6.412 | 1.90x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.881 | 1.38x ⚠️ worse |
| gen.chunk_ms_p95 | 3.325 | 5.949 | 1.79x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1010.27 | 1.67x ⚠️ worse |
| gen.starts_cold_ms | – | 0.963 | new |
| gen.terrain_hash | 1238443285367868 | 517294474285879 | ⚠️ changed |
| genphase.caves_ms | – | 1.334 | new |
| genphase.columns_ms | – | 0.306 | new |
| genphase.ores_ms | – | 0.275 | new |
| genphase.plants_ms | – | 0.247 | new |
| genphase.starts_ms | – | 0.01 | new |
| genphase.stone_ms | – | 0.239 | new |
| genphase.structures_ms | – | 0.288 | new |
| genphase.surface_ms | – | 0.033 | new |
| genphase.trees_ms | – | 0.054 | new |
| mesh.chunk_ms_max | 5.758 | 5.542 | 0.96x |
| mesh.chunk_ms_mean | 4.38 | 4.52 | 1.03x |
| mesh.quads_per_chunk | 4996 | 4974.44 | 1.00x |
| mesh.section_us_max | 1621.01 | 1505.97 | 0.93x |
| mesh.section_us_mean | 139.451 | 188.351 | 1.35x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 758.052 | 1.10x |
| mesh_lod1.chunk_ms_max | 5.44 | 7.156 | 1.32x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.568 | 1.11x |
| mesh_lod1.quads_per_chunk | 2535 | 2531.33 | 1.00x |
| mesh_lod1.section_us_max | 1477.96 | 2709.03 | 1.83x ⚠️ worse |
| mesh_lod1.section_us_mean | 126.754 | 190.354 | 1.50x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 743.985 | 1.31x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.58 | 0.98x |
| mobs.tick_150_ms_max | 1.25 | 1.89 | 1.51x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.438 | 1.61x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.157 | 2.64x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.201 | 6.48x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.892 | 10.88x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.131 | 1.37x ⚠️ worse |
| save.chunk_ms | 2.896 | 3.234 | 1.12x |
| save.load_chunk_ms | 0.587 | 0.248 | 0.42x ✅ better |
| save.main_thread_ms | 5.206 | 3.742 | 0.72x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.102 | 0.43x ✅ better |
| ships.assemble_ms | 19.313 | 16.295 | 0.84x |
| ships.assemble_remesh_s | 0.027 | 0.007 | 0.26x ✅ better |
| ships.blast_ms | 2.675 | 2.299 | 0.86x |
| ships.blast_remesh_ms | 5.466 | 5.458 | 1.00x |
| ships.collide_far_us | 0.214 | 0.258 | 1.21x |
| ships.collide_us | 1.047 | 1.218 | 1.16x |
| ships.dock_ms | 12.056 | 13.34 | 1.11x |
| ships.dock_remesh_s | 0.036 | 0.088 | 2.44x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.533 | 0.60x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.259 | 0.51x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.381 | 0.65x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.013 | 0.57x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.076 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 9.078 | 2.96x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.247 | 1.50x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.575 | 2.70x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 10.191 | 4.32x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 6.629 | 12.70x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.541 | 2.47x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.263 | 4.18x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.712 | 1.09x |
| startup.first_load_ms | 206.958 | 245.845 | 1.19x |
| startup.renderer_init_again_ms | 27.582 | 877.965 | 31.83x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1913.19 | 2.34x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.281 | 0.81x |
| startup.since_launch_s | 5.923 | 10.149 | 1.71x ⚠️ worse |
| startup.textures_ms | 26.537 | 753.838 | 28.41x ⚠️ worse |
| startup.world_init_ms | 2.198 | 21.447 | 9.76x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.693 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.937 | 0.32x ✅ better |
| tnt.remesh_s | 0.087 | 0.134 | 1.54x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 6.873 | 1.27x |
| tnt.tick_ms_p50 | 4.529 | 0.342 | 0.08x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 6.873 | 1.27x |
