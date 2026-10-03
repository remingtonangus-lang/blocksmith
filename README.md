# Blocksmith fast lane

Commit `2c0a7ed8170ad9fae56af6ab8f53655bd5586a60` on `claude/blocksmith-playtest`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37156221180

### Build errors
```
```
### Type-check (warnings, slowest first)
```
876 Sources/main.swift:1272
850 Sources/main.swift:1272
805 Sources/CapitalShips.swift:953
803 Sources/CapitalShips.swift:953
427 Sources/main.swift:1272
353 Sources/ShipCombat.swift:129
295 Sources/Mesher.swift:87
285 Sources/Banners.swift:215
258 Sources/Animals.swift:421
242 Sources/GameCircuit.swift:178
231 Sources/TexturesHD.swift:3949
230 Sources/main.swift:1243
228 Sources/Animals.swift:421
227 Sources/Ballistics.swift:464
218 Sources/TexturesHD.swift:2708
218 Sources/Ships.swift:108
214 Sources/GameCircuit.swift:178
201 Sources/GameCircuit.swift:178
194 Sources/Ballistics.swift:464
186 Sources/TerrainTools.swift:81
174 Sources/Banners.swift:88
173 Sources/CapitalShips.swift:1144
172 Sources/Banners.swift:88
168 Sources/Player.swift:246
166 Sources/Textures.swift:601
163 Sources/Player.swift:122
157 Sources/Animals.swift:430
154 Sources/Player.swift:246
153 Sources/PadTest.swift:631
```
### Snapshot
```
textures without a painter: missing
textures: 1668 layers at 16 px, BC3, 0.6 MB with mips (build 1059 ms, upload 546 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=39.3 hash=2102d462d56929af
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=39.3 hash=2102d462d56929af
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 8717 ms  mesh(all, parallel) 19892 ms  mesh(1 section) 131.36 ms  quads 301741 opaque / 2453 water
frame (encode+GPU, offscreen, median of 30) 4.24 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 114 MB
memory: resident 150 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
