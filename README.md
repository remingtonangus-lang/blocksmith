# Blocksmith fast lane

Commit `d93af332c3d7659ccc9ce60c6151ad165b81c39c` on `claude/project-thread-dkuflx`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38090345636

### Build errors
```
```
### Type-check (warnings, slowest first)
```
7545 Sources/PlaytestPM9BTests.swift:94
7477 Sources/PlaytestPM9BTests.swift:95
6247 Sources/RenderDistanceGovernor.swift:129
6001 Sources/Mob.swift:451
4683 Sources/Mob.swift:451
3327 Sources/InputMatrix.swift:83
2037 Sources/AshSites.swift:127
979 Sources/main.swift:1416
943 Sources/main.swift:1416
783 Sources/CapitalShips.swift:1315
770 Sources/CapitalShips.swift:1315
549 Sources/BaseTests.swift:107
530 Sources/Cinematic.swift:141
500 Sources/CapitalBases.swift:289
498 Sources/Cinematic.swift:141
486 Sources/BaseTests.swift:107
465 Sources/main.swift:1416
399 Sources/ShipCombat.swift:136
381 Sources/BaseTests.swift:107
333 Sources/Cinematic.swift:141
322 Sources/MainGun.swift:335
312 Sources/MainGun.swift:184
295 Sources/TexturesHD.swift:3990
282 Sources/CapitalBasesWork.swift:251
281 Sources/main.swift:1387
269 Sources/TexturesHD.swift:2749
264 Sources/Mesher.swift:96
253 Sources/WorldGenCheck.swift:47
253 Sources/CapitalBasesWork.swift:251
247 Sources/Ships.swift:110
247 Sources/GameCircuit.swift:262
244 Sources/main.swift:1511
243 Sources/GameCircuit.swift:262
243 Sources/Banners.swift:215
240 Sources/MainGun.swift:128
240 Sources/CapitalBasesWork.swift:251
239 Sources/AshSites.swift:64
234 Sources/GameCircuit.swift:262
233 Sources/FlightModel.swift:113
225 Sources/TerrainTools.swift:81
```
### Snapshot
```
posecheck: 603 raised limbs checked, 0 failed
textures: 1722 layers at 16 px, BC3, 0.6 MB with mips (build 1489 ms, upload 635 ms)
target: grass_block at 29 136 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(31.5, 136.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 14267 ms  mesh(all, parallel) 23927 ms  mesh(1 section) 142.22 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 13.30 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 147 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
