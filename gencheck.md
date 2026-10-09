# World-gen check

gencheck: 288 chunks over 3 seeds: floating_block 6, leak 2, leaves_orphan 1, ore_in_air 3, plant_floating 1, spring 10 (3.8 s)

leak kinds: water surface in-chunk onto dirt 2

- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **leak** seed 12345 at 49 63 53: water source beside air (-z: open 0 down to dirt, top 64)  `--snapshot snaps/g.png --seed 12345 --x 49 --z 53 --up 2 --pitch -40`
- **plant_floating** seed 12345 at 41 -7 2108: small_dripleaf over air  `--snapshot snaps/g.png --seed 12345 --x 41 --z 2108 --up 2 --pitch -40`
- **ore_in_air** seed 12345 at -2 -13 2143: deepslate_iron_ore with 5 open sides  `--snapshot snaps/g.png --seed 12345 --x -2 --z 2143 --up 2 --pitch -40`
- **ore_in_air** seed 12345 at 2236 30 -1714: coal_ore with 5 open sides  `--snapshot snaps/g.png --seed 12345 --x 2236 --z -1714 --up 2 --pitch -40`
- **spring** seed 777 at 51 -31 -9: lava source open to a cave (+z, flows on load)  `--snapshot snaps/g.png --seed 777 --x 51 --z -9 --up 2 --pitch -40`
- **spring** seed 777 at 52 -31 -8: lava source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 52 --z -8 --up 2 --pitch -40`
- **spring** seed 777 at 52 -31 -7: lava source open to a cave (-x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 52 --z -7 --up 2 --pitch -40`
- **spring** seed 777 at 53 -31 -7: lava source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 53 --z -7 --up 2 --pitch -40`
- **spring** seed 777 at 52 -31 -6: lava source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x 52 --z -6 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 17 -729: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -729 --up 2 --pitch -40`
- **floating_block** seed 777 at 528 14 -727: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 528 --z -727 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 16 -726: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -726 --up 2 --pitch -40`
- **floating_block** seed 777 at 543 22 -726: stone with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 543 --z -726 --up 2 --pitch -40`
- **floating_block** seed 777 at 578 0 -721: deepslate with nothing solid around it  `--snapshot snaps/g.png --seed 777 --x 578 --z -721 --up 2 --pitch -40`
- **ore_in_air** seed 777 at -2223 42 17: iron_ore with 5 open sides  `--snapshot snaps/g.png --seed 777 --x -2223 --z 17 --up 2 --pitch -40`
- **spring** seed 777 at -1468 -45 569: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x -1468 --z 569 --up 2 --pitch -40`
- **spring** seed 777 at -1467 -44 569: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x -1467 --z 569 --up 2 --pitch -40`
- **spring** seed 777 at -1467 -45 570: water source open to a cave (+x, flows on load)  `--snapshot snaps/g.png --seed 777 --x -1467 --z 570 --up 2 --pitch -40`
- **floating_block** seed 424242 at 27 92 98: grass_block with nothing solid around it  `--snapshot snaps/g.png --seed 424242 --x 27 --z 98 --up 2 --pitch -40`
- **leaves_orphan** seed 424242 at 1148 94 1271: jungle_leaves with no log within 6  `--snapshot snaps/g.png --seed 424242 --x 1148 --z 1271 --up 2 --pitch -40`
