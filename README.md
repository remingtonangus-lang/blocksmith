# Blocksmith fast lane

Commit `beef3af79b386738bf480d464adf75252eeb148a` on `claude/store-candidates-2026-10-31`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41196875213

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
23965 Sources/Structures.swift:813
17532 Sources/Mesher.swift:1164
12708 Sources/BalanceTests.swift:183
9238 Sources/FineField.swift:113
9040 Sources/FineField.swift:296
8165 Sources/FriendlyFireTests.swift:86
6912 Sources/TexturesHD.swift:2193
5657 Sources/AdaptiveGroundTests.swift:111
5415 Sources/PlaytestPM9BTests.swift:94
5414 Sources/ShapeClass.swift:161
5375 Sources/PlaytestPM9BTests.swift:95
5371 Sources/SmoothTerrain.swift:325
4748 Sources/TrainRoofs.swift:141
4464 Sources/Mob.swift:590
4405 Sources/TexturesHD.swift:2189
4392 Sources/RenderDistanceGovernor.swift:161
4272 Sources/HellLooks.swift:218
4259 Sources/TexturesHD.swift:2189
4175 Sources/ShapeClass.swift:161
4077 Sources/Greywall.swift:611
4033 Sources/Player.swift:108
4025 Sources/HellLooks.swift:78
3762 Sources/Fracture.swift:838
3754 Sources/Fracture.swift:838
3482 Sources/Mob.swift:590
3388 Sources/AshVaultGapTests.swift:134
3381 Sources/WorldObjectsGame.swift:212
3380 Sources/WorldObjectsGame.swift:213
3349 Sources/WorldObjectsGame.swift:212
3139 Sources/FreeBuild.swift:50
3096 Sources/AshCommandeer.swift:606
2821 Sources/ShapeRails.swift:88
2807 Sources/ShapeRails.swift:88
2273 Sources/AshCommandeer.swift:606
2262 Sources/InputMatrix.swift:83
2218 Sources/Trains.swift:157
2009 Sources/AshSites.swift:63
1732 Sources/AshCommandeer.swift:606
1657 Sources/Mesher.swift:1743
1655 Sources/Mesher.swift:1743
```
### Snapshot
```
```
![fast](fast.png)
