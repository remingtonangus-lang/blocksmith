# The Sparkstone Workshop (backlog L2)

A creative test world with the standard circuits players build, each on its own signed bench along a stone deck,
driven by an automated check against the genre reference. Pick it from Worlds > "Sparkstone Workshop (circuits)" on
the Quest or the Mac; the deck is built over the spawn the first time the world loads and the player stands on its
walkway looking east. Code: Sources/CircuitWorkshop.swift (benches, deck, Game.workshopTick),
Sources/CircuitWorkshopTests.swift (the checks); run alone with `questcheck --workshop-only`, in the full questcheck
run, and on the Mac with `--coppertest`.

## Objectives (the backlog's plus our own)
- Backlog: a test world with clocks, T flip-flops, piston doors, item sorters, observers and comparator subtraction,
  each behaving like the reference, checked automatically.
- Ours: a world players can open from the menu on both platforms (built once, kept in the save); every bench signed
  with what it does; the reference's exact timings, not just "it blinks" (torch clock period, observer clock duty,
  observer pulse length); each circuit driven the way a player would (the lever, the button, a block placed, items
  in a chest) through Game.useCircuit and World.redstone.tick(); fix the engine where a bench shows a difference; the
  check builds its deck far from the later checks and clears it after.

## Benches and what the check holds them to
| bench | circuit | check |
|---|---|---|
| Torch Clock | sparkstone torch on a block, its output looped through a 4-tick repeater back into the block | rising edges exactly 20 game ticks apart over 10 s, on half the time, no burnout, the lamp above the torch blinks |
| Observer Clock | two observers watching each other | each observer on 2 game ticks of every 4, its lamp held lit |
| Bulb Toggle | button -> copper bulb -> comparator -> lamp (a T flip-flop) | four presses: on, off, on, off (the release changes nothing) |
| Piston Door | 1x2 sticky-piston door held shut by a torch on a pillar (the lower piston through quasi-connectivity); the lever on the pillar turns the torch off | shut at rest, the lever opens a walkable 1x2 gap with both door blocks pulled back, off again it shuts |
| Hopper Sorter | hopper line over a filter hopper (18 iron + 4 fillers), comparator -> two dust -> block -> torch -> dust locking the hopper under the filter | 6 iron and 6 cobblestone in: all iron sorted, all cobblestone at the end, the filter back at 18 + 4 |
| Subtraction | comparator in subtract mode, 12 at the back, the lever's 5 at the side | 12 alone, 12 - 5 = 7 with the lever, the output dust reads 7, 6, ... 1 and lights the lamp |
| Observer Sensor | observer watching a gold mark | placing a block there gives a 2-tick pulse that flashes the lamp, which then goes out |

## Engine fixes the benches found (BUGS.md)
- Tick order: due components leave the schedule as they fire, and an observer schedules its own turn-off before its
  watchers see it change (the observer clock ran 2 on, 4 off).
- Pistons wake their neighbours when they extend or retract (the door's lower, quasi-powered piston stayed out).
- A hopper that was empty and gets an item waits a full transfer before passing it on (the sorter's filter lost the
  race to the line; it depended on the per-run order of the tracked set).
- Comparators read a lit copper bulb as 15.

## Not covered
The two-dropper T flip-flop and RS-latch designs are not on the deck; the copper bulb is the current standard T
flip-flop. Their parts are covered one by one in docs/status/copper-parity.md (--coppertest).

## Screenshots
`questcheck --render X --workshop-shots DIR` writes workshop_{walkway,door,sorter}.png (the deck built east of the
spawn, run 3.5 s so the clocks tick and the door shuts). In docs/status/evidence/sparkstone-workshop/.

## Verifier pass (2026-10-11)
- Blocking, fixed: the world looked for its deck site at the old fixed origin instead of the world's varied spawn, so the
  deck never built in the real game. Now `workshopTick` uses `Game.spawnPoint`, loads the deck area itself (any render
  distance), runs only in the overworld, and a questcheck test enters the world through a real save folder twice
  (built and standing on the walkway the first time; found and left alone the second).
- Also fixed: the sign posts stood on the walkway (now in the gap between benches, the walkway is 3 clear rows); the
  deck's corner block is the "already built" marker, so breaking a sign no longer rebuilds the deck.
- Left as is: a hopper's receive wait is 7 or 8 ticks depending on order (reference: always 7); once the world exists
  the Worlds list shows its save beside the "Sparkstone Workshop (circuits)" row (both open the same world).
