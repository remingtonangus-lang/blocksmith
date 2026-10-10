# Blocksmith fast lane

Commit `d9387c36fe4de9e41cbd8bf1278ea2c822c3776c` on `claude/quest-port`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38088970032

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:359:20: error: value of type 'PadManager' has no member 'touch'
    |                    `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:364:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:364:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:378:24: error: value of type 'PadManager' has no member 'touch'
    |                        `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:383:20: error: value of type 'PadManager' has no member 'touch'
    |                    `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/HorseTests.swift:383:28: error: 'nil' requires a contextual type
    |                            `- error: 'nil' requires a contextual type
```
### Type-check (warnings, slowest first)
```
6337 Sources/PlaytestPM9BTests.swift:94
6002 Sources/PlaytestPM9BTests.swift:95
5184 Sources/Mob.swift:449
5081 Sources/RenderDistanceGovernor.swift:129
3680 Sources/Mob.swift:449
2829 Sources/InputMatrix.swift:83
1546 Sources/AshSites.swift:127
977 Sources/main.swift:1416
848 Sources/main.swift:1416
601 Sources/CapitalShips.swift:1315
587 Sources/CapitalShips.swift:1315
445 Sources/Cinematic.swift:141
411 Sources/Cinematic.swift:141
403 Sources/BaseTests.swift:107
389 Sources/CapitalBases.swift:289
368 Sources/main.swift:1416
358 Sources/BaseTests.swift:107
289 Sources/Cinematic.swift:141
287 Sources/ShipCombat.swift:136
269 Sources/BaseTests.swift:107
250 Sources/MainGun.swift:184
233 Sources/TexturesHD.swift:3990
231 Sources/MainGun.swift:335
227 Sources/main.swift:1387
222 Sources/main.swift:1511
222 Sources/CapitalBasesWork.swift:251
212 Sources/Soldiers.swift:690
210 Sources/WorldGenCheck.swift:47
205 Sources/TexturesHD.swift:2749
205 Sources/Mesher.swift:96
193 Sources/FlightModel.swift:113
189 Sources/GameCircuit.swift:262
187 Sources/MainGun.swift:128
187 Sources/GameCircuit.swift:262
185 Sources/GameCircuit.swift:262
185 Sources/CapitalBasesWork.swift:251
184 Sources/Ships.swift:110
184 Sources/CapitalBasesWork.swift:251
183 Sources/Soldiers.swift:690
179 Sources/AshSites.swift:64
```
### Snapshot
```
```
![fast](fast.png)
