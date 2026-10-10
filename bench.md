| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 2.204 | 3.67x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.021 | 2.28x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.727 | 1.22x |
| edit.place_ms_max | 0.732 | 1.889 | 2.58x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.998 | 2.19x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.71 | 1.19x |
| flight16.arena_free_mb | 0.864 | 15.052 | 17.42x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.855 | 0.83x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.895 | 1.11x |
| flight16.coverage_min | 0.962 | 0.786 | 1.22x |
| flight16.cull_ms_p50 | 0.708 | 0.347 | 0.49x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.98 | 0.85x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.86 | 0.58x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.327 | 0.99x |
| flight16.frame_ms_max | 12.652 | 15.143 | 1.20x |
| flight16.frame_ms_p50 | 4.807 | 3.602 | 0.75x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 5.048 | 0.87x |
| flight16.frame_ms_p99 | 7.443 | 8.085 | 1.09x |
| flight16.gen_chunks_per_s | 43.68 | 43.549 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 3.561 | 0.74x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 4.856 | 0.85x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.228 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3502.99 | 0.56x ✅ better |
| flight16.preload_ms | 1871.23 | 1902.98 | 1.02x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 320.893 | 1.12x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 9.192 | 1.07x |
| flight16.tick_ms_p50 | 0.388 | 0.627 | 1.62x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.023 | 0.97x |
| flight16.update_ms_max | 8.289 | 2.241 | 0.27x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.298 | 17.53x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.979 | 0.56x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.28 | 1.13x |
| flight16.worker_mesh_us | 177.949 | 261.421 | 1.47x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 20.429 | 47.84x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 144.502 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1691 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.834 | 1.19x |
| flight24.coverage_min | 0.974 | 0.738 | 1.32x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.818 | 0.68x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 2.264 | 0.82x |
| flight24.cull_walked_sections | 7607 | 3786 | 0.50x ✅ better |
| flight24.draw_calls | 3175 | 1158 | 0.36x ✅ better |
| flight24.drawn_kquads | 821.704 | 215.935 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.673 | 0.68x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 4.551 | 0.87x |
| flight24.frame_ms_max | 13.319 | 40.4 | 3.03x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.591 | 0.59x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 7.825 | 0.83x |
| flight24.frame_ms_p99 | 10.337 | 13.399 | 1.30x |
| flight24.gen_chunks_per_s | 63.73 | 23.332 | 2.73x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.504 | 0.58x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 6.58 | 0.70x ✅ better |
| flight24.hitches | 0 | 3 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 66.909 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3500.58 | 0.70x ✅ better |
| flight24.preload_ms | 4742.83 | 4283.54 | 0.90x |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 491.831 | 0.96x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 17.494 | 1.51x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.83 | 2.07x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 3.041 | 1.03x |
| flight24.update_ms_max | 4.586 | 8.203 | 1.79x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.4 | 26.67x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.294 | 0.51x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.465 | 1.05x |
| flight24.worker_mesh_us | 177.947 | 339.287 | 1.91x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.761 | 4.41x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.083 | 0.41x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.252 | 0.83x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.419 | 0.75x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 1.113 | 1.34x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 10.756 | 0.81x |
| flight8.frame_ms_p50 | 2.588 | 2.549 | 0.98x |
| flight8.frame_ms_p95 | 3.197 | 4.377 | 1.37x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 7.791 | 1.77x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.741 | 0.99x |
| flight8.gpu_ms_p50 | 2.579 | 2.532 | 0.98x |
| flight8.gpu_ms_p95 | 3.081 | 4.149 | 1.35x ⚠️ worse |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 957.642 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 660.532 | 0.47x ✅ better |
| flight8.realtime | 0.994 | 1 | 0.99x |
| flight8.resident_peak_mb | 124.705 | 198.049 | 1.59x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 8.544 | 0.68x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.39 | 2.47x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.258 | 1.03x |
| flight8.update_ms_max | 12.421 | 2.236 | 0.18x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.005 | 0.50x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.59 | 0.68x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.296 | 0.71x ✅ better |
| flight8.worker_mesh_us | 181.115 | 274.24 | 1.51x ⚠️ worse |
| fluids.pending | 240 | 1284 | 5.35x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6753 | 2.59x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 11.457 | 3.35x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.436 | 1.93x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.841 | 0.98x |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 2.313 | 2.06x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 1.125 | 1.80x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 6.421 | 2.44x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 5.212 | 2.26x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 4.305 | 2.69x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.588 | 2.30x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 11.482 | 2.81x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 8.033 | 2.28x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.134 | 2.83x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.9 | 1.48x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 4.743 | 1.97x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.475 | 2.16x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 5.123 | 1.51x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.052 | 0.99x |
| gen.chunk_ms_p95 | 3.325 | 4.84 | 1.46x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 936.431 | 1.80x ⚠️ worse |
| gen.starts_cold_ms | – | 2.661 | new |
| gen.terrain_hash | 1238443285367868 | 2072315357721602 | ⚠️ changed |
| genphase.caves_ms | – | 0.827 | new |
| genphase.columns_ms | – | 0.264 | new |
| genphase.ores_ms | – | 0.217 | new |
| genphase.plants_ms | – | 0.218 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.189 | new |
| genphase.structures_ms | – | 0.18 | new |
| genphase.surface_ms | – | 0.026 | new |
| genphase.trees_ms | – | 0.043 | new |
| mesh.chunk_ms_max | 5.758 | 6.631 | 1.15x |
| mesh.chunk_ms_mean | 4.38 | 4.974 | 1.14x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1194.95 | 0.74x ✅ better |
| mesh.section_us_mean | 139.451 | 207.254 | 1.49x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 870.943 | 1.27x |
| mesh_lod1.chunk_ms_max | 5.44 | 5.442 | 1.00x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.494 | 1.10x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1503.94 | 1.02x |
| mesh_lod1.section_us_mean | 126.754 | 187.266 | 1.48x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 768.065 | 1.35x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 2.867 | 1.78x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 3.11 | 2.49x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.7 | 2.57x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.805 | 4.11x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.27 | 8.71x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.091 | 13.30x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 2.659 | 0.92x |
| save.load_chunk_ms | 0.587 | 0.304 | 0.52x ✅ better |
| save.main_thread_ms | 5.206 | 32.222 | 6.19x ⚠️ worse |
| save.unchanged_resave_ms | 2.544 | 1.89 | 0.74x ✅ better |
| ships.assemble_ms | 19.313 | 12.724 | 0.66x ✅ better |
| ships.assemble_remesh_s | 0.027 | 0.017 | 0.63x ✅ better |
| ships.blast_ms | 2.675 | 2.272 | 0.85x |
| ships.blast_remesh_ms | 5.466 | 10.23 | 1.87x ⚠️ worse |
| ships.collide_far_us | 0.214 | 0.72 | 3.36x ⚠️ worse |
| ships.collide_us | 1.047 | 1.375 | 1.31x ⚠️ worse |
| ships.dock_ms | 12.056 | 18.784 | 1.56x ⚠️ worse |
| ships.dock_remesh_s | 0.036 | 0.062 | 1.72x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.539 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.291 | 0.58x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.085 | 0.85x |
| ships.frame_encode_ms | 0.023 | -0.787 | -34.22x ✅ better |
| ships.frame_gpu_ms | -0.228 | -0.011 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 5.937 | 1.94x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.213 | 1.29x |
| ships.physics_ms_p95 | 0.213 | 0.501 | 2.35x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 11.153 | 4.73x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 14.402 | 27.59x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.511 | 2.33x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.242 | 4.11x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 2.813 | 0.65x ✅ better |
| startup.first_load_ms | 206.958 | 230.422 | 1.11x |
| startup.renderer_init_again_ms | 27.582 | 1038.04 | 37.63x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2404.37 | 2.94x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.407 | 1.17x |
| startup.since_launch_s | 5.923 | 8.74 | 1.48x ⚠️ worse |
| startup.textures_ms | 26.537 | 605.25 | 22.81x ⚠️ worse |
| startup.world_init_ms | 2.198 | 21.721 | 9.88x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.762 | 0.44x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.509 | 0.52x ✅ better |
| tnt.remesh_s | 0.087 | 0.06 | 0.69x ✅ better |
| tnt.tick_ms_max | 5.414 | 7.99 | 1.48x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 2.605 | 0.58x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 7.99 | 1.48x ⚠️ worse |
