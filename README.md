# Blocksmith fast lane

Commit `6a03bcf95406993d40f903b45328da511205f55b` on `claude/p281-kelp`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38824320548

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
21775 Sources/BalanceTests.swift:183
13050 Sources/TexturesHD.swift:2068
12756 Sources/FriendlyFireTests.swift:86
10237 Sources/ShapeClass.swift:157
9770 Sources/PlaytestPM9BTests.swift:95
9245 Sources/PlaytestPM9BTests.swift:94
8963 Sources/Mob.swift:556
8956 Sources/TrainRoofs.swift:128
8377 Sources/TexturesHD.swift:2064
7742 Sources/RenderDistanceGovernor.swift:161
7396 Sources/Player.swift:86
7352 Sources/ShapeClass.swift:157
7220 Sources/TexturesHD.swift:2064
6801 Sources/Greywall.swift:555
6498 Sources/Mob.swift:556
5905 Sources/AshVaultGapTests.swift:134
5840 Sources/Fracture.swift:838
5354 Sources/Fracture.swift:838
4326 Sources/AshSites.swift:56
4246 Sources/Trains.swift:137
3895 Sources/Structures.swift:732
3540 Sources/InputMatrix.swift:83
2924 Sources/NavalGuns.swift:62
2864 Sources/Mesher.swift:1076
2809 Sources/AshSites.swift:229
2552 Sources/NavalGuns.swift:62
2466 Sources/Mesher.swift:1076
2436 Sources/Mesher.swift:1076
2426 Sources/NavalGuns.swift:62
2261 Sources/NavalGuns.swift:62
2259 Sources/Fracture.swift:838
1940 Sources/PowerSuit.swift:28
1789 Sources/PowerSuit.swift:28
1444 Sources/main.swift:1415
1395 Sources/Mob.swift:2613
1329 Sources/main.swift:1415
1322 Sources/Greywall.swift:771
1286 Sources/Mob.swift:2613
1252 Sources/DebrisField.swift:56
1242 Sources/DebrisField.swift:56
```
### Snapshot
```
```
![fast](fast.png)
