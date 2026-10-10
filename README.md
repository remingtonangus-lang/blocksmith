# Blocksmith fast lane

Commit `95e8eed144c9eddb207e90e53fc6100d876c2a8b` on `claude/siberia-base-18qcso`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38015807040

### Build errors
```
```
### Type-check (warnings, slowest first)
```
7344 Sources/PlaytestPM9BTests.swift:94
7324 Sources/PlaytestPM9BTests.swift:95
6090 Sources/Mob.swift:447
4543 Sources/Mob.swift:447
2880 Sources/InputMatrix.swift:83
1867 Sources/AshSites.swift:127
1046 Sources/main.swift:1386
991 Sources/main.swift:1386
657 Sources/CapitalShips.swift:1309
646 Sources/CapitalShips.swift:1309
639 Sources/CapitalShips.swift:1304
605 Sources/CapitalShips.swift:1304
463 Sources/main.swift:1386
450 Sources/Cinematic.swift:141
430 Sources/Cinematic.swift:141
366 Sources/ShipCombat.swift:135
361 Sources/CapitalBases.swift:284
352 Sources/BaseTests.swift:107
351 Sources/BaseTests.swift:107
301 Sources/Mesher.swift:95
291 Sources/main.swift:1357
280 Sources/TexturesHD.swift:3990
263 Sources/Cinematic.swift:141
258 Sources/Ships.swift:110
255 Sources/main.swift:1481
249 Sources/CapitalBasesWork.swift:251
248 Sources/TerrainTools.swift:81
237 Sources/GameCircuit.swift:262
233 Sources/BaseTests.swift:107
230 Sources/CapitalBasesWork.swift:251
228 Sources/TexturesHD.swift:2749
220 Sources/CapitalBasesWork.swift:251
216 Sources/PadTest.swift:750
214 Sources/GameCircuit.swift:262
203 Sources/Game.swift:1922
201 Sources/Music.swift:298
199 Sources/GameCircuit.swift:262
194 Sources/Player.swift:189
193 Sources/Player.swift:349
190 Sources/FlightModel.swift:113
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1721 layers at 16 px, BC3, 0.6 MB with mips (build 1352 ms, upload 646 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 13166 ms  mesh(all, parallel) 24423 ms  mesh(1 section) 133.53 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 11.03 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 148 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
