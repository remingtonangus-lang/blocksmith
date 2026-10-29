# Agent runs: life

agent life: 0 oracle violations, 2 unmet goals over 2 seeds x 1 runs in 7 s
Ticks per run 6600 (110 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: none; worst tick 252.1 ms; chunks visited 5
- goal met: open a villager's trade screen - trade screen (ShopMenu) opened after 14 s
- goal met: sleep in a village bed at night - asleep at day time 0.53
- goal met: the night passes while asleep - woke at day time 0.01 after 4 s

## seed 777, bot seed 1
- oracle counts: none; worst tick 56.9 ms; chunks visited 7
- goal met: open a villager's trade screen - trade screen (ShopMenu) opened after 8 s
- goal **NOT MET**: sleep in a village bed at night - walking to the bed (beds tried 3; last toasts: "You found the Rook & Salt Western: 2 stations, marked on your map", "A stranger in town: Ezra Quill", "A bullion train runs the Rook & Salt Western today: armoured, guarded, and carrying the bank's gold")
- goal **NOT MET**: the night passes while asleep - never slept
- replay: `snaps/replay_life_777_1.jsonl`

