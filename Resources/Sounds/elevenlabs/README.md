# ElevenLabs sound effects (approved by Remington)

Generated with ElevenLabs sound generation (Remington's account, Starter plan), then approved one by one by Remington on
Oct 25, 2026 (batch 1: all 26 kept; batch 2: 50 of 56 kept). Converted from the MP3 that ElevenLabs returns to WAV, 44.1 kHz mono 16-bit,
with no other processing.

Wired in on Oct 29, 2026 (P457): each file now lives in `Resources/Sounds/real/` under the name of the game sound it
plays as (the "plays as" column; the originals are in git history). `tools/elevenlabs_wire.py` did the move and says
the rules: a loop replaces the old loop; a one-shot takes the base slot and the older recording stays on as another
take; files of several hits (footsteps, pick and axe strikes, bites, gulps, hoof falls, rungs, swim strokes, shots of a
burst) are cut into single hits that replace the old takes of that sound. Sounds that had no event before (tank, truck
and motorbike engines, the helicopter rotor, the jetpack, sonar, the ship's horn, the air raid siren, battle, town and
forest ambience, the saloon piano, metal ladders, armour hits, the pack rustle, the frigate's interior, dart traps,
flak, the tank gun, the plane passing) got their own sound and the code that plays it.

"Loop" means the prompt asked for a seamless loop; ElevenLabs does not guarantee the seam.

| file | length | loop | plays as | prompt |
|---|---|---|---|---|
| `tank_engine_idle_loop.wav` | 6.0 s | yes | `tankEngineLoop` | Heavy WW2 tank diesel engine idling, deep rumbling with metal rattles, steady, seamless loop |
| `tank_tracks_drive_loop.wav` | 6.0 s | yes | `tankTracksLoop` | WW2 tank driving on dirt, squeaking and clanking steel tracks with engine roar, seamless loop |
| `tank_cannon_fire.wav` | 3.0 s | no | `tankCannon` | Heavy WW2 tank main cannon firing, deep boom with metallic clank of the breech and a short rolling echo, outdoors |
| `truck_engine_drive_loop.wav` | 6.0 s | yes | `truckEngineLoop` | 1940s military cargo truck driving, petrol engine with gear whine and rattling body, seamless loop |
| `motorcycle_sidecar_engine_loop.wav` | 5.0 s | yes | `motorbikeLoop` | 1940s military motorcycle with sidecar, single-cylinder engine at cruising speed, seamless loop |
| `propeller_plane_flyby.wav` | 5.0 s | no | `planeFlyby` | WW2 propeller fighter plane flying fast overhead, rising and falling engine roar, doppler flyby |
| `siege_carriage_engine_loop.wav` | 6.0 s | yes | `carriageTreadLoop` | Enormous heavy armored land vehicle engine, huge low diesel roar with grinding gears and creaking steel hull, seamless loop |
| `bolt_rifle_shot.wav` | 2.0 s | no | `gun_16` | WW2 bolt-action rifle single gunshot outdoors, sharp crack with short echo |
| `assault_rifle_burst.wav` | 2.0 s | no | `gun_18_1..3 (3 hits)` | WW2-era assault rifle short three-round burst outdoors, punchy, with echo |
| `pistol_shot.wav` | 1.5 s | no | `gun_13` | 1940s semi-automatic pistol single gunshot, snappy, outdoors |
| `smg_burst.wav` | 2.0 s | no | `gun_17_1..5 (5 hits)` | WW2 submachine gun short burst, fast rattling, outdoors |
| `sniper_shot_distant.wav` | 3.0 s | no | `gun_distant_3` | Distant sniper rifle shot echoing across a snowy valley |
| `magazine_reload.wav` | 2.0 s | no | `gun_reload_18` | Rifle magazine reload: magazine out, new magazine slotted in, bolt racked, metallic |
| `gun_jam_click.wav` | 1.0 s | no | `gun_7` | Firearm jamming: dry trigger click then a stuck bolt rattle |
| `rocket_launch.wav` | 2.5 s | no | `gun_4` | Shoulder-fired rocket launching with a whoosh and backblast |
| `artillery_incoming_explosion.wav` | 4.0 s | no | `explodeLarge_2` | Artillery shell whistling in from above then a huge explosion with dirt and debris falling |
| `naval_gun_blast.wav` | 4.0 s | no | `gun_9` | Enormous battleship naval gun firing, massive concussive boom with long rolling echo |
| `flak_gun_fire.wav` | 3.0 s | no | `flakFire_1..3 (3 hits)` | WW2 anti-aircraft flak cannon firing several rapid heavy rounds |
| `large_explosion_debris.wav` | 4.0 s | no | `explodeLarge` | Large explosion destroying a stone building, boom followed by falling rubble and debris |
| `grenade_explosion.wav` | 2.5 s | no | `explodeSmall` | Hand grenade explosion outdoors, sharp blast with dirt spray |
| `bulkhead_door_open.wav` | 3.0 s | no | `ironDoorOpen` | Heavy steel bulkhead door on a warship being unlatched and swung open, metal groan and clunk |
| `frigate_interior_hum_loop.wav` | 8.0 s | yes | `frigateInsideLoop` | Interior of a large military airship, low engine hum with creaking steel and distant machinery, seamless loop |
| `hell_lava_ambience_loop.wav` | 8.0 s | yes | `netherWastesLoop` | Underground volcanic hell cavern ambience, bubbling lava, distant rumbles and hissing vents, seamless loop |
| `big_fire_crackle_loop.wav` | 6.0 s | yes | `campfireLoop` | Large campfire burning, crackling wood and popping embers, seamless loop |
| `snow_wind_loop.wav` | 8.0 s | yes | `snowWindLoop` | Cold wind blowing across a snowy plain, gusts with fine snow hiss, seamless loop |
| `footsteps_grass.wav` | 3.0 s | no | `step_grass_1..5 (5 hits)` | Footsteps walking on short dry grass and firm soil, about six steps, natural pace |

## Batch 2 (Oct 25, 50 kept)

Cut by Remington, not included (his notes in brackets): bow_arrow_shot, hell_creature_growl (too disgusting), marauder_war_cry (too inauthentic), minigun_spinup_fire, tree_crack_fall (doesn't sound right), wooden_door_open_creak (too annoying).

| file | length | loop | plays as | prompt |
|---|---|---|---|---|
| `helicopter_rotor_loop.wav` | 6.0 s | yes | `rotorLoop` | Military transport helicopter rotor blades thumping overhead with turbine whine, seamless loop |
| `dropship_engine_loop.wav` | 6.0 s | yes | `strikeRoarLoop` | Heavy futuristic military dropship hovering, deep jet thrusters with humming turbines, seamless loop |
| `jetpack_thrust_loop.wav` | 4.0 s | yes | `jetpackLoop` | Personal jetpack thrusting, roaring rocket flame with hiss, seamless loop |
| `submarine_sonar_ping.wav` | 4.0 s | no | `sonarPing` | Submarine sonar ping echoing underwater, single ping with long fading echo |
| `ship_horn_distant.wav` | 4.0 s | no | `shipHorn` | Large steamship horn blowing in the distance over water |
| `rail_cart_rolling_loop.wav` | 6.0 s | yes | `minecartLoop` | Heavy iron mine cart rolling fast on steel rails, rhythmic clacking and rumble, seamless loop |
| `sword_swing_hit.wav` | 1.5 s | no | `armourHit` | Steel sword swinging through the air and striking a body, whoosh then heavy impact (Remington: only on armour hits) |
| `shield_block_metal.wav` | 1.5 s | no | `shieldBlock` | Heavy metal shield blocking a sword strike, loud clang |
| `arrow_trap_fire.wav` | 2.0 s | no | `dartTrap` | Hidden dart trap in an ancient stone temple firing arrows with a mechanical click and whoosh |
| `tnt_fuse_hiss.wav` | 3.0 s | no | `tntFuse` | Lit fuse on explosive charge, sparking and hissing |
| `bombs_falling_whistle.wav` | 4.0 s | no | `shellIncoming` | Aerial bombs whistling down from a plane, several descending whistles, no explosion |
| `air_raid_siren.wav` | 6.0 s | no | `airRaidSiren` | WW2 air raid siren winding up and wailing in a town |
| `base_alarm_klaxon_loop.wav` | 4.0 s | yes | `gun_10` | Military base alarm klaxon blaring in a concrete corridor, seamless loop |
| `distant_battle_ambience_loop.wav` | 8.0 s | yes | `battleLoop` | Distant battlefield ambience, faraway gunfire, muffled explosions and artillery, seamless loop |
| `radio_static_chatter.wav` | 4.0 s | no | `gun_11` | Military field radio static with garbled unintelligible voice chatter and squelch, no clear words |
| `metal_door_slam.wav` | 2.0 s | no | `ironDoorClose` | Heavy steel door slamming shut with echo in a concrete bunker |
| `chest_open_wood.wav` | 1.5 s | no | `chestOpen` | Wooden treasure chest lid opening with a creak and thunk |
| `glass_shatter.wav` | 2.0 s | no | `break_glass` | Window glass shattering and falling onto a stone floor |
| `leaves_rustle_push.wav` | 3.0 s | no | `plantBrush_1..2 (2 hits)` | Pushing through dense jungle leaves and thin branches, rustling and snapping twigs |
| `stone_mining_pick.wav` | 2.0 s | no | `hit_stone_1..3 (3 hits)` | Iron pickaxe striking hard stone three times, sharp chips and clinks |
| `wood_chop_axe.wav` | 2.0 s | no | `hit_wood_1..3 (3 hits)` | Axe chopping into a thick wooden log twice, solid thunks |
| `dirt_dig_shovel.wav` | 2.0 s | no | `break_dirt` | Shovel digging into soft dirt and tossing it aside |
| `footsteps_snow.wav` | 3.0 s | no | `step_snow_1..5 (5 hits)` | Footsteps crunching through fresh deep snow, about six steps |
| `footsteps_gravel.wav` | 3.0 s | no | `step_gravel_1..5 (5 hits)` | Footsteps on loose gravel, about six steps, natural pace |
| `footsteps_wood_floor.wav` | 3.0 s | no | `step_wood_1..5 (5 hits)` | Boots walking on old wooden floorboards inside a saloon, about six steps with slight creaks |
| `footsteps_metal_deck.wav` | 3.0 s | no | `step_metal_1..5 (5 hits)` | Boots walking on a steel ship deck, metallic clanks, about six steps |
| `ladder_climb_metal.wav` | 3.0 s | no | `ladderClimb_1..5 (5 hits)` | Climbing a metal ladder, hands and boots clanking on rungs |
| `water_splash_jump.wav` | 2.0 s | no | `splash` | Person jumping into a lake, big splash |
| `swimming_strokes_loop.wav` | 5.0 s | yes | `swim_1..5 (5 hits)` | Swimming strokes in calm water, rhythmic splashes, seamless loop |
| `underwater_ambience_loop.wav` | 8.0 s | yes | `underwaterLoop` | Muffled underwater ambience with bubbles and low drone, seamless loop |
| `river_flow_loop.wav` | 8.0 s | yes | `riverLoop` | Gentle forest river flowing over rocks, seamless loop |
| `ocean_waves_loop.wav` | 8.0 s | yes | `oceanLoop` | Ocean waves rolling onto a sandy beach, seamless loop |
| `rain_heavy_loop.wav` | 8.0 s | yes | `rain` | Heavy rain falling on leaves and ground with occasional drips, seamless loop |
| `rain_on_roof_loop.wav` | 8.0 s | yes | `rainRoof` | Rain pattering on a wooden cabin roof, heard from inside, seamless loop |
| `thunder_crack.wav` | 5.0 s | no | `thunder` | Close thunder crack followed by long rolling rumble |
| `cave_drips_ambience_loop.wav` | 8.0 s | yes | `dripstoneLoop` | Deep stone cave ambience with water drips echoing and faint low wind, seamless loop |
| `forest_birds_day_loop.wav` | 8.0 s | yes | `forestDayLoop` | Daytime temperate forest ambience with songbirds and light breeze, seamless loop |
| `night_crickets_loop.wav` | 8.0 s | yes | `cricketsLoop` | Night countryside ambience with crickets and a distant owl, seamless loop |
| `village_ambience_loop.wav` | 8.0 s | yes | `townLoop` | Old western frontier town ambience, distant chatter murmur, horse hooves, creaking signs, no clear words, seamless loop |
| `saloon_piano_loop.wav` | 8.0 s | yes | `saloonPianoLoop` | Honky-tonk upright piano playing a simple ragtime tune in a saloon, seamless loop |
| `horse_gallop_loop.wav` | 4.0 s | yes | `hoof_earth_1..5 (5 hits)` | Horse galloping on hard dirt road, rhythmic hoofbeats, seamless loop |
| `horse_neigh.wav` | 2.0 s | no | `mob_horse_ambient` | Horse neighing and snorting |
| `eat_food.wav` | 2.0 s | no | `eat_1..3 (3 hits)` | Person eating, crunchy bites and chewing |
| `drink_gulp.wav` | 2.0 s | no | `drink_1..3 (3 hits)` | Drinking from a canteen, a few gulps and a sigh |
| `body_hit_thud.wav` | 1.0 s | no | `attackWeak` | Heavy punch impact on a body, dull thud |
| `hell_creature_screech.wav` | 2.0 s | no | `mob_searwing_ambient` | Flying fiery hell creature screeching, sharp and inhuman |
| `fire_ignite_whoosh.wav` | 2.0 s | no | `ignite` | Fire igniting with a whoosh as flames catch |
| `lava_bubble_pop.wav` | 2.0 s | no | `lavaPop` | Thick lava bubbling and popping |
| `crafting_hammer_anvil.wav` | 2.0 s | no | `anvil_1..4 (4 hits)` | Blacksmith hammer striking an anvil twice, ringing metal |
| `inventory_cloth_rustle.wav` | 1.0 s | no | `packRustle` | Soft canvas backpack rustle as items are moved, short |
