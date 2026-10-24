# Blocksmith fast lane

Commit `12d174c4d4dfc63f27272ab2b22b21c067706003` on `claude/sunderfall-lane-edv42v`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40126987410

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/AdaptiveGroundTests.swift:111:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:72:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/HellLooks.swift:197:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:98:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
### Type-check (warnings, slowest first)
```
23109 Sources/Mesher.swift:1140
16516 Sources/BalanceTests.swift:183
12573 Sources/FineField.swift:295
11794 Sources/FineField.swift:113
10628 Sources/FriendlyFireTests.swift:86
9024 Sources/TexturesHD.swift:2068
7886 Sources/PlaytestPM9BTests.swift:95
7786 Sources/ShapeClass.swift:157
7487 Sources/PlaytestPM9BTests.swift:94
7270 Sources/AdaptiveGroundTests.swift:111
7160 Sources/SmoothTerrain.swift:325
6679 Sources/TrainRoofs.swift:128
6520 Sources/Mob.swift:582
6337 Sources/RenderDistanceGovernor.swift:161
5999 Sources/WorldObjectsGame.swift:210
5910 Sources/WorldObjectsGame.swift:210
5897 Sources/TexturesHD.swift:2064
5751 Sources/ShapeClass.swift:157
5700 Sources/TexturesHD.swift:2064
5700 Sources/HellLooks.swift:218
5648 Sources/HellLooks.swift:78
5571 Sources/Player.swift:98
5444 Sources/WorldObjectsGame.swift:211
5097 Sources/Mob.swift:582
5072 Sources/Greywall.swift:555
4890 Sources/Fracture.swift:838
4802 Sources/Fracture.swift:838
4514 Sources/AshVaultGapTests.swift:134
4352 Sources/FreeBuild.swift:50
3933 Sources/ShapeRails.swift:80
3445 Sources/ShapeRails.swift:80
3259 Sources/InputMatrix.swift:83
3172 Sources/Structures.swift:769
3125 Sources/Trains.swift:147
2896 Sources/Mesher.swift:1111
2417 Sources/AshSites.swift:63
2339 Sources/WorldObjectsGame.swift:211
2329 Sources/Mesher.swift:1702
2262 Sources/Mesher.swift:1702
2169 Sources/Mesher.swift:1702
```
### Snapshot
```
```
![fast](fast.png)
