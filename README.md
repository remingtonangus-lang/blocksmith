# Blocksmith fast lane

Commit `d48be3722fe0a0ccd0f2fb713b13c1b096b8074e` on `claude/p-push-test`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38819592624

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
12793 Sources/BalanceTests.swift:183
8045 Sources/FriendlyFireTests.swift:86
6928 Sources/TexturesHD.swift:2066
5555 Sources/PlaytestPM9BTests.swift:95
5529 Sources/ShapeClass.swift:157
5433 Sources/PlaytestPM9BTests.swift:94
4715 Sources/TrainRoofs.swift:128
4486 Sources/Mob.swift:553
4432 Sources/RenderDistanceGovernor.swift:161
4154 Sources/ShapeClass.swift:157
4130 Sources/TexturesHD.swift:2062
4108 Sources/TexturesHD.swift:2062
4101 Sources/Player.swift:86
4036 Sources/Greywall.swift:555
3727 Sources/Fracture.swift:838
3709 Sources/Fracture.swift:838
3468 Sources/Mob.swift:553
3287 Sources/AshVaultGapTests.swift:134
2506 Sources/Structures.swift:732
2341 Sources/InputMatrix.swift:83
2193 Sources/Trains.swift:137
2069 Sources/AshSites.swift:56
1667 Sources/Mesher.swift:1057
1653 Sources/Mesher.swift:1057
1638 Sources/Mesher.swift:1057
1598 Sources/AshSites.swift:229
1506 Sources/NavalGuns.swift:62
1386 Sources/Fracture.swift:838
1246 Sources/NavalGuns.swift:62
1204 Sources/PowerSuit.swift:28
1200 Sources/PowerSuit.swift:28
1195 Sources/NavalGuns.swift:62
1190 Sources/NavalGuns.swift:62
785 Sources/DebrisField.swift:56
768 Sources/DebrisField.swift:56
761 Sources/main.swift:1415
741 Sources/main.swift:1415
740 Sources/Greywall.swift:771
718 Sources/Mob.swift:2568
718 Sources/Director.swift:518
```
### Snapshot
```
```
![fast](fast.png)
