# Blocksmith CI snapshots

Commit `bd4a908e79c9ee7b7c93c0e7af810fc09421d51f` on `claude/serene-bardeen-tu35re` — build: **success**, benchmarks: **failure**, snapshots: **failure**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/36923469095

```
memory: resident 181 MB  (section meshes 32 MB)
wrote snaps/vehicle_hud.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 75)
gen 166 ms  mesh(all, parallel) 223 ms  mesh(1 section) 0.65 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 8.31 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 146 MB
memory: resident 210 MB  (section meshes 32 MB)
wrote snaps/tv_map.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 71)
gen 169 ms  mesh(all, parallel) 221 ms  mesh(1 section) 0.63 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 3.48 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 117 MB
memory: resident 180 MB  (section meshes 32 MB)
wrote snaps/controls_ref.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 75)
gen 161 ms  mesh(all, parallel) 257 ms  mesh(1 section) 0.63 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 6.01 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 146 MB
memory: resident 209 MB  (section meshes 32 MB)
wrote snaps/tv_hud.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 71)
gen 176 ms  mesh(all, parallel) 222 ms  mesh(1 section) 0.64 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 3.42 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 117 MB
memory: resident 181 MB  (section meshes 32 MB)
wrote snaps/furnace.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 158.0 8.5  rd 8  chunks 297  (drawn 69)
gen 159 ms  mesh(all, parallel) 218 ms  mesh(1 section) 0.72 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 2.82 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 117 MB
memory: resident 182 MB  (section meshes 32 MB)
wrote snaps/drops.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 71)
gen 193 ms  mesh(all, parallel) 293 ms  mesh(1 section) 0.72 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 3.37 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 117 MB
memory: resident 180 MB  (section meshes 32 MB)
wrote snaps/subtitles.png
textures without a painter: missing
light probe: eye sky 15 block 0 in air; floor+1 (y 93) sky 15 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 297  (drawn 71)
gen 206 ms  mesh(all, parallel) 218 ms  mesh(1 section) 0.65 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 3.43 ms  biome forest
mesh slabs 36 MB, chunks 297 (block+light arrays 28 MB), Metal allocated 117 MB
memory: resident 181 MB  (section meshes 32 MB)
wrote snaps/survival.png
sim 12.0 s: tick avg 0.35 ms, worst 6.84 ms | pos -3.7 155.0 6.7 | health 20 hunger 20 | mobs 113 | fluid pending 942 | items held 571, dropped 4
textures without a painter: missing
light probe: eye sky 12 block 0 in air; floor+1 (y 91) sky 11 block 0 in air, daylight 1.0
seed 12345  pos 8.5 157.0 8.5  rd 8  chunks 316  (drawn 77)
gen 159 ms  mesh(all, parallel) 214 ms  mesh(1 section) 0.66 ms  quads 996045 opaque / 49989 water
frame (encode+GPU, offscreen, median of 30) 3.29 ms  biome forest
mesh slabs 40 MB, chunks 316 (block+light arrays 30 MB), Metal allocated 121 MB
memory: resident 196 MB  (section meshes 35 MB)
wrote snaps/sim.png
FAIL mountainWindLoop: silent (peak 0.000), too quiet (rms 0.0000)
FAIL snowWindLoop: silent (peak 0.000), too quiet (rms 0.0000)
  Blocks: 190 sounds
  Hostile Mobs: 197 sounds
  Friendly Mobs: 176 sounds
  Players: 127 sounds
  Ambient: 42 sounds
  Weather: 8 sounds
  Interface: 5 sounds
  wrote 32 soundscapes to build/sounds/scapes
  slowest renders: place_glass 18 ms, beaconActivate 16 ms, endPortalOpen 15 ms, hiveLoop 14 ms, endLoop 14 ms, swampInsectsLoop 13 ms
synthesized 745 sounds (659.6 s of audio) in 3108 ms, 2 failed
snap.sh: line 95: exit 1
```
### Synthesized sounds
- [*.wav](sounds/*.wav)
### aerial
![aerial.png](aerial.png)
### aerial16
![aerial16.png](aerial16.png)
### aerial16_424242
![aerial16_424242.png](aerial16_424242.png)
### aerial16_777
![aerial16_777.png](aerial16_777.png)
### aerial16_fast
![aerial16_fast.png](aerial16_fast.png)
### aerial24
![aerial24.png](aerial24.png)
### biome_badlands
![biome_badlands.png](biome_badlands.png)
### biome_birch_forest
![biome_birch_forest.png](biome_birch_forest.png)
### biome_cherry_grove
![biome_cherry_grove.png](biome_cherry_grove.png)
### biome_dark_forest
![biome_dark_forest.png](biome_dark_forest.png)
### biome_desert
![biome_desert.png](biome_desert.png)
### biome_jagged_peaks
![biome_jagged_peaks.png](biome_jagged_peaks.png)
### biome_jungle
![biome_jungle.png](biome_jungle.png)
### biome_mangrove_swamp
![biome_mangrove_swamp.png](biome_mangrove_swamp.png)
### biome_savanna
![biome_savanna.png](biome_savanna.png)
### biome_swamp
![biome_swamp.png](biome_swamp.png)
### biome_taiga
![biome_taiga.png](biome_taiga.png)
### biome_warm_ocean
![biome_warm_ocean.png](biome_warm_ocean.png)
### bugnotes
![bugnotes.png](bugnotes.png)
### clouds
![clouds.png](clouds.png)
### controls_ref
![controls_ref.png](controls_ref.png)
### crack
![crack.png](crack.png)
### crafting
![crafting.png](crafting.png)
### creative
![creative.png](creative.png)
### down
![down.png](down.png)
### drops
![drops.png](drops.png)
### forest
![forest.png](forest.png)
### forest_in
![forest_in.png](forest_in.png)
### furnace
![furnace.png](furnace.png)
### ground16
![ground16.png](ground16.png)
### ground16_fast
![ground16_fast.png](ground16_fast.png)
### inventory
![inventory.png](inventory.png)
### inventory_pad
![inventory_pad.png](inventory_pad.png)
### lake
![lake.png](lake.png)
### lake_glint
![lake_glint.png](lake_glint.png)
### meadow
![meadow.png](meadow.png)
### night
![night.png](night.png)
### ocean_night_777
![ocean_night_777.png](ocean_night_777.png)
### ocean_night_777_fast
![ocean_night_777_fast.png](ocean_night_777_fast.png)
### padmap
![padmap.png](padmap.png)
### padtest
![padtest.png](padtest.png)
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
### shore
![shore.png](shore.png)
### sim
![sim.png](sim.png)
### snowy
![snowy.png](snowy.png)
### spawn
![spawn.png](spawn.png)
### stars
![stars.png](stars.png)
### subtitles
![subtitles.png](subtitles.png)
### sunset
![sunset.png](sunset.png)
### sunset_fast
![sunset_fast.png](sunset_fast.png)
### sunset_sun
![sunset_sun.png](sunset_sun.png)
### survival
![survival.png](survival.png)
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
### torches
![torches.png](torches.png)
### torches_day
![torches_day.png](torches_day.png)
### torches_near
![torches_near.png](torches_near.png)
### tour_12345_aerial
![tour_12345_aerial.png](tour_12345_aerial.png)
### tour_12345_ground
![tour_12345_ground.png](tour_12345_ground.png)
### tour_1_aerial
![tour_1_aerial.png](tour_1_aerial.png)
### tour_1_ground
![tour_1_ground.png](tour_1_ground.png)
### tour_424242_aerial
![tour_424242_aerial.png](tour_424242_aerial.png)
### tour_424242_ground
![tour_424242_ground.png](tour_424242_ground.png)
### tour_777_aerial
![tour_777_aerial.png](tour_777_aerial.png)
### tour_777_ground
![tour_777_ground.png](tour_777_ground.png)
### tour_98765_aerial
![tour_98765_aerial.png](tour_98765_aerial.png)
### tour_98765_ground
![tour_98765_ground.png](tour_98765_ground.png)
### tour_coast
![tour_coast.png](tour_coast.png)
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
### tv_combat
![tv_combat.png](tv_combat.png)
### tv_confirm
![tv_confirm.png](tv_confirm.png)
### tv_hud
![tv_hud.png](tv_hud.png)
### tv_keyboard
![tv_keyboard.png](tv_keyboard.png)
### tv_map
![tv_map.png](tv_map.png)
### tv_options
![tv_options.png](tv_options.png)
### tv_title
![tv_title.png](tv_title.png)
### tv_worlds
![tv_worlds.png](tv_worlds.png)
### underwater
![underwater.png](underwater.png)
### underwater_up
![underwater_up.png](underwater_up.png)
### vehicle_hud
![vehicle_hud.png](vehicle_hud.png)
### water_flow
![water_flow.png](water_flow.png)
