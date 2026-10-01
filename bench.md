| metric | baseline | now | worse by |
|---|---|---|---|
| edit.break_ms_max | 0.6 | 1.053 | 1.75x ⚠️ worse |
| edit.break_ms_mean | 0.447 | 0.513 | 1.15x |
| edit.place_ms_max | 0.732 | 1.086 | 1.48x ⚠️ worse |
| edit.place_ms_mean | 0.455 | 0.514 | 1.13x |
| flight16.arena_free_mb | 0.864 | 0.813 | 0.94x |
| flight16.chunk_mb | 103.906 | 103.906 | 1.00x |
| flight16.chunks | 1056 | 1056 | 1.00x |
| flight16.coverage_mean | 0.991 | 0.992 | 1.00x |
| flight16.coverage_min | 0.962 | 0.962 | 1.00x |
| flight16.cull_ms_p50 | 0.708 | 0.39 | 0.55x ✅ better |
| flight16.cull_ms_p95 | 1.152 | 0.993 | 0.86x |
| flight16.cull_walked_sections | 2817 | 2817 | 1.00x |
| flight16.draw_calls | 1434 | 1434 | 1.00x |
| flight16.drawn_kquads | 475.516 | 475.516 | 1.00x |
| flight16.encode_ms_p50 | 1.494 | 0.832 | 0.56x ✅ better |
| flight16.encode_ms_p95 | 2.361 | 1.983 | 0.84x |
| flight16.frame_ms_max | 12.652 | 24.324 | 1.92x ⚠️ worse |
| flight16.frame_ms_p50 | 4.807 | 4.759 | 0.99x |
| flight16.frame_ms_p95 | 5.8 | 6.489 | 1.12x |
| flight16.frame_ms_p99 | 7.443 | 15.132 | 2.03x ⚠️ worse |
| flight16.gen_chunks_per_s | 43.68 | 43.618 | 1.00x |
| flight16.gpu_ms_p50 | 4.804 | 4.755 | 0.99x |
| flight16.gpu_ms_p95 | 5.71 | 6.28 | 1.10x |
| flight16.hitches | 0 | 0 | 1.00x |
| flight16.mesh_mb | 81.28 | 81.28 | 1.00x |
| flight16.mesh_sections_per_s | 1972.83 | 1970.04 | 1.00x |
| flight16.preload_ms | 1871.23 | 1458.66 | 0.78x |
| flight16.realtime | 0.998 | 0.997 | 1.00x |
| flight16.resident_peak_mb | 285.862 | 210.612 | 0.74x ✅ better |
| flight16.slab_mb | 96 | 96 | 1.00x |
| flight16.tick_ms_max | 8.551 | 23.425 | 2.74x ⚠️ worse |
| flight16.tick_ms_p50 | 0.388 | 0.317 | 0.82x |
| flight16.tick_ms_p95 | 2.08 | 1.557 | 0.75x ✅ better |
| flight16.update_ms_max | 8.289 | 23.343 | 2.82x ⚠️ worse |
| flight16.update_ms_p50 | 0.017 | 0.01 | 0.59x ✅ better |
| flight16.update_ms_p95 | 1.74 | 1.333 | 0.77x ✅ better |
| flight16.worker_gen_ms | 2.022 | 2.02 | 1.00x |
| flight16.worker_mesh_us | 177.949 | 154.245 | 0.87x |
| flight24.arena_free_mb | 0.427 | 0.395 | 0.93x |
| flight24.chunk_mb | 222.438 | 222.438 | 1.00x |
| flight24.chunks | 2176 | 2176 | 1.00x |
| flight24.coverage_mean | 0.994 | 0.995 | 1.00x |
| flight24.coverage_min | 0.974 | 0.974 | 1.00x |
| flight24.cull_ms_p50 | 1.198 | 0.965 | 0.81x |
| flight24.cull_ms_p95 | 2.767 | 2.333 | 0.84x |
| flight24.cull_walked_sections | 7607 | 7607 | 1.00x |
| flight24.draw_calls | 3175 | 3175 | 1.00x |
| flight24.drawn_kquads | 821.704 | 821.704 | 1.00x |
| flight24.encode_ms_p50 | 2.473 | 1.928 | 0.78x |
| flight24.encode_ms_p95 | 5.237 | 4.469 | 0.85x |
| flight24.frame_ms_max | 13.319 | 22.93 | 1.72x ⚠️ worse |
| flight24.frame_ms_p50 | 7.72 | 7.792 | 1.01x |
| flight24.frame_ms_p95 | 9.472 | 9.774 | 1.03x |
| flight24.frame_ms_p99 | 10.337 | 13.743 | 1.33x ⚠️ worse |
| flight24.gen_chunks_per_s | 63.73 | 63.63 | 1.00x |
| flight24.gpu_ms_p50 | 7.718 | 7.788 | 1.01x |
| flight24.gpu_ms_p95 | 9.428 | 9.772 | 1.04x |
| flight24.hitches | 0 | 0 | 1.00x |
| flight24.mesh_mb | 131.138 | 131.138 | 1.00x |
| flight24.mesh_sections_per_s | 2455.22 | 2451.36 | 1.00x |
| flight24.preload_ms | 4742.83 | 3201.7 | 0.68x ✅ better |
| flight24.realtime | 1 | 0.998 | 1.00x |
| flight24.resident_peak_mb | 512.018 | 413.565 | 0.81x |
| flight24.slab_mb | 148 | 148 | 1.00x |
| flight24.tick_ms_max | 11.61 | 7.091 | 0.61x ✅ better |
| flight24.tick_ms_p50 | 0.401 | 0.326 | 0.81x |
| flight24.tick_ms_p95 | 2.942 | 2.147 | 0.73x ✅ better |
| flight24.update_ms_max | 4.586 | 5.68 | 1.24x |
| flight24.update_ms_p50 | 0.015 | 0.009 | 0.60x ✅ better |
| flight24.update_ms_p95 | 2.535 | 1.894 | 0.75x ✅ better |
| flight24.worker_gen_ms | 2.355 | 1.83 | 0.78x |
| flight24.worker_mesh_us | 177.947 | 144.392 | 0.81x |
| flight8.arena_free_mb | 2.438 | 2.463 | 1.01x |
| flight8.chunk_mb | 30.25 | 30.25 | 1.00x |
| flight8.chunks | 328 | 328 | 1.00x |
| flight8.coverage_mean | 0.99 | 0.993 | 1.00x |
| flight8.coverage_min | 0.924 | 0.924 | 1.00x |
| flight8.cull_ms_p50 | 0.204 | 0.081 | 0.40x ✅ better |
| flight8.cull_ms_p95 | 0.305 | 0.211 | 0.69x ✅ better |
| flight8.cull_walked_sections | 517 | 517 | 1.00x |
| flight8.draw_calls | 463 | 463 | 1.00x |
| flight8.drawn_kquads | 211.463 | 211.463 | 1.00x |
| flight8.encode_ms_p50 | 0.562 | 0.25 | 0.44x ✅ better |
| flight8.encode_ms_p95 | 0.832 | 0.631 | 0.76x ✅ better |
| flight8.frame_ms_max | 13.232 | 22.213 | 1.68x ⚠️ worse |
| flight8.frame_ms_p50 | 2.588 | 2.181 | 0.84x |
| flight8.frame_ms_p95 | 3.197 | 3.437 | 1.08x |
| flight8.frame_ms_p99 | 4.401 | 8.168 | 1.86x ⚠️ worse |
| flight8.gen_chunks_per_s | 23.603 | 23.662 | 1.00x |
| flight8.gpu_ms_p50 | 2.579 | 2.181 | 0.85x |
| flight8.gpu_ms_p95 | 3.081 | 3.111 | 1.01x |
| flight8.hitches | 0 | 0 | 1.00x |
| flight8.mesh_mb | 40.975 | 40.975 | 1.00x |
| flight8.mesh_sections_per_s | 506.848 | 510.928 | 0.99x |
| flight8.preload_ms | 1398.04 | 385.416 | 0.28x ✅ better |
| flight8.realtime | 0.994 | 0.996 | 1.00x |
| flight8.resident_peak_mb | 124.705 | 144.611 | 1.16x |
| flight8.slab_mb | 52 | 52 | 1.00x |
| flight8.tick_ms_max | 12.539 | 7.837 | 0.63x ✅ better |
| flight8.tick_ms_p50 | 0.158 | 0.117 | 0.74x ✅ better |
| flight8.tick_ms_p95 | 1.223 | 0.871 | 0.71x ✅ better |
| flight8.update_ms_max | 12.421 | 2.042 | 0.16x ✅ better |
| flight8.update_ms_p50 | 0.01 | 0.005 | 0.50x ✅ better |
| flight8.update_ms_p95 | 0.869 | 0.443 | 0.51x ✅ better |
| flight8.worker_gen_ms | 3.236 | 1.495 | 0.46x ✅ better |
| flight8.worker_mesh_us | 181.115 | 148.585 | 0.82x |
| fluids.pending | 240 | 190 | 0.79x |
| fluids.remeshed_sections | 2605 | 2543 | 0.98x |
| fluids.tick_ms_max | 3.42 | 2.183 | 0.64x ✅ better |
| fluids.tick_ms_p50 | 0.226 | 0.125 | 0.55x ✅ better |
| fluids.tick_ms_p95 | 1.872 | 0.919 | 0.49x ✅ better |
| frame.draw_calls | 1076 | 1076 | 1.00x |
| frame.drawn_chunks | 272 | 272 | 1.00x |
| frame.drawn_kquads | 178.99 | 178.99 | 1.00x |
| frame.mesh_mb | 57.324 | 57.324 | 1.00x |
| frame.visible_sections | 686 | 686 | 1.00x |
| frame_1080p.encode_ms_max | 1.123 | 0.746 | 0.66x ✅ better |
| frame_1080p.encode_ms_p50 | 0.625 | 0.553 | 0.88x |
| frame_1080p.gpu_ms_max | 2.632 | 2.971 | 1.13x |
| frame_1080p.gpu_ms_p50 | 2.308 | 2.2 | 0.95x |
| frame_4k.encode_ms_max | 1.603 | 1.462 | 0.91x |
| frame_4k.encode_ms_p50 | 0.691 | 0.557 | 0.81x |
| frame_4k.gpu_ms_max | 4.083 | 4.374 | 1.07x |
| frame_4k.gpu_ms_p50 | 3.521 | 2.801 | 0.80x |
| frame_800p.encode_ms_max | 0.755 | 0.756 | 1.00x |
| frame_800p.encode_ms_p50 | 0.608 | 0.562 | 0.92x |
| frame_800p.gpu_ms_max | 2.405 | 2.624 | 1.09x |
| frame_800p.gpu_ms_p50 | 2.068 | 1.946 | 0.94x |
| gen.chunk_ms_max | 3.382 | 5.561 | 1.64x ⚠️ worse |
| gen.chunk_ms_mean | 2.082 | 1.984 | 0.95x |
| gen.chunk_ms_p95 | 3.325 | 4.41 | 1.33x ⚠️ worse |
| gen.lattice_mismatches | 0 | 0 | 1.00x |
| gen.parallel_chunks_per_s | 1683.33 | 2075.99 | 0.81x |
| gen.terrain_hash | 1238443285367868 | 1238443285367868 | same |
| mesh.chunk_ms_max | 5.758 | 23.002 | 3.99x ⚠️ worse |
| mesh.chunk_ms_mean | 3.347 | 7.945 | 2.37x ❌ regression |
| mesh.quads_per_chunk | 3763.89 | 3763.89 | 1.00x |
| mesh.section_us_max | 1621.01 | 8034.94 | 4.96x ⚠️ worse |
| mesh.section_us_mean | 139.451 | 331.049 | 2.37x ⚠️ worse |
| mesh.section_us_p95 | 686.049 | 1214.98 | 1.77x ⚠️ worse |
| mesh_lod1.chunk_ms_max | 5.44 | 6.153 | 1.13x |
| mesh_lod1.chunk_ms_mean | 3.042 | 2.876 | 0.95x |
| mesh_lod1.quads_per_chunk | 783.333 | 783.333 | 1.00x |
| mesh_lod1.section_us_max | 1477.96 | 1695.04 | 1.15x |
| mesh_lod1.section_us_mean | 126.754 | 119.839 | 0.95x |
| mesh_lod1.section_us_p95 | 568.032 | 563.025 | 0.99x |
| mobs.per_mob_us | 1.608 | 1.614 | 1.00x |
| mobs.tick_150_ms_max | 1.25 | 2.102 | 1.68x ⚠️ worse |
| mobs.tick_150_ms_mean | 0.272 | 0.268 | 0.99x |
| mobs.tick_150_ms_p95 | 0.439 | 0.401 | 0.91x |
| mobs.tick_base_ms_mean | 0.031 | 0.026 | 0.84x |
| mobs.tick_base_ms_p95 | 0.082 | 0.071 | 0.87x |
| save.chunk_kb | 4.471 | 4.471 | 1.00x |
| save.chunk_ms | 2.896 | 1.918 | 0.66x ✅ better |
| save.load_chunk_ms | 0.587 | 0.258 | 0.44x ✅ better |
| save.main_thread_ms | 5.206 | 3.507 | 0.67x ✅ better |
| save.unchanged_resave_ms | 2.544 | 1.386 | 0.54x ✅ better |
| startup.fill_rd12_s | 4.324 | 4.565 | 1.06x |
| startup.first_load_ms | 206.958 | 125.921 | 0.61x ✅ better |
| startup.renderer_init_again_ms | 27.582 | 13.93 | 0.51x ✅ better |
| startup.renderer_init_ms | 817.522 | 522.791 | 0.64x ✅ better |
| startup.shader_compile_ms | 0.347 | 0.452 | 1.30x ⚠️ worse |
| startup.since_launch_s | 5.923 | 6.358 | 1.07x |
| startup.textures_ms | 26.537 | 20.125 | 0.76x ✅ better |
| startup.world_init_ms | 2.198 | 1.862 | 0.85x |
| tnt.blast_ms_max | 8.579 | 2.878 | 0.34x ✅ better |
| tnt.blast_ms_mean | 2.904 | 1.827 | 0.63x ✅ better |
| tnt.remesh_s | 0.087 | 0.04 | 0.46x ✅ better |
| tnt.tick_ms_max | 5.414 | 2.419 | 0.45x ✅ better |
| tnt.tick_ms_p50 | 4.529 | 1.649 | 0.36x ✅ better |
| tnt.tick_ms_p95 | 5.414 | 2.419 | 0.45x ✅ better |

**Regressions past the CI gate:**

- mesh.chunk_ms_mean: 3.347 -> 7.945 (2.37x worse, gate 1.6x)
