# Blocksmith fast lane

Commit `57ce69e5ce1ffef1d91e83cc55d09e91316bb2fc` on `claude/quest-port`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40127429929

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:295:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
23671 Sources/Mesher.swift:1140
19239 Sources/BalanceTests.swift:183
12494 Sources/FineField.swift:113
11376 Sources/FineField.swift:295
10557 Sources/FriendlyFireTests.swift:86
9656 Sources/TexturesHD.swift:2068
8754 Sources/ShapeClass.swift:157
8458 Sources/SmoothTerrain.swift:325
8043 Sources/AdaptiveGroundTests.swift:111
7916 Sources/PlaytestPM9BTests.swift:95
7884 Sources/PlaytestPM9BTests.swift:94
7201 Sources/WorldObjectsGame.swift:210
7076 Sources/Mob.swift:582
6818 Sources/TrainRoofs.swift:128
6805 Sources/WorldObjectsGame.swift:210
6724 Sources/WorldObjectsGame.swift:211
6460 Sources/Mob.swift:582
6174 Sources/RenderDistanceGovernor.swift:161
5949 Sources/TexturesHD.swift:2064
5725 Sources/ShapeClass.swift:157
5641 Sources/TexturesHD.swift:2064
5578 Sources/Fracture.swift:838
5549 Sources/Fracture.swift:838
5308 Sources/Player.swift:98
4907 Sources/Greywall.swift:555
4901 Sources/HellLooks.swift:218
4839 Sources/AshVaultGapTests.swift:134
4616 Sources/HellLooks.swift:78
3766 Sources/FreeBuild.swift:50
3617 Sources/ShapeRails.swift:80
3569 Sources/ShapeRails.swift:80
3361 Sources/Structures.swift:769
3154 Sources/Trains.swift:147
2715 Sources/AshSites.swift:63
2708 Sources/InputMatrix.swift:83
2705 Sources/Mesher.swift:1111
2640 Sources/WorldObjectsGame.swift:211
2476 Sources/Mesher.swift:1702
2474 Sources/Mesher.swift:1702
2334 Sources/PowerSuit.swift:28
```
### Snapshot
```
```
![fast](fast.png)
