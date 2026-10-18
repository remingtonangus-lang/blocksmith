# Blocksmith fast lane

Commit `241b4370913534c25f49049da161fd736bd5f800` on `claude/project-thread-cj09b3`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/39154683348

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:90:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:776:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:778:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:779:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
```
### Type-check (warnings, slowest first)
```
22113 Sources/BalanceTests.swift:183
10966 Sources/TexturesHD.swift:2068
10794 Sources/FriendlyFireTests.swift:86
7185 Sources/PlaytestPM9BTests.swift:94
7072 Sources/ShapeClass.swift:157
6887 Sources/PlaytestPM9BTests.swift:95
6700 Sources/TrainRoofs.swift:128
6218 Sources/SmoothTerrain.swift:284
6111 Sources/TexturesHD.swift:2064
5813 Sources/HellLooks.swift:218
5586 Sources/TexturesHD.swift:2064
5579 Sources/RenderDistanceGovernor.swift:161
5505 Sources/HellLooks.swift:78
5399 Sources/ShapeClass.swift:157
5362 Sources/Greywall.swift:555
5255 Sources/Fracture.swift:838
5083 Sources/Player.swift:90
4965 Sources/Mob.swift:578
4629 Sources/Fracture.swift:838
4084 Sources/AshVaultGapTests.swift:134
3826 Sources/Mob.swift:578
3147 Sources/InputMatrix.swift:83
3143 Sources/Trains.swift:137
2865 Sources/Structures.swift:742
2790 Sources/AshSites.swift:63
2152 Sources/NavalGuns.swift:62
2142 Sources/AshSites.swift:270
1748 Sources/Mesher.swift:1110
1743 Sources/Fracture.swift:838
1715 Sources/PowerSuit.swift:28
1670 Sources/Mesher.swift:1110
1654 Sources/Mesher.swift:1110
1636 Sources/NavalGuns.swift:62
1555 Sources/PowerSuit.swift:28
1438 Sources/NavalGuns.swift:62
1311 Sources/NavalGuns.swift:62
1100 Sources/Director.swift:518
1072 Sources/main.swift:1430
1044 Sources/main.swift:1430
959 Sources/DebrisField.swift:56
```
### Snapshot
```
```
![fast](fast.png)
