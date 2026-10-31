# Blocksmith fast lane

Commit `c89de8887a15083204fce5e9e1b96a06319878ff` on `claude/quest-port`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41200692176

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:205:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Structures.swift:816:15: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |               `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TrainRoofs.swift:141:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TexturesHD.swift:2048:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
24006 Sources/Structures.swift:816
17453 Sources/Mesher.swift:1164
9364 Sources/FineField.swift:113
8965 Sources/FineField.swift:296
8117 Sources/FriendlyFireTests.swift:86
6592 Sources/TexturesHD.swift:2193
5524 Sources/AdaptiveGroundTests.swift:111
5465 Sources/SmoothTerrain.swift:325
5438 Sources/ShapeClass.swift:161
5398 Sources/PlaytestPM9BTests.swift:95
5350 Sources/PlaytestPM9BTests.swift:94
5093 Sources/BalanceTests.swift:205
4680 Sources/TrainRoofs.swift:141
4441 Sources/Mob.swift:590
4413 Sources/RenderDistanceGovernor.swift:161
4402 Sources/TexturesHD.swift:2189
4285 Sources/HellLooks.swift:218
4274 Sources/TexturesHD.swift:2189
4153 Sources/ShapeClass.swift:161
4082 Sources/HellLooks.swift:78
4055 Sources/Greywall.swift:620
3979 Sources/Player.swift:112
3910 Sources/Fracture.swift:838
3834 Sources/WorldObjectsGame.swift:212
3789 Sources/Fracture.swift:838
3778 Sources/WorldObjectsGame.swift:212
3693 Sources/WorldObjectsGame.swift:213
3461 Sources/Mob.swift:590
3301 Sources/AshVaultGapTests.swift:134
3118 Sources/FreeBuild.swift:50
2955 Sources/AshCommandeer.swift:606
2808 Sources/ShapeRails.swift:88
2734 Sources/ShapeRails.swift:88
2287 Sources/InputMatrix.swift:83
2258 Sources/AshCommandeer.swift:606
2212 Sources/Trains.swift:157
2013 Sources/AshSites.swift:63
1744 Sources/AshCommandeer.swift:606
1650 Sources/Mesher.swift:1743
1642 Sources/Mesher.swift:1743
```
### Snapshot
```
```
![fast](fast.png)
