# Collapse check

collapsecheck: 1 FAILED (10 scenes in 11 s)
Seed 12345. Destruction physics and persistent wrecks through Game.tick.

## bridge
- the scene stands before the blast (0 unsupported)
- blasts 2 ms; 1 collapses, 0 hull splits, up to 1 debris bodies, 26 blocks laid back; tick mean 0.18 p95 0.41 worst 2.1 ms over 341 ticks; last analysis 0.0 ms
- slowest laying-down 0.1 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 15 watched blocks left)
- it falls as a moving body (1 at once)
- debris bodies stay under the cap (1 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.41 ms under 16, worst 2.1 under 120)
- scene took 0 s

## mine
- the scene stands before the blast (0 unsupported)
- blasts 72 ms; 1 collapses, 0 hull splits, up to 1 debris bodies, 25 blocks laid back; tick mean 0.20 p95 0.57 worst 2.2 ms over 317 ticks; last analysis 0.0 ms
- slowest laying-down 0.1 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 15 watched blocks left)
- it falls as a moving body (1 at once)
- debris bodies stay under the cap (1 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.57 ms under 16, worst 2.2 under 120)
- scene took 0 s

## tower
- the scene stands before the blast (0 unsupported)
- blasts 3 ms; 5 collapses, 0 hull splits, up to 2 debris bodies, 869 blocks laid back; tick mean 0.27 p95 0.47 worst 3.1 ms over 1176 ticks; last analysis 0.2 ms
- slowest laying-down 1.4 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the part that lost its support falls (0 of 16 watched blocks left)
- it falls as a moving body (2 at once)
- debris bodies stay under the cap (2 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.47 ms under 16, worst 3.1 under 120)
- scene took 1 s

## stands
- the scene stands before the blast (0 unsupported)
- blasts 1 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 0.14 p95 0.34 worst 1.5 ms over 122 ticks; last analysis 1.3 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- the tower stands (250 of 250 floor blocks left)
- nothing falls (0 debris bodies)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.34 ms under 16, worst 1.5 under 120)
- scene took 0 s

## massive
- the scene stands before the blast (0 unsupported)
- blasts 2 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 0.18 p95 0.43 worst 3.7 ms over 122 ticks; last analysis 3.4 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- a crater in a solid block brings nothing down (0 debris bodies)
- a search that hits its cap stays within budget (3.4 ms under 15)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 0.43 ms under 16, worst 3.7 under 120)
- scene took 1 s

## desert
- the scene stands before the blast (0 unsupported)
- slow tick at 0.0 s: 37.1 ms (no destruction work; world update 0.0 with 0 sections sent to mesh; the rest 37.1): 0 ships, 0 debris, 0 wreck jobs
- blasts 5 ms; 0 collapses, 0 hull splits, up to 0 debris bodies, 0 blocks laid back; tick mean 1.95 p95 13.90 worst 37.1 ms over 122 ticks; last analysis 0.2 ms
- slowest laying-down 0.0 ms, slowest hull split 0.0 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- terrain blasts bring nothing down (0 debris bodies)
- the support search round the craters stays small (0.2 ms)
- debris bodies stay under the cap (0 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- (streaming, not judged) tick time within budget during the collapse (p95 13.90 ms under 16, worst 37.1 under 120)
- scene took 1 s

## relic
- as built: 533 blocks the analysis can't hold up (-275,86,52 (stone_bricks); 3 pieces in -302,86,49 to -274,92,82: stone_bricks 533)
- the scene has an overhang and a hulk the analysis can't hold up as built (533 blocks)
- mining the tip of an old overhang brings nothing else down (38 of 38 arm blocks stand)
- nor mining into its middle (37 of 37)
- mining a floating hulk brings nothing else down (47 of 47)
- the as-built rule held them (87 blocks kept)
- mining into an old hall roof brings nothing else down (573 of 573)
- and costs a frame's budget at most (1.3 ms, under 10)
- **FAIL** cut from its pillar, the old overhang falls with it (36 of 39 arm blocks left up there)
- every piece is laid back into the world once it rests
- no new floating leftovers (0 unsupported blocks)
- the hulk still floats as built (47 of 47)
- scene took 1 s

## frigate
- already unsupported in the region before the blast (a generated structure): 34 blocks at -381,81,107 (capital_stone); 7 pieces in -384,80,61 to -379,112,110: capital_stone 15, capital_stone_trim 14, light_panel 5
- slow tick at 24.6 s: 69.3 ms (wreck step 26.4; world update 0.1 with 55 sections sent to mesh; the rest 42.8): 23 ships, 1 debris, 1 wreck jobs
- slow tick at 24.6 s: 34.1 ms (wreck step 32.5; world update 0.4 with 63 sections sent to mesh; the rest 1.3): 23 ships, 1 debris, 1 wreck jobs
- slow tick at 24.7 s: 31.8 ms (wreck step 29.9, support 0.0; world update 0.2 with 48 sections sent to mesh; the rest 1.6): 23 ships, 1 debris, 1 wreck jobs
- slow tick at 24.7 s: 66.7 ms (wreck step 1.8; world update 0.2 with 63 sections sent to mesh; the rest 64.7): 18 ships, 1 debris, 0 wreck jobs
- blasts 655 ms; 0 collapses, 31 hull splits, up to 30 debris bodies, 26578 blocks laid back; tick mean 1.48 p95 4.11 worst 69.3 ms over 1761 ticks; last analysis 2.1 ms
- slowest laying-down 32.5 ms, slowest hull split 10.8 ms
- no particle draws the missing texture (0 seen; 0 bits of air skipped)
- after: 0 still flying (), wrecks section, section, section, section, section, capfrigate, capfrigate
- the cut hull breaks in two (31 splits)
- the severed half falls (99 blocks)
- both halves come down and stay as wrecks (7 wrecks, 0 still flying)
- debris bodies stay under the cap (30 of 32)
- every piece is laid back into the world once it rests
- no floating leftovers (0 unsupported blocks)
- nothing ends up inside the player (0 ticks)
- tick time within budget during the collapse (p95 4.11 ms under 16, worst 69.3 under 120)
- scene took 4 s

## wreck
- the disabled crawler becomes a wreck in the world (after 12 s)
- its hull is world blocks now (9846 plates)
- salvage to be had: 8 containers, 8 with loot
- sheltered floor inside it for mobs to move into (2778 cells)
- overgrowth: 63 steps; rusted plates 0 -> 75, moss and vines 5 -> 313
- three weeks of overgrowth catch up while the player is near (63 steps)
- it has rusted and overgrown (75 rusted plates, 313 moss and vines)
- wreck records survive a save round trip
- scene took 2 s

## dropship
- fell 28 blocks, a wreck after 5.0 s; 1 wrecks
- the shot-down dropship falls (28 blocks)
- it stays where it fell as a wreck (1 wrecks)
- its hull is world blocks now (327 blocks)
- scene took 1 s

