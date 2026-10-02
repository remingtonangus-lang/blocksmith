# Bug classes

Each class: what goes wrong, the oracle that catches it (machine, not a human), instances, the fix, status.
Status: open (oracle finds instances), fixed (oracle at 0 on CI, check made strict), watching (fixed, not strict yet).

| Class | Oracle | Instances | Fix | Status |
|---|---|---|---|---|
| Village house floors a block above the door sill (must jump in; beds, tables, villager spawns set into the floor) | `--structcheck` door_step, mob_in_block; `--agent village` goal | every village house (Remington, playtest) | floor at the sill level, lots on street ground (door_step 146 -> 4, villager mob_in_block 175 -> 0); door front cleared of road lamp posts | watching |
| Villagers acting weird (walking into walls, hopping, falling off ledges) | `--behaviorsim` stuck/fell/goal_missed | 62-103 stuck windows per villager, goals ~50% | root cause: wander() picked a random heading and walked straight; strolls now pathfind to a standable spot 3-9 blocks away (every wandering mob) | watching |
| Structure mobs spawned inside walls / furniture | `--structcheck` mob_in_block | 17 (end city 9, mansion 4, monument 2, ocean ruin 2) | World.freeSpawn nudges every pending structure mob to the nearest clear cell when its chunk installs | watching |
| Cave water standing as vertical walls beside air at aquifer cell edges (and over dry caves) | `--gencheck` leak | 18,692 over 288 chunks | dry side of a flooded aquifer cell keeps a rock barrier; no aquifer water over open cave air | watching |
| Far ocean showed the sky through the water (LOD 1 dropped unlit seabed faces) | tour_777_aerial visual check | seed 777 | Mesher keeps faces into water / sections with water at LOD 1 (1d894fa) | watching |
| Explosions destroyed the Blight Star | playthrough "Blight Star drops and is picked up" | 1 (run 338) | star survives blasts (ca7df81) | watching |
| Kelp / seagrass out of water | `--kelpcheck` | 0 kelp; seagrass in 1-deep shallows only | - | fixed |
| Build breaks only a compiler would catch (unbalanced braces) | tools/precheck.py (pre-push) | 1 (run 340) | precheck before every push | fixed |
| Expressions that time out the Mac's type checker | CI type-check gate (>= 600 ms) | ~35 split so far | typed lets, plain loops | watching |
| Mobs act and heal between a lethal hit and the death sweep (the Blight regenerated 1 HP and survived, losing the Blight Star) | playthrough "Blight Star drops and is picked up" | 1 (run 344) | Mob.update returns for health <= 0 (except the wyrm's death sequence); Blight regen / skull-kill heal only while alive | fix pushed |
| Mobs push into a wall forever when their goal is unreachable (A* returns a partial path to the closest cell) | `--behaviorsim` stuck (villagers stuck 78-111 of ~120 windows) | 199 stuck windows | give-up memory (15 s) at the end of a partial path or after 4 s without progress; strolls/schedules/beds skip given-up goals; villagers really walk to bed at night (the day schedule re-aimed them the same tick) | fix pushed |
| Decorative model boxes form a staircase the 0.6 step-up climbs (dragon egg, brewing stand, hanging lanterns, bell, stonecutter) | `--collisiontest` walk_through | 17 shapes | separate reference collision shapes (BlockRegistry.collisionShape) | fix pushed |
| Floating fancy-oak branch tips (log at len/2 and len: 2-block gap for len 3) | `--gencheck` trunk_floating | 29 | branches drawn as connected limbs | fix pushed |
| Grass / bushes left standing on structure blocks (village cobblestone) | `--gencheck` plant_soil | 3 | StructWriter removes soil plants above any non-soil block it writes | fix pushed |
| Missing-texture oracle false positive on crying obsidian's glowing tears | imagecheck magenta (gallery_hollow) | 1 shot | magenta counted only when red = blue (missing texture is pure magenta) | fix pushed |
| Distant cutout leaves turn into sparse black speckles (transparent texels' black RGB filtered in; alpha coverage thins per mip) | tour_777_aerial / forest_in eyes-on | spruce, dark oak crowns at 20+ blocks | colour bled into transparent texels; coverage-preserving alpha per mip level | fix pushed |
| Structures whose rooms/floors are sealed from each other (stronghold corridor end caps, trial-chamber corridors walled through the atrium, end-city house without stairs up, mansion stairs under the next floor, outpost with no door and a roofed-over ladder) | `--structcheck` poi_unreachable (all POIs of the kind) | stronghold 80/80, end city 33/33, trial chambers 19/19, mansion 24/36, outpost 7/7 | joints opened, corridors cut after rooms, stairwells cut after floors, doorway + roof ladder | fix pushed |
| Held block / arm in daylight colours under water | Gemini critic (underwater.png) | every underwater view | first-person pass fogs toward the water colour | fix pushed |
| Seabed covered by a uniform field of seagrass (40 % of columns) | eyes-on underwater.png | every ocean | seagrass meadows from low-frequency noise | fix pushed |
| Inventory player-preview box empty | Gemini critic (inventory.png) | always | player model projected into the HUD box | fix pushed |
