# Blocksmith fast lane

Commit `435196ccbaca4568dec7a1743d45c2c3681a1799` on `claude/tough-builder-p392-tag`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/39762897684

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:262:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:91:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
23973 Sources/Mesher.swift:1084
18243 Sources/BalanceTests.swift:183
13233 Sources/FineField.swift:113
12635 Sources/FineField.swift:262
11394 Sources/FriendlyFireTests.swift:86
11097 Sources/TexturesHD.swift:2068
8282 Sources/AdaptiveGroundTests.swift:111
7833 Sources/PlaytestPM9BTests.swift:95
7702 Sources/ShapeClass.swift:157
7464 Sources/PlaytestPM9BTests.swift:94
7283 Sources/SmoothTerrain.swift:325
7250 Sources/TrainRoofs.swift:128
6735 Sources/WorldObjectsGame.swift:199
6459 Sources/RenderDistanceGovernor.swift:161
6289 Sources/HellLooks.swift:218
6253 Sources/Mob.swift:579
6205 Sources/TexturesHD.swift:2064
6109 Sources/TexturesHD.swift:2064
6024 Sources/Player.swift:91
5811 Sources/WorldObjectsGame.swift:200
5783 Sources/ShapeClass.swift:157
5771 Sources/HellLooks.swift:78
5708 Sources/FreeBuild.swift:50
5616 Sources/WorldObjectsGame.swift:199
5544 Sources/Greywall.swift:555
5438 Sources/Fracture.swift:838
5322 Sources/Fracture.swift:838
5259 Sources/AshVaultGapTests.swift:134
4837 Sources/Mob.swift:579
3705 Sources/ShapeRails.swift:80
3469 Sources/ShapeRails.swift:80
3289 Sources/Structures.swift:760
3241 Sources/InputMatrix.swift:83
3236 Sources/Trains.swift:147
2938 Sources/AshSites.swift:63
2809 Sources/Mesher.swift:1057
2317 Sources/Mesher.swift:1640
2296 Sources/Mesher.swift:1640
2267 Sources/Mesher.swift:1640
2187 Sources/NavalGuns.swift:62
```
### Snapshot
```
```
![fast](fast.png)
