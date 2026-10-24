# Blocksmith fast lane

Commit `7a55a59800677744e0e729b43ef95082147b1e40` on `claude/project-thread-v51hra`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40134755776

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
20546 Sources/Mesher.swift:1140
14771 Sources/BalanceTests.swift:183
12773 Sources/FineField.swift:113
11987 Sources/FineField.swift:295
11034 Sources/FriendlyFireTests.swift:86
7786 Sources/TexturesHD.swift:2068
7020 Sources/AdaptiveGroundTests.swift:111
6497 Sources/SmoothTerrain.swift:325
6314 Sources/PlaytestPM9BTests.swift:95
6303 Sources/ShapeClass.swift:161
6103 Sources/PlaytestPM9BTests.swift:94
5764 Sources/TrainRoofs.swift:128
5486 Sources/FreeBuild.swift:50
5458 Sources/HellLooks.swift:78
5244 Sources/Greywall.swift:555
5162 Sources/Fracture.swift:838
5059 Sources/HellLooks.swift:218
5033 Sources/Mob.swift:582
5021 Sources/RenderDistanceGovernor.swift:161
4832 Sources/TexturesHD.swift:2064
4825 Sources/Fracture.swift:838
4754 Sources/WorldObjectsGame.swift:210
4720 Sources/WorldObjectsGame.swift:210
4716 Sources/TexturesHD.swift:2064
4697 Sources/ShapeClass.swift:161
4505 Sources/WorldObjectsGame.swift:211
4409 Sources/Player.swift:98
4375 Sources/AshVaultGapTests.swift:134
4156 Sources/Mob.swift:582
3137 Sources/ShapeRails.swift:80
3073 Sources/ShapeRails.swift:80
2872 Sources/Structures.swift:769
2729 Sources/InputMatrix.swift:83
2684 Sources/Mesher.swift:1111
2604 Sources/Trains.swift:147
2391 Sources/AshSites.swift:63
2041 Sources/Mesher.swift:1702
1991 Sources/AshSites.swift:270
1946 Sources/Mesher.swift:1702
1942 Sources/NavalGuns.swift:62
```
### Snapshot
```
```
![fast](fast.png)
