# Blocksmith fast lane

Commit `603815de9f47352b371313de448a9d0ab2081d12` on `claude/lane-a-30uc5r-pkhvk3`: build **failure**, snapshot **skipped**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38315103403

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
/Users/runner/work/blocksmith/blocksmith/Sources/FriendlyFireTests.swift:86:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
   |         `- error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:774:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:776:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:777:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:788:16: error: value of type 'PadManager' has no member 'touch'
    |                `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:788:24: error: 'nil' requires a contextual type
    |                        `- error: 'nil' requires a contextual type
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:813:12: error: value of type 'PadManager' has no member 'touch'
    |            `- error: value of type 'PadManager' has no member 'touch'
/Users/runner/work/blocksmith/blocksmith/Sources/PlaytestOct12Tests.swift:814:63: error: value of type 'PadManager' has no member 'touch'
    |                                                               `- error: value of type 'PadManager' has no member 'touch'
```
### Type-check (warnings, slowest first)
```
15561 Sources/BalanceTests.swift:183
13291 Sources/FriendlyFireTests.swift:86
7526 Sources/PlaytestPM9BTests.swift:94
6687 Sources/PlaytestPM9BTests.swift:95
5609 Sources/Mob.swift:506
5363 Sources/RenderDistanceGovernor.swift:146
4560 Sources/Mob.swift:506
3975 Sources/AshVaultGapTests.swift:134
3797 Sources/InputMatrix.swift:83
2735 Sources/AshSites.swift:56
1964 Sources/AshSites.swift:229
1246 Sources/Greywall.swift:696
1216 Sources/main.swift:1415
1209 Sources/main.swift:1415
894 Sources/HellMobs.swift:434
812 Sources/HellMobs.swift:434
663 Sources/CapitalShips.swift:1393
638 Sources/CapitalShips.swift:1393
623 Sources/HorseGapTests.swift:353
609 Sources/DeepGapTests.swift:331
564 Sources/main.swift:1415
559 Sources/HorseGapTests.swift:355
554 Sources/GreywallAlarm.swift:264
523 Sources/Cinematic.swift:141
505 Sources/DeepGapTests.swift:331
497 Sources/CapitalBases.swift:352
479 Sources/Soldiers.swift:421
469 Sources/HorseGapTests.swift:355
469 Sources/HorseGapTests.swift:353
468 Sources/LandmarkRender.swift:77
468 Sources/GreywallAlarm.swift:264
463 Sources/Soldiers.swift:421
462 Sources/Cinematic.swift:141
450 Sources/LandmarkRender.swift:77
445 Sources/Soldiers.swift:421
438 Sources/Soldiers.swift:421
433 Sources/HuntingTests.swift:191
420 Sources/MainGun.swift:236
420 Sources/HuntingTests.swift:191
417 Sources/BaseTests.swift:121
```
### Snapshot
```
```
![fast](fast.png)
