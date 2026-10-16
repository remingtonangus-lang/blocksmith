# Blocksmith fast lane

Commit `dfe3d88c859ca2c9cae3da5184bfe527c985cb14` on `claude/bs-destruction`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/38862550216

### Build errors
```
```
### Type-check (warnings, slowest first)
```
641 Sources/CapitalShips.swift:1369
595 Sources/Cinematic.swift:141
576 Sources/CapitalShips.swift:1369
555 Sources/Cinematic.swift:141
417 Sources/BaseTests.swift:107
404 Sources/BaseTests.swift:107
347 Sources/Cinematic.swift:141
340 Sources/CapitalBases.swift:282
323 Sources/TexturesHD.swift:3990
294 Sources/GameCircuit.swift:267
292 Sources/ShipCombat.swift:135
262 Sources/Mesher.swift:95
243 Sources/GameCircuit.swift:267
238 Sources/TerrainTools.swift:81
232 Sources/main.swift:1351
227 Sources/main.swift:1476
218 Sources/BaseTests.swift:107
214 Sources/TexturesHD.swift:2749
211 Sources/Textures.swift:642
205 Sources/FlightModel.swift:113
197 Sources/GameCircuit.swift:267
195 Sources/Banners.swift:215
193 Sources/Player.swift:185
176 Sources/AshSites.swift:64
175 Sources/Animals.swift:423
174 Sources/CapitalBasesWork.swift:251
166 Sources/Structures.swift:297
164 Sources/CapitalBasesWork.swift:251
164 Sources/Animals.swift:423
161 Sources/PadTest.swift:750
160 Sources/Ships.swift:110
159 Sources/Banners.swift:88
158 Sources/Banners.swift:88
156 Sources/Music.swift:296
154 Sources/CapitalBasesWork.swift:251
152 Sources/Villager.swift:85
```
### Snapshot
```
posecheck: 568 raised limbs checked, 0 failed
textures: 1711 layers at 16 px, BC3, 0.6 MB with mips (build 59 ms, upload 12 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=29.3 hash=bfaecea078e1823d
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 159 ms  mesh(all, parallel) 121 ms  mesh(1 section) 1.05 ms  quads 313011 opaque / 479 water
frame (encode+GPU, offscreen, median of 30) 4.70 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 113 MB
memory: resident 147 MB  (section meshes 10 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
### Focused check: success
```
PASS ride frigateboard: the bot can walk the starboard edge of the spine forward to the bridge, round the gun mount and back aft while the frigate cruises and turns
PASS ride frigateboard: the bot can do the same on the port side while the frigate cruises and turns
PASS ride frigateboard: the bot can take off and fly clear while the frigate cruises and turns
PASS ride frigateboard: aboard all the way round (0 ticks off)
PASS ride frigateboard: never inside a solid (0 ticks)
PASS ride frigateboard: landing and taking off keep the bot's world velocity (2 changes, worst jump 1.14 b/s)
PASS ride frigateboard: no velocity spikes or bouncing aboard (0, 0; worst 1.68)
ride frigateboard: scene took 1 s
ride crew: crew 15 of 15 aboard; ship at 4530,165,1982 speed 5.9
PASS ride crew: every crew post is manned (15/15)
PASS ride crew: the crew ride the moving vehicle (0 crew-ticks off it)
PASS ride crew: every soldier holds its post while it drives and turns (worst 0.30 blocks: soldier_trooper at post 13)
PASS ride crew: no crew member inside a solid (0 crew-ticks)
ride crew: disabled at 5.9 b/s (wheels destroyed): came to rest after 7.3 s; worst deceleration 1.46 b/s2, fastest drop 0.40 b/s; impact 0.0 b/s; 15 crew alive
PASS ride crew: the disabled vehicle comes to rest (wheels destroyed)
PASS ride crew: it stays in the world (no despawn: still a vessel, or laid down as a wreck, 1)
PASS ride crew: it grinds to a stop, not at once (7.3 s from 5.9 b/s)
PASS ride crew: no sudden stop (worst deceleration 1.46 b/s2)
PASS ride crew: the crew fight enemy soldiers from aboard (52 shots)
PASS ride crew: the crew stay aboard the disabled vehicle (0 crew-ticks off)
PASS ride crew: the crew survive it (15 of 15 alive when it came to rest, 15 at the end)
PASS ride crew: the crew are released to fight
ride crew: scene took 3 s
ride troops: before the foes: ramp up, AI wants 3.0 b/s, speed 3.0, driver alive yes
ride troops: t 5 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 2 troops walking out 25.0,10.0,62.4 (5 left); 8.1,10.0,42.0 (5 left)
ride troops: t 10 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 2 troops walking out 18.1,10.0,72.4 (4 left); 8.0,10.0,52.0 (5 left)
ride troops: t 15 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 1 troops walking out 8.0,10.0,62.0 (5 left)
ride troops: t 20 s: ramp down, AI wants 0.0 b/s, speed 0.5, target yes, 1 troops walking out 8.7,10.0,71.4 (4 left)
ride troops: t 25 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 1 troops walking out 17.5,10.0,73.7 (3 left)
ride troops: t 30 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 2 troops walking out 25.0,10.0,38.5 (5 left); 8.0,10.0,49.7 (5 left)
ride troops: ramp up before the foes came; 2 troops walked out in 30 s; troops left 4
PASS ride troops: the ramp is up while it drives and comes down for the troops
PASS ride troops: bay troops walk out by the ramp onto the ground (2)
PASS ride troops: no troop is teleported (0 jumps over a block in a tick)
ride troops: overlaps with the hull: deepest 0.00, longest 0 ticks running; 0 brief grazes (under 0.2 deep, under 3 ticks) not counted
PASS ride troops: no troop inside a solid on the way out (0 troop-ticks)
ride troops: scene took 2 s
ride frigatecrew: crew 11 of 11 aboard; ship at 5096,178,1391 speed 9.8
PASS ride frigatecrew: every crew post is manned (11/11)
PASS ride frigatecrew: the crew ride the moving vehicle (0 crew-ticks off it)
PASS ride frigatecrew: every soldier holds its post while it drives and turns (worst 0.03 blocks: soldier_recruit at post 6)
PASS ride frigatecrew: no crew member inside a solid (0 crew-ticks)
ride frigatecrew: disabled at 9.6 b/s (engines destroyed): came to rest after 8.0 s; worst deceleration 382.90 b/s2, fastest drop 6.50 b/s; impact 3.7 b/s; 11 crew alive
PASS ride frigatecrew: the disabled vehicle comes to rest (engines destroyed)
PASS ride frigatecrew: it stays in the world (no despawn: still a vessel, or laid down as a wreck, 1)
PASS ride frigatecrew: it comes down over time, not at once (8.0 s)
PASS ride frigatecrew: it never drops faster than 8 b/s (6.50)
PASS ride frigatecrew: the crew flare it: touchdown at 3.7 b/s (under 5)
PASS ride frigatecrew: the crew stay aboard the disabled vehicle (0 crew-ticks off)
PASS ride frigatecrew: the crew survive it (11 of 11 alive when it came to rest, 11 at the end)
PASS ride frigatecrew: the crew are released to fight
ride frigatecrew: scene took 1 s
ride frigatecrash: came down 48 blocks in 14 s, touchdown at 3.8 b/s; bot health 20 -> 20
PASS ride frigatecrash: the frigate crash-lands and stays (no despawn)
PASS ride frigatecrash: the bot rides it down on the deck (0 ticks off)
PASS ride frigatecrash: never inside a solid (0 ticks)
PASS ride frigatecrash: standing, it drifts 0.0131 blocks over the deck on the way down
PASS ride frigatecrash: the bot survives with sensible damage (20 -> 20)
ride frigatecrash: scene took 1 s
ridecheck: PASS (10 scenes in 19 s)
```
![fast](fast.png)
