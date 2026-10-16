# Blocksmith fast lane

Commit `b52a1374213cfff11b21291cce0575c91272a95f` on `claude/p291-hell-drop`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38825296525

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
13078 Sources/BalanceTests.swift:183
8162 Sources/FriendlyFireTests.swift:86
6760 Sources/TexturesHD.swift:2068
6457 Sources/ShapeClass.swift:157
5999 Sources/PlaytestPM9BTests.swift:95
5375 Sources/PlaytestPM9BTests.swift:94
4817 Sources/TrainRoofs.swift:128
4547 Sources/RenderDistanceGovernor.swift:161
4529 Sources/Mob.swift:556
4334 Sources/TexturesHD.swift:2064
4276 Sources/TexturesHD.swift:2064
4108 Sources/ShapeClass.swift:157
4097 Sources/Player.swift:86
4049 Sources/Greywall.swift:555
3779 Sources/Fracture.swift:838
3756 Sources/Fracture.swift:838
3533 Sources/AshVaultGapTests.swift:134
3433 Sources/Mob.swift:556
2645 Sources/Structures.swift:732
2315 Sources/Trains.swift:137
2254 Sources/InputMatrix.swift:83
2086 Sources/AshSites.swift:56
1657 Sources/Mesher.swift:1076
1644 Sources/Mesher.swift:1076
1642 Sources/Mesher.swift:1076
1545 Sources/AshSites.swift:229
1520 Sources/NavalGuns.swift:62
1401 Sources/Fracture.swift:838
1266 Sources/PowerSuit.swift:28
1254 Sources/NavalGuns.swift:62
1233 Sources/NavalGuns.swift:62
1222 Sources/NavalGuns.swift:62
1217 Sources/PowerSuit.swift:28
796 Sources/DebrisField.swift:56
768 Sources/main.swift:1415
767 Sources/main.swift:1415
767 Sources/DebrisField.swift:56
751 Sources/Mob.swift:2613
735 Sources/Greywall.swift:771
734 Sources/Director.swift:518
```
### Snapshot
```
```
![fast](fast.png)
