# Blocksmith fast lane

Commit `5c6706276a24e9e4e1997028b0d3f006e2831e47` on `claude/p293-loading`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38824784570

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
13168 Sources/BalanceTests.swift:183
8197 Sources/FriendlyFireTests.swift:86
7202 Sources/TexturesHD.swift:2068
5791 Sources/ShapeClass.swift:157
5768 Sources/PlaytestPM9BTests.swift:95
5511 Sources/PlaytestPM9BTests.swift:94
4843 Sources/TrainRoofs.swift:128
4530 Sources/Mob.swift:556
4445 Sources/RenderDistanceGovernor.swift:161
4321 Sources/TexturesHD.swift:2064
4171 Sources/ShapeClass.swift:157
4164 Sources/TexturesHD.swift:2064
4131 Sources/Player.swift:86
4042 Sources/Greywall.swift:555
3749 Sources/Fracture.swift:838
3744 Sources/Fracture.swift:838
3563 Sources/Mob.swift:556
3445 Sources/AshVaultGapTests.swift:134
2547 Sources/Structures.swift:732
2321 Sources/InputMatrix.swift:83
2199 Sources/Trains.swift:137
2061 Sources/AshSites.swift:56
1685 Sources/Mesher.swift:1076
1653 Sources/Mesher.swift:1076
1647 Sources/Mesher.swift:1076
1614 Sources/AshSites.swift:229
1580 Sources/NavalGuns.swift:62
1408 Sources/Fracture.swift:838
1314 Sources/NavalGuns.swift:62
1219 Sources/NavalGuns.swift:62
1202 Sources/PowerSuit.swift:28
1194 Sources/NavalGuns.swift:62
1193 Sources/PowerSuit.swift:28
803 Sources/DebrisField.swift:56
776 Sources/DebrisField.swift:56
770 Sources/Director.swift:518
761 Sources/main.swift:1415
748 Sources/Greywall.swift:771
730 Sources/Mob.swift:2613
724 Sources/main.swift:1415
```
### Snapshot
```
```
![fast](fast.png)
