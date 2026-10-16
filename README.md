# Blocksmith fast lane

Commit `1cb4d1f798c3a6ba630d2b97bded7fa6a9de9333` on `claude/p311-body-collision`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38846229221

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
18045 Sources/BalanceTests.swift:183
8124 Sources/FriendlyFireTests.swift:86
6998 Sources/TexturesHD.swift:2068
5633 Sources/ShapeClass.swift:157
5609 Sources/PlaytestPM9BTests.swift:94
5556 Sources/PlaytestPM9BTests.swift:95
4860 Sources/TrainRoofs.swift:128
4659 Sources/RenderDistanceGovernor.swift:161
4518 Sources/Mob.swift:557
4360 Sources/TexturesHD.swift:2064
4242 Sources/ShapeClass.swift:157
4127 Sources/TexturesHD.swift:2064
4090 Sources/Greywall.swift:555
4061 Sources/Player.swift:87
3876 Sources/Fracture.swift:838
3799 Sources/Fracture.swift:838
3517 Sources/Mob.swift:557
3359 Sources/AshVaultGapTests.swift:134
2522 Sources/Structures.swift:732
2337 Sources/InputMatrix.swift:83
2335 Sources/Trains.swift:137
2076 Sources/AshSites.swift:56
1724 Sources/Mesher.swift:1076
1670 Sources/Mesher.swift:1076
1652 Sources/Mesher.swift:1076
1538 Sources/AshSites.swift:229
1524 Sources/NavalGuns.swift:62
1395 Sources/Fracture.swift:838
1247 Sources/NavalGuns.swift:62
1237 Sources/NavalGuns.swift:62
1220 Sources/PowerSuit.swift:28
1218 Sources/NavalGuns.swift:62
1210 Sources/PowerSuit.swift:28
763 Sources/Director.swift:518
762 Sources/main.swift:1415
762 Sources/Greywall.swift:771
761 Sources/Mob.swift:2660
760 Sources/DebrisField.swift:56
755 Sources/DebrisField.swift:56
734 Sources/main.swift:1415
```
### Snapshot
```
```
![fast](fast.png)
