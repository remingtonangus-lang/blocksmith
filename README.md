# Blocksmith fast lane

Commit `ddd3c9af382a89060ca409df4ef229d75354e7be` on `claude/project-thread-fpep32`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38152105263

### Build errors
```
```
### Type-check (warnings, slowest first)
```
6008 Sources/PlaytestPM9BTests.swift:95
5712 Sources/PlaytestPM9BTests.swift:94
4769 Sources/RenderDistanceGovernor.swift:129
4671 Sources/Mob.swift:487
4537 Sources/AshVaultGapTests.swift:134
3556 Sources/Mob.swift:487
2635 Sources/InputMatrix.swift:83
2598 Sources/AshSites.swift:56
2357 Sources/AshSites.swift:229
852 Sources/main.swift:1415
846 Sources/main.swift:1415
800 Sources/CapitalShips.swift:1317
749 Sources/CapitalShips.swift:1317
633 Sources/DeepGapTests.swift:331
625 Sources/HellMobs.swift:433
598 Sources/HellMobs.swift:433
552 Sources/DeepGapTests.swift:331
538 Sources/CapitalBases.swift:295
500 Sources/BaseTests.swift:107
468 Sources/BaseTests.swift:107
448 Sources/Cinematic.swift:141
426 Sources/Cinematic.swift:141
397 Sources/main.swift:1415
381 Sources/HorseGapTests.swift:355
371 Sources/HorseGapTests.swift:355
367 Sources/CapitalBasesWork.swift:252
338 Sources/CapitalBasesWork.swift:252
337 Sources/HorseGapTests.swift:354
336 Sources/HorseGapTests.swift:353
318 Sources/BaseTests.swift:107
317 Sources/HorseGapTests.swift:354
317 Sources/HorseGapTests.swift:353
315 Sources/TexturesHD.swift:3992
298 Sources/Cinematic.swift:141
287 Sources/LandmarkRender.swift:76
285 Sources/ShipCombat.swift:136
282 Sources/CapitalBasesWork.swift:252
267 Sources/LandmarkRender.swift:76
254 Sources/CountriesTests.swift:191
244 Sources/main.swift:1386
```
### Snapshot
```
posecheck: 898 raised limbs checked, 0 failed
textures: 1807 layers at 16 px, BC3, 0.6 MB with mips (build 1248 ms, upload 529 ms)
target: grass_block at -10 145 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(-8.5, 145.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 81) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=25.0 hash=3410a2b27e40da2c
seed 12345  pos -8.5 145.0 29.5  rd 4  chunks 109  (drawn 23)
gen 10336 ms  mesh(all, parallel) 18511 ms  mesh(1 section) 84.45 ms  quads 320803 opaque / 518 water
frame (encode+GPU, offscreen, median of 30) 9.89 ms  biome plains
mesh slabs 12 MB, chunks 109 (block+light arrays 11 MB), Metal allocated 114 MB
memory: resident 151 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
