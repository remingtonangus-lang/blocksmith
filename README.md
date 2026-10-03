# Blocksmith fast lane

Commit `0823106580590876fddad4ea83ff3aeae17bb399` on `claude/happy-brown-mr5q6z`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37082866203

### Build errors
```
```
### Type-check (warnings, slowest first)
```
981 Sources/main.swift:1272
918 Sources/main.swift:1272
801 Sources/CapitalShips.swift:953
755 Sources/CapitalShips.swift:953
464 Sources/main.swift:1272
393 Sources/ShipCombat.swift:129
305 Sources/TexturesHD.swift:2708
275 Sources/TexturesHD.swift:3949
264 Sources/GameCircuit.swift:178
261 Sources/Mesher.swift:87
251 Sources/GameCircuit.swift:178
245 Sources/Textures.swift:601
244 Sources/Ships.swift:108
228 Sources/GameCircuit.swift:178
227 Sources/Banners.swift:215
222 Sources/main.swift:1243
213 Sources/PadTest.swift:631
213 Sources/Music.swift:296
201 Sources/Banners.swift:88
193 Sources/Player.swift:246
186 Sources/Player.swift:122
185 Sources/TerrainTools.swift:81
185 Sources/Player.swift:246
179 Sources/App.swift:453
157 Sources/Game.swift:1576
156 Sources/TexturesHD.swift:4482
155 Sources/main.swift:1243
```
### Snapshot
```
textures without a painter: missing
textures: 1668 layers at 16 px, BC3, 0.6 MB with mips (build 1114 ms, upload 545 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0001 white=0.0008 std=39.4 hash=d2dbb1c6ba08bb3c
imagecheck fast.png magenta=0.00000 black=0.0001 white=0.0008 std=39.4 hash=d2dbb1c6ba08bb3c
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 9647 ms  mesh(all, parallel) 22351 ms  mesh(1 section) 125.01 ms  quads 301741 opaque / 2453 water
frame (encode+GPU, offscreen, median of 30) 4.22 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 114 MB
memory: resident 144 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
