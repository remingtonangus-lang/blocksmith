# Blocksmith fast lane

Commit `51445ae581f7ada69c92f80f6e0a7fd72c5403d7` on `claude/bs-frigates`: build **success**, snapshot **success**

Run: https://github.com/remingtonangus-lang/blocksmith/actions/runs/37264830751

### Build errors
```
```
### Type-check (warnings, slowest first)
```
811 Sources/main.swift:1312
792 Sources/main.swift:1312
581 Sources/CapitalShips.swift:1269
574 Sources/CapitalShips.swift:1269
366 Sources/Cinematic.swift:141
361 Sources/main.swift:1312
342 Sources/Mesher.swift:87
338 Sources/TexturesHD.swift:2708
337 Sources/Cinematic.swift:141
307 Sources/Cinematic.swift:141
291 Sources/ShipCombat.swift:129
287 Sources/TexturesHD.swift:3949
225 Sources/Ships.swift:108
220 Sources/TerrainTools.swift:81
210 Sources/Banners.swift:215
208 Sources/Animals.swift:421
207 Sources/PadTest.swift:727
206 Sources/TexturesHD.swift:4482
205 Sources/GameCircuit.swift:178
204 Sources/Textures.swift:601
195 Sources/Mesher.swift:349
194 Sources/main.swift:1283
192 Sources/main.swift:1405
189 Sources/Music.swift:296
186 Sources/GameCircuit.swift:178
174 Sources/Player.swift:123
153 Sources/main.swift:1283
152 Sources/TexturesHD.swift:618
150 Sources/TexturesHD.swift:2355
```
### Snapshot
```
posecheck: 474 raised limbs checked, 0 failed
textures without a painter: missing
textures: 1677 layers at 16 px, BC3, 0.6 MB with mips (build 57 ms, upload 10 ms)
light probe: eye sky 15 block 0 in air; floor+1 (y 72) sky 15 block 0 in air, daylight 1.0
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
imagecheck fast.png magenta=0.00000 black=0.0000 white=0.0008 std=31.4 hash=87693c5af36462c8
seed 12345  pos 31.5 136.0 29.5  rd 4  chunks 109  (drawn 29)
gen 94 ms  mesh(all, parallel) 85 ms  mesh(1 section) 1.17 ms  quads 301613 opaque / 2485 water
frame (encode+GPU, offscreen, median of 30) 3.09 ms  biome forest
mesh slabs 12 MB, chunks 109 (block+light arrays 10 MB), Metal allocated 114 MB
memory: resident 151 MB  (section meshes 9 MB)
wrote snaps/fast.png
imagecheck: 1 frames, no flags
```
### Focused check: success
```
PASS ride frigateboard: the bot can walk the hangar to the ladder and climb to the crew deck while the frigate cruises and turns
PASS ride frigateboard: the bot can walk the crew deck's corridor forward and back while the frigate cruises and turns
PASS ride frigateboard: the bot can go down the ladder to the hangar while the frigate cruises and turns
PASS ride frigateboard: the bot can walk out through the port opening and take off while the frigate cruises and turns
PASS ride frigateboard: aboard all the way round (0 ticks off)
PASS ride frigateboard: never inside a solid (0 ticks)
PASS ride frigateboard: landing and taking off keep the bot's world velocity (2 changes, worst jump 1.04 b/s)
PASS ride frigateboard: no velocity spikes or bouncing aboard (0, 0; worst 2.98)
ride frigateboard: scene took 1 s
ride crew: crew 15 of 15 aboard; ship at 90,151,0 speed 5.9
PASS ride crew: every crew post is manned (15/15)
PASS ride crew: the crew ride the moving vehicle (0 crew-ticks off it)
PASS ride crew: every soldier holds its post while it drives and turns (worst 0.30 blocks: soldier_marksman at post 6)
PASS ride crew: no crew member inside a solid (0 crew-ticks)
ride crew: disabled at 5.8 b/s (wheels destroyed): came to rest after 7.1 s; worst deceleration 1.46 b/s2, fastest drop 0.21 b/s; impact 0.0 b/s; 15 crew alive
PASS ride crew: the disabled vehicle comes to rest (wheels destroyed)
PASS ride crew: it stays in the world (no despawn)
PASS ride crew: it grinds to a stop, not at once (7.1 s from 5.8 b/s)
PASS ride crew: no sudden stop (worst deceleration 1.46 b/s2)
PASS ride crew: the crew fight enemy soldiers from aboard (360 shots)
PASS ride crew: the crew stay aboard the disabled vehicle (0 crew-ticks off)
PASS ride crew: the crew survive it (15 of 15 alive when it came to rest, 15 at the end)
PASS ride crew: the crew are released to fight
ride crew: scene took 6 s
ride troops: before the foes: ramp up, AI wants 3.0 b/s, speed 3.0, driver alive yes
ride troops: t 5 s: ramp down, AI wants 1.0 b/s, speed 1.0, target yes, 2 troops walking out 8.4,10.0,42.3 (5 left); 24.7,10.0,62.7 (5 left)
ride troops: t 10 s: ramp down, AI wants 1.0 b/s, speed 1.0, target yes, 2 troops walking out 8.0,10.0,52.3 (5 left); 18.3,10.0,72.3 (4 left)
ride troops: t 15 s: ramp down, AI wants 0.0 b/s, speed 0.1, target yes, 2 troops walking out 7.9,10.0,62.3 (5 left); 16.9,0.6,84.2 (1 left)
ride troops: t 20 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 1 troops walking out 9.1,10.0,71.2 (4 left)
ride troops: t 25 s: ramp down, AI wants 0.0 b/s, speed 0.0, target yes, 1 troops walking out 17.4,10.0,74.1 (2 left)
ride troops: t 30 s: ramp down, AI wants 1.0 b/s, speed 1.0, target yes, 3 troops walking out 15.6,5.6,79.2 (2 left); 8.3,10.0,50.0 (5 left)
ride troops: ramp up before the foes came; 2 troops walked out in 30 s; troops left 4
PASS ride troops: the ramp is up while it drives and comes down for the troops
PASS ride troops: bay troops walk out by the ramp onto the ground (2)
PASS ride troops: no troop is teleported (0 jumps over a block in a tick)
PASS ride troops: no troop inside a solid on the way out (0 troop-ticks)
ride troops: scene took 3 s
ride frigatecrew: crew 9 of 9 aboard; ship at -21,308,-726 speed 10.2
PASS ride frigatecrew: every crew post is manned (9/9)
PASS ride frigatecrew: the crew ride the moving vehicle (0 crew-ticks off it)
PASS ride frigatecrew: every soldier holds its post while it drives and turns (worst 0.01 blocks: soldier_marksman at post 1)
PASS ride frigatecrew: no crew member inside a solid (0 crew-ticks)
ride frigatecrew: disabled at 9.9 b/s (engines destroyed): came to rest after 14.5 s; worst deceleration 243.13 b/s2, fastest drop 6.99 b/s; impact 3.6 b/s; 9 crew alive
PASS ride frigatecrew: the disabled vehicle comes to rest (engines destroyed)
PASS ride frigatecrew: it stays in the world (no despawn)
PASS ride frigatecrew: it comes down over time, not at once (14.5 s)
PASS ride frigatecrew: it never drops faster than 8 b/s (6.99)
PASS ride frigatecrew: the crew flare it: touchdown at 3.6 b/s (under 5)
PASS ride frigatecrew: the crew stay aboard the disabled vehicle (0 crew-ticks off)
PASS ride frigatecrew: the crew survive it (9 of 9 alive when it came to rest, 9 at the end)
PASS ride frigatecrew: the crew are released to fight
ride frigatecrew: scene took 2 s
ride frigatecrash: came down 87 blocks in 20 s, touchdown at 3.9 b/s; bot health 20 -> 20
PASS ride frigatecrash: the frigate crash-lands and stays (no despawn)
PASS ride frigatecrash: the bot rides it down on the deck (0 ticks off)
PASS ride frigatecrash: never inside a solid (0 ticks)
PASS ride frigatecrash: standing, it drifts 0.0015 blocks over the deck on the way down
PASS ride frigatecrash: the bot survives with sensible damage (20 -> 20)
ride frigatecrash: scene took 1 s
ridecheck: PASS (10 scenes in 35 s)
```
![fast](fast.png)
