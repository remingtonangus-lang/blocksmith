# Blocksmith fast lane

Commit `00d311b8077fc26b468bb7f5bdc26c11d3129fe1` on `claude/quest-port`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/39053207096

### Build errors
```
/Users/runner/work/blocksmith/blocksmith/Sources/BalanceTests.swift:183:13: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |             `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
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
21832 Sources/BalanceTests.swift:183
12217 Sources/FriendlyFireTests.swift:86
8466 Sources/TexturesHD.swift:2068
8250 Sources/SmoothTerrain.swift:284
7582 Sources/Mob.swift:573
7547 Sources/ShapeClass.swift:157
7411 Sources/PlaytestPM9BTests.swift:94
7105 Sources/PlaytestPM9BTests.swift:95
7042 Sources/Fracture.swift:838
6729 Sources/RenderDistanceGovernor.swift:161
6267 Sources/ShapeClass.swift:157
5990 Sources/Player.swift:90
5954 Sources/HellLooks.swift:218
5943 Sources/AshVaultGapTests.swift:134
5870 Sources/Fracture.swift:838
5637 Sources/TrainRoofs.swift:128
5478 Sources/Greywall.swift:555
5358 Sources/HellLooks.swift:78
5107 Sources/TexturesHD.swift:2064
4495 Sources/TexturesHD.swift:2064
4494 Sources/Mob.swift:573
3718 Sources/AshSites.swift:63
3088 Sources/Trains.swift:137
3052 Sources/InputMatrix.swift:83
2778 Sources/AshSites.swift:267
2717 Sources/Structures.swift:733
2514 Sources/Mesher.swift:1106
2512 Sources/Mesher.swift:1106
2341 Sources/Fracture.swift:838
2284 Sources/Mesher.swift:1106
1978 Sources/NavalGuns.swift:62
1967 Sources/NavalGuns.swift:62
1791 Sources/NavalGuns.swift:62
1681 Sources/PowerSuit.swift:28
1621 Sources/PowerSuit.swift:28
1608 Sources/NavalGuns.swift:62
1404 Sources/Director.swift:518
1157 Sources/DebrisField.swift:56
1122 Sources/Greywall.swift:771
1113 Sources/DebrisField.swift:56
```
### Snapshot
```
```
![fast](fast.png)
