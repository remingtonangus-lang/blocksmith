# Blocksmith fast lane

Commit `d4bd471ad8b00385428fdc1dc2ae966f2c965072` on `claude/polygon-ground-up-0ah37u`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38442393878

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:38:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:38:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:62:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:72:20: error: value of type 'PadManager' has no member 'touch'
    |                    `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:74:34: error: value of type 'PadManager' has no member 'touch'
    |                                  `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/InputLatencyTests.swift:76:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:774:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:776:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:777:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:788:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:788:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:813:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:814:63: error: value of type 'PadManager' has no member 'touch'
    |                                                               `- error: value of type 'PadManager' has no member 'touch'
```
### Type-check (warnings, slowest first)
```
17509 Sources/BalanceTests.swift:183
10187 Sources/FriendlyFireTests.swift:86
9211 Sources/TexturesHD.swift:2051
7276 Sources/Mob.swift:512
6979 Sources/PlaytestPM9BTests.swift:94
6754 Sources/PlaytestPM9BTests.swift:95
6599 Sources/RenderDistanceGovernor.swift:146
6024 Sources/Greywall.swift:529
5813 Sources/TexturesHD.swift:2047
5157 Sources/Mob.swift:512
5087 Sources/TexturesHD.swift:2047
4745 Sources/AshVaultGapTests.swift:134
3027 Sources/InputMatrix.swift:83
2935 Sources/AshSites.swift:56
2736 Sources/Trains.swift:131
2345 Sources/AshSites.swift:229
1186 Sources/Greywall.swift:736
1184 Sources/main.swift:1415
1060 Sources/main.swift:1415
991 Sources/HellMobs.swift:434
933 Sources/HellMobs.swift:434
906 Sources/CapitalShips.swift:1525
847 Sources/CapitalShips.swift:1525
683 Sources/DeepGapTests.swift:331
602 Sources/Soldiers.swift:426
586 Sources/DeepGapTests.swift:331
563 Sources/CapitalBases.swift:372
558 Sources/Soldiers.swift:426
506 Sources/HorseGapTests.swift:355
488 Sources/PlaytestOct12PMTests.swift:90
482 Sources/Soldiers.swift:426
471 Sources/Soldiers.swift:426
468 Sources/MainGunTests.swift:452
443 Sources/BaseTests.swift:121
441 Sources/PlaytestOct12PMTests.swift:90
439 Sources/Cinematic.swift:141
434 Sources/PlaytestOct12PMTests.swift:95
431 Sources/HorseGapTests.swift:353
425 Sources/HorseGapTests.swift:355
420 Sources/PlaytestOct12PMTests.swift:92
```
### Snapshot
```
```
![fast](fast.png)
