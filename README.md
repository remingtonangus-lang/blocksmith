# Blocksmith fast lane

Commit `11a29fecd0d649c00ee5518ccc996452abb77b26` on `claude/quest-port`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41369126594

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:207:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/AshCommandeer.swift:609:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:113:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FineField.swift:296:29: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLands.swift:89:44: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                                            `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:72:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:197:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:112:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Mesher.swift:1098:17: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |                 `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TrainRoofs.swift:141:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Structures.swift:837:15: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |               `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/TexturesHD.swift:2048:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
     |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
26154 Sources/Structures.swift:837
20065 Sources/Mesher.swift:1183
11168 Sources/FineField.swift:113
10585 Sources/FineField.swift:296
9582 Sources/FriendlyFireTests.swift:86
9380 Sources/TexturesHD.swift:2193
6604 Sources/AdaptiveGroundTests.swift:111
6597 Sources/SmoothTerrain.swift:325
6563 Sources/BalanceTests.swift:207
6469 Sources/ShapeClass.swift:161
6314 Sources/PlaytestPM9BTests.swift:95
5845 Sources/PlaytestPM9BTests.swift:94
5802 Sources/TrainRoofs.swift:141
5497 Sources/HellLooks.swift:218
5469 Sources/TexturesHD.swift:2189
5431 Sources/TexturesHD.swift:2189
5337 Sources/ShapeClass.swift:161
5289 Sources/WorldObjectsGame.swift:212
5210 Sources/HellLooks.swift:78
5185 Sources/Mob.swift:593
4970 Sources/RenderDistanceGovernor.swift:161
4801 Sources/Player.swift:112
4469 Sources/WorldObjectsGame.swift:213
4461 Sources/WorldObjectsGame.swift:212
4445 Sources/Fracture.swift:838
4274 Sources/Greywall.swift:627
4180 Sources/Mob.swift:593
4138 Sources/Fracture.swift:838
4089 Sources/AshVaultGapTests.swift:134
3844 Sources/AshCommandeer.swift:609
3341 Sources/FreeBuild.swift:50
3330 Sources/ShapeRails.swift:93
3207 Sources/ShapeRails.swift:93
2977 Sources/InputMatrix.swift:83
2919 Sources/Trains.swift:157
2747 Sources/AshCommandeer.swift:609
2278 Sources/AshSites.swift:63
2241 Sources/AshCommandeer.swift:609
2051 Sources/WorldObjectsGame.swift:213
1793 Sources/NavalGuns.swift:73
```
### Snapshot
```
```
![fast](fast.png)
