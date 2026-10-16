| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.309 | 2.18x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.799 | 1.79x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.784 | 1.32x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.242 | 1.70x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.792 | 1.74x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.761 | 1.28x |
| flight16.arena_free_mb | 0.864 | 16.312 | 18.88x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.688 | 0.82x |
| flight16.chunks | 1056 | 1054 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.877 | 1.13x |
| flight16.coverage_min | 0.962 | 0.774 | 1.24x |
| flight16.cull_ms_p50 | 0.708 | 0.342 | 0.48x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.983 | 0.85x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.878 | 0.59x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.301 | 0.97x |
| flight16.frame_ms_max | 12.652 | 25.134 | 1.99x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.804 | 0.79x |
| flight16.frame_ms_p95 | 5.8 | 6.622 | 1.14x |
| flight16.frame_ms_p99 | 7.443 | 11.179 | 1.50x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.391 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.774 | 0.79x |
| flight16.gpu_ms_p95 | 5.71 | 5.807 | 1.02x |
| flight16.hitches | 0 | 1 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.334 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3453.32 | 0.57x ✅ better |
| flight16.preload_ms | 1871.23 | 2147.37 | 1.15x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_after_load_mb | – | 245.033 | new |
| flight16.resident_after_renderer_mb | – | 320.534 | new |
| flight16.resident_peak_mb | 285.862 | 338.955 | 1.19x |
| flight16.slab_mb | 96 | 72 | 0.75x ✅ better |
| flight16.tick_ms_max | 8.551 | 10.257 | 1.20x |
| flight16.tick_ms_p50 | 0.388 | 0.664 | 1.71x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.344 | 1.13x |
| flight16.update_ms_max | 8.289 | 4.169 | 0.50x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.3 | 17.65x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.195 | 0.69x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.313 | 1.14x |
| flight16.worker_mesh_us | 177.949 | 296.229 | 1.66x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 23.412 | 54.83x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 144.184 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1687 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.832 | 1.19x |
| flight24.coverage_min | 0.974 | 0.731 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.724 | 0.60x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.205 | 0.80x |
| flight24.cull_walked_sections | 7607 | 3698 | 0.49x ✅ better |
| flight24.draw_calls | 3175 | 1124 | 0.35x ✅ better |
| flight24.drawn_kquads | 821.704 | 211.166 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.441 | 0.58x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.021 | 0.77x ✅ better |
| flight24.frame_ms_max | 13.319 | 17.808 | 1.34x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.617 | 0.60x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 8.428 | 0.89x |
| flight24.frame_ms_p99 | 10.337 | 14.693 | 1.42x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 22.985 | 2.77x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.583 | 0.59x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.586 | 0.70x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 68.459 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3470.51 | 0.71x ✅ better |
| flight24.preload_ms | 4742.83 | 5138.65 | 1.08x |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_after_load_mb | – | 444.206 | new |
| flight24.resident_after_renderer_mb | – | 485.237 | new |
| flight24.resident_peak_mb | 512.018 | 504.206 | 0.98x |
| flight24.slab_mb | 148 | 100 | 0.68x ✅ better |
| flight24.tick_ms_max | 11.61 | 15.766 | 1.36x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.814 | 2.03x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.423 | 1.16x |
| flight24.update_ms_max | 4.586 | 15.586 | 3.40x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.391 | 26.07x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.763 | 0.70x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.269 | 0.96x |
| flight24.worker_mesh_us | 177.947 | 340.075 | 1.91x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.71 | 4.39x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.08 | 0.39x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.224 | 0.73x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.435 | 0.77x |
| flight8.encode_ms_p95 | 0.832 | 1.124 | 1.35x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 16.887 | 1.28x |
| flight8.frame_ms_p50 | 2.588 | 2.523 | 0.97x |
| flight8.frame_ms_p95 | 3.197 | 4.033 | 1.26x |
| flight8.frame_ms_p99 | 4.401 | 8.071 | 1.83x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.712 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.515 | 0.98x |
| flight8.gpu_ms_p95 | 3.081 | 3.748 | 1.22x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 954.956 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 494.856 | 0.35x ✅ better |
| flight8.realtime | 0.994 | 0.998 | 1.00x |
| flight8.resident_after_load_mb | – | 106.33 | new |
| flight8.resident_after_renderer_mb | – | 190.752 | new |
| flight8.resident_peak_mb | 124.705 | 213.018 | 1.71x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 15.74 | 1.26x |
| flight8.tick_ms_p50 | 0.158 | 0.389 | 2.46x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.378 | 1.13x |
| flight8.update_ms_max | 12.421 | 4.926 | 0.40x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.004 | 0.40x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.628 | 0.72x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.588 | 0.80x |
| flight8.worker_mesh_us | 181.115 | 309.507 | 1.71x ⚠️ worse |
| fluids.pending | 240 | 1271 | 5.30x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6702 | 2.57x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.091 | 1.49x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.372 | 1.65x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.558 | 0.83x |
| frame.draw_calls | 1076 | 1221 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 253.057 | 1.41x ⚠️ worse |
| frame.mesh_mb | 57.324 | 53.594 | 0.93x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.805 | 2.50x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.028 | 1.64x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 7.672 | 2.91x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.615 | 2.00x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.55 | 1.59x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.919 | 1.33x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 10.498 | 2.57x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.095 | 2.02x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.293 | 4.36x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.418 | 2.33x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 5.173 | 2.15x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.448 | 2.15x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.854 | 1.44x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.921 | 0.92x |
| gen.chunk_ms_p95 | 3.325 | 3.787 | 1.14x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1155.53 | 1.46x ⚠️ worse |
| gen.starts_cold_ms | – | 1.286 | new |
| gen.terrain_hash | 1238443285367868 | 1538201698069241 | ⚠️ changed |
| genphase.caves_ms | – | 0.828 | new |
| genphase.columns_ms | – | 0.207 | new |
| genphase.ores_ms | – | 0.216 | new |
| genphase.plants_ms | – | 0.197 | new |
| genphase.starts_ms | – | 0.005 | new |
| genphase.stone_ms | – | 0.164 | new |
| genphase.structures_ms | – | 0.182 | new |
| genphase.surface_ms | – | 0.023 | new |
| genphase.trees_ms | – | 0.035 | new |
| mesh.chunk_ms_max | 5.758 | 6.969 | 1.21x |
| mesh.chunk_ms_mean | 4.38 | 5.54 | 1.26x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1932.98 | 1.19x |
| mesh.section_us_mean | 139.451 | 230.85 | 1.66x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 905.991 | 1.32x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 9.379 | 1.72x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 5.604 | 1.37x ⚠️ worse |
| mesh_lod1.quads_per_chunk | 2535 | 2515.56 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 2091.05 | 1.41x ⚠️ worse |
| mesh_lod1.section_us_mean | 126.754 | 233.502 | 1.84x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 972.033 | 1.71x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 2.055 | 1.28x |
| mobs.tick_150_ms_max | 1.25 | 4.225 | 3.38x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.559 | 2.06x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.427 | 3.25x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.251 | 8.10x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.915 | 11.16x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.48 | 0.51x ✅ better |
| save.load_chunk_ms | 0.587 | 0.196 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 3.626 | 0.70x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.382 | 0.54x ✅ better |
| ships.assemble_ms | 19.313 | 11.964 | 0.62x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.021 | 0.78x |
| ships.blast_ms | 2.675 | 2.308 | 0.86x |
| ships.blast_remesh_ms | 5.466 | 5.358 | 0.98x |
| ships.collide_far_us | 0.214 | 0.232 | 1.08x |
| ships.collide_us | 1.047 | 0.917 | 0.88x |
| ships.dock_ms | 12.056 | 11.897 | 0.99x |
| ships.dock_remesh_s | 0.036 | 0.07 | 1.94x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.649 | 0.73x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.29 | 0.57x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.285 | 0.63x ✅ better |
| ships.frame_encode_ms | 0.023 | -0.092 | -4.00x ✅ better |
| ships.frame_gpu_ms | -0.228 | -0.023 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.285 | 1.40x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.281 | 1.70x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.763 | 3.58x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 2.38 | 1.01x |
| ships.tick_ms_max | 0.522 | 7.964 | 15.26x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.64 | 2.92x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.999 | 6.62x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.08 | 0.71x ✅ better |
| startup.first_load_ms | 206.958 | 182.859 | 0.88x |
| startup.renderer_init_again_ms | 27.582 | 1717.44 | 62.27x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2995.89 | 3.66x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.699 | 2.01x ⚠️ worse |
| startup.since_launch_s | 5.923 | 10.633 | 1.80x ⚠️ worse |
| startup.textures_ms | 26.537 | 1083.17 | 40.82x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.892 | 6.78x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.757 | 0.20x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1 | 0.34x ✅ better |
| tnt.remesh_s | 0.087 | 0.087 | 1.00x |
| tnt.tick_ms_max | 5.414 | 4.525 | 0.84x |
| tnt.tick_ms_p50 | 4.529 | 0.412 | 0.09x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 4.525 | 0.84x |
| weather.decal_quads | – | 74 | new |
| weather.fire_burning_peak | – | 96 | new |
| weather.fire_tick_ms_worst | – | 0.783 | new |
| weather.flood_step_ms_worst | – | 1.736 | new |
| weather.storm_ms_worst | – | 1.739 | new |
| weather.tick_ms_max | – | 15.132 | new |
| weather.tick_ms_p50 | – | 0.353 | new |
| weather.tick_ms_p95 | – | 1.406 | new |
