# Agent runs: life

agent life: 0 oracle violations, 4 unmet goals over 2 seeds x 1 runs in 18 s
Ticks per run 6600 (110 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: tick_spikes 2; worst tick 73.8 ms; chunks visited 4
- goal **NOT MET**: open a villager's trade screen - walked to a villager but no trade screen opened; gave up after 50 s
- goal met: sleep in a village bed at night - asleep at day time 0.53
- goal met: the night passes while asleep - woke at day time 0.01 after 4 s
- replay: `snaps/replay_life_12345_1.jsonl`

## seed 777, bot seed 1
- oracle counts: none; worst tick 42.5 ms; chunks visited 4
- goal **NOT MET**: open a villager's trade screen - walked to a villager but no trade screen opened; gave up after 50 s
- goal **NOT MET**: sleep in a village bed at night - walking to the bed
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_777_1.jsonl`

