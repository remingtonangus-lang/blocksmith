# Blocksmith fast lane

Commit `9acd55e75e585da24d183a5eacb727c6c52f8dad` on `claude/project-thread-l1pyon`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41066143263

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AshCommandeer.swift:606:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:72:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:197:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:296:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:108:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Mesher.swift:1079:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Structures.swift:813:15: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |               `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TrainRoofs.swift:141:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TexturesHD.swift:2048:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
23948 Sources/Structures.swift:813
17421 Sources/Mesher.swift:1164
13174 Sources/BalanceTests.swift:183
9306 Sources/FineField.swift:113
9013 Sources/FineField.swift:296
8110 Sources/FriendlyFireTests.swift:86
7503 Sources/TexturesHD.swift:2193
5400 Sources/AdaptiveGroundTests.swift:111
5399 Sources/PlaytestPM9BTests.swift:94
5386 Sources/SmoothTerrain.swift:325
5370 Sources/PlaytestPM9BTests.swift:95
5367 Sources/ShapeClass.swift:161
4685 Sources/TrainRoofs.swift:141
4583 Sources/Mob.swift:590
4457 Sources/RenderDistanceGovernor.swift:161
4316 Sources/TexturesHD.swift:2189
4274 Sources/TexturesHD.swift:2189
4233 Sources/HellLooks.swift:218
4149 Sources/ShapeClass.swift:161
4082 Sources/FreeBuild.swift:50
4051 Sources/Greywall.swift:611
4038 Sources/HellLooks.swift:78
4008 Sources/Player.swift:108
3829 Sources/Fracture.swift:838
3812 Sources/Fracture.swift:838
3614 Sources/WorldObjectsGame.swift:213
3612 Sources/WorldObjectsGame.swift:212
3519 Sources/WorldObjectsGame.swift:212
3484 Sources/Mob.swift:590
3398 Sources/AshVaultGapTests.swift:134
3084 Sources/AshCommandeer.swift:606
2794 Sources/ShapeRails.swift:88
2779 Sources/ShapeRails.swift:88
2334 Sources/AshCommandeer.swift:606
2245 Sources/Trains.swift:157
2244 Sources/InputMatrix.swift:83
1985 Sources/AshSites.swift:63
1792 Sources/AshCommandeer.swift:606
1649 Sources/Mesher.swift:1743
1643 Sources/Mesher.swift:1743
```
### Snapshot
```
```
![fast](fast.png)
