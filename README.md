# Blocksmith fast lane

Commit `f15dc0d715733908c64a27fb1d6b3ca2e191d08f` on `p456-crawler-music`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40956683656

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
/Users/runner/work/blocksmith/blocksmith/Sources/TrainRoofs.swift:141:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Structures.swift:813:15: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |               `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TexturesHD.swift:2048:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
29900 Sources/Structures.swift:813
21888 Sources/Mesher.swift:1164
16462 Sources/BalanceTests.swift:183
12135 Sources/FineField.swift:296
11787 Sources/FineField.swift:113
10878 Sources/FriendlyFireTests.swift:86
9479 Sources/TexturesHD.swift:2193
7148 Sources/PlaytestPM9BTests.swift:94
6962 Sources/AdaptiveGroundTests.swift:111
6815 Sources/SmoothTerrain.swift:325
6651 Sources/TrainRoofs.swift:141
6520 Sources/ShapeClass.swift:161
6475 Sources/TexturesHD.swift:2189
6258 Sources/TexturesHD.swift:2189
6030 Sources/PlaytestPM9BTests.swift:95
5785 Sources/ShapeClass.swift:161
5753 Sources/RenderDistanceGovernor.swift:161
5549 Sources/HellLooks.swift:78
5325 Sources/WorldObjectsGame.swift:212
5315 Sources/Player.swift:108
5292 Sources/WorldObjectsGame.swift:212
4918 Sources/HellLooks.swift:218
4878 Sources/Mob.swift:590
4829 Sources/Fracture.swift:838
4818 Sources/WorldObjectsGame.swift:213
4658 Sources/Fracture.swift:838
4643 Sources/AshVaultGapTests.swift:134
4498 Sources/Greywall.swift:593
4296 Sources/Mob.swift:590
3865 Sources/FreeBuild.swift:50
3576 Sources/ShapeRails.swift:88
3528 Sources/AshCommandeer.swift:606
3514 Sources/ShapeRails.swift:88
3335 Sources/Trains.swift:157
2896 Sources/AshCommandeer.swift:606
2864 Sources/InputMatrix.swift:83
2364 Sources/AshCommandeer.swift:606
2352 Sources/Mesher.swift:1737
2242 Sources/AshSites.swift:63
2103 Sources/WorldObjectsGame.swift:213
```
### Snapshot
```
```
![fast](fast.png)
