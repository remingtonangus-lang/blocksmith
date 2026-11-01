# Blocksmith fast lane

Commit `ebc915ce76b84134dc9f9f571e98944a92a17869` on `claude/project-thread-1q6065`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41308789070

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
34257 Sources/Structures.swift:825
26335 Sources/Mesher.swift:1164
15619 Sources/FineField.swift:113
14816 Sources/FineField.swift:296
12884 Sources/FriendlyFireTests.swift:86
12096 Sources/TexturesHD.swift:2193
9168 Sources/ShapeClass.swift:161
8699 Sources/SmoothTerrain.swift:325
8299 Sources/PlaytestPM9BTests.swift:94
8193 Sources/AdaptiveGroundTests.swift:111
7852 Sources/PlaytestPM9BTests.swift:95
7683 Sources/TrainRoofs.swift:141
7513 Sources/TexturesHD.swift:2189
7340 Sources/BalanceTests.swift:207
7251 Sources/Mob.swift:590
7064 Sources/TexturesHD.swift:2189
6973 Sources/HellLooks.swift:78
6680 Sources/WorldObjectsGame.swift:212
6642 Sources/HellLooks.swift:218
6636 Sources/RenderDistanceGovernor.swift:161
6618 Sources/ShapeClass.swift:161
6581 Sources/Player.swift:112
6374 Sources/Fracture.swift:838
6140 Sources/Greywall.swift:624
6022 Sources/Fracture.swift:838
5478 Sources/Mob.swift:590
5400 Sources/WorldObjectsGame.swift:212
5313 Sources/AshVaultGapTests.swift:134
5146 Sources/WorldObjectsGame.swift:213
4655 Sources/FreeBuild.swift:50
4393 Sources/ShapeRails.swift:88
4386 Sources/AshCommandeer.swift:606
4214 Sources/ShapeRails.swift:88
3756 Sources/Trains.swift:157
3399 Sources/InputMatrix.swift:83
3327 Sources/AshCommandeer.swift:606
2744 Sources/Mesher.swift:1743
2600 Sources/NavalGuns.swift:71
2545 Sources/Mesher.swift:1743
2426 Sources/AshSites.swift:63
```
### Snapshot
```
```
![fast](fast.png)
