# Blocksmith fast lane

Commit `84c49b155e98ecd0058ed32ad2aeaab1cc337400` on `claude/blocksmith-playtest`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38861235732

### Build errors
```
```
### Type-check (warnings, slowest first)
```
557 Sources/CapitalShips.swift:1309
553 Sources/CapitalShips.swift:1309
546 Sources/CapitalShips.swift:1304
543 Sources/CapitalShips.swift:1304
373 Sources/CapitalBases.swift:282
356 Sources/BaseTests.swift:107
355 Sources/Cinematic.swift:141
354 Sources/BaseTests.swift:107
281 Sources/ShipCombat.swift:135
243 Sources/Cinematic.swift:141
237 Sources/BaseTests.swift:107
226 Sources/TexturesHD.swift:3990
211 Sources/CapitalBasesWork.swift:251
206 Sources/main.swift:1350
203 Sources/TexturesHD.swift:2749
191 Sources/Mesher.swift:95
190 Sources/CapitalBasesWork.swift:251
188 Sources/main.swift:1475
185 Sources/FlightModel.swift:113
179 Sources/GameCircuit.swift:267
178 Sources/GameCircuit.swift:267
178 Sources/CapitalBasesWork.swift:251
172 Sources/Ships.swift:110
172 Sources/GameCircuit.swift:267
166 Sources/Banners.swift:215
163 Sources/TerrainTools.swift:81
152 Sources/Textures.swift:642
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 977 ms, upload 481 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 9857 ms  mesh(all, parallel) 19448 ms  mesh(1 section) 104.21 ms  quads 312550 opaque / 533 water
frame (encode+GPU, offscreen, median of 30) 9.68 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 151 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
