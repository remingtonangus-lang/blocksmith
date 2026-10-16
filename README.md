# Blocksmith fast lane

Commit `282ebdb458c0e06d58ff6933adbf4b4c26195ff1` on `claude/p301-rack`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38826845081

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
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:86:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:775:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:777:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:778:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:789:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:789:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
```
### Type-check (warnings, slowest first)
```
19544 Sources/BalanceTests.swift:183
9357 Sources/TexturesHD.swift:2068
8942 Sources/FriendlyFireTests.swift:86
7543 Sources/ShapeClass.swift:157
7312 Sources/TrainRoofs.swift:128
7163 Sources/PlaytestPM9BTests.swift:95
7100 Sources/PlaytestPM9BTests.swift:94
6480 Sources/TexturesHD.swift:2064
5896 Sources/TexturesHD.swift:2064
5707 Sources/RenderDistanceGovernor.swift:161
5460 Sources/ShapeClass.swift:157
5267 Sources/Mob.swift:556
4967 Sources/Player.swift:86
4541 Sources/Fracture.swift:838
4452 Sources/Greywall.swift:555
4085 Sources/Fracture.swift:838
3850 Sources/Mob.swift:556
3733 Sources/AshVaultGapTests.swift:134
3318 Sources/Structures.swift:732
3294 Sources/Trains.swift:137
2538 Sources/InputMatrix.swift:83
2448 Sources/AshSites.swift:56
2050 Sources/Mesher.swift:1076
1945 Sources/NavalGuns.swift:62
1940 Sources/Fracture.swift:838
1797 Sources/Mesher.swift:1076
1782 Sources/Mesher.swift:1076
1732 Sources/AshSites.swift:229
1514 Sources/NavalGuns.swift:62
1434 Sources/PowerSuit.swift:28
1394 Sources/NavalGuns.swift:62
1367 Sources/PowerSuit.swift:28
1222 Sources/NavalGuns.swift:62
1200 Sources/main.swift:1415
1184 Sources/main.swift:1415
941 Sources/Mob.swift:2613
855 Sources/DebrisField.swift:56
843 Sources/DebrisField.swift:56
834 Sources/Mob.swift:2613
829 Sources/Greywall.swift:771
```
### Snapshot
```
```
![fast](fast.png)
