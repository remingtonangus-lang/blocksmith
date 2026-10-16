# Blocksmith fast lane

Commit `0553020556f3b084bbf95ecd94177c4f7d48230e` on `claude/bs-capital-soldiers`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38855720548

### Build errors
```
```
### Type-check (warnings, slowest first)
```
8705 Sources/PlaytestPM9BTests.swift:94
8505 Sources/PlaytestPM9BTests.swift:95
7139 Sources/Mob.swift:445
5289 Sources/Mob.swift:445
3750 Sources/InputMatrix.swift:83
2516 Sources/AshSites.swift:127
1367 Sources/main.swift:1380
1213 Sources/main.swift:1380
920 Sources/CapitalShips.swift:1309
905 Sources/CapitalShips.swift:1304
892 Sources/CapitalShips.swift:1304
743 Sources/CapitalShips.swift:1309
533 Sources/main.swift:1380
529 Sources/CapitalBases.swift:282
508 Sources/Cinematic.swift:141
462 Sources/ShipCombat.swift:135
442 Sources/Cinematic.swift:141
419 Sources/BaseTests.swift:109
399 Sources/BaseTests.swift:109
380 Sources/Mesher.swift:95
379 Sources/Cinematic.swift:141
369 Sources/CapitalBasesWork.swift:251
368 Sources/main.swift:1351
326 Sources/FlightModel.swift:132
308 Sources/GameCircuit.swift:262
296 Sources/Textures.swift:642
296 Sources/GameCircuit.swift:262
294 Sources/TexturesHD.swift:3990
287 Sources/AshSites.swift:64
285 Sources/TexturesHD.swift:2749
279 Sources/main.swift:1475
277 Sources/GameCircuit.swift:262
277 Sources/BaseTests.swift:109
269 Sources/Ships.swift:110
264 Sources/Animals.swift:423
262 Sources/TerrainTools.swift:81
244 Sources/Animals.swift:423
242 Sources/CapitalBasesWork.swift:251
240 Sources/Player.swift:185
234 Sources/Music.swift:296
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 1387 ms, upload 718 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 14301 ms  mesh(all, parallel) 25612 ms  mesh(1 section) 146.31 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 12.41 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 153 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
