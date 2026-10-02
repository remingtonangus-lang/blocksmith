# Agent runs: life

agent life: 0 oracle violations, 2 unmet goals over 2 seeds x 1 runs in 11 s
Ticks per run 6600 (110 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 42.3 ms; chunks visited 2
- goal met: open a villager's trade screen - trade screen opened after 4 s
- goal met: sleep in a village bed at night - asleep at day time 0.53
- goal met: the night passes while asleep - woke at day time 0.01 after 2 s

## seed 777, bot seed 1
- oracle counts: none; worst tick 14.7 ms; chunks visited 1
- goal met: open a villager's trade screen - trade screen opened after 1 s
- goal **NOT MET**: sleep in a village bed at night - couldn't sleep in the bed at 958 69 268
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_777_1.jsonl`

