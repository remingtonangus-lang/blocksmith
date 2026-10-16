# Collapse check

collapsecheck: 1 FAILED (10 scenes in 13 s)
Seed 12345. Destruction physics and persistent wrecks through Game.tick.

## bridge
- the scene stands before the blast (0 unsupported)
- blasts 2 ms; 1 collapses, 0 hull splits, up to 3 debris bodies, 72 blocks laid back; tick mean 0.24 p95 0.95 worst 4.2 ms over 544 ticks; last analysis 0.1 ms
- slowest laying-down 0.2 ms, slowest hull split 0.0 ms
- collapses: falling 18 (y 138-139), 34 (y 142-144), 18 (y 134-135); tipping none
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 15 watched blocks left)
- it falls as a moving body (3 at once)
- debris bodies stay under the cap (3 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.95 ms under 16, worst 4.2 under 120)
- scene took 1 s

## mine
- the scene stands before the blast (0 unsupported)
- blasts 60 ms; 1 collapses, 0 hull splits, up to 1 debris bodies, 25 blocks laid back; tick mean 0.21 p95 0.79 worst 4.5 ms over 281 ticks; last analysis 0.0 ms
- slowest laying-down 0.1 ms, slowest hull split 0.0 ms
- collapses: falling 25 (y 143-144); tipping none
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 15 watched blocks left)
- it falls as a moving body (1 at once)
- debris bodies stay under the cap (1 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.79 ms under 16, worst 4.5 under 120)
- scene took 1 s

## tower
- the scene stands before the blast (0 unsupported)
- blasts 4 ms; 1 collapses, 0 hull splits, up to 2 debris bodies, 422 blocks laid back; tick mean 0.17 p95 0.49 worst 4.0 ms over 2400 ticks; last analysis 0.3 ms
- slowest laying-down 1.2 ms, slowest hull split 0.0 ms
- collapses: falling 78 (y 135-160); tipping 372 (y 134-160) | settle: falling 2 (y 144-145); tipping none
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 16 watched blocks left)
- it falls as a moving body (2 at once)
- debris bodies stay under the cap (2 of 32)
- **FAIL** every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.49 ms under 16, worst 4.0 under 120)
- scene took 1 s

## stands
- the scene stands before the blast (0 unsupported)
- blasts 1 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 0.17 p95 0.88 worst 3.8 ms over 122 ticks; last analysis 1.4 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the tower stands (250 of 250 floor blocks left)
- nothing falls (0 debris bodies)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.88 ms under 16, worst 3.8 under 120)
- scene took 1 s

## massive
- the scene stands before the blast (0 unsupported)
- blasts 1 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 0.20 p95 1.04 worst 4.8 ms over 122 ticks; last analysis 4.5 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- a crater in a solid block brings nothing down (0 debris bodies)
- a search that hits its cap stays within budget (4.5 ms under 15)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 1.04 ms under 16, worst 4.8 under 120)
- scene took 1 s

## desert
- the scene stands before the blast (0 unsupported)
- slow tick at 0.0 s: 51.2 ms (no destruction work; world update 0.0 with 0 sections sent to mesh; the rest 51.2): 0 ships, 0 debris, 0 wreck jobs
- slow tick at 0.8 s: 32.2 ms (no destruction work; world update 0.0 with 0 sections sent to mesh; the rest 32.2): 0 ships, 0 debris, 0 wreck jobs
- blasts 5 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 2.37 p95 14.92 worst 51.2 ms over 122 ticks; last analysis 0.1 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- terrain blasts bring nothing down (0 debris bodies)
- the support search round the craters stays small (0.1 ms)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- (streaming, not judged) tick time within budget during the collapse (p95 14.92 ms under 16, worst 51.2 under 120)
- scene took 1 s

## relic
- as built: 533 blocks the analysis can't hold up (4598,75,1793 (stone_bricks); 3 pieces in 4573,75,1791 to 4601,81,1824: stone_bricks 533)
- the scene has an overhang and a hulk the analysis can't hold up as built (533 blocks)
- mining the tip of an old overhang brings nothing else down (38 of 38 arm blocks stand)
- nor mining into its middle (37 of 37)
- mining a floating hulk brings nothing else down (47 of 47)
- the as-built rule held them (87 blocks kept)
- mining into an old hall roof brings nothing else down (573 of 573)
- and costs a frame's budget at most (1.8 ms, under 10)
- pillar foot: 9 of 9 mined (first at 4586,131,1792); 1 collapses, 115 blocks laid back, 0 more kept as built; arm blocks a layer down 6
- cut from its pillar, the old overhang falls with it (0 of 39 arm blocks left up there)
- every piece is laid back into the world once it rests
- no new floating leftovers (0 unsupported blocks)
- the hulk still floats as built (47 of 47)
- scene took 1 s

## frigate
- blasts 1480 ms; 0 collapses, 1 hull splits, up to 0 debris bodies, 14889 blocks laid back; tick mean 0.42 p95 1.70 worst 17.9 ms over 1149 ticks; last analysis 0.0 ms
- slowest laying-down 17.3 ms, slowest hull split 2.8 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- after: 0 still flying (), wrecks capfrigate, capfrigate
- the cut hull breaks in two (1 splits)
- the severed half falls (45 blocks)
- both halves come down and stay as wrecks (2 wrecks, 0 still flying)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 1.70 ms under 16, worst 17.9 under 120)
- scene took 3 s

## wreck
- the disabled crawler becomes a wreck in the world (after 12 s)
- its hull is world blocks now (9860 plates)
- salvage to be had: 8 containers, 8 with loot
- sheltered floor inside it for mobs to move into (1915 cells)
- overgrowth: 63 steps; rusted plates 0 -> 76, moss and vines 168 -> 560
- three weeks of overgrowth catch up while the player is near (63 steps)
- it has rusted and overgrown (76 rusted plates, 560 moss and vines)
- wreck records survive a save round trip
- scene took 2 s

## dropship
- fell 26 blocks, a wreck after 4.9 s; 1 wrecks
- the shot-down dropship falls (26 blocks)
- it stays where it fell as a wreck (1 wrecks)
- its hull is world blocks now (264 blocks)
- scene took 1 s

