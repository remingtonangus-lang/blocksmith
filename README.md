# Blocksmith fast lane

Commit `9fe191a40c7a8a2bfa588e8bc00fad5f36e1dfb0` on `claude/project-thread-1q6065`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/41682100857

### Build errors
```
```
### Type-check (warnings, slowest first)
```
5963 Sources/Greywall.swift:627
4477 Sources/AshVaultGapTests.swift:134
4031 Sources/FreeBuild.swift:50
3978 Sources/ShapeRails.swift:110
3855 Sources/ShapeRails.swift:110
3541 Sources/InputMatrix.swift:83
2825 Sources/Trains.swift:206
2368 Sources/NavalGuns.swift:73
2311 Sources/AshSites.swift:63
2167 Sources/Mesher.swift:1803
2135 Sources/Mesher.swift:1803
2121 Sources/Structure.swift:68
2040 Sources/Mesher.swift:1166
1958 Sources/Mesher.swift:1803
1661 Sources/AshSites.swift:295
1609 Sources/PowerSuit.swift:28
1597 Sources/NavalGuns.swift:73
1549 Sources/PowerSuit.swift:28
1470 Sources/NavalGuns.swift:73
1467 Sources/NavalGuns.swift:73
1440 Sources/Greywall.swift:852
1359 Sources/DebrisField.swift:58
1337 Sources/TexturesHD.swift:3728
1334 Sources/DebrisField.swift:58
1109 Sources/AdaptiveGround.swift:82
1068 Sources/AdaptiveGround.swift:82
1016 Sources/Mob.swift:2994
1002 Sources/GreywallAlarm.swift:420
958 Sources/Mob.swift:2994
904 Sources/HellMobs.swift:530
894 Sources/Director.swift:462
878 Sources/HellMobs.swift:530
867 Sources/Mob.swift:2994
852 Sources/main.swift:1436
847 Sources/main.swift:1436
749 Sources/HellLooks.swift:387
710 Sources/SmoothTerrain.swift:124
684 Sources/SmoothTerrain.swift:124
673 Sources/CampSmoke.swift:98
646 Sources/Renderer.swift:2874
```
### Snapshot
```
natural census: 63 sample chunks in 20186 ms
posecheck: weapon clearance: 330 of 925 poses had the weapon through an arm or the body before clearing; worst after 0.46 px
posecheck: 1034 raised limbs checked, 0 failed
textures: 2032 layers at 16 px, BC3, 0.7 MB with mips (build 1567 ms, upload 744 ms)
target: grass_block at 24 136 28, boxes [(SIMD3<Float>(0.0, 0.0, 0.0), SIMD3<Float>(1.0, 1.0, 1.0))], feet SIMD3<Float>(25.5, 136.0, 31.5)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0071 white=0.0008 std=39.8 hash=8e2bb75820bbfdf6
imagecheck fast.png magenta=0.00000 black=0.0071 white=0.0008 std=39.8 hash=8e2bb75820bbfdf6
seed 12345  pos 25.5 136.0 31.5  rd 4  chunks 109  (drawn 28)
gen 98988 ms  mesh(all, parallel) 22660 ms  mesh(1 section) 168.51 ms  quads 302646 opaque / 571 water
frame (encode+GPU, offscreen, median of 30) 17.52 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 11 MB), Metal allocated 114 MB
memory: resident 156 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
![fast](fast.png)
