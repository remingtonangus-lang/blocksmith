# Blocksmith fast lane

Commit `aed8937e8d326d9795038b1e0c313f8ec84881db` on `claude/bs-destruction`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37309446473

### Build errors
```
```
### Type-check (warnings, slowest first)
```
836 Sources/main.swift:1322
805 Sources/main.swift:1322
646 Sources/Cinematic.swift:141
631 Sources/BaseTests.swift:94
622 Sources/BaseTests.swift:94
609 Sources/Cinematic.swift:141
554 Sources/BaseTests.swift:94
523 Sources/CapitalBases.swift:250
452 Sources/ShipCombat.swift:130
406 Sources/BaseTests.swift:94
404 Sources/main.swift:1322
385 Sources/Cinematic.swift:141
362 Sources/TexturesHD.swift:3949
338 Sources/TerrainTools.swift:81
338 Sources/FlightModel.swift:113
320 Sources/Banners.swift:215
319 Sources/GameCircuit.swift:178
307 Sources/GameCircuit.swift:178
306 Sources/TexturesHD.swift:2708
298 Sources/GameCircuit.swift:178
264 Sources/Mesher.swift:87
263 Sources/CapitalBasesWork.swift:251
259 Sources/main.swift:1293
257 Sources/BaseTests.swift:159
254 Sources/Textures.swift:601
253 Sources/Ships.swift:110
246 Sources/CapitalBasesWork.swift:251
236 Sources/main.swift:1293
229 Sources/Music.swift:296
225 Sources/CapitalBasesWork.swift:251
224 Sources/Villager.swift:82
223 Sources/PadTest.swift:727
214 Sources/Animals.swift:421
213 Sources/Player.swift:123
205 Sources/Player.swift:247
200 Sources/Banners.swift:88
198 Sources/main.swift:1293
198 Sources/Animals.swift:421
193 Sources/main.swift:1415
189 Sources/Player.swift:247
```
### Snapshot
```
posecheck: 510 raised limbs checked, 0 failed
textures without a painter: missing
textures: 1680 layers at 16 px, BC3, 0.6 MB with mips (build 1354 ms, upload 685 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 9384 ms  mesh(all, parallel) 19008 ms  mesh(1 section) 158.07 ms  quads 301613 opaque / 2485 water
frame (encode+GPU, offscreen, median of 30) 20.40 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 144 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
