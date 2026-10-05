# Blocksmith fast lane

Commit `594cb12de385c68453753fb60909849fa8786782` on `claude/bs-capital-soldiers`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37309530495

### Build errors
```
```
### Type-check (warnings, slowest first)
```
1110 Sources/main.swift:1324
1102 Sources/main.swift:1324
702 Sources/CapitalShips.swift:1263
685 Sources/CapitalShips.swift:1263
584 Sources/main.swift:1324
474 Sources/BaseTests.swift:109
469 Sources/CapitalBases.swift:281
466 Sources/Cinematic.swift:141
436 Sources/ShipCombat.swift:130
435 Sources/BaseTests.swift:109
423 Sources/Cinematic.swift:141
345 Sources/TexturesHD.swift:3949
318 Sources/TexturesHD.swift:2708
305 Sources/BaseTests.swift:109
299 Sources/main.swift:1295
286 Sources/GameCircuit.swift:182
282 Sources/GameCircuit.swift:182
275 Sources/Cinematic.swift:141
269 Sources/Mesher.swift:87
262 Sources/TerrainTools.swift:81
262 Sources/FlightModel.swift:132
258 Sources/CapitalBasesWork.swift:251
257 Sources/Ships.swift:110
249 Sources/main.swift:1417
238 Sources/Player.swift:144
236 Sources/Textures.swift:601
236 Sources/PadTest.swift:727
236 Sources/GameCircuit.swift:182
216 Sources/Soldiers.swift:657
203 Sources/Music.swift:296
200 Sources/CapitalBasesWork.swift:251
197 Sources/Player.swift:275
196 Sources/CapitalBasesWork.swift:251
191 Sources/TexturesHD.swift:4482
187 Sources/Banners.swift:215
180 Sources/Soldiers.swift:657
180 Sources/Player.swift:275
174 Sources/BaseTests.swift:182
167 Sources/main.swift:1295
162 Sources/Renderer.swift:1594
```
### Snapshot
```
posecheck: 510 raised limbs checked, 0 failed
textures: 1679 layers at 16 px, BC3, 0.6 MB with mips (build 1005 ms, upload 491 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 10338 ms  mesh(all, parallel) 21821 ms  mesh(1 section) 126.02 ms  quads 301617 opaque / 2485 water
frame (encode+GPU, offscreen, median of 30) 9.87 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 147 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
