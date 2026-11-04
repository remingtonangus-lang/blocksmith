# Agent runs: monkey

agent monkey: 29 oracle violations, 0 unmet goals over 4 seeds x 3 runs in 251 s
Ticks per run 7200 (120 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 48.7 ms; chunks visited 4

## seed 12345, bot seed 2
- oracle counts: inside_solid 3, tick_spikes 1; worst tick 51.8 ms; chunks visited 8
- **inside_solid** at tick 3997 (4691.3 65.6 1777.2): player overlaps a solid block (air at head height)
- **inside_solid** at tick 4028 (4689.1 65.6 1776.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 4059 (4687.7 65.6 1775.2): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_12345_2.jsonl`
- minimised inside_solid: 4057 -> 2276 non-idle ticks; `snaps/replay_min_inside_solid.jsonl`

## seed 12345, bot seed 3
- oracle counts: inside_solid 9; worst tick 49.4 ms; chunks visited 5
- **inside_solid** at tick 1836 (4680.5 64.6 1751.1): player overlaps a solid block (air at head height)
- **inside_solid** at tick 1867 (4680.4 64.6 1750.7): player overlaps a solid block (air at head height)
- **inside_solid** at tick 1898 (4680.4 64.6 1750.7): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_12345_3.jsonl`

## seed 424242, bot seed 1
- oracle counts: none; worst tick 50.6 ms; chunks visited 6

## seed 424242, bot seed 2
- oracle counts: inside_solid 2; worst tick 50.6 ms; chunks visited 9
- **inside_solid** at tick 3236 (-5493.1 141.7 -2018.2): player overlaps a solid block (air at head height)
- **inside_solid** at tick 6211 (-5530.0 135.6 -2057.5): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_424242_2.jsonl`

## seed 424242, bot seed 3
- oracle counts: inside_solid 8; worst tick 52.8 ms; chunks visited 12
- **inside_solid** at tick 365 (-5514.4 147.4 -2007.1): player overlaps a solid block (air at head height)
- **inside_solid** at tick 394 (-5514.7 147.5 -2007.8): player overlaps a solid block (air at head height)
- **inside_solid** at tick 465 (-5514.5 147.4 -2007.8): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_424242_3.jsonl`

## seed 777, bot seed 1
- oracle counts: inside_solid 35; worst tick 52.4 ms; chunks visited 9
- **inside_solid** at tick 78 (3784.7 93.4 -4039.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 438 (3787.2 92.8 -4050.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 918 (3792.0 92.6 -4051.4): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_1.jsonl`

## seed 777, bot seed 2
- oracle counts: inside_solid 41; worst tick 52.2 ms; chunks visited 7
- **inside_solid** at tick 277 (3782.2 93.4 -4037.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 306 (3780.1 93.5 -4039.3): player overlaps a solid block (air at head height)
- **inside_solid** at tick 466 (3779.0 92.6 -4047.4): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_2.jsonl`

## seed 777, bot seed 3
- oracle counts: inside_solid 50, tick_spikes 1; worst tick 63.3 ms; chunks visited 11
- **inside_solid** at tick 97 (3784.4 93.6 -4039.4): player overlaps a solid block (air at head height)
- **inside_solid** at tick 125 (3784.2 93.7 -4039.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 156 (3784.6 93.6 -4038.7): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_3.jsonl`

## seed 31337, bot seed 1
- oracle counts: inside_solid 37; worst tick 48.5 ms; chunks visited 5
- **inside_solid** at tick 71 (2488.6 97.6 4440.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 103 (2488.5 97.6 4439.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 132 (2488.2 97.7 4437.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_1.jsonl`

## seed 31337, bot seed 2
- oracle counts: inside_solid 36, stuck_events 1, tick_spikes 3; worst tick 61.1 ms; chunks visited 6
- **inside_solid** at tick 23 (2487.1 97.0 4440.2): player overlaps a solid block (air at head height)
- **inside_solid** at tick 74 (2487.8 97.0 4441.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 112 (2488.2 97.0 4441.9): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_2.jsonl`

## seed 31337, bot seed 3
- oracle counts: inside_solid 47, tick_spikes 2; worst tick 57.2 ms; chunks visited 6
- **inside_solid** at tick 88 (2488.5 97.8 4440.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 119 (2488.2 97.8 4440.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 150 (2488.5 97.8 4441.3): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_31337_3.jsonl`

