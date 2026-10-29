# Blocksmith fast lane

Commit `7d54f2e3512f7c7083bd8b81ee4477ae9f393454` on `lane/own-items`: build **success**, snapshot **failure**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/40960648073

### Build errors
```
```
### Type-check (warnings, slowest first)
```
8084 Sources/ShapeClass.swift:161
8065 Sources/SmoothTerrain.swift:325
6572 Sources/Greywall.swift:593
6511 Sources/PlaytestPM9BTests.swift:94
6080 Sources/FreeBuild.swift:50
5925 Sources/PlaytestPM9BTests.swift:95
5863 Sources/ShapeClass.swift:161
5728 Sources/Mob.swift:590
5591 Sources/RenderDistanceGovernor.swift:161
5411 Sources/WorldObjectsGame.swift:212
5250 Sources/WorldObjectsGame.swift:212
5125 Sources/WorldObjectsGame.swift:213
4614 Sources/AshVaultGapTests.swift:134
4380 Sources/Mob.swift:590
4065 Sources/ShapeRails.swift:88
3457 Sources/ShapeRails.swift:88
2903 Sources/InputMatrix.swift:83
2866 Sources/AshSites.swift:63
2701 Sources/Trains.swift:157
2128 Sources/WorldObjectsGame.swift:213
2119 Sources/AshSites.swift:295
2056 Sources/NavalGuns.swift:66
2051 Sources/Mesher.swift:1739
2037 Sources/Structure.swift:68
1936 Sources/Mesher.swift:1739
1906 Sources/Mesher.swift:1739
1653 Sources/PowerSuit.swift:28
1638 Sources/PowerSuit.swift:28
1423 Sources/NavalGuns.swift:66
1388 Sources/NavalGuns.swift:66
1373 Sources/NavalGuns.swift:66
1360 Sources/AdaptiveGround.swift:82
1320 Sources/AdaptiveGround.swift:82
1269 Sources/HellMobs.swift:530
1258 Sources/TexturesHD.swift:3734
1233 Sources/Greywall.swift:814
1198 Sources/WorldObjectsGame.swift:141
1085 Sources/HellLooks.swift:387
1059 Sources/Director.swift:462
1058 Sources/main.swift:1436
```
### Snapshot
```
posecheck FAIL ash_chancellor gun_needle aim down left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_needle aim down left hand on the fore grip: 16.5 px off
posecheck FAIL ash_chancellor gun_needle firing left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_needle firing left hand on the fore grip: 16.5 px off
posecheck FAIL ash_chancellor gun_needle aim seated muzzle ahead of the hands: muzzle -3.7 hand -5.3
posecheck FAIL ash_chancellor gun_needle aim seated right hand on the grip: 4.4 px off
posecheck FAIL ash_chancellor gun_needle aim seated left hand on the fore grip: 8.2 px off
posecheck FAIL ash_chancellor gun_breaker aim level left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_breaker aim level left hand on the fore grip: 16.5 px off
posecheck FAIL ash_chancellor gun_breaker aim up left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_breaker aim up left hand on the fore grip: 16.6 px off
posecheck FAIL ash_chancellor gun_breaker aim down left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_breaker aim down left hand on the fore grip: 16.5 px off
posecheck FAIL ash_chancellor gun_breaker firing left hand ahead of the chest: z 2.2
posecheck FAIL ash_chancellor gun_breaker firing left hand on the fore grip: 16.5 px off
posecheck FAIL ash_chancellor gun_breaker aim seated muzzle ahead of the hands: muzzle -3.7 hand -5.3
posecheck FAIL ash_chancellor gun_breaker aim seated right hand on the grip: 4.4 px off
posecheck FAIL ash_chancellor gun_breaker aim seated left hand on the fore grip: 8.2 px off
posecheck: weapon clearance: 353 of 1100 poses had the weapon through an arm or the body before clearing; worst after 0.45 px
posecheck: 1209 raised limbs checked, 96 failed -> soldier_recruit gun_needle aim seated muzzle ahead of the hands, soldier_recruit gun_needle aim seated right hand on the grip, soldier_recruit gun_needle aim seated left hand on the fore grip, soldier_recruit gun_breaker aim seated muzzle ahead of the hands, soldier_recruit gun_breaker aim seated right hand on the grip, soldier_recruit gun_breaker aim seated left hand on the fore grip, soldier_trooper gun_needle aim seated muzzle ahead of the hands, soldier_trooper gun_needle aim seated right hand on the grip, soldier_trooper gun_needle aim seated left hand on the fore grip, soldier_trooper gun_breaker aim seated muzzle ahead of the hands, soldier_trooper gun_breaker aim seated right hand on the grip, soldier_trooper gun_breaker aim seated left hand on the fore grip
```
![fast](fast.png)
