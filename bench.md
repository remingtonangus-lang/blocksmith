| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 0.711 | 1.19x |
| edit.break_ms_mean | 0.447 | 0.593 | 1.33x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.586 | 0.98x |
| edit.place_ms_max | 0.732 | 0.686 | 0.94x |
| edit.place_ms_mean | 0.455 | 0.592 | 1.30x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.587 | 0.99x |
| flight16.arena_free_mb | 0.864 | 3.956 | 4.58x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 113.141 | 1.09x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.37 | 0.52x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.984 | 0.85x |
| flight16.cull_walked_sections | 2817 | 2435 | 0.86x |
| flight16.draw_calls | 1434 | 1210 | 0.84x |
| flight16.drawn_kquads | 475.516 | 300.238 | 0.63x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 1.271 | 0.85x |
| flight16.encode_ms_p95 | 2.361 | 3.574 | 1.51x ⚠️ worse |
| flight16.frame_ms_max | 12.652 | 20.716 | 1.64x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.247 | 0.88x |
| flight16.frame_ms_p95 | 5.8 | 6.83 | 1.18x |
| flight16.frame_ms_p99 | 7.443 | 10.381 | 1.39x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.706 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.152 | 0.86x |
| flight16.gpu_ms_p95 | 5.71 | 5.302 | 0.93x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 75.214 | 0.93x |
| flight16.mesh_sections_per_s | 1972.83 | 2368.97 | 0.83x |
| flight16.preload_ms | 1871.23 | 1854.76 | 0.99x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 342.534 | 1.20x |
| flight16.slab_mb | 96 | 92 | 0.96x |
| flight16.tick_ms_max | 8.551 | 17.308 | 2.02x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 1.181 | 3.04x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 3.069 | 1.48x ⚠️ worse |
| flight16.update_ms_max | 8.289 | 5.529 | 0.67x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.218 | 12.82x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 1.243 | 0.71x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.399 | 1.19x |
| flight16.worker_mesh_us | 177.949 | 178.433 | 1.00x |
| flight24.arena_free_mb | 0.427 | 4.214 | 9.87x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 239.281 | 1.08x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.99 | 1.00x |
| flight24.coverage_min | 0.974 | 0.964 | 1.01x |
| flight24.cull_ms_p50 | 1.198 | 0.971 | 0.81x |
| flight24.cull_ms_p95 | 2.767 | 2.917 | 1.05x |
| flight24.cull_walked_sections | 7607 | 8001 | 1.05x |
| flight24.draw_calls | 3175 | 3021 | 0.95x |
| flight24.drawn_kquads | 821.704 | 591.253 | 0.72x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 2.353 | 0.95x |
| flight24.encode_ms_p95 | 5.237 | 6.008 | 1.15x |
| flight24.frame_ms_max | 13.319 | 27.351 | 2.05x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 6.952 | 0.90x |
| flight24.frame_ms_p95 | 9.472 | 10.75 | 1.13x |
| flight24.frame_ms_p99 | 10.337 | 17.097 | 1.65x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.743 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 6.778 | 0.88x |
| flight24.gpu_ms_p95 | 9.428 | 9.271 | 0.98x |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 128.114 | 0.98x |
| flight24.mesh_sections_per_s | 2455.22 | 3717.6 | 0.66x ✅ better |
| flight24.preload_ms | 4742.83 | 4467.17 | 0.94x |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 575.722 | 1.12x |
| flight24.slab_mb | 148 | 152 | 1.03x |
| flight24.tick_ms_max | 11.61 | 18.152 | 1.56x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 1.899 | 4.74x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 5.203 | 1.77x ⚠️ worse |
| flight24.update_ms_max | 4.586 | 7.286 | 1.59x ⚠️ worse |
| flight24.update_ms_p50 | 0.015 | 0.896 | 59.73x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 2.203 | 0.87x |
| flight24.worker_gen_ms | 2.355 | 2.627 | 1.12x |
| flight24.worker_mesh_us | 177.947 | 199.397 | 1.12x |
| flight8.arena_free_mb | 2.438 | 5.218 | 2.14x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 33.828 | 1.12x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.995 | 0.99x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.089 | 0.44x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.249 | 0.82x |
| flight8.cull_walked_sections | 517 | 378 | 0.73x ✅ better |
| flight8.draw_calls | 463 | 256 | 0.55x ✅ better |
| flight8.drawn_kquads | 211.463 | 97.139 | 0.46x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.635 | 1.13x |
| flight8.encode_ms_p95 | 0.832 | 1.97 | 2.37x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 33.529 | 2.53x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.705 | 1.05x |
| flight8.frame_ms_p95 | 3.197 | 5.793 | 1.81x ⚠️ worse |
| flight8.frame_ms_p99 | 4.401 | 11.86 | 2.69x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.679 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.651 | 1.03x |
| flight8.gpu_ms_p95 | 3.081 | 4.784 | 1.55x ⚠️ worse |
| flight8.hitches | 0 | 3 | infx ⚠️ worse |
| flight8.mesh_mb | 40.975 | 34.838 | 0.85x |
| flight8.mesh_sections_per_s | 506.848 | 597.466 | 0.85x |
| flight8.preload_ms | 1398.04 | 443.73 | 0.32x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 200.095 | 1.60x ⚠️ worse |
| flight8.slab_mb | 52 | 48 | 0.92x |
| flight8.tick_ms_max | 12.539 | 11.661 | 0.93x |
| flight8.tick_ms_p50 | 0.158 | 0.593 | 3.75x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.907 | 1.56x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 8.411 | 0.68x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.01 | 1.00x |
| flight8.update_ms_p95 | 0.869 | 0.659 | 0.76x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.939 | 0.91x |
| flight8.worker_mesh_us | 181.115 | 224.763 | 1.24x |
| fluids.pending | 240 | 1629 | 6.79x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 3532 | 1.36x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 4.78 | 1.40x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.401 | 1.77x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 1.652 | 0.88x |
| frame.draw_calls | 1076 | 951 | 0.88x |
| frame.drawn_chunks | 272 | 277 | 1.02x |
| frame.drawn_kquads | 178.99 | 188.48 | 1.05x |
| frame.mesh_mb | 57.324 | 65.782 | 1.15x |
| frame.visible_sections | 686 | 575 | 0.84x |
| frame_1080p.encode_ms_max | 1.123 | 2.084 | 1.86x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.819 | 1.31x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 4.164 | 1.58x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 3.253 | 1.41x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 1.039 | 0.65x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.795 | 1.15x |
| frame_4k.gpu_ms_max | 4.083 | 5.602 | 1.37x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 4.578 | 1.30x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 0.943 | 1.25x |
| frame_800p.encode_ms_p50 | 0.608 | 0.785 | 1.29x |
| frame_800p.gpu_ms_max | 2.405 | 3.509 | 1.46x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 2.679 | 1.30x |
| gen.chunk_ms_max | 3.382 | 4.492 | 1.33x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.815 | 0.87x |
| gen.chunk_ms_p95 | 3.325 | 2.566 | 0.77x |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 1928.56 | 0.87x |
| gen.starts_cold_ms | – | 0.531 | new |
| gen.terrain_hash | 1238443285367868 | 1841051858670656 | ⚠️ changed |
| genphase.caves_ms | – | 0.814 | new |
| genphase.columns_ms | – | 0.247 | new |
| genphase.ores_ms | – | 0.242 | new |
| genphase.plants_ms | – | 0.153 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.144 | new |
| genphase.structures_ms | – | 0.048 | new |
| genphase.surface_ms | – | 0.027 | new |
| genphase.trees_ms | – | 0.051 | new |
| mesh.chunk_ms_max | 5.758 | 2.459 | 0.43x ✅ better |
| mesh.chunk_ms_mean | 3.347 | 2.211 | 0.66x ✅ better |
| mesh.quads_per_chunk | 3763.89 | 4652.22 | 1.24x |
| mesh.section_us_max | 1621.01 | 638.008 | 0.39x ✅ better |
| mesh.section_us_mean | 139.451 | 92.109 | 0.66x ✅ better |
| mesh.section_us_p95 | 686.049 | 463.963 | 0.68x ✅ better |
| mesh_lod1.chunk_ms_max | 5.44 | 2.246 | 0.41x ✅ better |
| mesh_lod1.chunk_ms_mean | 3.042 | 1.919 | 0.63x ✅ better |
| mesh_lod1.quads_per_chunk | 783.333 | 1251.67 | 1.60x ⚠️ worse |
| mesh_lod1.section_us_max | 1477.96 | 479.937 | 0.32x ✅ better |
| mesh_lod1.section_us_mean | 126.754 | 79.95 | 0.63x ✅ better |
| mesh_lod1.section_us_p95 | 568.032 | 388.026 | 0.68x ✅ better |
| mobs.per_mob_us | 1.608 | 4.607 | 2.87x ⚠️ worse |
| mobs.tick_150_ms_max | 1.25 | 5.77 | 4.62x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.941 | 3.46x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 2.556 | 5.82x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.25 | 8.06x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.242 | 15.15x ⚠️ worse |
| save.chunk_kb | 4.471 | 5.015 | 1.12x |
| save.chunk_ms | 2.896 | 1.091 | 0.38x ✅ better |
| save.load_chunk_ms | 0.587 | 0.195 | 0.33x ✅ better |
| save.main_thread_ms | 5.206 | 2.626 | 0.50x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.021 | 0.40x ✅ better |
| ships.assemble_ms | 19.313 | 15.738 | 0.81x |
| ships.assemble_remesh_s | 0.027 | 0.013 | 0.48x ✅ better |
| ships.blast_ms | 2.675 | 2.445 | 0.91x |
| ships.blast_remesh_ms | 5.466 | 4.158 | 0.76x ✅ better |
| ships.collide_far_us | 0.214 | 0.56 | 2.62x ⚠️ worse |
| ships.collide_us | 1.047 | 2.426 | 2.32x ⚠️ worse |
| ships.dock_ms | 12.056 | 15.246 | 1.26x |
| ships.dock_remesh_s | 0.036 | 0.017 | 0.47x ✅ better |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.54 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.257 | 0.51x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.077 | 0.84x |
| ships.frame_encode_ms | 0.023 | 0.137 | 5.96x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.494 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.164 | 0.71x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.156 | 0.95x |
| ships.physics_ms_p95 | 0.213 | 0.262 | 1.23x |
| ships.spawn_frigate_ms | 2.358 | 1.078 | 0.46x ✅ better |
| ships.tick_ms_max | 0.522 | 3.638 | 6.97x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.468 | 2.14x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 1.174 | 3.89x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 3.213 | 0.74x ✅ better |
| startup.first_load_ms | 206.958 | 159.074 | 0.77x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 956.17 | 34.67x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1974.38 | 2.42x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.295 | 0.85x |
| startup.since_launch_s | 5.923 | 8.165 | 1.38x ⚠️ worse |
| startup.textures_ms | 26.537 | 823.698 | 31.04x ⚠️ worse |
| startup.world_init_ms | 2.198 | 4.581 | 2.08x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.867 | 0.22x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.711 | 0.59x ✅ better |
| tnt.remesh_s | 0.087 | 0.079 | 0.91x |
| tnt.tick_ms_max | 5.414 | 13.732 | 2.54x ⚠️ worse |
| tnt.tick_ms_p50 | 4.529 | 7.633 | 1.69x ⚠️ worse |
| tnt.tick_ms_p95 | 5.414 | 13.732 | 2.54x ⚠️ worse |
