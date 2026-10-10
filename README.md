# Blocksmith fast lane

Commit `177237a70ad0d4d1216cb721a823cb5b0eb836c9` on `claude/project-thread-j7cbv2`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38089113969

### Build errors
```
```
### Type-check (warnings, slowest first)
```
7554 Sources/PlaytestPM9BTests.swift:94
7268 Sources/PlaytestPM9BTests.swift:95
5557 Sources/Mob.swift:449
5164 Sources/RenderDistanceGovernor.swift:129
4182 Sources/Mob.swift:449
2717 Sources/InputMatrix.swift:83
1982 Sources/AshSites.swift:127
870 Sources/main.swift:1416
843 Sources/CapitalShips.swift:1315
771 Sources/main.swift:1416
749 Sources/CapitalShips.swift:1315
524 Sources/BaseTests.swift:107
463 Sources/BaseTests.swift:107
450 Sources/ShipCombat.swift:136
425 Sources/Cinematic.swift:141
415 Sources/Cinematic.swift:141
396 Sources/CapitalBases.swift:289
378 Sources/CapitalBasesWork.swift:251
367 Sources/main.swift:1387
348 Sources/TexturesHD.swift:2749
345 Sources/main.swift:1511
343 Sources/WorldGenCheck.swift:47
342 Sources/main.swift:1416
316 Sources/CapitalBasesWork.swift:251
288 Sources/TerrainTools.swift:81
285 Sources/BaseTests.swift:107
278 Sources/GameCircuit.swift:262
276 Sources/TexturesHD.swift:3990
274 Sources/Cinematic.swift:141
262 Sources/CapitalBasesWork.swift:251
248 Sources/Banners.swift:215
245 Sources/MainGun.swift:184
240 Sources/MainGun.swift:335
232 Sources/GameCircuit.swift:262
229 Sources/Textures.swift:642
229 Sources/FlightModel.swift:113
206 Sources/Player.swift:350
206 Sources/Mesher.swift:96
206 Sources/MainGun.swift:128
196 Sources/AshSites.swift:64
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1721 layers at 16 px, BC3, 0.6 MB with mips (build 1384 ms, upload 556 ms)
target: grass_block at 29 136 26, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(31.5, 136.0, 29.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 11709 ms  mesh(all, parallel) 26393 ms  mesh(1 section) 145.91 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 12.67 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 154 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
