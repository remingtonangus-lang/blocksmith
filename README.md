# Blocksmith fast lane

Commit `b3acaf2661e546bebd7292f4d0bff59d509d30ae` on `claude/p304-menu-spacing`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38827335037

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
18623 Sources/BalanceTests.swift:183
13314 Sources/FriendlyFireTests.swift:86
10092 Sources/TexturesHD.swift:2068
8782 Sources/PlaytestPM9BTests.swift:95
8426 Sources/ShapeClass.swift:157
8173 Sources/PlaytestPM9BTests.swift:94
7194 Sources/TrainRoofs.swift:128
7032 Sources/RenderDistanceGovernor.swift:161
6971 Sources/ShapeClass.swift:157
6590 Sources/Fracture.swift:838
6575 Sources/Fracture.swift:838
6547 Sources/Mob.swift:556
6405 Sources/TexturesHD.swift:2064
5811 Sources/TexturesHD.swift:2064
5513 Sources/Greywall.swift:555
5122 Sources/AshVaultGapTests.swift:134
4580 Sources/Player.swift:86
4483 Sources/Mob.swift:556
3561 Sources/InputMatrix.swift:83
3435 Sources/Structures.swift:732
3249 Sources/Trains.swift:137
3114 Sources/AshSites.swift:56
2775 Sources/Mesher.swift:1076
2609 Sources/Mesher.swift:1076
2527 Sources/Mesher.swift:1076
2420 Sources/AshSites.swift:229
2415 Sources/Fracture.swift:838
2208 Sources/NavalGuns.swift:62
1922 Sources/NavalGuns.swift:62
1514 Sources/NavalGuns.swift:62
1476 Sources/DebrisField.swift:56
1458 Sources/DebrisField.swift:56
1405 Sources/Director.swift:518
1360 Sources/NavalGuns.swift:62
1273 Sources/PowerSuit.swift:28
1263 Sources/PowerSuit.swift:28
968 Sources/HellMobs.swift:456
939 Sources/GreywallAlarm.swift:344
920 Sources/main.swift:1415
919 Sources/CapitalShips.swift:1595
```
### Snapshot
```
```
![fast](fast.png)
