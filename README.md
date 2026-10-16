# Blocksmith fast lane

Commit `042fce7e32747a12a3669d15bc6f1049e7d90c40` on `claude/p302-difficulty`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38827404703

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
/Users/runner/work/blocksmith/blocksmith/Sources/Fracture.swift:838:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                     `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/Player.swift:86:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
    |                `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:775:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:777:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:778:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:789:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:789:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
```
### Type-check (warnings, slowest first)
```
18407 Sources/BalanceTests.swift:183
11618 Sources/FriendlyFireTests.swift:86
11587 Sources/TexturesHD.swift:2068
8231 Sources/ShapeClass.swift:157
8161 Sources/PlaytestPM9BTests.swift:94
7821 Sources/PlaytestPM9BTests.swift:95
6823 Sources/RenderDistanceGovernor.swift:161
6762 Sources/TrainRoofs.swift:128
6671 Sources/Mob.swift:556
6624 Sources/TexturesHD.swift:2064
6428 Sources/ShapeClass.swift:157
6305 Sources/TexturesHD.swift:2064
5738 Sources/Player.swift:86
5653 Sources/Fracture.swift:838
5552 Sources/Fracture.swift:838
5489 Sources/Greywall.swift:555
4973 Sources/Mob.swift:556
4560 Sources/AshVaultGapTests.swift:134
3701 Sources/Structures.swift:732
3697 Sources/Trains.swift:137
3488 Sources/InputMatrix.swift:83
3356 Sources/AshSites.swift:56
2519 Sources/Mesher.swift:1076
2497 Sources/AshSites.swift:229
2335 Sources/Mesher.swift:1076
2332 Sources/Mesher.swift:1076
2317 Sources/PowerSuit.swift:28
2248 Sources/NavalGuns.swift:62
1915 Sources/PowerSuit.swift:28
1876 Sources/Fracture.swift:838
1831 Sources/NavalGuns.swift:62
1792 Sources/NavalGuns.swift:62
1718 Sources/NavalGuns.swift:62
1369 Sources/main.swift:1415
1322 Sources/main.swift:1415
1178 Sources/Director.swift:518
1163 Sources/DebrisField.swift:56
1106 Sources/Greywall.swift:771
1059 Sources/DebrisField.swift:56
1038 Sources/Mob.swift:2617
```
### Snapshot
```
```
![fast](fast.png)
