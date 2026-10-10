# Blocksmith fast lane

Commit `ce043f250e448ed1dffba33984fc4d23c358bc76` on `claude/project-thread-db44wr`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38087870455

### Build errors
```
```
### Type-check (warnings, slowest first)
```
5844 Sources/PlaytestPM9BTests.swift:95
5544 Sources/PlaytestPM9BTests.swift:94
4860 Sources/RenderDistanceGovernor.swift:129
4460 Sources/Mob.swift:448
3504 Sources/Mob.swift:448
2288 Sources/InputMatrix.swift:83
1541 Sources/AshSites.swift:127
778 Sources/main.swift:1411
761 Sources/main.swift:1411
575 Sources/CapitalShips.swift:1315
574 Sources/CapitalShips.swift:1315
391 Sources/BaseTests.swift:107
380 Sources/CapitalBases.swift:288
377 Sources/BaseTests.swift:107
358 Sources/Cinematic.swift:141
354 Sources/Cinematic.swift:141
351 Sources/main.swift:1411
284 Sources/ShipCombat.swift:136
261 Sources/Cinematic.swift:141
256 Sources/main.swift:1382
242 Sources/MainGun.swift:184
240 Sources/BaseTests.swift:107
219 Sources/TexturesHD.swift:3990
212 Sources/MainGun.swift:335
212 Sources/CapitalBasesWork.swift:251
210 Sources/Mesher.swift:96
207 Sources/WorldGenCheck.swift:47
202 Sources/GameCircuit.swift:262
201 Sources/GameCircuit.swift:262
199 Sources/TexturesHD.swift:2749
197 Sources/GameCircuit.swift:262
192 Sources/main.swift:1506
188 Sources/MainGun.swift:128
182 Sources/CapitalBasesWork.swift:251
181 Sources/FlightModel.swift:113
180 Sources/CapitalBasesWork.swift:251
172 Sources/Ships.swift:110
164 Sources/TerrainTools.swift:81
156 Sources/Player.swift:189
156 Sources/Banners.swift:215
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1721 layers at 16 px, BC3, 0.6 MB with mips (build 1092 ms, upload 467 ms)
target: grass_block at 29 136 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(31.5, 136.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 10270 ms  mesh(all, parallel) 19001 ms  mesh(1 section) 130.49 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 9.36 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 146 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
