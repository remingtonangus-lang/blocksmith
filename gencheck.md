# World-gen check

gencheck: 288 chunks over 3 seeds: floating_block 6, leak 2, leaves_orphan 1, ore_in_air 2, plant_floating 1, spring 60 (3.3 s)

leak kinds: water surface in-chunk onto dirt 2

- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **plant_floating** seed 12345 at 41 -7 2108: small_dripleaf over air  `--snapshot snaps/g.png --seed 12345 --x 41 --z 2108 --up 2 --pitch -40`
- **ore_in_air** seed 12345 at -2 -13 2143: deepslate_iron_ore with 5 open sides  `--snapshot snaps/g.png --seed 12345 --x -2 --z 2143 --up 2 --pitch -40`
- **spring** seed 12345 at 22 -32 2134: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 22 --z 2134 --up 2 --pitch -40`
- **spring** seed 12345 at 23 -31 2135: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 23 --z 2135 --up 2 --pitch -40`
- **spring** seed 12345 at 24 -30 2137: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 24 --z 2137 --up 2 --pitch -40`
- **spring** seed 12345 at 25 -29 2138: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 25 --z 2138 --up 2 --pitch -40`
- **spring** seed 12345 at 26 -27 2140: water source open to a cave (-z, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 26 --z 2140 --up 2 --pitch -40`
- **spring** seed 12345 at 39 -54 2130: lava source open to a cave (+z, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 39 --z 2130 --up 2 --pitch -40`
- **spring** seed 12345 at 38 -54 2131: lava source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 12345 --x 38 --z 2131 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 17 -729: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -729 --up 2 --pitch -40`
- **floating_block** seed 777 at 528 14 -727: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 528 --z -727 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 16 -726: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -726 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 22 -726: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -726 --up 2 --pitch -40`
- **floating_block** seed 777 at 578 0 -721: deepslate with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 578 --z -721 --up 2 --pitch -40`
- **ore_in_air** seed 777 at -1456 18 556: iron_ore with 5 open sides  `--snapshot snaps/g.png --seed 777 --x -1456 --z 556 --up 2 --pitch -40`
- **floating_block** seed 424242 at 27 92 98: grass_block with nothing solid around it  `--snapshot snaps/g.png --seed 424242 --x 27 --z 98 --up 2 --pitch -40`
- **leaves_orphan** seed 424242 at 1148 94 1271: jungle_leaves with no log within 6  `--snapshot snaps/g.png --seed 424242 --x 1148 --z 1271 --up 2 --pitch -40`
- **spring** seed 424242 at 1126 -58 1283: lava source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 424242 --x 1126 --z 1283 --up 2 --pitch -40`
