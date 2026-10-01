# Blocksmith CI snapshots

Commit `b9b5f079bc3275cb55c4a1457a8e518d8a0452b1` on `claude/stoic-hypatia-70gb8a` — build: **success**, benchmarks: **failure**, snapshots: **failure**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/36923684845

```
light probe: eye sky 15 block 0 in air; floor+1 (y 117) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 28.2 219.4 9.0  rd 10  chunks 554  (drawn 105)
gen 406 ms  mesh(all, parallel) 418 ms  mesh(1 section) 0.85 ms  quads 1137878 opaque / 72874 water
frame (encode+GPU, offscreen, median of 30) 3.44 ms  biome forest
mesh slabs 56 MB, chunks 554 (block+light arrays 52 MB), Metal allocated 87 MB
memory: resident 176 MB  (section meshes 49 MB)
wrote snaps/ship_frigate.png
ship carriage: 1037 blocks 1925 t  pos -39.5 167.3 26.5  speed 0.00 b/s  turrets 1  crew 2  physics 0.24 ms/frame
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 84) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 2.0 177.7 24.9  rd 8  chunks 368  (drawn 70)
gen 238 ms  mesh(all, parallel) 284 ms  mesh(1 section) 1.37 ms  quads 866717 opaque / 46466 water
frame (encode+GPU, offscreen, median of 30) 2.76 ms  biome forest
mesh slabs 44 MB, chunks 368 (block+light arrays 34 MB), Metal allocated 75 MB
memory: resident 145 MB  (section meshes 37 MB)
wrote snaps/ship_carriage.png
physicstest boat: Assembled 126 blocks (68.0 t)
physicstest PASS: boat has helm, propeller and engine
physicstest boat: mass 68.0 t, submerged 68.0, draft 1.23, vy 0.000, up 1.000
physicstest PASS: boat floats upright at rest
physicstest boat: 10 s at full throttle: 39.0 blocks, speed 4.51 b/s, rider at 2.50 1.00 5.69 (deck 2.5 1.0 5.5)
physicstest PASS: boat sails under propeller power
physicstest PASS: player stays on the moving deck
physicstest boat: turned -92 degrees in 5 s
physicstest PASS: boat turns right under helm
physicstest boat: 6 sails, wind 5.0 b/s: drifted 9.3 blocks in 8 s
physicstest PASS: sails carry the boat with the wind
physicstest PASS: ship saves and loads (620 bytes)
physicstest gunboat: Assembled 135 blocks (94.1 t, 1 turret)
physicstest PASS: turret carries its cannons
physicstest gunboat: turret yaw 1.57 (wanted 1.57), bearing gap 0.000
physicstest PASS: turret turns on its ring and stays mounted
physicstest PASS: turret link saves and loads
physicstest gunboat: fired 3 shells, 20 of 20 wall blocks destroyed, 0 in flight
physicstest PASS: cannon shells fly and explode on impact
physicstest gunboat: blast removed 9 hull blocks
physicstest PASS: explosions break ship blocks
physicstest gunboat: sawn through 4 blocks: 1 new ship(s), 71 + 45 blocks
physicstest PASS: a hull cut in two becomes two ships
physicstest airship: Assembled 236 blocks (46.3 t)
physicstest airship: mass 46.3 t, 154 balloons, lift 0.15, drift -0.00 in 4 s
physicstest PASS: airship hovers
physicstest airship: climbed 11.5 in 3 s
physicstest PASS: airship climbs
physicstest airship: flew 52.9 blocks in 6 s, altitude change 0.11
physicstest PASS: airship flies level under propellers
physicstest plane: Assembled 78 blocks (25.7 t)
physicstest plane: mass 25.7 t, 38 airfoils, 6 s: 85.9 blocks, altitude change -9.4, speed 0.0, up 0.94
physicstest PASS: aircraft flies under power
physicstest plane: climb input 2 s: altitude change -0.6
physicstest FAIL: aircraft climbs when pulled up
physicstest takeoff: Assembled 81 blocks (27.5 t)
physicstest takeoff: rolled 46.0 blocks in 4 s (1.8 b/s), then 3 s pulled up: climbed 2.8, up 0.64
physicstest FAIL: aircraft takes off from a runway
physicstest car: Assembled 48 blocks (28.5 t)
physicstest car: mass 28.5 t, grounded yes, up 1.000, vy -0.000
physicstest PASS: car rests on its wheels
physicstest car: drove 39.3 blocks in 6 s, speed 7.93, up 1.000
physicstest PASS: car drives
physicstest car: docked 48 of 48 blocks back into the world
physicstest PASS: car docks back into the world
physicstest frigate: 3151 blocks 826 t, 1716 balloons, lift 0.24, 10 s patrol: 15.3 blocks, altitude change -0.00, up 1.000
physicstest PASS: frigate patrols at its altitude
physicstest frigate: turret aim error 0.000 rad
physicstest PASS: frigate turret tracks a target
physicstest carriage: 1037 blocks 1925 t, grounded yes, up 1.000, 6 s: 22.2 blocks
physicstest PASS: siege carriage rolls on six wheels
physicstest PASS: siege carriage's giant gun fires
physicstest encounters: 34 frigates, 20 siege carriages in 441 regions of 2048 blocks
physicstest PASS: vessel encounters are rare
physicstest: 2 checks failed, 2.1 s, ships 7
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 60) sky 9 block 0 in water, daylight 1.0
seed 12345  pos 123.2 134.4 55.0  rd 8  chunks 1068  (drawn 71)
gen 314 ms  mesh(all, parallel) 326 ms  mesh(1 section) 0.33 ms  quads 955172 opaque / 50130 water
frame (encode+GPU, offscreen, median of 30) 2.26 ms  biome river
mesh slabs 92 MB, chunks 1068 (block+light arrays 97 MB), Metal allocated 123 MB
memory: resident 229 MB  (section meshes 82 MB)
wrote snaps/physicstest.png
snap.sh: line 54: exit 1
```
### Playthrough
```
playthrough: seed 12345
---- spawn (0.0 s wall, 0 s game)
PASS spawn: standing on solid ground (oak_leaves at y 93)
PASS spawn: not in water or lava
PASS spawn: alive and healthy
---- gather + craft (0.2 s wall, 3 s game)
PASS gather: logs mined by hand (3)
INFO bulk: +3 oak_log (more trees)
PASS craft: 24 oak_planks
PASS craft: crafting table + wooden pickaxe
---- stone age (0.4 s wall, 14 s game)
PASS hold wooden pickaxe
PASS mine: 3 cobblestone with a wooden pickaxe (3 mined; bare hand would take 7.5 s and drop nothing)
INFO bulk: +8 cobblestone (more stone)
PASS craft: stone pickaxe + furnace
---- iron age (0.4 s wall, 20 s game)
PASS worldgen: iron ore within 64 blocks of spawn
PASS rules: wooden pickaxe can't harvest iron ore
PASS mine: raw iron with a stone pickaxe (1)
INFO coal from ore: 0
INFO bulk: +5 raw_iron (more iron ore)
FAIL place: furnace placed with a right click (air)
FAIL furnace block entity
INFO bulk: +6 iron_ingot (no furnace)
INFO bulk: +1 flint (gravel)
PASS craft: iron pickaxe + flint and steel
---- diamonds (0.9 s wall, 25 s game)
PASS worldgen: diamond ore within 80 blocks of spawn
PASS rules: stone pickaxe can't harvest diamond ore
PASS mine: diamond with an iron pickaxe at y -59 (1)
INFO bulk: +4 diamond (more diamonds)
INFO bulk: +3 string (spiders)
INFO bulk: +4 flint (gravel)
INFO bulk: +4 feather (chickens)
PASS craft: diamond pickaxe, sword, bow, 16 arrows
INFO bulk: +19 diamond (more diamonds)
INFO bulk: +5 gold_ingot (gold ore)
PASS armour: 19 armour points worn
---- obsidian + portal (1.0 s wall, 26 s game)
PASS fluids: water on a lava source makes obsidian (got obsidian)
PASS rules: iron pickaxe can't harvest obsidian
PASS rules: obsidian takes 9.4 s with a diamond pickaxe (9.4)
PASS mine: obsidian with a diamond pickaxe (1)
INFO bulk: +9 obsidian (more obsidian)
PASS portal: flint and steel lights the frame (nether_portal)
PASS portal: standing in the portal for 4 s goes to the Emberdeep
---- emberdeep (1.9 s wall, 45 s game)
PASS emberdeep: arrived inside a portal
PASS emberdeep: arrival portal is safe
PASS emberdeep: nearest fortress 138 blocks from the portal
PASS fortress: 4 cinderwisp spawner(s)
PASS fortress: the spawner makes cinderwisps
PASS fortress: 7 cinder rods from 15 cinderwisps in 468 s
INFO cinder rod rate 0.47 per kill (reference 0.5 without looting)
---- void pearls (10.9 s wall, 516 s game)
PASS voidwalkers: 12 void pearls from 21 kills
---- back to the surface (12.6 s wall, 624 s game)
PASS portal: back to the Surface through the arrival portal
PASS portal: returned to the portal we built (0 blocks off)
---- seeker eyes (12.9 s wall, 629 s game)
PASS craft: 12 seeker eyes
PASS worldgen: nearest stronghold 1727 blocks from the origin (first ring 1280-2816)
PASS seeker eye: thrown with a right click
PASS seeker eye: flew 11.6 blocks toward the stronghold
PASS seeker eye: drops or shatters after its flight
INFO bulk: +1 ender_eye (eye shattered)
---- stronghold (12.9 s wall, 633 s game)
PASS stronghold: portal room with 12 hollow gate frames
INFO stronghold: 3 frames already hold an eye
PASS hollow gate: 12/12 frames filled with right clicks
PASS hollow gate: the 3x3 gate opens (9/9)
---- the hollow (13.2 s wall, 634 s game)
PASS hollow gate: stepping in goes to the Hollow
PASS hollow: arrived on the obsidian platform at 100 49 0
PASS hollow: standing safely on the platform
PASS hollow: exactly one Hollow Wyrm (1)
PASS hollow: 10 hollow crystals on the spikes (10)
PASS wyrm: 200 health (200)
INFO fountain at y 58, spikes [76, 79, 82, 85, 88, 91, 94, 97, 100, 103]
---- crystals (13.3 s wall, 645 s game)
PASS crystals: all destroyed (10 by arrow, 0 up close, 0 left)
INFO crystal explosions cost 399 health so far (topped up)
---- hollow wyrm fight (13.5 s wall, 668 s game)
PASS wyrm: defeated in 208 s (3 perches, 21 sword hits, 25 arrows for 46 damage, health left 1)
INFO wyrm fight: player took 122 damage (half-hearts, healed by the test)
PASS wyrm: death sequence finishes
PASS wyrm: 12000 XP (level 13 -> 68)
PASS wyrm: gone after dying
PASS exit portal: active (24 gate blocks)
PASS egg: the wyrm egg sits on the exit portal (4)
PASS rift: a hollow rift gateway opened on the ring
---- egg (15.0 s wall, 889 s game)
PASS egg: hitting the egg makes it teleport (1 hops)
PASS egg: collected by dropping it onto a torch (1)
---- rift (15.1 s wall, 896 s game)
INFO bulk: +2 ender_pearl (spare pearls)
PASS rift: teleports to the far islands (1040 blocks out)
PASS rift: landed on solid ground (end_stone)
PASS rift: a return rift near the landing spot
---- hollow spire (15.1 s wall, 899 s game)
PASS spire: nearest hollow spire 1371 blocks from the landing spot (with ship)
INFO spire: 6 shellsentries
PASS spire: the ship's hold has glider wings
PASS wings: open with space while falling
PASS wings: glided 106 blocks while dropping 27
INFO after: player 1043.50 58.13 -4.47
FAIL rift: the return rift leads back to the central island (1044 blocks out)
---- save + reload (15.3 s wall, 909 s game)
PASS reload: back in the Hollow (end)
PASS reload: wyrm stays defeated (true, 1 rifts)
PASS reload: the egg is still in the inventory
PASS reload: exit portal still open (24)
PASS reload: no new wyrm appears
---- credits (15.4 s wall, 909 s game)
PASS exit portal: the credits roll
PASS credits: back on the Surface after the credits
PASS credits: at the spawn point
PASS credits: alive at home
---- blight (15.6 s wall, 965 s game)
INFO bulk: +4 soul_sand (emberdeep soul sand valley)
INFO bulk: +3 wither_skeleton_skull (blight skeletons (2.5% each))
PASS blight: soul sand T + three skulls summons the Blight
PASS blight: charging after the summon
PASS blight: 11 s charge ends at full health (300/300) with a blast
---- blight fight (23.6 s wall, 978 s game)
INFO bulk: Smite V on the sword, Power V on the bow
INFO bulk: +1 golden_helmet (armour)
INFO bulk: +1 diamond_chestplate (armour)
INFO bulk: +1 diamond_leggings (armour)
INFO bulk: +1 diamond_boots (armour)
PASS armour: 19 armour points worn
PASS blight: defeated in 30 s (13 arrows for 168 damage, 8 sword hits)
PASS blight: arrows bounce off its armour below half health (0 damage from 3)
INFO blight fight: player took 91 damage (healed by the test); 8 of 8 sword hits landed for 154
PASS blight: the Blight Star drops and is picked up (1)
INFO bulk: +5 glass (sand + furnace)
INFO bulk: +3 obsidian (obsidian)
PASS craft: beacon from the Blight Star
---- advancements (24.0 s wall, 1016 s game)
PASS advancement nether/obtain_blaze_rod
PASS advancement end/root
PASS advancement end/kill_dragon
PASS advancement end/dragon_egg
PASS advancement end/enter_end_gateway
PASS advancement nether/summon_wither
INFO 19 advancements earned: adventure/kill_a_mob, adventure/root, end/dragon_egg, end/elytra, end/enter_end_gateway, end/kill_dragon, end/root, enter_the_end, enter_the_nether, iron_tools, mine_stone, nether/find_fortress, nether/obtain_blaze_rod, nether/root, nether/summon_wither, root, shiny_gear, smelt_iron, upgrade_tools
---- summary (24.0 s wall, 1018 s game)
INFO deaths: 0, damage healed by the test: 642 half-hearts
playthrough: 3 failed checks, 1018 s of game time in 24.0 s wall
```
### Synthesized sounds
- [bell.wav](sounds/bell.wav)
- [birdCall.wav](sounds/birdCall.wav)
- [break_glass.wav](sounds/break_glass.wav)
- [break_wood.wav](sounds/break_wood.wav)
- [bulletWhizz.wav](sounds/bulletWhizz.wav)
- [bullet_impact_metal.wav](sounds/bullet_impact_metal.wav)
- [carriageTreadLoop.wav](sounds/carriageTreadLoop.wav)
- [chestOpen.wav](sounds/chestOpen.wav)
- [doorOpen.wav](sounds/doorOpen.wav)
- [dragonGrowl.wav](sounds/dragonGrowl.wav)
- [engineFullLoop.wav](sounds/engineFullLoop.wav)
- [explode.wav](sounds/explode.wav)
- [frigateDroneLoop.wav](sounds/frigateDroneLoop.wav)
- [gun_0.wav](sounds/gun_0.wav)
- [gun_1.wav](sounds/gun_1.wav)
- [gun_10.wav](sounds/gun_10.wav)
- [gun_2.wav](sounds/gun_2.wav)
- [gun_3.wav](sounds/gun_3.wav)
- [gun_4.wav](sounds/gun_4.wav)
- [gun_5.wav](sounds/gun_5.wav)
- [gun_9.wav](sounds/gun_9.wav)
- [gun_distant_0.wav](sounds/gun_distant_0.wav)
- [gun_reload_0.wav](sounds/gun_reload_0.wav)
- [hullCreak.wav](sounds/hullCreak.wav)
- [levelUp.wav](sounds/levelUp.wav)
- [lever.wav](sounds/lever.wav)
- [mob_cow_ambient.wav](sounds/mob_cow_ambient.wav)
- [mob_enderman_ambient.wav](sounds/mob_enderman_ambient.wav)
- [mob_ghast_ambient.wav](sounds/mob_ghast_ambient.wav)
- [mob_skeleton_hurt.wav](sounds/mob_skeleton_hurt.wav)
- [mob_villager_ambient.wav](sounds/mob_villager_ambient.wav)
- [mob_warden_death.wav](sounds/mob_warden_death.wav)
- [mob_zombie_ambient.wav](sounds/mob_zombie_ambient.wav)
- [mountainWindLoop.wav](sounds/mountainWindLoop.wav)
- [note_0_12.wav](sounds/note_0_12.wav)
- [owlHoot.wav](sounds/owlHoot.wav)
- [pistonExtend.wav](sounds/pistonExtend.wav)
- [place_metal.wav](sounds/place_metal.wav)
- [propFastLoop.wav](sounds/propFastLoop.wav)
- [riverLoop.wav](sounds/riverLoop.wav)
- [shipCollideHard.wav](sounds/shipCollideHard.wav)
- [soldier_1_alert.wav](sounds/soldier_1_alert.wav)
- [soldier_3_death.wav](sounds/soldier_3_death.wav)
- [step_gravel.wav](sounds/step_gravel.wav)
- [step_stone.wav](sounds/step_stone.wav)
- [step_wood.wav](sounds/step_wood.wav)
- [thunder.wav](sounds/thunder.wav)
- [thunderFar.wav](sounds/thunderFar.wav)
- [villager_work_0.wav](sounds/villager_work_0.wav)
- [wardenRoar.wav](sounds/wardenRoar.wav)
- [waterfallLoop.wav](sounds/waterfallLoop.wav)
- [wingRushLoop.wav](sounds/wingRushLoop.wav)
- [witherSpawn.wav](sounds/witherSpawn.wav)
### audiotest
![audiotest.png](audiotest.png)
### physicstest
![physicstest.png](physicstest.png)
### relief_1
![relief_1.png](relief_1.png)
### relief_12345
![relief_12345.png](relief_12345.png)
### relief_424242
![relief_424242.png](relief_424242.png)
### relief_777
![relief_777.png](relief_777.png)
### relief_98765
![relief_98765.png](relief_98765.png)
### ship_airship
![ship_airship.png](ship_airship.png)
### ship_boat
![ship_boat.png](ship_boat.png)
### ship_car
![ship_car.png](ship_car.png)
### ship_carriage
![ship_carriage.png](ship_carriage.png)
### ship_deck
![ship_deck.png](ship_deck.png)
### ship_frigate
![ship_frigate.png](ship_frigate.png)
### ship_gunboat
![ship_gunboat.png](ship_gunboat.png)
### ship_plane
![ship_plane.png](ship_plane.png)
### spawn
![spawn.png](spawn.png)
### terrain_1
![terrain_1.png](terrain_1.png)
### terrain_12345
![terrain_12345.png](terrain_12345.png)
### terrain_424242
![terrain_424242.png](terrain_424242.png)
### terrain_777
![terrain_777.png](terrain_777.png)
### terrain_98765
![terrain_98765.png](terrain_98765.png)
### tour_12345_aerial
![tour_12345_aerial.png](tour_12345_aerial.png)
### tour_12345_low
![tour_12345_low.png](tour_12345_low.png)
### tour_1_aerial
![tour_1_aerial.png](tour_1_aerial.png)
### tour_1_low
![tour_1_low.png](tour_1_low.png)
### tour_424242_aerial
![tour_424242_aerial.png](tour_424242_aerial.png)
### tour_424242_low
![tour_424242_low.png](tour_424242_low.png)
### tour_777_aerial
![tour_777_aerial.png](tour_777_aerial.png)
### tour_777_low
![tour_777_low.png](tour_777_low.png)
### tour_98765_aerial
![tour_98765_aerial.png](tour_98765_aerial.png)
### tour_98765_low
![tour_98765_low.png](tour_98765_low.png)
### tour_coast
![tour_coast.png](tour_coast.png)
### tour_desert
![tour_desert.png](tour_desert.png)
### tour_forest_floor
![tour_forest_floor.png](tour_forest_floor.png)
### tour_jungle
![tour_jungle.png](tour_jungle.png)
### tour_mesa
![tour_mesa.png](tour_mesa.png)
### tour_peaks
![tour_peaks.png](tour_peaks.png)
### tour_river
![tour_river.png](tour_river.png)
### tour_river_777
![tour_river_777.png](tour_river_777.png)
### tour_snowline
![tour_snowline.png](tour_snowline.png)
