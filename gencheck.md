# World-gen check

gencheck: 288 chunks over 3 seeds: floating_block 3, leak 72, leaves_orphan 1, ore_in_air 4, plant_floating 1, spring 116 (3.4 s)

leak kinds: water underground border onto rail 35; water underground border onto oak_planks 20; water underground border onto deepslate 8; water underground border onto deepslate_gold_ore 3; lava underground border onto deepslate 2; water surface in-chunk onto dirt 2; water underground border onto stone 2

- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **plant_floating** seed 12345 at 41 -7 2108: small_dripleaf over air  `--snapshot snaps/g.png --seed 12345 --x 41 --z 2108 --up 2 --pitch -40`
- **ore_in_air** seed 12345 at 2236 30 -1714: coal_ore with 5 open sides  `--snapshot snaps/g.png --seed 12345 --x 2236 --z -1714 --up 2 --pitch -40`
- **ore_in_air** seed 777 at 35 -25 43: deepslate_lapis_ore with 5 open sides  `--snapshot snaps/g.png --seed 777 --x 35 --z 43 --up 2 --pitch -40`
- **spring** seed 777 at 87 17 -48: water source open to a cave (+z, flows on load)  `--snapshot snaps/g.png --seed 777 --x 87 --z -48 --up 2 --pitch -40`
- **spring** seed 777 at 88 17 -48: water source open to a cave (+z, flows on load)  `--snapshot snaps/g.png --seed 777 --x 88 --z -48 --up 2 --pitch -40`
- **spring** seed 777 at 89 18 -48: water source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 89 --z -48 --up 2 --pitch -40`
- **spring** seed 777 at 90 19 -48: water source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 90 --z -48 --up 2 --pitch -40`
- **spring** seed 777 at 85 18 -47: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 85 --z -47 --up 2 --pitch -40`
- **spring** seed 777 at 89 17 -47: water source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 89 --z -47 --up 2 --pitch -40`
- **spring** seed 777 at 87 17 -46: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 87 --z -46 --up 2 --pitch -40`
- **spring** seed 777 at 87 17 -45: water source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 87 --z -45 --up 2 --pitch -40`
- **leak** seed 777 at 544 -31 -755: water source beside air (-x: open 0 down to rail, top 89, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -755 --up 2 --pitch -40`
- **leak** seed 777 at 544 -30 -755: water source beside air (-x: open 1 down to rail, top 89, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -755 --up 2 --pitch -40`
- **leak** seed 777 at 544 -31 -754: water source beside air (-x: open 0 down to rail, top 89, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -754 --up 2 --pitch -40`
- **leak** seed 777 at 544 -31 -753: water source beside air (-x: open 0 down to rail, top 87, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -753 --up 2 --pitch -40`
- **leak** seed 777 at 544 -30 -753: water source beside air (-x: open 1 down to rail, top 87, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -753 --up 2 --pitch -40`
- **leak** seed 777 at 544 -31 -752: water source beside air (-x: open 1 down to oak_planks, top 87, across a chunk border)  `--snapshot snaps/g.png --seed 777 --x 544 --z -752 --up 2 --pitch -40`
- **floating_block** seed 777 at 528 14 -727: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 528 --z -727 --up 2 --pitch -40`
- **floating_block** seed 777 at 578 0 -721: deepslate with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 578 --z -721 --up 2 --pitch -40`
- **ore_in_air** seed 777 at -2223 42 17: iron_ore with 5 open sides  `--snapshot snaps/g.png --seed 777 --x -2223 --z 17 --up 2 --pitch -40`
- **floating_block** seed 424242 at 27 92 98: grass_block with nothing solid around it  `--snapshot snaps/g.png --seed 424242 --x 27 --z 98 --up 2 --pitch -40`
- **ore_in_air** seed 424242 at -1033 -40 1760: deepslate_diamond_ore with 5 open sides  `--snapshot snaps/g.png --seed 424242 --x -1033 --z 1760 --up 2 --pitch -40`
- **leaves_orphan** seed 424242 at 1148 94 1271: jungle_leaves with no log within 6  `--snapshot snaps/g.png --seed 424242 --x 1148 --z 1271 --up 2 --pitch -40`
