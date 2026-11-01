# Blocksmith fast lane

Commit `18c3e368f4982a954978cf1e8aac6e9b8f43b994` on `claude/project-thread-ddeimn`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41262800151

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:207:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:112:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Mesher.swift:1079:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Structures.swift:825:15: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |               `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TrainRoofs.swift:141:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TexturesHD.swift:2048:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
31078 Sources/Structures.swift:825
30715 Sources/Mesher.swift:1164
14433 Sources/FineField.swift:113
12667 Sources/FineField.swift:296
11677 Sources/FriendlyFireTests.swift:86
9463 Sources/TexturesHD.swift:2193
8556 Sources/PlaytestPM9BTests.swift:94
8166 Sources/PlaytestPM9BTests.swift:95
8032 Sources/Player.swift:112
7354 Sources/RenderDistanceGovernor.swift:161
7264 Sources/SmoothTerrain.swift:325
7067 Sources/Mob.swift:590
6865 Sources/HellLooks.swift:218
6725 Sources/ShapeClass.swift:161
6669 Sources/HellLooks.swift:78
6624 Sources/Fracture.swift:838
6308 Sources/TrainRoofs.swift:141
6045 Sources/Fracture.swift:838
5874 Sources/BalanceTests.swift:207
5790 Sources/AdaptiveGroundTests.swift:111
5500 Sources/TexturesHD.swift:2189
5435 Sources/TexturesHD.swift:2189
5125 Sources/Mob.swift:590
4965 Sources/ShapeClass.swift:161
4961 Sources/WorldObjectsGame.swift:212
4865 Sources/Greywall.swift:624
4741 Sources/WorldObjectsGame.swift:213
4738 Sources/AshCommandeer.swift:606
4467 Sources/WorldObjectsGame.swift:212
4447 Sources/InputMatrix.swift:83
4231 Sources/ShapeRails.swift:88
4181 Sources/ShapeRails.swift:88
3570 Sources/AshVaultGapTests.swift:134
3426 Sources/FreeBuild.swift:50
2769 Sources/Trains.swift:157
2769 Sources/NavalGuns.swift:71
2753 Sources/Mesher.swift:1743
2489 Sources/AshCommandeer.swift:606
2435 Sources/NavalGuns.swift:71
2430 Sources/Mesher.swift:1743
```
### Snapshot
```
```
![fast](fast.png)
