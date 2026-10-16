# Blocksmith fast lane

Commit `34e73de7f33d7f04118746a1e252490e5307819e` on `claude/bs-world-fx`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38855915298

### Build errors
```
```
### Type-check (warnings, slowest first)
```
6639 Sources/PlaytestPM9BTests.swift:94
6020 Sources/PlaytestPM9BTests.swift:95
4617 Sources/Mob.swift:445
4029 Sources/Mob.swift:445
2613 Sources/InputMatrix.swift:83
1644 Sources/AshSites.swift:127
806 Sources/main.swift:1424
787 Sources/main.swift:1424
710 Sources/CapitalShips.swift:1309
655 Sources/CapitalShips.swift:1309
617 Sources/CapitalShips.swift:1304
605 Sources/CapitalShips.swift:1304
504 Sources/CapitalBases.swift:282
462 Sources/ItemHD.swift:525
427 Sources/Cinematic.swift:141
395 Sources/Cinematic.swift:141
388 Sources/BaseTests.swift:107
356 Sources/main.swift:1424
353 Sources/BaseTests.swift:107
343 Sources/ItemHD.swift:728
329 Sources/ShipCombat.swift:135
310 Sources/Cinematic.swift:141
298 Sources/ItemHDGear.swift:740
296 Sources/ItemHD.swift:339
294 Sources/BaseTests.swift:107
291 Sources/ItemHD.swift:511
286 Sources/ItemHD.swift:478
273 Sources/ItemHD.swift:729
263 Sources/TexturesHD.swift:3990
262 Sources/ItemHD.swift:525
260 Sources/ItemHD.swift:453
254 Sources/main.swift:1519
253 Sources/ItemHD.swift:338
252 Sources/ItemHDGear.swift:740
234 Sources/Mesher.swift:95
233 Sources/ItemHDGear.swift:740
233 Sources/ItemHD.swift:525
230 Sources/main.swift:1395
227 Sources/CapitalBasesWork.swift:251
223 Sources/GameCircuit.swift:262
```
### Snapshot
```
posecheck: 551 raised limbs checked, 0 failed
textures: 1821 layers at 16 px, BC3, 0.6 MB with mips (build 2170 ms, upload 767 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 12104 ms  mesh(all, parallel) 20416 ms  mesh(1 section) 146.81 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 11.66 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 114 MB
memory: resident 147 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
