# Blocksmith fast lane

Commit `28099b111fd678b08870bda059cc3365583eb2b9` on `claude/p279-drowned`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38821872155

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
16976 Sources/BalanceTests.swift:183
10970 Sources/TexturesHD.swift:2066
10716 Sources/FriendlyFireTests.swift:86
8177 Sources/ShapeClass.swift:157
7741 Sources/PlaytestPM9BTests.swift:94
7664 Sources/PlaytestPM9BTests.swift:95
7134 Sources/TrainRoofs.swift:128
6345 Sources/RenderDistanceGovernor.swift:161
6149 Sources/TexturesHD.swift:2062
5978 Sources/Mob.swift:556
5900 Sources/ShapeClass.swift:157
5633 Sources/Player.swift:86
5627 Sources/TexturesHD.swift:2062
5382 Sources/Greywall.swift:555
5073 Sources/Fracture.swift:838
5043 Sources/Fracture.swift:838
4990 Sources/Mob.swift:556
4436 Sources/AshVaultGapTests.swift:134
3419 Sources/Structures.swift:732
3143 Sources/Trains.swift:137
3082 Sources/InputMatrix.swift:83
2918 Sources/AshSites.swift:56
2166 Sources/Mesher.swift:1057
2158 Sources/Mesher.swift:1057
2152 Sources/Mesher.swift:1057
2114 Sources/AshSites.swift:229
2058 Sources/NavalGuns.swift:62
1893 Sources/NavalGuns.swift:62
1846 Sources/Fracture.swift:838
1813 Sources/NavalGuns.swift:62
1650 Sources/NavalGuns.swift:62
1629 Sources/PowerSuit.swift:28
1597 Sources/PowerSuit.swift:28
1227 Sources/main.swift:1415
1134 Sources/Greywall.swift:771
1119 Sources/main.swift:1415
1039 Sources/DebrisField.swift:56
994 Sources/DebrisField.swift:56
983 Sources/Mob.swift:2611
962 Sources/Mob.swift:2611
```
### Snapshot
```
```
![fast](fast.png)
