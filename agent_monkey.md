# Agent runs: monkey

agent monkey: 28 oracle violations, 0 unmet goals over 4 seeds x 3 runs in 108 s
Ticks per run 7200 (120 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 49.9 ms; chunks visited 4

## seed 12345, bot seed 2
- oracle counts: inside_solid 7; worst tick 39.3 ms; chunks visited 5
- **inside_solid** at tick 361 (4680.0 64.5 1754.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 495 (4681.2 64.7 1748.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 525 (4681.2 64.6 1748.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_12345_2.jsonl`
- minimised inside_solid: 421 -> 312 non-idle ticks; `snaps/replay_min_inside_solid.jsonl`

## seed 12345, bot seed 3
- oracle counts: inside_solid 15; worst tick 42.0 ms; chunks visited 4
- **inside_solid** at tick 1836 (4680.9 64.6 1751.4): player overlaps a solid block (air at head height)
- **inside_solid** at tick 1867 (4680.7 64.6 1750.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 1898 (4680.7 64.6 1750.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_12345_3.jsonl`

## seed 424242, bot seed 1
- oracle counts: none; worst tick 37.3 ms; chunks visited 8

## seed 424242, bot seed 2
- oracle counts: inside_solid 1; worst tick 42.6 ms; chunks visited 9
- **inside_solid** at tick 6210 (-5529.9 135.6 -2057.5): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_424242_2.jsonl`

## seed 424242, bot seed 3
- oracle counts: inside_solid 6; worst tick 46.1 ms; chunks visited 10
- **inside_solid** at tick 365 (-5514.4 147.4 -2007.1): player overlaps a solid block (air at head height)
- **inside_solid** at tick 394 (-5514.7 147.5 -2007.8): player overlaps a solid block (air at head height)
- **inside_solid** at tick 465 (-5514.5 147.4 -2007.8): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_424242_3.jsonl`

## seed 777, bot seed 1
- oracle counts: inside_solid 33; worst tick 48.6 ms; chunks visited 8
- **inside_solid** at tick 78 (3784.7 93.4 -4039.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 908 (3791.8 93.2 -4052.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 918 (3791.1 92.6 -4051.1): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_1.jsonl`

## seed 777, bot seed 2
- oracle counts: inside_solid 24; worst tick 35.6 ms; chunks visited 9
- **inside_solid** at tick 277 (3782.1 93.4 -4036.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 306 (3780.6 93.5 -4039.2): player overlaps a solid block (air at head height)
- **inside_solid** at tick 466 (3778.9 92.6 -4047.2): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_2.jsonl`

## seed 777, bot seed 3
- oracle counts: inside_solid 48; worst tick 48.0 ms; chunks visited 10
- **inside_solid** at tick 97 (3784.4 93.6 -4039.4): player overlaps a solid block (air at head height)
- **inside_solid** at tick 125 (3784.2 93.7 -4039.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 156 (3784.6 93.6 -4038.7): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_3.jsonl`

## seed 31337, bot seed 1
- oracle counts: inside_solid 41; worst tick 42.0 ms; chunks visited 5
- **inside_solid** at tick 71 (2488.6 97.6 4440.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 103 (2488.5 97.6 4439.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 132 (2488.2 97.7 4437.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_1.jsonl`

## seed 31337, bot seed 2
- oracle counts: inside_solid 41; worst tick 47.2 ms; chunks visited 7
- **inside_solid** at tick 23 (2487.1 97.0 4440.2): player overlaps a solid block (air at head height)
- **inside_solid** at tick 74 (2487.8 97.0 4441.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 112 (2488.2 97.0 4441.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_2.jsonl`

## seed 31337, bot seed 3
- oracle counts: inside_solid 44; worst tick 59.3 ms; chunks visited 6
- **inside_solid** at tick 88 (2488.5 97.8 4440.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 119 (2488.2 97.8 4440.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 150 (2488.5 97.8 4441.3): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_3.jsonl`

