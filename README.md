# Blocksmith fast lane

Commit `290a6e4f15e0bcb4d256821f8d30d855aaef4600` on `claude/project-thread-v51hra`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40126672051

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:295:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:98:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
21515 Sources/Mesher.swift:1140
17633 Sources/BalanceTests.swift:183
13550 Sources/FineField.swift:113
12259 Sources/FineField.swift:295
11252 Sources/TexturesHD.swift:2068
10924 Sources/FriendlyFireTests.swift:86
8397 Sources/PlaytestPM9BTests.swift:95
8374 Sources/PlaytestPM9BTests.swift:94
7477 Sources/SmoothTerrain.swift:325
7364 Sources/AdaptiveGroundTests.swift:111
7167 Sources/Mob.swift:582
6730 Sources/ShapeClass.swift:157
6715 Sources/TrainRoofs.swift:128
6218 Sources/WorldObjectsGame.swift:211
6050 Sources/TexturesHD.swift:2064
6039 Sources/TexturesHD.swift:2064
6009 Sources/Fracture.swift:838
5943 Sources/WorldObjectsGame.swift:210
5892 Sources/WorldObjectsGame.swift:210
5737 Sources/RenderDistanceGovernor.swift:161
5717 Sources/Player.swift:98
5586 Sources/HellLooks.swift:78
5577 Sources/Fracture.swift:838
5503 Sources/Mob.swift:582
5204 Sources/ShapeClass.swift:157
5018 Sources/HellLooks.swift:218
4992 Sources/Greywall.swift:555
4731 Sources/AshVaultGapTests.swift:134
4069 Sources/FreeBuild.swift:50
3547 Sources/ShapeRails.swift:80
3364 Sources/Trains.swift:147
3314 Sources/Structures.swift:769
3065 Sources/ShapeRails.swift:80
3010 Sources/InputMatrix.swift:83
2501 Sources/AshSites.swift:63
2425 Sources/Mesher.swift:1111
2247 Sources/Mesher.swift:1702
2238 Sources/Fracture.swift:838
2169 Sources/WorldObjectsGame.swift:211
2133 Sources/Mesher.swift:1702
```
### Snapshot
```
```
![fast](fast.png)
