| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.831 | 3.05x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.812 | 1.82x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.706 | 1.19x |
| edit.place_ms_max | 0.732 | 1.883 | 2.57x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.813 | 1.79x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.708 | 1.19x |
| flight16.arena_free_mb | 0.864 | 15.005 | 17.37x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.858 | 1.16x |
| flight16.coverage_min | 0.962 | 0.744 | 1.29x |
| flight16.cull_ms_p50 | 0.708 | 0.337 | 0.48x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.989 | 0.86x |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.834 | 0.56x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 2.154 | 0.91x |
| flight16.frame_ms_max | 12.652 | 46.143 | 3.65x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 3.394 | 0.71x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 6.743 | 1.16x |
| flight16.frame_ms_p99 | 7.443 | 13.458 | 1.81x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.181 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 3.376 | 0.70x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 5.969 | 1.05x |
| flight16.hitches | 0 | 2 | infx ⚠️ worse |
| flight16.mesh_mb | 81.28 | 46.168 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3247.38 | 0.61x ✅ better |
| flight16.preload_ms | 1871.23 | 1908.16 | 1.02x |
| flight16.realtime | 0.998 | 0.998 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 342.034 | 1.20x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 17.873 | 2.09x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.641 | 1.65x ⚠️ worse |
| flight16.tick_ms_p95 | 2.08 | 2.155 | 1.04x |
| flight16.update_ms_max | 8.289 | 17.62 | 2.13x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.278 | 16.35x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.995 | 0.57x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.486 | 1.23x |
| flight16.worker_mesh_us | 177.949 | 276.735 | 1.56x ⚠️ worse |
| flight24.arena_free_mb | 0.427 | 20.134 | 47.15x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 145.299 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1700 | 0.78x |
| flight24.coverage_mean | 0.994 | 0.831 | 1.20x |
| flight24.coverage_min | 0.974 | 0.732 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.665 | 0.56x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.486 | 0.54x ✅ better |
| flight24.cull_walked_sections | 7607 | 3931 | 0.52x ✅ better |
| flight24.draw_calls | 3175 | 1187 | 0.37x ✅ better |
| flight24.drawn_kquads | 821.704 | 220.274 | 0.27x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.324 | 0.54x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 2.861 | 0.55x ✅ better |
| flight24.frame_ms_max | 13.319 | 31.791 | 2.39x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 4.062 | 0.53x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.84 | 0.62x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 8.668 | 0.84x |
| flight24.gen_chunks_per_s | 63.73 | 24.047 | 2.65x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.032 | 0.52x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.546 | 0.59x ✅ better |
| flight24.hitches | 0 | 1 | infx ⚠️ worse |
| flight24.mesh_mb | 131.138 | 67.183 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3393.48 | 0.72x ✅ better |
| flight24.preload_ms | 4742.83 | 3875.79 | 0.82x |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 491.847 | 0.96x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 29.946 | 2.58x ⚠️ worse |
| flight24.tick_ms_p50 | 0.401 | 0.624 | 1.56x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.009 | 0.68x ✅ better |
| flight24.update_ms_max | 4.586 | 2.44 | 0.53x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.293 | 19.53x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 0.853 | 0.34x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.074 | 0.88x |
| flight24.worker_mesh_us | 177.947 | 286.742 | 1.61x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.906 | 4.47x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.992 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.078 | 0.38x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.182 | 0.60x ✅ better |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.387 | 0.69x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.931 | 1.12x |
| flight8.frame_ms_max | 13.232 | 16.647 | 1.26x |
| flight8.frame_ms_p50 | 2.588 | 2.228 | 0.86x |
| flight8.frame_ms_p95 | 3.197 | 2.899 | 0.91x |
| flight8.frame_ms_p99 | 4.401 | 5.638 | 1.28x |
| flight8.gen_chunks_per_s | 23.603 | 23.681 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.217 | 0.86x |
| flight8.gpu_ms_p95 | 3.081 | 2.798 | 0.91x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 956.784 | 0.53x ✅ better |
| flight8.preload_ms | 1398.04 | 526.531 | 0.38x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 201.939 | 1.62x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 16.291 | 1.30x |
| flight8.tick_ms_p50 | 0.158 | 0.355 | 2.25x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.125 | 0.92x |
| flight8.update_ms_max | 12.421 | 3.816 | 0.31x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.006 | 0.60x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.468 | 0.54x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.152 | 0.67x ✅ better |
| flight8.worker_mesh_us | 181.115 | 249.572 | 1.38x ⚠️ worse |
| fluids.pending | 240 | 1166 | 4.86x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6581 | 2.53x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 5.226 | 1.53x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.247 | 1.09x |
| fluids.tick_ms_p95 | 1.872 | 1.412 | 0.75x ✅ better |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 1.878 | 1.67x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.876 | 1.40x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 5.065 | 1.92x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.091 | 1.77x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 0.966 | 0.60x ✅ better |
| frame_4k.encode_ms_p50 | 0.691 | 0.842 | 1.22x |
| frame_4k.gpu_ms_max | 4.083 | 7.035 | 1.72x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 6.751 | 1.92x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 1.822 | 2.41x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.881 | 1.45x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 7.353 | 3.06x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 3.523 | 1.70x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 6.321 | 1.87x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.284 | 1.10x |
| gen.chunk_ms_p95 | 3.325 | 5.172 | 1.56x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 855.919 | 1.97x ⚠️ worse |
| gen.starts_cold_ms | – | 2.937 | new |
| gen.terrain_hash | 1238443285367868 | 849284524592011 | ⚠️ changed |
| genphase.caves_ms | – | 0.929 | new |
| genphase.columns_ms | – | 0.252 | new |
| genphase.ores_ms | – | 0.225 | new |
| genphase.plants_ms | – | 0.307 | new |
| genphase.starts_ms | – | 0.009 | new |
| genphase.stone_ms | – | 0.191 | new |
| genphase.structures_ms | – | 0.194 | new |
| genphase.surface_ms | – | 0.038 | new |
| genphase.trees_ms | – | 0.052 | new |
| mesh.chunk_ms_max | 5.758 | 6.416 | 1.11x |
| mesh.chunk_ms_mean | 4.38 | 4.863 | 1.11x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1453.04 | 0.90x |
| mesh.section_us_mean | 139.451 | 202.611 | 1.45x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 824.094 | 1.20x |
| mesh_lod1.chunk_ms_max | 5.44 | 5.877 | 1.08x |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.81 | 1.17x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1179.1 | 0.80x |
| mesh_lod1.section_us_mean | 126.754 | 200.433 | 1.58x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 841.975 | 1.48x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.872 | 1.16x |
| mobs.tick_150_ms_max | 1.25 | 2.969 | 2.38x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.485 | 1.78x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.369 | 3.12x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.204 | 6.58x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 0.853 | 10.40x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.688 | 0.58x ✅ better |
| save.load_chunk_ms | 0.587 | 0.475 | 0.81x |
| save.main_thread_ms | 5.206 | 3.076 | 0.59x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.715 | 0.67x ✅ better |
| ships.assemble_ms | 19.313 | 17.177 | 0.89x |
| ships.assemble_remesh_s | 0.027 | 0.038 | 1.41x ⚠️ worse |
| ships.blast_ms | 2.675 | 1.914 | 0.72x ✅ better |
| ships.blast_remesh_ms | 5.466 | 5.469 | 1.00x |
| ships.collide_far_us | 0.214 | 0.234 | 1.09x |
| ships.collide_us | 1.047 | 9.353 | 8.93x ⚠️ worse |
| ships.dock_ms | 12.056 | 11.155 | 0.93x |
| ships.dock_remesh_s | 0.036 | 0.092 | 2.56x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 0.541 | 0.61x ✅ better |
| ships.edit_ms_mean | 0.505 | 0.262 | 0.52x ✅ better |
| ships.edit_remesh_ms | 3.642 | 3.673 | 1.01x |
| ships.frame_encode_ms | 0.023 | 0.965 | 41.96x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.41 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 2.23 | 0.73x ✅ better |
| ships.physics_ms_mean | 0.165 | 0.149 | 0.90x |
| ships.physics_ms_p95 | 0.213 | 0.178 | 0.84x |
| ships.spawn_frigate_ms | 2.358 | 2.105 | 0.89x |
| ships.tick_ms_max | 0.522 | 4.957 | 9.50x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.327 | 1.49x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 0.862 | 2.85x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.415 | 1.02x |
| startup.first_load_ms | 206.958 | 224.506 | 1.08x |
| startup.renderer_init_again_ms | 27.582 | 891.469 | 32.32x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 1819.39 | 2.23x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.246 | 0.71x ✅ better |
| startup.since_launch_s | 5.923 | 9.614 | 1.62x ⚠️ worse |
| startup.textures_ms | 26.537 | 589.704 | 22.22x ⚠️ worse |
| startup.world_init_ms | 2.198 | 14.942 | 6.80x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 1.597 | 0.19x ✅ better |
| tnt.blast_ms_mean | 2.904 | 0.926 | 0.32x ✅ better |
| tnt.remesh_s | 0.087 | 0.061 | 0.70x ✅ better |
| tnt.tick_ms_max | 5.414 | 1.094 | 0.20x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.742 | 0.16x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.094 | 0.20x ✅ better |
