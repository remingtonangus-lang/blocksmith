# Blocksmith fast lane

Commit `861691d3d47c137064565456abfbc4f7bc6460ff` on `claude/p300-less-text`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38826089954

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
12749 Sources/BalanceTests.swift:183
8045 Sources/FriendlyFireTests.swift:86
6826 Sources/TexturesHD.swift:2068
5479 Sources/PlaytestPM9BTests.swift:94
5456 Sources/PlaytestPM9BTests.swift:95
5424 Sources/ShapeClass.swift:157
4690 Sources/TrainRoofs.swift:128
4457 Sources/Mob.swift:556
4389 Sources/RenderDistanceGovernor.swift:161
4147 Sources/ShapeClass.swift:157
4078 Sources/Player.swift:86
4075 Sources/TexturesHD.swift:2064
4035 Sources/Greywall.swift:555
3960 Sources/TexturesHD.swift:2064
3841 Sources/Fracture.swift:838
3787 Sources/Fracture.swift:838
3460 Sources/Mob.swift:556
3316 Sources/AshVaultGapTests.swift:134
2511 Sources/Structures.swift:732
2309 Sources/InputMatrix.swift:83
2213 Sources/Trains.swift:137
2073 Sources/AshSites.swift:56
1622 Sources/Mesher.swift:1076
1621 Sources/Mesher.swift:1076
1615 Sources/Mesher.swift:1076
1500 Sources/AshSites.swift:229
1497 Sources/NavalGuns.swift:62
1379 Sources/Fracture.swift:838
1218 Sources/NavalGuns.swift:62
1204 Sources/NavalGuns.swift:62
1200 Sources/PowerSuit.swift:28
1192 Sources/PowerSuit.swift:28
1185 Sources/NavalGuns.swift:62
782 Sources/DebrisField.swift:56
779 Sources/DebrisField.swift:56
739 Sources/main.swift:1415
733 Sources/main.swift:1415
729 Sources/Greywall.swift:771
711 Sources/Director.swift:518
708 Sources/Mob.swift:2613
```
### Snapshot
```
```
![fast](fast.png)
