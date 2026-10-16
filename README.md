# Blocksmith fast lane

Commit `8b772c42e036c9b3d4f43e05b75a755e3016cb7d` on `claude/p289-pillars`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38826651130

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
18059 Sources/BalanceTests.swift:183
12407 Sources/FriendlyFireTests.swift:86
9604 Sources/TexturesHD.swift:2068
8104 Sources/Mob.swift:556
7469 Sources/TrainRoofs.swift:128
7403 Sources/ShapeClass.swift:157
7376 Sources/PlaytestPM9BTests.swift:94
7151 Sources/PlaytestPM9BTests.swift:95
6674 Sources/Player.swift:86
6506 Sources/TexturesHD.swift:2064
6454 Sources/Greywall.swift:555
6426 Sources/Fracture.swift:838
6169 Sources/Mob.swift:556
6099 Sources/TexturesHD.swift:2064
5926 Sources/Fracture.swift:838
5719 Sources/RenderDistanceGovernor.swift:161
5435 Sources/ShapeClass.swift:157
4714 Sources/AshVaultGapTests.swift:134
3619 Sources/InputMatrix.swift:83
3558 Sources/Structures.swift:732
3342 Sources/Trains.swift:137
2988 Sources/AshSites.swift:56
2805 Sources/Mesher.swift:1076
2753 Sources/Mesher.swift:1076
2650 Sources/NavalGuns.swift:62
2346 Sources/Mesher.swift:1076
2301 Sources/AshSites.swift:229
2299 Sources/Fracture.swift:838
2273 Sources/NavalGuns.swift:62
2223 Sources/NavalGuns.swift:62
2197 Sources/NavalGuns.swift:62
2042 Sources/PowerSuit.swift:28
1951 Sources/PowerSuit.swift:28
1267 Sources/Greywall.swift:771
1246 Sources/main.swift:1415
1222 Sources/DebrisField.swift:56
1207 Sources/Mob.swift:2613
1189 Sources/DebrisField.swift:56
1122 Sources/Director.swift:518
1082 Sources/main.swift:1415
```
### Snapshot
```
```
![fast](fast.png)
