# Blocksmith fast lane

Commit `8d21d6fb33ddd57f22e2720629b51558786f2c6f` on `claude/project-thread-j7cbv2`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38088583180

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
/Users/runner/work/blocksmith/blocksmith/Sources/VRMeleeTests.swift:60:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
33841 Sources/VRMeleeTests.swift:60
7590 Sources/PlaytestPM9BTests.swift:94
6672 Sources/RenderDistanceGovernor.swift:129
6627 Sources/PlaytestPM9BTests.swift:95
6257 Sources/Mob.swift:449
4331 Sources/Mob.swift:449
3271 Sources/InputMatrix.swift:83
1693 Sources/AshSites.swift:127
986 Sources/main.swift:1416
937 Sources/main.swift:1416
654 Sources/CapitalShips.swift:1315
644 Sources/CapitalShips.swift:1315
502 Sources/CapitalBases.swift:289
481 Sources/Cinematic.swift:141
479 Sources/main.swift:1416
432 Sources/Cinematic.swift:141
408 Sources/ShipCombat.swift:136
375 Sources/TexturesHD.swift:3990
369 Sources/BaseTests.swift:107
367 Sources/BaseTests.swift:107
346 Sources/TexturesHD.swift:2749
334 Sources/MainGun.swift:335
304 Sources/main.swift:1387
289 Sources/MainGun.swift:184
283 Sources/main.swift:1511
283 Sources/Cinematic.swift:141
280 Sources/Mesher.swift:96
277 Sources/WorldGenCheck.swift:47
271 Sources/GameCircuit.swift:262
263 Sources/GameCircuit.swift:262
256 Sources/GameCircuit.swift:262
255 Sources/BaseTests.swift:107
249 Sources/MainGun.swift:128
239 Sources/FlightModel.swift:113
237 Sources/CapitalBasesWork.swift:251
234 Sources/Player.swift:190
233 Sources/Textures.swift:642
226 Sources/Soldiers.swift:690
225 Sources/Player.swift:350
215 Sources/CapitalBasesWork.swift:251
```
### Snapshot
```
```
![fast](fast.png)
