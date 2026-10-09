# Blocksmith fast lane

Commit `aeee0a721026cc7aef77fa252c7307eabfbec8dd` on `claude/towns-of-people-j6qgts`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37991238709

### Build errors
```
```
### Type-check (warnings, slowest first)
```
7878 Sources/PlaytestPM9BTests.swift:94
6676 Sources/PlaytestPM9BTests.swift:95
6564 Sources/Mob.swift:447
4717 Sources/Mob.swift:447
3361 Sources/InputMatrix.swift:83
1936 Sources/AshSites.swift:127
1032 Sources/main.swift:1386
969 Sources/main.swift:1386
692 Sources/CapitalShips.swift:1304
684 Sources/CapitalShips.swift:1304
654 Sources/CapitalShips.swift:1309
647 Sources/CapitalShips.swift:1309
514 Sources/BaseTests.swift:107
426 Sources/Cinematic.swift:141
424 Sources/main.swift:1386
422 Sources/CapitalBases.swift:282
400 Sources/Cinematic.swift:141
392 Sources/BaseTests.swift:107
359 Sources/GameCircuit.swift:262
358 Sources/ShipCombat.swift:135
354 Sources/Cinematic.swift:141
320 Sources/FlightModel.swift:113
314 Sources/GameCircuit.swift:262
292 Sources/main.swift:1357
292 Sources/Mesher.swift:95
254 Sources/GameCircuit.swift:262
254 Sources/CapitalBasesWork.swift:251
245 Sources/TexturesHD.swift:2749
239 Sources/TexturesHD.swift:3990
238 Sources/BaseTests.swift:107
236 Sources/Player.swift:180
229 Sources/Soldiers.swift:690
228 Sources/Player.swift:340
223 Sources/TerrainTools.swift:81
218 Sources/main.swift:1481
215 Sources/CapitalBasesWork.swift:251
211 Sources/Player.swift:340
198 Sources/CapitalBasesWork.swift:251
196 Sources/PadTest.swift:750
188 Sources/Structures.swift:288
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 920 ms, upload 476 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 10059 ms  mesh(all, parallel) 18942 ms  mesh(1 section) 108.14 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 9.65 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 150 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
