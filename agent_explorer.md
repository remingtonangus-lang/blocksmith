# Agent runs: explorer

agent explorer: 1 oracle violations, 0 unmet goals over 2 seeds x 1 runs in 6 s
Ticks per run 3600 (60 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: tick_spikes 1; worst tick 57.7 ms; chunks visited 9
- goal met: reach most chosen targets on foot - 4 of 5 reached, 0 given up
- goal met: swim at least once - swam

## seed 777, bot seed 1
- oracle counts: inside_solid 1; worst tick 56.7 ms; chunks visited 16
- **inside_solid** at tick 913 (3812.5 94.4 -4008.1): player overlaps a solid block (air at head height)
- goal met: reach most chosen targets on foot - 9 of 10 reached, 0 given up
- goal met: swim at least once - swam
- replay: `snaps/replay_explorer_777_1.jsonl`

