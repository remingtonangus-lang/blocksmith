# Blocksmith fast lane

Commit `915cdc953ad1258924c5d9cc1dda285dbc3a4348` on `claude/cloud-quest-build-chkowz`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37980886298

### Build errors
```
```
### Type-check (warnings, slowest first)
```
4656 Sources/Mob.swift:444
3527 Sources/Mob.swift:444
2344 Sources/InputMatrix.swift:83
1598 Sources/AshSites.swift:127
745 Sources/main.swift:1379
743 Sources/main.swift:1379
576 Sources/CapitalShips.swift:1309
567 Sources/CapitalShips.swift:1309
561 Sources/CapitalShips.swift:1304
555 Sources/CapitalShips.swift:1304
504 Sources/CapitalBases.swift:282
474 Sources/BaseTests.swift:107
399 Sources/BaseTests.swift:107
378 Sources/Cinematic.swift:141
372 Sources/Cinematic.swift:141
356 Sources/main.swift:1379
301 Sources/ShipCombat.swift:135
256 Sources/TexturesHD.swift:3990
247 Sources/BaseTests.swift:107
246 Sources/Cinematic.swift:141
224 Sources/main.swift:1350
214 Sources/CapitalBasesWork.swift:251
197 Sources/TexturesHD.swift:2749
196 Sources/Mesher.swift:95
194 Sources/GameCircuit.swift:195
192 Sources/GameCircuit.swift:195
190 Sources/main.swift:1473
187 Sources/FlightModel.swift:113
187 Sources/CapitalBasesWork.swift:251
186 Sources/TerrainTools.swift:81
186 Sources/GameCircuit.swift:195
181 Sources/Ships.swift:110
175 Sources/CapitalBasesWork.swift:251
165 Sources/Banners.swift:215
164 Sources/Music.swift:298
159 Sources/AshSites.swift:64
156 Sources/Textures.swift:642
151 Sources/Player.swift:178
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1710 layers at 16 px, BC3, 0.6 MB with mips (build 946 ms, upload 464 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.0 hash=62a5b9e467a86e9f
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.0 hash=62a5b9e467a86e9f
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 9837 ms  mesh(all, parallel) 18466 ms  mesh(1 section) 119.81 ms  quads 316293 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 9.73 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 149 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
