# Blocksmith fast lane

Commit `382204544c79f38640bc60270ec0c5d9b4fc1973` on `claude/p316-icons`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38846249373

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
13214 Sources/BalanceTests.swift:183
8402 Sources/FriendlyFireTests.swift:86
6912 Sources/TexturesHD.swift:2068
5699 Sources/ShapeClass.swift:157
5562 Sources/PlaytestPM9BTests.swift:94
5437 Sources/PlaytestPM9BTests.swift:95
4778 Sources/TrainRoofs.swift:128
4718 Sources/RenderDistanceGovernor.swift:161
4564 Sources/Mob.swift:556
4183 Sources/ShapeClass.swift:157
4153 Sources/Player.swift:86
4114 Sources/Greywall.swift:555
4107 Sources/TexturesHD.swift:2064
4072 Sources/TexturesHD.swift:2064
3843 Sources/Fracture.swift:838
3810 Sources/Fracture.swift:838
3535 Sources/Mob.swift:556
3494 Sources/AshVaultGapTests.swift:134
2548 Sources/Structures.swift:732
2478 Sources/InputMatrix.swift:83
2240 Sources/Trains.swift:137
2106 Sources/AshSites.swift:56
1702 Sources/Mesher.swift:1076
1689 Sources/Mesher.swift:1076
1655 Sources/Mesher.swift:1076
1571 Sources/AshSites.swift:229
1528 Sources/NavalGuns.swift:62
1386 Sources/Fracture.swift:838
1250 Sources/NavalGuns.swift:62
1242 Sources/NavalGuns.swift:62
1223 Sources/PowerSuit.swift:28
1223 Sources/NavalGuns.swift:62
1216 Sources/PowerSuit.swift:28
770 Sources/DebrisField.swift:56
765 Sources/DebrisField.swift:56
761 Sources/Greywall.swift:771
759 Sources/Director.swift:518
755 Sources/main.swift:1415
751 Sources/main.swift:1415
720 Sources/Mob.swift:2617
```
### Snapshot
```
```
![fast](fast.png)
