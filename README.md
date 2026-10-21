# Blocksmith fast lane

Commit `a3bf7fb79f5d5a8723646f10a64655d42166e430` on `claude/sunderfall-tough-edv42v`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/39633482189

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:72:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:197:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:262:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:90:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
22059 Sources/BalanceTests.swift:183
20379 Sources/Mesher.swift:1084
11503 Sources/FineField.swift:113
10744 Sources/FineField.swift:262
9745 Sources/FriendlyFireTests.swift:86
8464 Sources/TexturesHD.swift:2068
8052 Sources/AdaptiveGroundTests.swift:111
7501 Sources/SmoothTerrain.swift:325
7304 Sources/ShapeClass.swift:157
6563 Sources/PlaytestPM9BTests.swift:95
6539 Sources/PlaytestPM9BTests.swift:94
5454 Sources/HellLooks.swift:78
5442 Sources/TrainRoofs.swift:128
5386 Sources/Mob.swift:579
5272 Sources/ShapeClass.swift:157
5016 Sources/Greywall.swift:555
4960 Sources/HellLooks.swift:218
4916 Sources/Player.swift:90
4810 Sources/TexturesHD.swift:2064
4806 Sources/RenderDistanceGovernor.swift:161
4715 Sources/TexturesHD.swift:2064
4701 Sources/FreeBuild.swift:50
4664 Sources/WorldObjectsGame.swift:199
4506 Sources/Fracture.swift:838
4497 Sources/AshVaultGapTests.swift:134
4366 Sources/WorldObjectsGame.swift:200
4341 Sources/WorldObjectsGame.swift:199
4190 Sources/Fracture.swift:838
3812 Sources/Mob.swift:579
3688 Sources/ShapeRails.swift:80
3367 Sources/Structures.swift:760
3019 Sources/ShapeRails.swift:80
2933 Sources/AshSites.swift:63
2619 Sources/InputMatrix.swift:83
2493 Sources/Trains.swift:147
2359 Sources/Mesher.swift:1057
2193 Sources/AshSites.swift:270
2041 Sources/Mesher.swift:1640
2017 Sources/Mesher.swift:1640
1892 Sources/Mesher.swift:1640
```
### Snapshot
```
```
![fast](fast.png)
