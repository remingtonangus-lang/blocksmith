# Blocksmith fast lane

Commit `7f3c87b97032545a5ce9cfa829651bdaf38375d4` on `claude/p282-drive-hands`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38822514642

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
17388 Sources/BalanceTests.swift:183
11963 Sources/TexturesHD.swift:2066
11095 Sources/FriendlyFireTests.swift:86
7920 Sources/ShapeClass.swift:157
7673 Sources/PlaytestPM9BTests.swift:94
7623 Sources/PlaytestPM9BTests.swift:95
6884 Sources/TrainRoofs.swift:128
6580 Sources/Mob.swift:556
6388 Sources/RenderDistanceGovernor.swift:161
5987 Sources/ShapeClass.swift:157
5579 Sources/Player.swift:86
5486 Sources/Greywall.swift:555
5202 Sources/TexturesHD.swift:2062
5100 Sources/Fracture.swift:838
5063 Sources/TexturesHD.swift:2062
4785 Sources/Fracture.swift:838
4663 Sources/Mob.swift:556
4311 Sources/Trains.swift:137
4285 Sources/AshVaultGapTests.swift:134
3059 Sources/InputMatrix.swift:83
2908 Sources/Structures.swift:732
2774 Sources/AshSites.swift:56
2468 Sources/AshSites.swift:229
2370 Sources/Mesher.swift:1057
2334 Sources/NavalGuns.swift:62
2149 Sources/Mesher.swift:1057
1974 Sources/Mesher.swift:1057
1809 Sources/Fracture.swift:838
1724 Sources/NavalGuns.swift:62
1705 Sources/NavalGuns.swift:62
1678 Sources/PowerSuit.swift:28
1670 Sources/NavalGuns.swift:62
1653 Sources/PowerSuit.swift:28
1359 Sources/main.swift:1415
1271 Sources/main.swift:1415
1209 Sources/DebrisField.swift:56
1084 Sources/Mob.swift:2611
1079 Sources/DebrisField.swift:56
1012 Sources/Mob.swift:2611
989 Sources/Mob.swift:2611
```
### Snapshot
```
```
![fast](fast.png)
