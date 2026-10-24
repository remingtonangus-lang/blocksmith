# Blocksmith fast lane

Commit `f298f4887a9d4cd47055223fc8fad23d7b6f37bf` on `claude/project-thread-l1pyon`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40128379992

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
23807 Sources/Mesher.swift:1140
21527 Sources/BalanceTests.swift:183
14610 Sources/FineField.swift:295
12308 Sources/FineField.swift:113
11243 Sources/FriendlyFireTests.swift:86
8554 Sources/TexturesHD.swift:2068
8336 Sources/AdaptiveGroundTests.swift:111
7650 Sources/PlaytestPM9BTests.swift:94
6716 Sources/SmoothTerrain.swift:325
6578 Sources/PlaytestPM9BTests.swift:95
6482 Sources/ShapeClass.swift:157
6364 Sources/TrainRoofs.swift:128
6261 Sources/Mob.swift:582
6067 Sources/Player.swift:98
6008 Sources/HellLooks.swift:218
5944 Sources/HellLooks.swift:78
5521 Sources/TexturesHD.swift:2064
5410 Sources/RenderDistanceGovernor.swift:161
5331 Sources/TexturesHD.swift:2064
5307 Sources/Greywall.swift:555
5282 Sources/WorldObjectsGame.swift:210
5053 Sources/AshVaultGapTests.swift:134
5017 Sources/ShapeClass.swift:157
4911 Sources/WorldObjectsGame.swift:211
4891 Sources/Fracture.swift:838
4640 Sources/WorldObjectsGame.swift:210
4634 Sources/Fracture.swift:838
4415 Sources/FreeBuild.swift:50
4031 Sources/Mob.swift:582
3455 Sources/ShapeRails.swift:80
3257 Sources/InputMatrix.swift:83
3219 Sources/ShapeRails.swift:80
2874 Sources/Trains.swift:147
2858 Sources/AshSites.swift:63
2840 Sources/Structures.swift:769
2459 Sources/Mesher.swift:1702
2381 Sources/AshSites.swift:270
2337 Sources/Mesher.swift:1111
2123 Sources/Mesher.swift:1702
2085 Sources/Mesher.swift:1702
```
### Snapshot
```
```
![fast](fast.png)
