# Blocksmith fast lane

Commit `8e63b6b12acf1082b1956d12e14b3b4af3e1c7b2` on `claude/project-thread-7wqmvf`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38013469070

### Build errors
```
```
### Type-check (warnings, slowest first)
```
7308 Sources/PlaytestPM9BTests.swift:95
6992 Sources/PlaytestPM9BTests.swift:94
5028 Sources/Mob.swift:447
3991 Sources/Mob.swift:447
2502 Sources/InputMatrix.swift:83
1920 Sources/AshSites.swift:127
849 Sources/main.swift:1386
802 Sources/main.swift:1386
696 Sources/CapitalShips.swift:1309
633 Sources/CapitalShips.swift:1304
610 Sources/CapitalShips.swift:1304
604 Sources/CapitalShips.swift:1309
460 Sources/CapitalBases.swift:282
420 Sources/BaseTests.swift:107
391 Sources/Cinematic.swift:141
387 Sources/BaseTests.swift:107
378 Sources/Cinematic.swift:141
337 Sources/main.swift:1386
313 Sources/ShipCombat.swift:135
308 Sources/BaseTests.swift:107
284 Sources/Cinematic.swift:141
283 Sources/GameCircuit.swift:262
268 Sources/TexturesHD.swift:2749
241 Sources/TexturesHD.swift:3990
234 Sources/Mesher.swift:95
218 Sources/main.swift:1357
217 Sources/CapitalBasesWork.swift:251
215 Sources/Soldiers.swift:690
204 Sources/GameCircuit.swift:262
202 Sources/GameCircuit.swift:262
200 Sources/Ships.swift:110
193 Sources/main.swift:1481
192 Sources/CapitalBasesWork.swift:251
185 Sources/Soldiers.swift:690
185 Sources/FlightModel.swift:113
182 Sources/Banners.swift:215
178 Sources/CapitalBasesWork.swift:251
161 Sources/TerrainTools.swift:81
159 Sources/AshSites.swift:64
157 Sources/Textures.swift:642
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 1044 ms, upload 508 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 11811 ms  mesh(all, parallel) 28757 ms  mesh(1 section) 120.87 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 9.99 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 150 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
