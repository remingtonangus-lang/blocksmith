# Agent runs: life

agent life: 0 oracle violations, 2 unmet goals over 2 seeds x 1 runs in 8 s
Ticks per run 6600 (110 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 244.3 ms; chunks visited 5
- goal met: open a villager's trade screen - trade screen (ShopMenu) opened after 13 s
- goal met: sleep in a village bed at night - asleep at day time 0.53
- goal met: the night passes while asleep - woke at day time 0.01 after 4 s

## seed 777, bot seed 1
- oracle counts: none; worst tick 27.9 ms; chunks visited 3
- goal met: open a villager's trade screen - trade screen (ShopMenu) opened after 9 s
- goal **NOT MET**: sleep in a village bed at night - walking to the bed (beds tried 2; last toasts: "Spring: the snow melts and the young are born", "A stranger in town: Ezra Quill")
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_777_1.jsonl`

