| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.927 | 3.21x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.705 | 1.58x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.614 | 1.03x |
| edit.place_ms_max | 0.732 | 1.012 | 1.38x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.663 | 1.46x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.609 | 1.02x |
| flight16.arena_free_mb | 0.864 | 3.706 | 4.29x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.133 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.405 | 0.57x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.967 | 0.84x |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1209 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.012 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.305 | 0.87x |
| flight16.encode_ms_p95 | 2.361 | 3.245 | 1.37x ⚠️ worse |
| flight16.frame_ms_max | 12.652 | 20.794 | 1.64x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.121 | 0.86x |
| flight16.frame_ms_p95 | 5.8 | 5.675 | 0.98x |
| flight16.frame_ms_p99 | 7.443 | 9.146 | 1.23x |
| flight16.gen_chunks_per_s | 43.68 | 43.667 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.061 | 0.85x |
| flight16.gpu_ms_p95 | 5.71 | 5.258 | 0.92x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 75.234 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2271.25 | 0.87x |
| flight16.preload_ms | 1871.23 | 1789.01 | 0.96x |
| flight16.realtime | 0.998 | 0.998 | 1.00x |
| flight16.resident_after_load_mb | – | 249.862 | new |
| flight16.resident_after_renderer_mb | – | 331.159 | new |
| flight16.resident_peak_mb | 285.862 | 352.331 | 1.23x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 10.905 | 1.28x |
| flight16.tick_ms_p50 | 0.388 | 0.904 | 2.33x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.226 | 1.07x |
| flight16.update_ms_max | 8.289 | 2.72 | 0.33x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.088 | 5.18x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.977 | 0.56x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.555 | 1.26x |
| flight16.worker_mesh_us | 177.949 | 177.94 | 1.00x |
| flight24.arena_free_mb | 0.427 | 4.227 | 9.90x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.273 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.994 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 1.023 | 0.85x |
| flight24.cull_ms_p95 | 2.767 | 2.527 | 0.91x |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3016 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.368 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.414 | 0.98x |
| flight24.encode_ms_p95 | 5.237 | 5.475 | 1.05x |
| flight24.frame_ms_max | 13.319 | 33.189 | 2.49x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.68 | 0.87x |
| flight24.frame_ms_p95 | 9.472 | 9.627 | 1.02x |
| flight24.frame_ms_p99 | 10.337 | 17.836 | 1.73x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.603 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.566 | 0.85x |
| flight24.gpu_ms_p95 | 9.428 | 8.954 | 0.95x |
| flight24.hitches | 0 | 3 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 128.151 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 2909.19 | 0.84x |
| flight24.preload_ms | 4742.83 | 4474.82 | 0.94x |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_after_load_mb | – | 450.565 | new |
| flight24.resident_after_renderer_mb | – | 506.237 | new |
| flight24.resident_peak_mb | 512.018 | 533.691 | 1.04x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 18.571 | 1.60x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.119 | 2.79x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.766 | 1.28x |
| flight24.update_ms_max | 4.586 | 10.41 | 2.27x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.251 | 16.73x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.544 | 0.61x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.696 | 1.14x |
| flight24.worker_mesh_us | 177.947 | 184.593 | 1.04x |
| flight8.arena_free_mb | 2.438 | 5.298 | 2.17x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.994 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.091 | 0.45x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.239 | 0.78x |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.137 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.552 | 0.98x |
| flight8.encode_ms_p95 | 0.832 | 1.438 | 1.73x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 19.959 | 1.51x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.458 | 0.95x |
| flight8.frame_ms_p95 | 3.197 | 3.448 | 1.08x |
| flight8.frame_ms_p99 | 4.401 | 6.195 | 1.41x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.734 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.44 | 0.95x |
| flight8.gpu_ms_p95 | 3.081 | 3.157 | 1.02x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 34.839 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 579.266 | 0.87x |
| flight8.preload_ms | 1398.04 | 556.045 | 0.40x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_after_load_mb | – | 104.627 | new |
| flight8.resident_after_renderer_mb | – | 191.517 | new |
| flight8.resident_peak_mb | 124.705 | 218.33 | 1.75x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 16.126 | 1.29x |
| flight8.tick_ms_p50 | 0.158 | 0.491 | 3.11x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.349 | 1.10x |
| flight8.update_ms_max | 12.421 | 1.836 | 0.15x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.003 | 0.30x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.378 | 0.43x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.424 | 0.75x ✅ better |
| flight8.worker_mesh_us | 181.115 | 160.356 | 0.89x |
| fluids.pending | 240 | 1449 | 6.04x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3546 | 1.36x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.028 | 1.47x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.368 | 1.63x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.975 | 1.06x |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.48 | 1.05x |
| frame.mesh_mb | 57.324 | 65.841 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 2.07 | 1.84x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.803 | 1.28x |
| frame_1080p.gpu_ms_max | 2.632 | 5.815 | 2.21x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.64 | 1.58x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 1.202 | 0.75x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.875 | 1.27x |
| frame_4k.gpu_ms_max | 4.083 | 6.398 | 1.57x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 5.368 | 1.52x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.998 | 3.97x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.185 | 1.95x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.483 | 1.86x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.661 | 1.77x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 3.79 | 1.12x |
| gen.chunk_ms_mean | 2.082 | 1.652 | 0.79x |
| gen.chunk_ms_p95 | 3.325 | 2.217 | 0.67x ✅ better |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 2027.88 | 0.83x |
| gen.starts_cold_ms | – | 0.316 | new |
| gen.terrain_hash | 1238443285367868 | 1411295188973264 | ⚠️ changed |
| genphase.caves_ms | – | 0.789 | new |
| genphase.columns_ms | – | 0.204 | new |
| genphase.ores_ms | – | 0.214 | new |
| genphase.plants_ms | – | 0.134 | new |
| genphase.starts_ms | – | 0.006 | new |
| genphase.stone_ms | – | 0.137 | new |
| genphase.structures_ms | – | 0.04 | new |
| genphase.surface_ms | – | 0.025 | new |
| genphase.trees_ms | – | 0.035 | new |
| mesh.chunk_ms_max | 5.758 | 2.931 | 0.51x ✅ better |
| mesh.chunk_ms_mean | 3.347 | 2.605 | 0.78x |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 697.017 | 0.43x ✅ better |
| mesh.section_us_mean | 139.451 | 108.535 | 0.78x |
| mesh.section_us_p95 | 686.049 | 501.99 | 0.73x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 3.053 | 0.56x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.32 | 0.76x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 951.052 | 0.64x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 96.681 | 0.76x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 460.029 | 0.81x |
| mobs.per_mob_us | 1.608 | 2.993 | 1.86x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 2.756 | 2.20x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.669 | 2.46x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.365 | 3.11x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.22 | 7.10x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.536 | 6.54x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.015 | 1.12x |
| save.chunk_ms | 2.896 | 1.894 | 0.65x ✅ better |
| save.load_chunk_ms | 0.587 | 0.442 | 0.75x ✅ better |
| save.main_thread_ms | 5.206 | 3.704 | 0.71x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.167 | 0.46x ✅ better |
| ships.assemble_ms | 19.313 | 21.342 | 1.11x |
| ships.assemble_remesh_s | 0.027 | 0.013 | 0.48x ✅ better |
| ships.blast_ms | 2.675 | 2.659 | 0.99x |
| ships.blast_remesh_ms | 5.466 | 5.621 | 1.03x |
| ships.collide_far_us | 0.214 | 0.305 | 1.43x ⚠️ worse |
| ships.collide_us | 1.047 | 0.91 | 0.87x |
| ships.dock_ms | 12.056 | 14.071 | 1.17x |
| ships.dock_remesh_s | 0.036 | 0.016 | 0.44x ✅ better |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.717 | 0.81x |
| ships.edit_ms_mean | 0.505 | 0.365 | 0.72x ✅ better |
| ships.edit_remesh_ms | 3.642 | 2.741 | 0.75x ✅ better |
| ships.frame_encode_ms | 0.023 | -0.424 | -18.43x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.04 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.906 | 1.60x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.159 | 0.96x |
| ships.physics_ms_p95 | 0.213 | 0.329 | 1.54x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.069 | 0.45x ✅ better |
| ships.tick_ms_max | 0.522 | 1.63 | 3.12x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.398 | 1.82x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.752 | 2.49x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.586 | 0.83x |
| startup.first_load_ms | 206.958 | 171.458 | 0.83x |
| startup.renderer_init_again_ms | 27.582 | 1675.02 | 60.73x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2674.42 | 3.27x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.327 | 0.94x |
| startup.since_launch_s | 5.923 | 10.886 | 1.84x ⚠️ worse |
| startup.textures_ms | 26.537 | 1475.59 | 55.60x ⚠️ worse |
| startup.world_init_ms | 2.198 | 6.555 | 2.98x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.922 | 0.22x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.701 | 0.59x ✅ better |
| tnt.remesh_s | 0.087 | 0.071 | 0.82x |
| tnt.tick_ms_max | 5.414 | 5.049 | 0.93x |
| tnt.tick_ms_p50 | 4.529 | 0.661 | 0.15x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 5.049 | 0.93x |
| weather.decal_quads | – | 120 | new |
| weather.fire_burning_peak | – | 103 | new |
| weather.fire_tick_ms_worst | – | 0.597 | new |
| weather.flood_step_ms_worst | – | 1.905 | new |
| weather.storm_ms_worst | – | 1.909 | new |
| weather.tick_ms_max | – | 20.923 | new |
| weather.tick_ms_p50 | – | 0.377 | new |
| weather.tick_ms_p95 | – | 1.224 | new |
