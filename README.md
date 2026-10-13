# Blocksmith fast lane

Commit `9bad91248f27f5f58bff4e0db85b521765f4f553` on `claude/project-thread-qgi3ub`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38472186919

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
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
```
### Type-check (warnings, slowest first)
```
34343 Sources/BalanceTests.swift:183
10096 Sources/FriendlyFireTests.swift:86
9292 Sources/TexturesHD.swift:2066
7323 Sources/ShapeClass.swift:157
6999 Sources/PlaytestPM9BTests.swift:95
6508 Sources/AshSites.swift:56
5875 Sources/PlaytestPM9BTests.swift:94
5741 Sources/Fracture.swift:838
5690 Sources/RenderDistanceGovernor.swift:146
5502 Sources/ShapeClass.swift:157
5499 Sources/AshVaultGapTests.swift:134
5327 Sources/Mob.swift:518
5320 Sources/Fracture.swift:838
5100 Sources/AshSites.swift:229
4850 Sources/TexturesHD.swift:2062
4725 Sources/TexturesHD.swift:2062
4577 Sources/Greywall.swift:531
4069 Sources/Mob.swift:518
2941 Sources/InputMatrix.swift:83
2412 Sources/Mesher.swift:992
2386 Sources/Trains.swift:131
2226 Sources/Fracture.swift:838
2169 Sources/Mesher.swift:992
2033 Sources/Mesher.swift:992
1358 Sources/PowerSuit.swift:28
1345 Sources/PowerSuit.swift:28
1293 Sources/DebrisField.swift:56
1284 Sources/DebrisField.swift:56
999 Sources/HellMobs.swift:455
984 Sources/DeepGapTests.swift:331
968 Sources/HellMobs.swift:455
899 Sources/CapitalShips.swift:1536
890 Sources/CapitalShips.swift:1536
859 Sources/main.swift:1415
847 Sources/Greywall.swift:738
828 Sources/CapitalBases.swift:377
775 Sources/main.swift:1415
769 Sources/CapitalBasesWork.swift:285
680 Sources/GreywallAlarm.swift:330
668 Sources/DeepGapTests.swift:331
```
### Snapshot
```
```
![fast](fast.png)
