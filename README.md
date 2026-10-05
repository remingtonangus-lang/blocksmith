# Blocksmith fast lane

Commit `07e106d27c71d20ef4ba21091221a8f8c49c4fbc` on `claude/bs-world-fx`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37309488709

### Build errors
```
```
### Type-check (warnings, slowest first)
```
945 Sources/main.swift:1368
823 Sources/CapitalShips.swift:1263
710 Sources/Cinematic.swift:141
698 Sources/CapitalShips.swift:1263
522 Sources/ItemHD.swift:524
507 Sources/CapitalBases.swift:281
487 Sources/main.swift:1368
471 Sources/BaseTests.swift:107
468 Sources/Cinematic.swift:141
446 Sources/BaseTests.swift:107
402 Sources/main.swift:1461
369 Sources/ItemHD.swift:477
350 Sources/ShipCombat.swift:130
350 Sources/BaseTests.swift:107
341 Sources/Mesher.swift:87
341 Sources/ItemHD.swift:452
339 Sources/ItemHDGear.swift:664
331 Sources/Cinematic.swift:141
322 Sources/ItemHD.swift:338
318 Sources/ItemHD.swift:727
306 Sources/ItemHD.swift:726
303 Sources/ItemHDGear.swift:664
297 Sources/main.swift:1339
297 Sources/Ships.swift:110
292 Sources/ItemHD.swift:337
290 Sources/ItemHD.swift:524
278 Sources/ItemHDGear.swift:664
262 Sources/TexturesHD.swift:3949
259 Sources/CapitalBasesWork.swift:251
255 Sources/Soldiers.swift:656
255 Sources/ItemHD.swift:510
251 Sources/CapitalBasesWork.swift:251
251 Sources/Banners.swift:215
246 Sources/Soldiers.swift:656
246 Sources/GameCircuit.swift:182
245 Sources/CapitalBasesWork.swift:251
236 Sources/GameCircuit.swift:182
223 Sources/ItemHD.swift:524
221 Sources/GameCircuit.swift:182
221 Sources/FlightModel.swift:113
```
### Snapshot
```
posecheck: 510 raised limbs checked, 0 failed
textures: 1785 layers at 16 px, BC3, 0.6 MB with mips (build 2018 ms, upload 667 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 10300 ms  mesh(all, parallel) 21738 ms  mesh(1 section) 123.80 ms  quads 301617 opaque / 2485 water
frame (encode+GPU, offscreen, median of 30) 14.82 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 114 MB
memory: resident 147 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
