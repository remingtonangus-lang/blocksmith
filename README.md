# Blocksmith fast lane

Commit `5efc1b56c5cb1312b78e439c082153a4d1ef715e` on `claude/project-thread-kw71v5`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38094940004

### Build errors
```
```
### Type-check (warnings, slowest first)
```
6579 Sources/PlaytestPM9BTests.swift:95
6258 Sources/PlaytestPM9BTests.swift:94
5176 Sources/RenderDistanceGovernor.swift:129
5157 Sources/Mob.swift:451
3996 Sources/Mob.swift:451
2743 Sources/InputMatrix.swift:83
1861 Sources/AshSites.swift:127
783 Sources/main.swift:1416
776 Sources/main.swift:1416
643 Sources/CapitalShips.swift:1317
635 Sources/CapitalShips.swift:1317
472 Sources/Cinematic.swift:141
461 Sources/BaseTests.swift:107
433 Sources/BaseTests.swift:107
414 Sources/CapitalBases.swift:289
382 Sources/Cinematic.swift:141
375 Sources/Cinematic.swift:141
352 Sources/main.swift:1416
334 Sources/FlightModel.swift:113
321 Sources/TexturesHD.swift:3990
318 Sources/main.swift:1387
307 Sources/MainGun.swift:192
300 Sources/Ships.swift:110
300 Sources/ShipCombat.swift:136
264 Sources/BaseTests.swift:107
263 Sources/Banners.swift:215
247 Sources/Mesher.swift:96
239 Sources/GameCircuit.swift:262
238 Sources/CapitalBasesWork.swift:251
237 Sources/MainGun.swift:356
215 Sources/TerrainTools.swift:81
215 Sources/CapitalBasesWork.swift:251
208 Sources/WorldGenCheck.swift:47
204 Sources/TexturesHD.swift:2749
203 Sources/Structures.swift:301
196 Sources/main.swift:1511
194 Sources/MainGun.swift:139
192 Sources/GameCircuit.swift:262
187 Sources/Textures.swift:642
185 Sources/GameCircuit.swift:262
```
### Snapshot
```
posecheck: 603 raised limbs checked, 0 failed
textures: 1730 layers at 16 px, BC3, 0.6 MB with mips (build 1356 ms, upload 587 ms)
target: grass_block at 29 136 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(31.5, 136.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 10977 ms  mesh(all, parallel) 20319 ms  mesh(1 section) 124.75 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 8.40 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 149 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
