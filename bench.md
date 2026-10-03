| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.698 | 1.16x |
| edit.break_ms_mean | 0.447 | 0.578 | 1.29x |
| edit.break_ms_p50 | 0.595 | 0.564 | 0.95x |
| edit.place_ms_max | 0.732 | 0.771 | 1.05x |
| edit.place_ms_mean | 0.455 | 0.573 | 1.26x |
| edit.place_ms_p50 | 0.595 | 0.562 | 0.94x |
| flight16.arena_free_mb | 0.864 | 3.937 | 4.56x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.141 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.281 | 0.40x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.347 | 0.30x ✅ better |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1210 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.243 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.21 | 0.81x |
| flight16.encode_ms_p95 | 2.361 | 1.942 | 0.82x |
| flight16.frame_ms_max | 12.652 | 7.019 | 0.55x ✅ better |
| flight16.frame_ms_p50 | 4.807 | 3.856 | 0.80x |
| flight16.frame_ms_p95 | 5.8 | 4.6 | 0.79x |
| flight16.frame_ms_p99 | 7.443 | 5.181 | 0.70x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 43.686 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.836 | 0.80x |
| flight16.gpu_ms_p95 | 5.71 | 4.503 | 0.79x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 75.217 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2379.09 | 0.83x |
| flight16.preload_ms | 1871.23 | 1460.35 | 0.78x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 369.846 | 1.29x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 6.081 | 0.71x ✅ better |
| flight16.tick_ms_p50 | 0.388 | 0.832 | 2.14x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.201 | 1.06x |
| flight16.update_ms_max | 8.289 | 1.841 | 0.22x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.254 | 14.94x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.894 | 0.51x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.951 | 0.96x |
| flight16.worker_mesh_us | 177.949 | 134.117 | 0.75x ✅ better |
| flight24.arena_free_mb | 0.427 | 4.147 | 9.71x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.281 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.991 | 1.00x |
| flight24.coverage_min | 0.974 | 0.969 | 1.01x |
| flight24.cull_ms_p50 | 1.198 | 0.724 | 0.60x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.081 | 0.39x ✅ better |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3021 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.209 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.075 | 0.84x |
| flight24.encode_ms_p95 | 5.237 | 3.369 | 0.64x ✅ better |
| flight24.frame_ms_max | 13.319 | 29.727 | 2.23x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.304 | 0.82x |
| flight24.frame_ms_p95 | 9.472 | 7.436 | 0.79x |
| flight24.frame_ms_p99 | 10.337 | 10.031 | 0.97x |
| flight24.gen_chunks_per_s | 63.73 | 63.636 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.255 | 0.81x |
| flight24.gpu_ms_p95 | 9.428 | 7.144 | 0.76x ✅ better |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 128.113 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 3753.03 | 0.65x ✅ better |
| flight24.preload_ms | 4742.83 | 3078.1 | 0.65x ✅ better |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 614.925 | 1.20x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 16.138 | 1.39x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.353 | 3.37x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.397 | 1.15x |
| flight24.update_ms_max | 4.586 | 14.78 | 3.22x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.64 | 42.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.254 | 0.49x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.057 | 0.87x |
| flight24.worker_mesh_us | 177.947 | 156.572 | 0.88x |
| flight8.arena_free_mb | 2.438 | 5.531 | 2.27x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.836 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.994 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.069 | 0.34x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.086 | 0.28x ✅ better |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.137 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.673 | 1.20x |
| flight8.encode_ms_p95 | 0.832 | 0.917 | 1.10x |
| flight8.frame_ms_max | 13.232 | 22.431 | 1.70x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.257 | 0.87x |
| flight8.frame_ms_p95 | 3.197 | 2.834 | 0.89x |
| flight8.frame_ms_p99 | 4.401 | 5.488 | 1.25x |
| flight8.gen_chunks_per_s | 23.603 | 23.742 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.247 | 0.87x |
| flight8.gpu_ms_p95 | 3.081 | 2.792 | 0.91x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 34.85 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 600.306 | 0.84x |
| flight8.preload_ms | 1398.04 | 397.377 | 0.28x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 232.33 | 1.86x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 12.444 | 0.99x |
| flight8.tick_ms_p50 | 0.158 | 0.409 | 2.59x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.518 | 1.24x |
| flight8.update_ms_max | 12.421 | 1.185 | 0.10x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.008 | 0.80x |
| flight8.update_ms_p95 | 0.869 | 0.325 | 0.37x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.869 | 0.58x ✅ better |
| flight8.worker_mesh_us | 181.115 | 133.838 | 0.74x ✅ better |
| fluids.pending | 240 | 1530 | 6.38x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3549 | 1.36x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 12.328 | 3.60x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.251 | 1.11x |
| fluids.tick_ms_p95 | 1.872 | 1.497 | 0.80x |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.604 | 1.05x |
| frame.mesh_mb | 57.324 | 65.787 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 1.052 | 0.94x |
| frame_1080p.encode_ms_p50 | 0.625 | 0.721 | 1.15x |
| frame_1080p.gpu_ms_max | 2.632 | 3.972 | 1.51x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.138 | 1.36x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.03 | 1.27x |
| frame_4k.encode_ms_p50 | 0.691 | 0.825 | 1.19x |
| frame_4k.gpu_ms_max | 4.083 | 6.002 | 1.47x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 5.25 | 1.49x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.048 | 1.39x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.804 | 1.32x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 3.543 | 1.47x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 2.82 | 1.36x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 3.936 | 1.16x |
| gen.chunk_ms_mean | 2.082 | 1.652 | 0.79x |
| gen.chunk_ms_p95 | 3.325 | 2.944 | 0.89x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1894.95 | 0.89x |
| gen.starts_cold_ms | – | 1.054 | new |
| gen.terrain_hash | 1238443285367868 | 1593291283128891 | ⚠️ changed |
| genphase.caves_ms | – | 0.769 | new |
| genphase.columns_ms | – | 0.201 | new |
| genphase.ores_ms | – | 0.222 | new |
| genphase.plants_ms | – | 0.164 | new |
| genphase.starts_ms | – | 0.005 | new |
| genphase.stone_ms | – | 0.116 | new |
| genphase.structures_ms | – | 0.055 | new |
| genphase.surface_ms | – | 0.022 | new |
| genphase.trees_ms | – | 0.035 | new |
| mesh.chunk_ms_max | 5.758 | 2.498 | 0.43x ✅ better |
| mesh.chunk_ms_mean | 3.347 | 2.226 | 0.67x ✅ better |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 636.935 | 0.39x ✅ better |
| mesh.section_us_mean | 139.451 | 92.767 | 0.67x ✅ better |
| mesh.section_us_p95 | 686.049 | 459.075 | 0.67x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 2.275 | 0.42x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 1.927 | 0.63x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 483.99 | 0.33x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 80.311 | 0.63x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 401.02 | 0.71x ✅ better |
| mobs.per_mob_us | 1.608 | 4.125 | 2.57x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 6.647 | 5.32x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.903 | 3.32x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.374 | 5.41x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.284 | 9.16x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.29 | 15.73x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.016 | 1.12x |
| save.chunk_ms | 2.896 | 1.388 | 0.48x ✅ better |
| save.load_chunk_ms | 0.587 | 0.2 | 0.34x ✅ better |
| save.main_thread_ms | 5.206 | 2.777 | 0.53x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.101 | 0.43x ✅ better |
| ships.assemble_ms | 19.313 | 21.141 | 1.09x |
| ships.assemble_remesh_s | 0.027 | 0.015 | 0.56x ✅ better |
| ships.blast_ms | 2.675 | 1.976 | 0.74x ✅ better |
| ships.blast_remesh_ms | 5.466 | 5.518 | 1.01x |
| ships.collide_far_us | 0.214 | 0.239 | 1.12x |
| ships.collide_us | 1.047 | 0.723 | 0.69x ✅ better |
| ships.dock_ms | 12.056 | 9.723 | 0.81x |
| ships.dock_remesh_s | 0.036 | 0.042 | 1.17x |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.634 | 0.71x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.305 | 0.60x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.664 | 1.01x |
| ships.frame_encode_ms | 0.023 | 0.07 | 3.04x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.236 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 9.591 | 3.13x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.141 | 0.85x |
| ships.physics_ms_p95 | 0.213 | 0.237 | 1.11x |
| ships.spawn_frigate_ms | 2.358 | 2.65 | 1.12x |
| ships.tick_ms_max | 0.522 | 3.12 | 5.98x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.468 | 2.14x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.062 | 3.52x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.567 | 0.59x ✅ better |
| startup.first_load_ms | 206.958 | 128.328 | 0.62x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 830.128 | 30.10x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1840.8 | 2.25x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.196 | 0.56x ✅ better |
| startup.since_launch_s | 5.923 | 7.007 | 1.18x |
| startup.textures_ms | 26.537 | 566.275 | 21.34x ⚠️ worse |
| startup.world_init_ms | 2.198 | 2.716 | 1.24x |
| tnt.blast_ms_max | 8.579 | 1.611 | 0.19x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.488 | 0.51x ✅ better |
| tnt.remesh_s | 0.087 | 0.116 | 1.33x ⚠️ worse |
| tnt.tick_ms_max | 5.414 | 7.137 | 1.32x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 2.87 | 0.63x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.137 | 1.32x ⚠️ worse |
