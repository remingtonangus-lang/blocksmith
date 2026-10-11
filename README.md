# Blocksmith fast lane

Commit `dd45494818c6e8fa8a2f8dcfea8d2c24badac03d` on `claude/project-thread-n6c75e`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38137355544

### Build errors
```
```
### Type-check (warnings, slowest first)
```
9435 Sources/PlaytestPM9BTests.swift:94
8766 Sources/PlaytestPM9BTests.swift:95
7218 Sources/RenderDistanceGovernor.swift:129
6457 Sources/Mob.swift:484
5148 Sources/Mob.swift:484
4930 Sources/AshVaultGapTests.swift:134
3286 Sources/InputMatrix.swift:83
2534 Sources/AshSites.swift:144
1172 Sources/HellMobs.swift:433
1150 Sources/main.swift:1415
1127 Sources/main.swift:1415
976 Sources/HellMobs.swift:433
856 Sources/CapitalShips.swift:1317
850 Sources/DeepGapTests.swift:329
811 Sources/CapitalShips.swift:1317
735 Sources/DeepGapTests.swift:329
685 Sources/HorseGapTests.swift:355
630 Sources/main.swift:1415
560 Sources/BaseTests.swift:107
546 Sources/Cinematic.swift:141
535 Sources/Cinematic.swift:141
530 Sources/HorseGapTests.swift:355
530 Sources/BaseTests.swift:107
516 Sources/CapitalBases.swift:295
507 Sources/HorseGapTests.swift:354
488 Sources/HorseGapTests.swift:354
470 Sources/HorseGapTests.swift:353
464 Sources/HorseGapTests.swift:353
462 Sources/ShipCombat.swift:136
455 Sources/LandmarkRender.swift:76
451 Sources/HorseGapTests.swift:355
395 Sources/MainGun.swift:367
389 Sources/Cinematic.swift:141
365 Sources/CapitalBasesWork.swift:252
361 Sources/MainGun.swift:196
352 Sources/main.swift:1386
349 Sources/HuntingTests.swift:191
346 Sources/CountriesTests.swift:191
343 Sources/HuntingTests.swift:191
343 Sources/BaseTests.swift:107
```
### Snapshot
```
posecheck: 643 raised limbs checked, 0 failed
textures: 1786 layers at 16 px, BC3, 0.6 MB with mips (build 1612 ms, upload 748 ms)
target: grass_block at -10 145 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(-8.5, 145.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 81) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
seed 12345  pos -8.5 145.0 29.5  rd 4  chunks 109  (drawn 23)
gen 15240 ms  mesh(all, parallel) 26023 ms  mesh(1 section) 129.61 ms  quads 320803 opaque / 518 water
frame (encode+GPU, offscreen, median of 30) 10.53 ms  biome plains
mesh slabs 12 MB, chunks 109 (block+light arrays 11 MB), Metal allocated 114 MB
memory: resident 149 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
