| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.876 | 3.13x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 1.05 | 2.35x ⚠️ worse |
| edit.break_ms_p50 | 0.595 | 0.825 | 1.39x ⚠️ worse |
| edit.place_ms_max | 0.732 | 1.844 | 2.52x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 1.035 | 2.27x ⚠️ worse |
| edit.place_ms_p50 | 0.595 | 0.786 | 1.32x ⚠️ worse |
| flight16.arena_free_mb | 0.864 | 14.755 | 17.08x ⚠️ worse |
| flight16.chunk_mb | 103.906 | 85.521 | 0.82x |
| flight16.chunks | 1056 | 1052 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.852 | 1.16x |
| flight16.coverage_min | 0.962 | 0.731 | 1.32x ⚠️ worse |
| flight16.cull_ms_p50 | 0.708 | 0.287 | 0.41x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.468 | 0.41x ✅ better |
| flight16.cull_walked_sections | 2817 | 1568 | 0.56x ✅ better |
| flight16.draw_calls | 1434 | 968 | 0.68x ✅ better |
| flight16.drawn_kquads | 475.516 | 188.368 | 0.40x ✅ better |
| flight16.encode_ms_p50 | 1.494 | 0.7 | 0.47x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.223 | 0.52x ✅ better |
| flight16.frame_ms_max | 12.652 | 8.421 | 0.67x ✅ better |
| flight16.frame_ms_p50 | 4.807 | 2.929 | 0.61x ✅ better |
| flight16.frame_ms_p95 | 5.8 | 3.62 | 0.62x ✅ better |
| flight16.frame_ms_p99 | 7.443 | 4.218 | 0.57x ✅ better |
| flight16.gen_chunks_per_s | 43.68 | 43.222 | 1.01x |
| flight16.gpu_ms_p50 | 4.804 | 2.927 | 0.61x ✅ better |
| flight16.gpu_ms_p95 | 5.71 | 3.59 | 0.63x ✅ better |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 46.421 | 0.57x ✅ better |
| flight16.mesh_sections_per_s | 1972.83 | 3188.89 | 0.62x ✅ better |
| flight16.preload_ms | 1871.23 | 1995.06 | 1.07x |
| flight16.realtime | 0.998 | 0.999 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 349.971 | 1.22x |
| flight16.slab_mb | 96 | 68 | 0.71x ✅ better |
| flight16.tick_ms_max | 8.551 | 7.551 | 0.88x |
| flight16.tick_ms_p50 | 0.388 | 0.452 | 1.16x |
| flight16.tick_ms_p95 | 2.08 | 1.393 | 0.67x ✅ better |
| flight16.update_ms_max | 8.289 | 1.353 | 0.16x ✅ better |
| flight16.update_ms_p50 | 0.017 | 0.165 | 9.71x ⚠️ worse |
| flight16.update_ms_p95 | 1.74 | 0.58 | 0.33x ✅ better |
| flight16.worker_gen_ms | 2.022 | 1.892 | 0.94x |
| flight16.worker_mesh_us | 177.949 | 218.81 | 1.23x |
| flight24.arena_free_mb | 0.427 | 20.323 | 47.59x ⚠️ worse |
| flight24.chunk_mb | 222.438 | 143.955 | 0.65x ✅ better |
| flight24.chunks | 2176 | 1684 | 0.77x |
| flight24.coverage_mean | 0.994 | 0.831 | 1.20x |
| flight24.coverage_min | 0.974 | 0.73 | 1.33x ⚠️ worse |
| flight24.cull_ms_p50 | 1.198 | 0.624 | 0.52x ✅ better |
| flight24.cull_ms_p95 | 2.767 | 1.548 | 0.56x ✅ better |
| flight24.cull_walked_sections | 7607 | 3786 | 0.50x ✅ better |
| flight24.draw_calls | 3175 | 1158 | 0.36x ✅ better |
| flight24.drawn_kquads | 821.704 | 215.935 | 0.26x ✅ better |
| flight24.encode_ms_p50 | 2.473 | 1.235 | 0.50x ✅ better |
| flight24.encode_ms_p95 | 5.237 | 3.032 | 0.58x ✅ better |
| flight24.frame_ms_max | 13.319 | 10.821 | 0.81x |
| flight24.frame_ms_p50 | 7.72 | 4.274 | 0.55x ✅ better |
| flight24.frame_ms_p95 | 9.472 | 5.752 | 0.61x ✅ better |
| flight24.frame_ms_p99 | 10.337 | 6.842 | 0.66x ✅ better |
| flight24.gen_chunks_per_s | 63.73 | 23.411 | 2.72x ⚠️ worse |
| flight24.gpu_ms_p50 | 7.718 | 4.231 | 0.55x ✅ better |
| flight24.gpu_ms_p95 | 9.428 | 5.259 | 0.56x ✅ better |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 66.797 | 0.51x ✅ better |
| flight24.mesh_sections_per_s | 2455.22 | 3315.07 | 0.74x ✅ better |
| flight24.preload_ms | 4742.83 | 3366.07 | 0.71x ✅ better |
| flight24.realtime | 1 | 1 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 536.003 | 1.05x |
| flight24.slab_mb | 148 | 96 | 0.65x ✅ better |
| flight24.tick_ms_max | 11.61 | 8.932 | 0.77x ✅ better |
| flight24.tick_ms_p50 | 0.401 | 0.625 | 1.56x ⚠️ worse |
| flight24.tick_ms_p95 | 2.942 | 2.226 | 0.76x ✅ better |
| flight24.update_ms_max | 4.586 | 3.242 | 0.71x ✅ better |
| flight24.update_ms_p50 | 0.015 | 0.281 | 18.73x ⚠️ worse |
| flight24.update_ms_p95 | 2.535 | 1.008 | 0.40x ✅ better |
| flight24.worker_gen_ms | 2.355 | 2.108 | 0.90x |
| flight24.worker_mesh_us | 177.947 | 280.621 | 1.58x ⚠️ worse |
| flight8.arena_free_mb | 2.438 | 10.958 | 4.49x ⚠️ worse |
| flight8.chunk_mb | 30.25 | 25.32 | 0.84x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.991 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.167 | 0.82x |
| flight8.cull_ms_p95 | 0.305 | 0.332 | 1.09x |
| flight8.cull_walked_sections | 517 | 359 | 0.69x ✅ better |
| flight8.draw_calls | 463 | 336 | 0.73x ✅ better |
| flight8.drawn_kquads | 211.463 | 82.249 | 0.39x ✅ better |
| flight8.encode_ms_p50 | 0.562 | 0.828 | 1.47x ⚠️ worse |
| flight8.encode_ms_p95 | 0.832 | 1.663 | 2.00x ⚠️ worse |
| flight8.frame_ms_max | 13.232 | 11.896 | 0.90x |
| flight8.frame_ms_p50 | 2.588 | 2.607 | 1.01x |
| flight8.frame_ms_p95 | 3.197 | 3.559 | 1.11x |
| flight8.frame_ms_p99 | 4.401 | 5.879 | 1.34x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.686 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.592 | 1.01x |
| flight8.gpu_ms_p95 | 3.081 | 3.429 | 1.11x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 24.345 | 0.59x ✅ better |
| flight8.mesh_sections_per_s | 506.848 | 940.377 | 0.54x ✅ better |
| flight8.preload_ms | 1398.04 | 695.762 | 0.50x ✅ better |
| flight8.realtime | 0.994 | 0.997 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 207.94 | 1.67x ⚠️ worse |
| flight8.slab_mb | 52 | 40 | 0.77x ✅ better |
| flight8.tick_ms_max | 12.539 | 11.523 | 0.92x |
| flight8.tick_ms_p50 | 0.158 | 0.484 | 3.06x ⚠️ worse |
| flight8.tick_ms_p95 | 1.223 | 1.607 | 1.31x ⚠️ worse |
| flight8.update_ms_max | 12.421 | 6.183 | 0.50x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.043 | 4.30x ⚠️ worse |
| flight8.update_ms_p95 | 0.869 | 0.625 | 0.72x ✅ better |
| flight8.worker_gen_ms | 3.236 | 2.888 | 0.89x |
| flight8.worker_mesh_us | 181.115 | 305.398 | 1.69x ⚠️ worse |
| fluids.pending | 240 | 1283 | 5.35x ⚠️ worse |
| fluids.remeshed_sections | 2605 | 6448 | 2.48x ⚠️ worse |
| fluids.tick_ms_max | 3.42 | 19.842 | 5.80x ⚠️ worse |
| fluids.tick_ms_p50 | 0.226 | 0.402 | 1.78x ⚠️ worse |
| fluids.tick_ms_p95 | 1.872 | 2.239 | 1.20x |
| frame.draw_calls | 1076 | 1216 | 1.13x |
| frame.drawn_chunks | 272 | 270 | 0.99x |
| frame.drawn_kquads | 178.99 | 235.239 | 1.31x ⚠️ worse |
| frame.mesh_mb | 57.324 | 52.328 | 0.91x |
| frame.visible_sections | 686 | 697 | 1.02x |
| frame_1080p.encode_ms_max | 1.123 | 4.042 | 3.60x ⚠️ worse |
| frame_1080p.encode_ms_p50 | 0.625 | 0.908 | 1.45x ⚠️ worse |
| frame_1080p.gpu_ms_max | 2.632 | 9.607 | 3.65x ⚠️ worse |
| frame_1080p.gpu_ms_p50 | 2.308 | 4.996 | 2.16x ⚠️ worse |
| frame_4k.encode_ms_max | 1.603 | 2.33 | 1.45x ⚠️ worse |
| frame_4k.encode_ms_p50 | 0.691 | 1.414 | 2.05x ⚠️ worse |
| frame_4k.gpu_ms_max | 4.083 | 9.416 | 2.31x ⚠️ worse |
| frame_4k.gpu_ms_p50 | 3.521 | 7.407 | 2.10x ⚠️ worse |
| frame_800p.encode_ms_max | 0.755 | 2.624 | 3.48x ⚠️ worse |
| frame_800p.encode_ms_p50 | 0.608 | 0.839 | 1.38x ⚠️ worse |
| frame_800p.gpu_ms_max | 2.405 | 5.61 | 2.33x ⚠️ worse |
| frame_800p.gpu_ms_p50 | 2.068 | 4.287 | 2.07x ⚠️ worse |
| gen.chunk_ms_max | 3.382 | 8.038 | 2.38x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 2.857 | 1.37x ⚠️ worse |
| gen.chunk_ms_p95 | 3.325 | 5.304 | 1.60x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 996.418 | 1.69x ⚠️ worse |
| gen.starts_cold_ms | – | 3.089 | new |
| gen.terrain_hash | 1238443285367868 | 2072315357721602 | ⚠️ changed |
| genphase.caves_ms | – | 1.222 | new |
| genphase.columns_ms | – | 0.331 | new |
| genphase.ores_ms | – | 0.314 | new |
| genphase.plants_ms | – | 0.254 | new |
| genphase.starts_ms | – | 0.012 | new |
| genphase.stone_ms | – | 0.217 | new |
| genphase.structures_ms | – | 0.302 | new |
| genphase.surface_ms | – | 0.035 | new |
| genphase.trees_ms | – | 0.062 | new |
| mesh.chunk_ms_max | 5.758 | 6.953 | 1.21x |
| mesh.chunk_ms_mean | 4.38 | 4.551 | 1.04x |
| mesh.quads_per_chunk | 4996 | 4942.22 | 0.99x |
| mesh.section_us_max | 1621.01 | 1901.03 | 1.17x |
| mesh.section_us_mean | 139.451 | 189.611 | 1.36x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 771.999 | 1.13x |
| mesh_lod1.chunk_ms_max | 5.44 | 7.248 | 1.33x ⚠️ worse |
| mesh_lod1.chunk_ms_mean | 4.1 | 4.704 | 1.15x |
| mesh_lod1.quads_per_chunk | 2535 | 2498.11 | 0.99x |
| mesh_lod1.section_us_max | 1477.96 | 1574.04 | 1.07x |
| mesh_lod1.section_us_mean | 126.754 | 196.003 | 1.55x ⚠️ worse |
| mesh_lod1.section_us_p95 | 568.032 | 778.913 | 1.37x ⚠️ worse |
| mobs.per_mob_us | 1.608 | 1.029 | 0.64x ✅ better |
| mobs.tick_150_ms_max | 1.25 | 2.916 | 2.33x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.553 | 2.03x ⚠️ worse |
| mobs.tick_150_ms_p95 | 0.439 | 1.398 | 3.18x ⚠️ worse |
| mobs.tick_base_ms_mean | 0.031 | 0.398 | 12.84x ⚠️ worse |
| mobs.tick_base_ms_p95 | 0.082 | 1.087 | 13.26x ⚠️ worse |
| save.chunk_kb | 4.471 | 6.207 | 1.39x ⚠️ worse |
| save.chunk_ms | 2.896 | 1.957 | 0.68x ✅ better |
| save.load_chunk_ms | 0.587 | 0.277 | 0.47x ✅ better |
| save.main_thread_ms | 5.206 | 3.946 | 0.76x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.92 | 0.75x ✅ better |
| ships.assemble_ms | 19.313 | 44.352 | 2.30x ⚠️ worse |
| ships.assemble_remesh_s | 0.027 | 0.046 | 1.70x ⚠️ worse |
| ships.blast_ms | 2.675 | 5.353 | 2.00x ⚠️ worse |
| ships.blast_remesh_ms | 5.466 | 4.147 | 0.76x ✅ better |
| ships.collide_far_us | 0.214 | 0.236 | 1.10x |
| ships.collide_us | 1.047 | 0.965 | 0.92x |
| ships.dock_ms | 12.056 | 14.935 | 1.24x |
| ships.dock_remesh_s | 0.036 | 0.1 | 2.78x ⚠️ worse |
| ships.draw_calls | 66 | 66 | 1.00x |
| ships.edit_ms_max | 0.887 | 1.316 | 1.48x ⚠️ worse |
| ships.edit_ms_mean | 0.505 | 0.47 | 0.93x |
| ships.edit_remesh_ms | 3.642 | 3.723 | 1.02x |
| ships.frame_encode_ms | 0.023 | 0.233 | 10.13x ⚠️ worse |
| ships.frame_gpu_ms | -0.228 | 0.152 | infx ⚠️ worse |
| ships.mesh_frigate_ms | 3.066 | 4.579 | 1.49x ⚠️ worse |
| ships.physics_ms_mean | 0.165 | 0.36 | 2.18x ❌ regression |
| ships.physics_ms_p95 | 0.213 | 1.04 | 4.88x ⚠️ worse |
| ships.spawn_frigate_ms | 2.358 | 4.533 | 1.92x ⚠️ worse |
| ships.tick_ms_max | 0.522 | 10.972 | 21.02x ⚠️ worse |
| ships.tick_ms_mean | 0.219 | 0.919 | 4.20x ⚠️ worse |
| ships.tick_ms_p95 | 0.302 | 2.752 | 9.11x ⚠️ worse |
| startup.fill_rd12_s | 4.324 | 4.469 | 1.03x |
| startup.first_load_ms | 206.958 | 180.883 | 0.87x |
| startup.renderer_init_again_ms | 27.582 | 1151.27 | 41.74x ⚠️ worse |
| startup.renderer_init_ms | 817.522 | 2604.8 | 3.19x ⚠️ worse |
| startup.shader_compile_ms | 0.347 | 0.271 | 0.78x |
| startup.since_launch_s | 5.923 | 10.812 | 1.83x ⚠️ worse |
| startup.textures_ms | 26.537 | 582.241 | 21.94x ⚠️ worse |
| startup.world_init_ms | 2.198 | 15.381 | 7.00x ⚠️ worse |
| tnt.blast_ms_max | 8.579 | 3.394 | 0.40x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.61 | 0.55x ✅ better |
| tnt.remesh_s | 0.087 | 0.093 | 1.07x |
| tnt.tick_ms_max | 5.414 | 1.539 | 0.28x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 0.898 | 0.20x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 1.539 | 0.28x ✅ better |

**Regressions past the CI gate:**

- ships.physics_ms_mean: 0.165 -> 0.36 (2.18x worse, 2.18x for runner speed, gate 2.0x)
