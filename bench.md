| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.72 | 1.20x |
| edit.break_ms_mean | 0.447 | 0.614 | 1.37x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.599 | 1.01x |
| edit.place_ms_max | 0.732 | 0.777 | 1.06x |
| edit.place_ms_mean | 0.455 | 0.614 | 1.35x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.596 | 1.00x |
| flight16.arena_free_mb | 0.864 | 14.9 | 17.25x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.867 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.893 | 1.11x |
| flight16.coverage_min | 0.962 | 0.774 | 1.24x |
| flight16.cull_ms_p50 | 0.708 | 0.286 | 0.40x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.404 | 0.35x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.439 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.691 | 0.46x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 0.972 | 0.41x ✅ better |
| flight16.frame_ms_max | 12.652 | 11.858 | 0.94x |
| flight16.frame_ms_p50 | 4.807 | 2.985 | 0.62x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 3.735 | 0.64x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 4.151 | 0.56x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 43.546 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 2.985 | 0.62x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 3.727 | 0.65x ✅ better |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.254 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3475.33 | 0.57x ✅ better |
| flight16.preload_ms | 1871.23 | 1488.41 | 0.80x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 331.003 | 1.16x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 10.954 | 1.28x |
| flight16.tick_ms_p50 | 0.388 | 0.436 | 1.12x |
| flight16.tick_ms_p95 | 2.08 | 1.33 | 0.64x ✅ better |
| flight16.update_ms_max | 8.289 | 1.392 | 0.17x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.168 | 9.88x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.589 | 0.34x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.789 | 0.88x |
| flight16.worker_mesh_us | 177.949 | 202.678 | 1.14x |
| flight24.arena_free_mb | 0.427 | 19.377 | 45.38x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 148.01 | 0.67x ✅ better |
| flight24.chunks | 2176 | 1732 | 0.80x |
| flight24.coverage_mean | 0.994 | 0.837 | 1.19x |
| flight24.coverage_min | 0.974 | 0.738 | 1.32x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.572 | 0.48x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 0.966 | 0.35x ✅ better |
| flight24.cull_walked_sections | 7607 | 4237 | 0.56x ✅ better |
| flight24.draw_calls | 3175 | 1287 | 0.41x ✅ better |
| flight24.drawn_kquads | 821.704 | 233.352 | 0.28x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.133 | 0.46x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 1.82 | 0.35x ✅ better |
| flight24.frame_ms_max | 13.319 | 18.799 | 1.41x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 3.785 | 0.49x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 4.948 | 0.52x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 7.179 | 0.69x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 26.722 | 2.38x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 3.779 | 0.49x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 4.857 | 0.52x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 68.144 | 0.52x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3734.44 | 0.66x ✅ better |
| flight24.preload_ms | 4742.83 | 3132.08 | 0.66x ✅ better |
| flight24.realtime | 1 | 0.999 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 540.378 | 1.06x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 14.778 | 1.27x |
| flight24.tick_ms_p50 | 0.401 | 0.557 | 1.39x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.842 | 0.63x ✅ better |
| flight24.update_ms_max | 4.586 | 14.204 | 3.10x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.268 | 17.87x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.796 | 0.31x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.814 | 0.77x |
| flight24.worker_mesh_us | 177.947 | 245.588 | 1.38x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.552 | 4.33x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.073 | 0.36x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.11 | 0.36x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.297 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.366 | 0.65x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.567 | 0.68x ✅ better |
| flight8.frame_ms_max | 13.232 | 11.398 | 0.86x |
| flight8.frame_ms_p50 | 2.588 | 2.099 | 0.81x |
| flight8.frame_ms_p95 | 3.197 | 2.55 | 0.80x |
| flight8.frame_ms_p99 | 4.401 | 3.303 | 0.75x ✅ better |
| flight8.gen_chunks_per_s | 23.603 | 23.726 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.099 | 0.81x |
| flight8.gpu_ms_p95 | 3.081 | 2.539 | 0.82x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.353 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 955.131 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 465.066 | 0.33x ✅ better |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 213.612 | 1.71x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 10.959 | 0.87x |
| flight8.tick_ms_p50 | 0.158 | 0.296 | 1.87x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 0.823 | 0.67x ✅ better |
| flight8.update_ms_max | 12.421 | 1.366 | 0.11x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.004 | 0.40x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.39 | 0.45x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.025 | 0.63x ✅ better |
| flight8.worker_mesh_us | 181.115 | 219.372 | 1.21x |
| fluids.pending | 240 | 1141 | 4.75x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6864 | 2.63x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 7.057 | 2.06x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.315 | 1.39x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.189 | 0.64x ✅ better |
| frame.draw_calls | 1076 | 1218 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.522 | 1.32x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.334 | 0.91x |
| frame.visible_sections | 686 | 699 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 0.954 | 0.85x |
| frame_1080p.encode_ms_p50 | 0.625 | 0.705 | 1.13x |
| frame_1080p.gpu_ms_max | 2.632 | 4.029 | 1.53x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.842 | 1.66x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 0.972 | 0.61x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.817 | 1.18x |
| frame_4k.gpu_ms_max | 4.083 | 6.682 | 1.64x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.215 | 1.77x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 0.828 | 1.10x |
| frame_800p.encode_ms_p50 | 0.608 | 0.596 | 0.98x |
| frame_800p.gpu_ms_max | 2.405 | 3.336 | 1.39x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.031 | 1.47x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 4.581 | 1.35x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.793 | 0.86x |
| gen.chunk_ms_p95 | 3.325 | 3.701 | 1.11x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1267.66 | 1.33x ⚠️ worse |
| gen.starts_cold_ms | – | 2.385 | new |
| gen.terrain_hash | 1238443285367868 | 629285074282282 | ⚠️ changed |
| genphase.caves_ms | – | 0.758 | new |
| genphase.columns_ms | – | 0.198 | new |
| genphase.ores_ms | – | 0.209 | new |
| genphase.plants_ms | – | 0.191 | new |
| genphase.starts_ms | – | 0.005 | new |
| genphase.stone_ms | – | 0.151 | new |
| genphase.structures_ms | – | 0.162 | new |
| genphase.surface_ms | – | 0.022 | new |
| genphase.trees_ms | – | 0.035 | new |
| mesh.chunk_ms_max | 5.758 | 4.631 | 0.80x |
| mesh.chunk_ms_mean | 4.38 | 3.938 | 0.90x |
| mesh.quads_per_chunk | 4996 | 4972.22 | 1.00x |
| mesh.section_us_max | 1621.01 | 859.976 | 0.53x ✅ better |
| mesh.section_us_mean | 139.451 | 164.073 | 1.18x |
| mesh.section_us_p95 | 686.049 | 699.997 | 1.02x |
| mesh_lod1.chunk_ms_max | 5.44 | 4.56 | 0.84x |
| mesh_lod1.chunk_ms_mean | 4.1 | 3.877 | 0.95x |
| mesh_lod1.quads_per_chunk | 2535 | 2502.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 858.068 | 0.58x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 161.524 | 1.27x |
| mesh_lod1.section_us_p95 | 568.032 | 686.049 | 1.21x |
| mobs.per_mob_us | 1.608 | 1.79 | 1.11x |
| mobs.tick_150_ms_max | 1.25 | 3.362 | 2.69x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.467 | 1.72x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.284 | 2.92x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.198 | 6.39x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.797 | 9.72x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.463 | 1.45x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.253 | 0.43x ✅ better |
| save.load_chunk_ms | 0.587 | 0.193 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 2.769 | 0.53x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.004 | 0.39x ✅ better |
| ships.assemble_ms | 19.313 | 13.225 | 0.68x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.022 | 0.81x |
| ships.blast_ms | 2.675 | 2.153 | 0.80x |
| ships.blast_remesh_ms | 5.466 | 4.095 | 0.75x ✅ better |
| ships.collide_far_us | 0.214 | 0.223 | 1.04x |
| ships.collide_us | 1.047 | 0.904 | 0.86x |
| ships.dock_ms | 12.056 | 11.725 | 0.97x |
| ships.dock_remesh_s | 0.036 | 0.063 | 1.75x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 1.907 | 2.15x ⚠️ worse |
| ships.edit_ms_mean | 0.505 | 0.456 | 0.90x |
| ships.edit_remesh_ms | 3.642 | 3.062 | 0.84x |
| ships.frame_encode_ms | 0.023 | -0.058 | -2.52x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.015 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.242 | 1.38x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.152 | 0.92x |
| ships.physics_ms_p95 | 0.213 | 0.178 | 0.84x |
| ships.spawn_frigate_ms | 2.358 | 2.115 | 0.90x |
| ships.tick_ms_max | 0.522 | 5.63 | 10.79x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.354 | 1.62x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.947 | 3.14x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.246 | 0.75x ✅ better |
| startup.first_load_ms | 206.958 | 156.021 | 0.75x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 862.591 | 31.27x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2180.25 | 2.67x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.26 | 0.75x ✅ better |
| startup.since_launch_s | 5.923 | 8.448 | 1.43x ⚠️ worse |
| startup.textures_ms | 26.537 | 592.006 | 22.31x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.306 | 6.51x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.666 | 0.19x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.974 | 0.34x ✅ better |
| tnt.remesh_s | 0.087 | 0.066 | 0.76x ✅ better |
| tnt.tick_ms_max | 5.414 | 1.019 | 0.19x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.782 | 0.17x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.019 | 0.19x ✅ better |
