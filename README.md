# Blocksmith fast lane

Commit `dc4ee63ccb4f10209f4b1b4f7d4d5d08d17d6eab` on `claude/p317-items`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38846687857

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
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:87:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
17142 Sources/BalanceTests.swift:183
12277 Sources/FriendlyFireTests.swift:86
10498 Sources/TexturesHD.swift:2068
8129 Sources/ShapeClass.swift:157
7778 Sources/PlaytestPM9BTests.swift:95
7755 Sources/PlaytestPM9BTests.swift:94
7293 Sources/TrainRoofs.swift:128
6494 Sources/RenderDistanceGovernor.swift:161
6425 Sources/Mob.swift:557
6116 Sources/TexturesHD.swift:2064
6035 Sources/ShapeClass.swift:157
5970 Sources/TexturesHD.swift:2064
5901 Sources/Player.swift:87
5647 Sources/Greywall.swift:555
5235 Sources/Fracture.swift:838
5131 Sources/Fracture.swift:838
4741 Sources/Mob.swift:557
4537 Sources/AshVaultGapTests.swift:134
3506 Sources/Structures.swift:732
3276 Sources/InputMatrix.swift:83
3079 Sources/Trains.swift:137
2868 Sources/AshSites.swift:56
2320 Sources/Mesher.swift:1076
2313 Sources/Mesher.swift:1076
2226 Sources/Mesher.swift:1076
2172 Sources/NavalGuns.swift:62
2095 Sources/AshSites.swift:229
1833 Sources/Fracture.swift:838
1753 Sources/NavalGuns.swift:62
1732 Sources/PowerSuit.swift:28
1712 Sources/PowerSuit.swift:28
1698 Sources/NavalGuns.swift:62
1641 Sources/NavalGuns.swift:62
1107 Sources/main.swift:1415
1084 Sources/Greywall.swift:771
1082 Sources/DebrisField.swift:56
1031 Sources/main.swift:1415
1024 Sources/Mob.swift:2660
1016 Sources/DebrisField.swift:56
994 Sources/HellMobs.swift:462
```
### Snapshot
```
```
![fast](fast.png)
