# Agent runs: monkey

agent monkey: 26 oracle violations, 0 unmet goals over 4 seeds x 3 runs in 263 s
Ticks per run 7200 (120 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 70.7 ms; chunks visited 4

## seed 12345, bot seed 2
- oracle counts: inside_solid 1, tick_spikes 1; worst tick 55.9 ms; chunks visited 6
- **inside_solid** at tick 3480 (4687.1 66.6 1774.8): player overlaps a solid block (oak_leaves at head height)
- replay: `snaps/replay_monkey_12345_2.jsonl`
- minimised inside_solid: 3540 -> 884 non-idle ticks; `snaps/replay_min_inside_solid.jsonl`

## seed 12345, bot seed 3
- oracle counts: inside_solid 2, tick_spikes 1; worst tick 52.8 ms; chunks visited 7
- **inside_solid** at tick 2076 (4680.2 65.6 1753.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 2106 (4680.1 65.6 1752.3): player overlaps a solid block (oak_leaves at head height)
- replay: `snaps/replay_monkey_12345_3.jsonl`

## seed 424242, bot seed 1
- oracle counts: none; worst tick 59.0 ms; chunks visited 7

## seed 424242, bot seed 2
- oracle counts: inside_solid 2, tick_spikes 1; worst tick 58.9 ms; chunks visited 9
- **inside_solid** at tick 3220 (-5492.7 142.5 -2019.1): player overlaps a solid block (air at head height)
- **inside_solid** at tick 6210 (-5530.1 135.6 -2057.6): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_424242_2.jsonl`

## seed 424242, bot seed 3
- oracle counts: inside_solid 3, tick_spikes 1; worst tick 57.4 ms; chunks visited 10
- **inside_solid** at tick 608 (-5515.9 147.6 -2006.0): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 625 (-5515.9 147.8 -2005.0): player overlaps a solid block (air at head height)
- **inside_solid** at tick 3327 (-5496.2 146.6 -2004.2): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_424242_3.jsonl`

## seed 777, bot seed 1
- oracle counts: inside_solid 33, tick_spikes 4; worst tick 100.7 ms; chunks visited 4
- **inside_solid** at tick 905 (3791.3 93.5 -4052.1): player overlaps a solid block (air at head height)
- **inside_solid** at tick 926 (3790.3 93.6 -4050.8): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 1022 (3790.6 93.6 -4050.1): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_777_1.jsonl`

## seed 777, bot seed 2
- oracle counts: inside_solid 32; worst tick 47.6 ms; chunks visited 8
- **inside_solid** at tick 483 (3781.2 93.4 -4043.7): player overlaps a solid block (air at head height)
- **inside_solid** at tick 503 (3781.2 93.6 -4043.8): player overlaps a solid block (air at head height)
- **inside_solid** at tick 533 (3781.2 93.6 -4043.8): player overlaps a solid block (air at head height)
- replay: `snaps/replay_monkey_777_2.jsonl`

## seed 777, bot seed 3
- oracle counts: inside_solid 27; worst tick 54.2 ms; chunks visited 6
- **inside_solid** at tick 2145 (3775.1 93.2 -4055.3): player overlaps a solid block (air at head height)
- **inside_solid** at tick 3017 (3797.8 92.6 -4039.4): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 3046 (3798.7 92.6 -4038.9): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_777_3.jsonl`

## seed 31337, bot seed 1
- oracle counts: inside_solid 28, tick_spikes 1; worst tick 92.2 ms; chunks visited 4
- **inside_solid** at tick 72 (2488.6 97.6 4440.5): player overlaps a solid block (air at head height)
- **inside_solid** at tick 80 (2488.7 98.6 4440.5): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 109 (2488.5 98.6 4439.9): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_31337_1.jsonl`

## seed 31337, bot seed 2
- oracle counts: inside_solid 36; worst tick 46.2 ms; chunks visited 6
- **inside_solid** at tick 279 (2485.3 98.6 4443.0): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 306 (2484.2 97.8 4441.9): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 467 (2484.2 97.8 4439.4): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_31337_2.jsonl`

## seed 31337, bot seed 3
- oracle counts: inside_solid 30, tick_spikes 1; worst tick 52.5 ms; chunks visited 6
- **inside_solid** at tick 97 (2488.4 98.6 4440.6): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 125 (2488.2 98.7 4441.0): player overlaps a solid block (spruce_leaves at head height)
- **inside_solid** at tick 156 (2488.6 98.6 4441.3): player overlaps a solid block (spruce_leaves at head height)
- replay: `snaps/replay_monkey_31337_3.jsonl`

