# Blocksmith fast lane

Commit `794517d182212f8ef3f79bea596c008b98aecab8` on `claude/project-thread-6x53kn`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38091049230

### Build errors
```
```
### Type-check (warnings, slowest first)
```
8731 Sources/PlaytestPM9BTests.swift:94
8409 Sources/PlaytestPM9BTests.swift:95
7427 Sources/Mob.swift:451
7055 Sources/RenderDistanceGovernor.swift:129
5131 Sources/Mob.swift:451
3307 Sources/InputMatrix.swift:83
2159 Sources/AshSites.swift:127
1103 Sources/main.swift:1416
1053 Sources/main.swift:1416
826 Sources/CapitalShips.swift:1317
821 Sources/CapitalShips.swift:1317
597 Sources/CapitalBases.swift:289
582 Sources/BaseTests.swift:107
576 Sources/BaseTests.swift:107
524 Sources/Cinematic.swift:141
502 Sources/Cinematic.swift:141
479 Sources/main.swift:1416
428 Sources/BaseTests.swift:107
417 Sources/ShipCombat.swift:136
355 Sources/MainGun.swift:192
344 Sources/TexturesHD.swift:3990
337 Sources/MainGun.swift:356
335 Sources/CapitalBasesWork.swift:251
333 Sources/Cinematic.swift:141
318 Sources/WorldGenCheck.swift:47
308 Sources/Mesher.swift:96
299 Sources/main.swift:1511
297 Sources/MainGun.swift:139
296 Sources/main.swift:1387
274 Sources/GameCircuit.swift:262
273 Sources/CapitalBasesWork.swift:251
270 Sources/TexturesHD.swift:2749
268 Sources/GameCircuit.swift:262
267 Sources/Ships.swift:110
263 Sources/GameCircuit.swift:262
260 Sources/AshSites.swift:64
253 Sources/PadTest.swift:750
251 Sources/CapitalBasesWork.swift:251
244 Sources/FlightModel.swift:113
236 Sources/Soldiers.swift:690
```
### Snapshot
```
posecheck: 603 raised limbs checked, 0 failed
textures: 1723 layers at 16 px, BC3, 0.6 MB with mips (build 1556 ms, upload 679 ms)
target: grass_block at 29 136 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(31.5, 136.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 14356 ms  mesh(all, parallel) 24931 ms  mesh(1 section) 133.28 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 15.07 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 150 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
