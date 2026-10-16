# Blocksmith fast lane

Commit `9d98a610e20a4b513262fa5a6720f7ae27848168` on `claude/p309-drop`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38827854315

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
18467 Sources/BalanceTests.swift:183
10646 Sources/FriendlyFireTests.swift:86
9766 Sources/ShapeClass.swift:157
8648 Sources/PlaytestPM9BTests.swift:95
8231 Sources/PlaytestPM9BTests.swift:94
7978 Sources/TexturesHD.swift:2068
6631 Sources/ShapeClass.swift:157
6351 Sources/Mob.swift:556
6212 Sources/RenderDistanceGovernor.swift:161
5887 Sources/Fracture.swift:838
5264 Sources/AshVaultGapTests.swift:134
5207 Sources/Greywall.swift:555
5123 Sources/TrainRoofs.swift:128
5084 Sources/Fracture.swift:838
4955 Sources/Player.swift:86
4497 Sources/TexturesHD.swift:2064
4466 Sources/TexturesHD.swift:2064
4438 Sources/Mob.swift:556
3147 Sources/InputMatrix.swift:83
2947 Sources/AshSites.swift:56
2615 Sources/Structures.swift:732
2611 Sources/Trains.swift:137
2544 Sources/AshSites.swift:229
2434 Sources/Mesher.swift:1076
2296 Sources/Mesher.swift:1076
2245 Sources/Mesher.swift:1076
2096 Sources/NavalGuns.swift:62
1783 Sources/NavalGuns.swift:62
1781 Sources/Fracture.swift:838
1753 Sources/NavalGuns.swift:62
1624 Sources/NavalGuns.swift:62
1506 Sources/PowerSuit.swift:28
1292 Sources/PowerSuit.swift:28
1124 Sources/DebrisField.swift:56
1036 Sources/DebrisField.swift:56
1033 Sources/Mob.swift:2617
1016 Sources/Director.swift:518
981 Sources/main.swift:1415
974 Sources/Mob.swift:2617
906 Sources/Greywall.swift:771
```
### Snapshot
```
```
![fast](fast.png)
