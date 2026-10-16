# Blocksmith fast lane

Commit `886845a42dcd74e651325187337f82ee9d47395d` on `claude/p307-spawns`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38827958769

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
18292 Sources/BalanceTests.swift:183
8265 Sources/FriendlyFireTests.swift:86
7023 Sources/TexturesHD.swift:2068
5485 Sources/PlaytestPM9BTests.swift:95
5458 Sources/PlaytestPM9BTests.swift:94
5427 Sources/ShapeClass.swift:157
4777 Sources/TrainRoofs.swift:128
4748 Sources/Mob.swift:556
4563 Sources/RenderDistanceGovernor.swift:161
4233 Sources/Player.swift:86
4217 Sources/TexturesHD.swift:2064
4203 Sources/ShapeClass.swift:157
4163 Sources/Greywall.swift:555
3989 Sources/TexturesHD.swift:2064
3809 Sources/Fracture.swift:838
3748 Sources/Fracture.swift:838
3620 Sources/Mob.swift:556
3480 Sources/AshVaultGapTests.swift:134
2575 Sources/Structures.swift:732
2320 Sources/InputMatrix.swift:83
2237 Sources/Trains.swift:137
2108 Sources/AshSites.swift:56
1716 Sources/Mesher.swift:1076
1659 Sources/Mesher.swift:1076
1656 Sources/Mesher.swift:1076
1581 Sources/NavalGuns.swift:62
1547 Sources/AshSites.swift:229
1360 Sources/Fracture.swift:838
1271 Sources/NavalGuns.swift:62
1258 Sources/NavalGuns.swift:62
1255 Sources/NavalGuns.swift:62
1200 Sources/PowerSuit.swift:28
1193 Sources/PowerSuit.swift:28
785 Sources/DebrisField.swift:56
779 Sources/Director.swift:518
778 Sources/DebrisField.swift:56
765 Sources/main.swift:1415
762 Sources/Greywall.swift:771
760 Sources/main.swift:1415
751 Sources/Mob.swift:2617
```
### Snapshot
```
```
![fast](fast.png)
