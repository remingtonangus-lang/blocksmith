# Blocksmith fast lane

Commit `a209300320158585572bcc19f6e9490f29fbdc06` on `claude/p284-bed-owner`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38823608264

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
24057 Sources/BalanceTests.swift:183
10910 Sources/FriendlyFireTests.swift:86
8204 Sources/TexturesHD.swift:2066
7268 Sources/PlaytestPM9BTests.swift:94
7064 Sources/ShapeClass.swift:157
6735 Sources/PlaytestPM9BTests.swift:95
6093 Sources/TrainRoofs.swift:128
6045 Sources/Player.swift:86
6043 Sources/RenderDistanceGovernor.swift:161
5879 Sources/Fracture.swift:838
5743 Sources/Fracture.swift:838
5707 Sources/ShapeClass.swift:157
5617 Sources/TexturesHD.swift:2062
5296 Sources/TexturesHD.swift:2062
5014 Sources/Mob.swift:556
4741 Sources/AshVaultGapTests.swift:134
4726 Sources/Greywall.swift:555
4181 Sources/Mob.swift:556
3330 Sources/InputMatrix.swift:83
3187 Sources/Structures.swift:732
2911 Sources/AshSites.swift:56
2783 Sources/Trains.swift:137
2245 Sources/Mesher.swift:1057
2041 Sources/Mesher.swift:1057
2040 Sources/AshSites.swift:229
2037 Sources/Fracture.swift:838
2011 Sources/Mesher.swift:1057
1752 Sources/NavalGuns.swift:62
1751 Sources/PowerSuit.swift:28
1653 Sources/PowerSuit.swift:28
1471 Sources/NavalGuns.swift:62
1441 Sources/NavalGuns.swift:62
1369 Sources/NavalGuns.swift:62
1352 Sources/DebrisField.swift:56
1347 Sources/DebrisField.swift:56
1335 Sources/Director.swift:518
1152 Sources/Mob.swift:2613
1110 Sources/main.swift:1415
1100 Sources/Mob.swift:2613
1053 Sources/Greywall.swift:771
```
### Snapshot
```
```
![fast](fast.png)
