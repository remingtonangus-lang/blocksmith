| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.977 | 3.30x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.723 | 1.62x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.674 | 1.13x |
| edit.place_ms_max | 0.732 | 1.155 | 1.58x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.709 | 1.56x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.68 | 1.14x |
| flight16.arena_free_mb | 0.864 | 14.724 | 17.04x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.599 | 0.82x |
| flight16.chunks | 1056 | 1053 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.863 | 1.15x |
| flight16.coverage_min | 0.962 | 0.756 | 1.27x |
| flight16.cull_ms_p50 | 0.708 | 0.336 | 0.47x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.986 | 0.86x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.439 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.84 | 0.56x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.311 | 0.98x |
| flight16.frame_ms_max | 12.652 | 26.111 | 2.06x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.696 | 0.77x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 6.929 | 1.19x |
| flight16.frame_ms_p99 | 7.443 | 14.721 | 1.98x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.184 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.638 | 0.76x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 6.178 | 1.08x |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.329 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3311.47 | 0.60x ✅ better |
| flight16.preload_ms | 1871.23 | 2125.22 | 1.14x |
| flight16.realtime | 0.998 | 0.997 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 322.955 | 1.13x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 13.325 | 1.56x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.656 | 1.69x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.451 | 1.18x |
| flight16.update_ms_max | 8.289 | 4.716 | 0.57x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.275 | 16.18x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.297 | 0.75x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.321 | 1.15x |
| flight16.worker_mesh_us | 177.949 | 282.68 | 1.59x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 20.05 | 46.96x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 145.19 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1699 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.833 | 1.19x |
| flight24.coverage_min | 0.974 | 0.735 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.625 | 0.52x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.46 | 0.53x ✅ better |
| flight24.cull_walked_sections | 7607 | 3861 | 0.51x ✅ better |
| flight24.draw_calls | 3175 | 1170 | 0.37x ✅ better |
| flight24.drawn_kquads | 821.704 | 217.89 | 0.27x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.252 | 0.51x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.8 | 0.53x ✅ better |
| flight24.frame_ms_max | 13.319 | 16.545 | 1.24x |
| flight24.frame_ms_p50 | 7.72 | 4.078 | 0.53x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.758 | 0.61x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 6.84 | 0.66x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 23.997 | 2.66x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.07 | 0.53x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.665 | 0.60x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 67.207 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3490.42 | 0.70x ✅ better |
| flight24.preload_ms | 4742.83 | 3803.69 | 0.80x |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 471.956 | 0.92x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 14.554 | 1.25x |
| flight24.tick_ms_p50 | 0.401 | 0.575 | 1.43x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 1.95 | 0.66x ✅ better |
| flight24.update_ms_max | 4.586 | 6.204 | 1.35x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.287 | 19.13x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.818 | 0.32x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.983 | 0.84x |
| flight24.worker_mesh_us | 177.947 | 275.956 | 1.55x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.733 | 4.40x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.093 | 0.46x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.241 | 0.79x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.297 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.486 | 0.86x |
| flight8.encode_ms_p95 | 0.832 | 1.204 | 1.45x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 31.937 | 2.41x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.57 | 0.99x |
| flight8.frame_ms_p95 | 3.197 | 4.318 | 1.35x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 7.639 | 1.74x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.618 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.567 | 1.00x |
| flight8.gpu_ms_p95 | 3.081 | 3.916 | 1.27x |
| flight8.hitches | 0 | 1 | infx ⚠️ worse |
| flight8.mesh_mb | 40.975 | 24.353 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 957.068 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 633.812 | 0.45x ✅ better |
| flight8.realtime | 0.994 | 0.994 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 207.674 | 1.67x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 22.535 | 1.80x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.442 | 2.80x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.599 | 1.31x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 3.991 | 0.32x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.007 | 0.70x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.733 | 0.84x |
| flight8.worker_gen_ms | 3.236 | 2.708 | 0.84x |
| flight8.worker_mesh_us | 181.115 | 317.483 | 1.75x ⚠️ worse |
| fluids.pending | 240 | 1340 | 5.58x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6604 | 2.54x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 6.94 | 2.03x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.277 | 1.23x |
| fluids.tick_ms_p95 | 1.872 | 1.236 | 0.66x ✅ better |
| frame.draw_calls | 1076 | 1218 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.522 | 1.32x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.334 | 0.91x |
| frame.visible_sections | 686 | 699 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 15.431 | 13.74x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.893 | 1.43x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 13.62 | 5.17x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.689 | 2.03x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.151 | 1.34x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 0.954 | 1.38x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 7.801 | 1.91x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.587 | 1.87x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.138 | 4.16x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.919 | 1.51x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 6.122 | 2.55x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.593 | 1.74x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 5.124 | 1.52x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.049 | 0.98x |
| gen.chunk_ms_p95 | 3.325 | 3.715 | 1.12x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1263.01 | 1.33x ⚠️ worse |
| gen.starts_cold_ms | – | 2.669 | new |
| gen.terrain_hash | 1238443285367868 | 3856083894865104 | ⚠️ changed |
| genphase.caves_ms | – | 0.846 | new |
| genphase.columns_ms | – | 0.238 | new |
| genphase.ores_ms | – | 0.23 | new |
| genphase.plants_ms | – | 0.201 | new |
| genphase.starts_ms | – | 0.008 | new |
| genphase.stone_ms | – | 0.182 | new |
| genphase.structures_ms | – | 0.196 | new |
| genphase.surface_ms | – | 0.026 | new |
| genphase.trees_ms | – | 0.044 | new |
| mesh.chunk_ms_max | 5.758 | 5.725 | 0.99x |
| mesh.chunk_ms_mean | 4.38 | 4.351 | 0.99x |
| mesh.quads_per_chunk | 4996 | 4972.22 | 1.00x |
| mesh.section_us_max | 1621.01 | 1433.02 | 0.88x |
| mesh.section_us_mean | 139.451 | 181.307 | 1.30x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 723.958 | 1.06x |
| mesh_lod1.chunk_ms_max | 5.44 | 6.704 | 1.23x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.592 | 1.12x |
| mesh_lod1.quads_per_chunk | 2535 | 2502.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1502.99 | 1.02x |
| mesh_lod1.section_us_mean | 126.754 | 191.342 | 1.51x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 771.046 | 1.36x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.313 | 0.82x |
| mobs.tick_150_ms_max | 1.25 | 1.772 | 1.42x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.472 | 1.74x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.274 | 2.90x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.275 | 8.87x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.946 | 11.54x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.493 | 1.45x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.377 | 0.48x ✅ better |
| save.load_chunk_ms | 0.587 | 0.165 | 0.28x ✅ better |
| save.main_thread_ms | 5.206 | 3.405 | 0.65x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.11 | 0.44x ✅ better |
| ships.assemble_ms | 19.313 | 19.801 | 1.03x |
| ships.assemble_remesh_s | 0.027 | 0.034 | 1.26x |
| ships.blast_ms | 2.675 | 7.794 | 2.91x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 35.029 | 6.41x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.58 | 2.71x ⚠️ worse |
| ships.collide_us | 1.047 | 2.962 | 2.83x ⚠️ worse |
| ships.dock_ms | 12.056 | 11.856 | 0.98x |
| ships.dock_remesh_s | 0.036 | 0.099 | 2.75x ⚠️ worse |
| ships.draw_calls | 66 | 67 | 1.02x |
| ships.edit_ms_max | 0.887 | 1.847 | 2.08x ⚠️ worse |
| ships.edit_ms_mean | 0.505 | 0.795 | 1.57x ⚠️ worse |
| ships.edit_remesh_ms | 3.642 | 2.781 | 0.76x ✅ better |
| ships.frame_encode_ms | 0.023 | 0.252 | 10.96x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.142 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.366 | 1.42x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.269 | 1.63x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.548 | 2.57x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 59.218 | 25.11x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 10.801 | 20.69x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.598 | 2.73x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.311 | 4.34x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.536 | 1.05x |
| startup.first_load_ms | 206.958 | 188.443 | 0.91x |
| startup.renderer_init_again_ms | 27.582 | 1045.78 | 37.92x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2352.74 | 2.88x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.255 | 0.73x ✅ better |
| startup.since_launch_s | 5.923 | 10.374 | 1.75x ⚠️ worse |
| startup.textures_ms | 26.537 | 631.856 | 23.81x ⚠️ worse |
| startup.world_init_ms | 2.198 | 31.791 | 14.46x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.613 | 0.19x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.971 | 0.33x ✅ better |
| tnt.remesh_s | 0.087 | 0.07 | 0.80x |
| tnt.tick_ms_max | 5.414 | 1.184 | 0.22x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.786 | 0.17x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.184 | 0.22x ✅ better |
