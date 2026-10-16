# Agent runs: life

agent life: 0 oracle violations, 4 unmet goals over 2 seeds x 1 runs in 15 s
Ticks per run 6600 (110 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 52.3 ms; chunks visited 2
- goal met: open a villager's trade screen - trade screen opened after 5 s
- goal **NOT MET**: sleep in a village bed at night - couldn't sleep in the bed at 22 125 -324 (1.8 blocks from it, health 20, day time 0.56); last toasts: "Village marked on the map"
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_12345_1.jsonl`

## seed 777, bot seed 1
- oracle counts: none; worst tick 23.2 ms; chunks visited 4
- goal met: open a villager's trade screen - trade screen opened after 10 s
- goal **NOT MET**: sleep in a village bed at night - walking to the bed
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_777_1.jsonl`

