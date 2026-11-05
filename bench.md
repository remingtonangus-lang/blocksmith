| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 4.199 | 7.00x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.393 | 3.12x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.924 | 1.55x ⚠️ worse |
| edit.place_ms_max | 0.732 | 2.576 | 3.52x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.278 | 2.81x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.934 | 1.57x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 11.688 | 13.53x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 62.43 | 0.60x ✅ better |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.99 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.548 | 0.77x |
| flight16.cull_ms_p95 | 1.152 | 1.36 | 1.18x |
| flight16.cull_walked_sections | 2817 | 1836 | 0.65x ✅ better |
| flight16.draw_calls | 1434 | 989 | 0.69x ✅ better |
| flight16.drawn_kquads | 475.516 | 119.771 | 0.25x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.318 | 0.88x |
| flight16.encode_ms_p95 | 2.361 | 3.372 | 1.43x ⚠️ worse |
| flight16.frame_ms_max | 12.652 | 23.484 | 1.86x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.935 | 0.82x |
| flight16.frame_ms_p95 | 5.8 | 6.797 | 1.17x |
| flight16.frame_ms_p99 | 7.443 | 12.022 | 1.62x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 81.521 | 0.54x ✅ better |
| flight16.gpu_ms_p50 | 4.804 | 3.843 | 0.80x |
| flight16.gpu_ms_p95 | 5.71 | 5.715 | 1.00x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 34.844 | 0.43x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 2094.98 | 0.94x |
| flight16.preload_ms | 1871.23 | 3348.46 | 1.79x ⚠️ worse |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 335.362 | 1.17x |
| flight16.slab_mb | 96 | 52 | 0.54x ✅ better |
| flight16.tick_ms_max | 8.551 | 21.902 | 2.56x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.526 | 1.36x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.374 | 1.14x |
| flight16.update_ms_max | 8.289 | 7.415 | 0.89x |
| flight16.update_ms_p50 | 0.017 | 0.176 | 10.35x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.726 | 0.99x |
| flight16.worker_gen_ms | 2.022 | 3.066 | 1.52x ⚠️ worse |
| flight16.worker_mesh_us | 177.949 | 233.835 | 1.31x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 4.677 | 10.95x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 73.531 | 0.33x ✅ better |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.991 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 1.66 | 1.39x ⚠️ worse |
| flight24.cull_ms_p95 | 2.767 | 3.537 | 1.28x |
| flight24.cull_walked_sections | 7607 | 5485 | 0.72x ✅ better |
| flight24.draw_calls | 3175 | 2559 | 0.81x |
| flight24.drawn_kquads | 821.704 | 264.131 | 0.32x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 3.222 | 1.30x ⚠️ worse |
| flight24.encode_ms_p95 | 5.237 | 6.811 | 1.30x ⚠️ worse |
| flight24.frame_ms_max | 13.319 | 54.918 | 4.12x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.194 | 0.80x |
| flight24.frame_ms_p95 | 9.472 | 11.893 | 1.26x |
| flight24.frame_ms_p99 | 10.337 | 17.977 | 1.74x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 108.646 | 0.59x ✅ better |
| flight24.gpu_ms_p50 | 7.718 | 5.953 | 0.77x |
| flight24.gpu_ms_p95 | 9.428 | 10.217 | 1.08x |
| flight24.hitches | 0 | 2 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 62.115 | 0.47x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 2577.68 | 0.95x |
| flight24.preload_ms | 4742.83 | 5975.04 | 1.26x |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 450.394 | 0.88x |
| flight24.slab_mb | 148 | 76 | 0.51x ✅ better |
| flight24.tick_ms_max | 11.61 | 52.462 | 4.52x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.73 | 1.82x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.854 | 0.97x |
| flight24.update_ms_max | 4.586 | 37.883 | 8.26x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.378 | 25.20x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 2.355 | 0.93x |
| flight24.worker_gen_ms | 2.355 | 3.236 | 1.37x ⚠️ worse |
| flight24.worker_mesh_us | 177.947 | 243.783 | 1.37x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 7.344 | 3.01x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.992 | 0.86x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.994 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.113 | 0.55x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.281 | 0.92x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 335 | 0.72x ✅ better |
| flight8.drawn_kquads | 211.463 | 78.865 | 0.37x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.645 | 1.15x |
| flight8.encode_ms_p95 | 0.832 | 1.627 | 1.96x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 53.9 | 4.07x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.648 | 1.02x |
| flight8.frame_ms_p95 | 3.197 | 6.1 | 1.91x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 14.121 | 3.21x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.726 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.627 | 1.02x |
| flight8.gpu_ms_p95 | 3.081 | 5.801 | 1.88x ⚠️ worse |
| flight8.hitches | 0 | 1 | infx ⚠️ worse |
| flight8.mesh_mb | 40.975 | 20.229 | 0.49x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 619.363 | 0.82x |
| flight8.preload_ms | 1398.04 | 1359.08 | 0.97x |
| flight8.realtime | 0.994 | 0.999 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 225.236 | 1.81x ⚠️ worse |
| flight8.slab_mb | 52 | 32 | 0.62x ✅ better |
| flight8.tick_ms_max | 12.539 | 22.123 | 1.76x ⚠️ worse |
| flight8.tick_ms_p50 | 0.158 | 0.393 | 2.49x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.351 | 1.10x |
| flight8.update_ms_max | 12.421 | 3.088 | 0.25x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.022 | 2.20x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.791 | 0.91x |
| flight8.worker_gen_ms | 3.236 | 3.199 | 0.99x |
| flight8.worker_mesh_us | 181.115 | 332.891 | 1.84x ⚠️ worse |
| fluids.pending | 240 | 14 | 0.06x ✅ better |
| fluids.remeshed_sections | 2605 | 1785 | 0.69x ✅ better |
| fluids.tick_ms_max | 3.42 | 2.435 | 0.71x ✅ better |
| fluids.tick_ms_p50 | 0.226 | 0.285 | 1.26x |
| fluids.tick_ms_p95 | 1.872 | 0.806 | 0.43x ✅ better |
| frame.draw_calls | 1076 | 1316 | 1.22x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 207.513 | 1.16x |
| frame.mesh_mb | 57.324 | 43.345 | 0.76x ✅ better |
| frame.visible_sections | 686 | 719 | 1.05x |
| frame_1080p.encode_ms_max | 1.123 | 3.956 | 3.52x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.492 | 2.39x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.67 | 2.15x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.983 | 2.16x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 3.183 | 1.99x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.554 | 2.25x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 23.542 | 5.77x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.812 | 2.22x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 3.984 | 5.28x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 1.187 | 1.95x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 5.1 | 2.12x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.329 | 2.09x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 1135.78 | 335.83x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 63.051 | 30.28x ❌ regression |
| gen.chunk_ms_p95 | 3.325 | 259.375 | 78.01x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 136.452 | 12.34x ⚠️ worse |
| gen.starts_cold_ms | – | 0.886 | new |
| gen.terrain_hash | 1238443285367868 | 163195936105986 | ⚠️ changed |
| genphase.caves_ms | – | 0.947 | new |
| genphase.columns_ms | – | 0.244 | new |
| genphase.ores_ms | – | 0.358 | new |
| genphase.plants_ms | – | 0.233 | new |
| genphase.starts_ms | – | 0.549 | new |
| genphase.stone_ms | – | 0.247 | new |
| genphase.structures_ms | – | 57.134 | new |
| genphase.surface_ms | – | 0.027 | new |
| genphase.trees_ms | – | 3.225 | new |
| mesh.chunk_ms_max | 5.758 | 10.038 | 1.74x ⚠️ worse |
| mesh.chunk_ms_mean | 4.38 | 7.368 | 1.68x ⚠️ worse |
| mesh.quads_per_chunk | 4996 | 4430.11 | 0.89x |
| mesh.section_us_max | 1621.01 | 4107 | 2.53x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 307.012 | 2.20x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1181.96 | 1.72x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 9.81 | 1.80x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 7.658 | 1.87x ❌ regression |
| mesh_lod1.quads_per_chunk | 2535 | 2359.33 | 0.93x |
| mesh_lod1.section_us_max | 1477.96 | 2210.97 | 1.50x ⚠️ worse |
| mesh_lod1.section_us_mean | 126.754 | 319.095 | 2.52x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 1368.05 | 2.41x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 5.039 | 3.13x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 4.018 | 3.21x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.946 | 3.48x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.328 | 5.30x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.191 | 6.16x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.732 | 8.93x ⚠️ worse |
| save.chunk_kb | 4.471 | 7.015 | 1.57x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.527 | 0.87x |
| save.load_chunk_ms | 0.587 | 0.371 | 0.63x ✅ better |
| save.main_thread_ms | 5.206 | 28.252 | 5.43x ⚠️ worse |
| save.unchanged_resave_ms | 2.544 | 2.189 | 0.86x |
| ships.assemble_ms | 19.313 | 68.563 | 3.55x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.026 | 0.96x |
| ships.blast_ms | 2.675 | 1.894 | 0.71x ✅ better |
| ships.blast_remesh_ms | 5.466 | 6.315 | 1.16x |
| ships.collide_far_us | 0.214 | 0.264 | 1.23x |
| ships.collide_us | 1.047 | 1.076 | 1.03x |
| ships.dock_ms | 12.056 | 28.195 | 2.34x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.202 | 5.61x ⚠️ worse |
| ships.draw_calls | 66 | 68 | 1.03x |
| ships.edit_ms_max | 0.887 | 1.011 | 1.14x |
| ships.edit_ms_mean | 0.505 | 0.491 | 0.97x |
| ships.edit_remesh_ms | 3.642 | 4.28 | 1.18x |
| ships.frame_encode_ms | 0.023 | -0.132 | -5.74x ✅ better |
| ships.frame_gpu_ms | -0.228 | 0.139 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 8.157 | 2.66x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.261 | 1.58x ⚠️ worse |
| ships.physics_ms_p95 | 0.213 | 0.648 | 3.04x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 1.627 | 0.69x ✅ better |
| ships.tick_ms_max | 0.522 | 3.383 | 6.48x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.431 | 1.97x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.15 | 3.81x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.684 | 0.85x |
| startup.first_load_ms | 206.958 | 794.016 | 3.84x ⚠️ worse |
| startup.renderer_init_again_ms | 27.582 | 1971.67 | 71.48x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 3105.89 | 3.80x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.832 | 2.40x ⚠️ worse |
| startup.since_launch_s | 5.923 | 16.511 | 2.79x ⚠️ worse |
| startup.textures_ms | 26.537 | 1152.42 | 43.43x ⚠️ worse |
| startup.world_init_ms | 2.198 | 27.135 | 12.35x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 4.038 | 0.47x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.09 | 0.38x ✅ better |
| tnt.remesh_s | 0.087 | 0.109 | 1.25x |
| tnt.tick_ms_max | 5.414 | 3.462 | 0.64x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.889 | 0.20x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 3.462 | 0.64x ✅ better |

**Regressions past the CI gate:**

- gen.chunk_ms_mean: 2.082 -> 63.051 (30.28x worse, 27.30x for runner speed, gate 1.6x)
- mesh_lod1.chunk_ms_mean: 4.1 -> 7.658 (1.87x worse, 1.68x for runner speed, gate 1.6x)
