# Blocksmith fast lane

Commit `90dccf9703af468e7d3187f912656adfb74ff5d5` on `claude/p280-island`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38823015898

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
12785 Sources/BalanceTests.swift:183
8208 Sources/FriendlyFireTests.swift:86
6739 Sources/TexturesHD.swift:2066
5471 Sources/PlaytestPM9BTests.swift:94
5458 Sources/ShapeClass.swift:157
5443 Sources/PlaytestPM9BTests.swift:95
4762 Sources/TrainRoofs.swift:128
4469 Sources/Mob.swift:556
4382 Sources/RenderDistanceGovernor.swift:161
4075 Sources/TexturesHD.swift:2062
4073 Sources/ShapeClass.swift:157
4069 Sources/TexturesHD.swift:2062
4068 Sources/Player.swift:86
4051 Sources/Greywall.swift:555
3755 Sources/Fracture.swift:838
3738 Sources/Fracture.swift:838
3474 Sources/Mob.swift:556
3289 Sources/AshVaultGapTests.swift:134
2524 Sources/Structures.swift:732
2320 Sources/InputMatrix.swift:83
2196 Sources/Trains.swift:137
2081 Sources/AshSites.swift:56
1659 Sources/Mesher.swift:1057
1652 Sources/Mesher.swift:1057
1639 Sources/Mesher.swift:1057
1526 Sources/AshSites.swift:229
1524 Sources/NavalGuns.swift:62
1406 Sources/Fracture.swift:838
1246 Sources/NavalGuns.swift:62
1212 Sources/NavalGuns.swift:62
1210 Sources/NavalGuns.swift:62
1200 Sources/PowerSuit.swift:28
1194 Sources/PowerSuit.swift:28
781 Sources/main.swift:1415
759 Sources/DebrisField.swift:56
758 Sources/DebrisField.swift:56
756 Sources/main.swift:1415
750 Sources/Greywall.swift:771
728 Sources/Mob.swift:2613
726 Sources/Director.swift:518
```
### Snapshot
```
```
![fast](fast.png)
