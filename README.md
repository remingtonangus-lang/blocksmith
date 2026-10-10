# Blocksmith fast lane

Commit `7629ff8ad70788560a3d369e9d53d4b25dd6a9ec` on `claude/blocksmith-playtest`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38023362948

### Build errors
```
```
### Type-check (warnings, slowest first)
```
8036 Sources/PlaytestPM9BTests.swift:94
7385 Sources/PlaytestPM9BTests.swift:95
5371 Sources/Mob.swift:445
4121 Sources/Mob.swift:445
2685 Sources/InputMatrix.swift:83
2162 Sources/AshSites.swift:127
1151 Sources/main.swift:1379
1120 Sources/main.swift:1379
839 Sources/CapitalShips.swift:1304
776 Sources/CapitalShips.swift:1309
765 Sources/CapitalShips.swift:1304
717 Sources/CapitalShips.swift:1309
631 Sources/Cinematic.swift:141
503 Sources/Cinematic.swift:141
493 Sources/BaseTests.swift:107
486 Sources/main.swift:1379
444 Sources/BaseTests.swift:107
421 Sources/CapitalBases.swift:282
380 Sources/ShipCombat.swift:135
361 Sources/Cinematic.swift:141
315 Sources/TexturesHD.swift:2749
308 Sources/main.swift:1350
300 Sources/TexturesHD.swift:3990
278 Sources/BaseTests.swift:107
276 Sources/Mesher.swift:95
270 Sources/main.swift:1474
264 Sources/Player.swift:185
244 Sources/GameCircuit.swift:262
243 Sources/CapitalBasesWork.swift:251
242 Sources/CapitalBasesWork.swift:251
239 Sources/CapitalBasesWork.swift:251
237 Sources/Textures.swift:642
229 Sources/FlightModel.swift:113
229 Sources/Banners.swift:215
228 Sources/Ships.swift:110
225 Sources/AshSites.swift:64
218 Sources/TerrainTools.swift:81
212 Sources/GameCircuit.swift:262
211 Sources/Structures.swift:288
202 Sources/GameCircuit.swift:262
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 1248 ms, upload 708 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 12950 ms  mesh(all, parallel) 21846 ms  mesh(1 section) 112.78 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 10.09 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 151 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
