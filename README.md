# Blocksmith fast lane

Commit `f1890fee73246a77ec0bb3fb9c0ed6bd1883356c` on `claude/project-thread-o2nc78`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38140640516

### Build errors
```
```
### Type-check (warnings, slowest first)
```
8670 Sources/PlaytestPM9BTests.swift:95
8306 Sources/PlaytestPM9BTests.swift:94
7363 Sources/RenderDistanceGovernor.swift:129
6924 Sources/Mob.swift:488
5347 Sources/Mob.swift:488
5143 Sources/AshVaultGapTests.swift:134
3782 Sources/InputMatrix.swift:83
2280 Sources/AshSites.swift:144
1293 Sources/main.swift:1415
1238 Sources/main.swift:1415
961 Sources/HellMobs.swift:433
954 Sources/CapitalShips.swift:1317
842 Sources/HellMobs.swift:433
794 Sources/DeepGapTests.swift:329
757 Sources/CapitalShips.swift:1317
679 Sources/CapitalBases.swift:295
670 Sources/DeepGapTests.swift:329
647 Sources/Cinematic.swift:141
598 Sources/BaseTests.swift:107
586 Sources/HorseGapTests.swift:355
584 Sources/Cinematic.swift:141
577 Sources/BaseTests.swift:107
574 Sources/main.swift:1415
553 Sources/HorseGapTests.swift:355
543 Sources/HorseGapTests.swift:353
534 Sources/HorseGapTests.swift:354
528 Sources/HorseGapTests.swift:353
447 Sources/HorseGapTests.swift:354
423 Sources/Cinematic.swift:141
419 Sources/ShipCombat.swift:136
375 Sources/TexturesHD.swift:3992
370 Sources/LandmarkRender.swift:76
363 Sources/HorseGapTests.swift:355
362 Sources/CountriesTests.swift:191
358 Sources/LandmarkRender.swift:76
349 Sources/MainGun.swift:196
343 Sources/HuntingTests.swift:191
334 Sources/main.swift:1386
334 Sources/WorldGenCheck.swift:47
321 Sources/BaseTests.swift:107
```
### Snapshot
```
posecheck: 643 raised limbs checked, 0 failed
textures: 1786 layers at 16 px, BC3, 0.6 MB with mips (build 1530 ms, upload 646 ms)
target: grass_block at -10 145 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(-8.5, 145.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 81) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
seed 12345  pos -8.5 145.0 29.5  rd 4  chunks 109  (drawn 23)
gen 14821 ms  mesh(all, parallel) 25176 ms  mesh(1 section) 109.15 ms  quads 320803 opaque / 518 water
frame (encode+GPU, offscreen, median of 30) 14.16 ms  biome plains
mesh slabs 12 MB, chunks 109 (block+light arrays 11 MB), Metal allocated 114 MB
memory: resident 150 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
