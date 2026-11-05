# Blocksmith fast lane

Commit `71c49d2d5e6c6f89af28e83f66c00e7810f037ee` on `claude/quest-port`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/42050849249

### Build errors
```
```
### Type-check (warnings, slowest first)
```
5859 Sources/Greywall.swift:627
4676 Sources/FreeBuild.swift:50
3765 Sources/AshVaultGapTests.swift:134
3595 Sources/InputMatrix.swift:83
3154 Sources/ShapeRails.swift:110
3145 Sources/ShapeRails.swift:110
2956 Sources/Trains.swift:206
2899 Sources/Mesher.swift:1803
2802 Sources/NavalGuns.swift:73
2470 Sources/Mesher.swift:1803
2454 Sources/Mesher.swift:1803
2311 Sources/AshSites.swift:63
2163 Sources/NavalGuns.swift:73
2146 Sources/NavalGuns.swift:73
2118 Sources/Structure.swift:68
1957 Sources/Mesher.swift:1166
1740 Sources/PowerSuit.swift:28
1705 Sources/AshSites.swift:295
1686 Sources/NavalGuns.swift:73
1419 Sources/TexturesHD.swift:3728
1377 Sources/PowerSuit.swift:28
1340 Sources/Mob.swift:3028
1281 Sources/Mob.swift:3028
1200 Sources/Mob.swift:3028
1135 Sources/AdaptiveGround.swift:82
1123 Sources/DebrisField.swift:58
1116 Sources/DebrisField.swift:58
1085 Sources/HellLooks.swift:387
1079 Sources/AdaptiveGround.swift:82
1021 Sources/Greywall.swift:852
983 Sources/main.swift:1436
922 Sources/main.swift:1436
909 Sources/Director.swift:462
794 Sources/HellMobs.swift:530
749 Sources/HellMobs.swift:530
741 Sources/CampSmoke.swift:98
731 Sources/Mesher.swift:1219
698 Sources/Mesher.swift:159
685 Sources/Soldiers.swift:705
650 Sources/GreywallAlarm.swift:420
```
### Snapshot
```
natural census: 63 sample chunks in 20980 ms
posecheck: clearance measure: 24864 measures, largest difference 0.000000 px, 1692.93 ms in all (before 1608.98 ms)
posecheck: weapon clearance: 330 of 925 poses had the weapon through an arm or the body before clearing; worst after 0.46 px
posecheck: 1034 raised limbs checked, 0 failed
textures: 2032 layers at 16 px, BC3, 0.7 MB with mips (build 1729 ms, upload 720 ms)
target: grass_block at 24 136 28, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(25.5, 136.0, 31.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0071 white=0.0008 std=39.8 hash=8e2bb75820bbfdf6
imagecheck fast.png magenta=0.00000 black=0.0071 white=0.0008 std=39.8 hash=8e2bb75820bbfdf6
seed 12345  pos 25.5 136.0 31.5  rd 4  chunks 109  (drawn 28)
gen 99738 ms  mesh(all, parallel) 24087 ms  mesh(1 section) 159.86 ms  quads 302646 opaque / 571 water
frame (encode+GPU, offscreen, median of 30) 17.03 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 11 MB), Metal allocated 114 MB
memory: resident 161 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
