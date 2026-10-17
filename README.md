# Blocksmith fast lane

Commit `11e9e8123d64e8258b13b7c81c37ae153794b933` on `claude/project-thread-cj09b3`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/39053191446

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
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:72:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:197:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:90:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:776:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:778:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:779:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
```
### Type-check (warnings, slowest first)
```
16781 Sources/BalanceTests.swift:183
10707 Sources/TexturesHD.swift:2068
10624 Sources/FriendlyFireTests.swift:86
7766 Sources/ShapeClass.swift:157
7611 Sources/PlaytestPM9BTests.swift:95
7486 Sources/SmoothTerrain.swift:284
6925 Sources/TrainRoofs.swift:128
6806 Sources/PlaytestPM9BTests.swift:94
6639 Sources/HellLooks.swift:218
6463 Sources/RenderDistanceGovernor.swift:161
6261 Sources/Mob.swift:573
6109 Sources/TexturesHD.swift:2064
5787 Sources/TexturesHD.swift:2064
5732 Sources/ShapeClass.swift:157
5617 Sources/HellLooks.swift:78
5606 Sources/Player.swift:90
5540 Sources/Greywall.swift:555
5260 Sources/Fracture.swift:838
5083 Sources/Fracture.swift:838
4776 Sources/AshVaultGapTests.swift:134
4607 Sources/Mob.swift:573
3560 Sources/Structures.swift:733
3510 Sources/Trains.swift:137
3309 Sources/InputMatrix.swift:83
2952 Sources/AshSites.swift:63
2402 Sources/Mesher.swift:1106
2267 Sources/Mesher.swift:1106
2260 Sources/Mesher.swift:1106
2162 Sources/AshSites.swift:267
2056 Sources/NavalGuns.swift:62
1756 Sources/Fracture.swift:838
1717 Sources/NavalGuns.swift:62
1715 Sources/NavalGuns.swift:62
1672 Sources/NavalGuns.swift:62
1465 Sources/PowerSuit.swift:28
1397 Sources/PowerSuit.swift:28
1239 Sources/DebrisField.swift:56
1233 Sources/main.swift:1425
1161 Sources/Director.swift:518
1109 Sources/main.swift:1425
```
### Snapshot
```
```
![fast](fast.png)
