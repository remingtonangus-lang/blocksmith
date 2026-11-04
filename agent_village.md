# Agent runs: village

agent village: 3 oracle violations, 3 unmet goals over 3 seeds x 1 runs in 11 s
Ticks per run 4800 (80 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: goal_failed 1; worst tick 287.9 ms; chunks visited 7
- **goal_failed** at tick 4252 (-274.8 75.1 -925.8): couldn't walk into the building at door -284 70 -990
- goal met: enter the building with the door at -296 71 -948 - in after 7 s
- goal met: enter the building with the door at -300 72 -928 - in after 7 s
- goal met: enter the building with the door at -276 73 -921 - in after 6 s
- goal met: enter the building with the door at -271 73 -921 - in after 0 s
- goal met: enter the building with the door at -271 73 -925 - in after 1 s
- goal met: enter the building with the door at -271 73 -917 - in after 1 s
- goal **NOT MET**: enter the building with the door at -284 70 -990 - came within 64.5 blocks in 45 s; stopped at -275 75 -926
- replay: `snaps/replay_village_12345_1.jsonl`

## seed 777, bot seed 1
- oracle counts: goal_failed 1; worst tick 39.7 ms; chunks visited 6
- **goal_failed** at tick 4224 (294.2 83.0 -1847.2): couldn't walk into the building at door 261 79 -1760
- goal met: enter the building with the door at 262 80 -1810 - in after 8 s
- goal met: enter the building with the door at 276 81 -1823 - in after 6 s
- goal met: enter the building with the door at 284 81 -1823 - in after 2 s
- goal met: enter the building with the door at 293 82 -1849 - in after 7 s
- goal **NOT MET**: enter the building with the door at 261 79 -1760 - came within 92.7 blocks in 45 s; stopped at 294 82 -1848
- replay: `snaps/replay_village_777_1.jsonl`

## seed 424242, bot seed 1
- oracle counts: goal_failed 1; worst tick 31.6 ms; chunks visited 2
- **goal_failed** at tick 3008 (-1420.2 82.3 283.2): couldn't walk into the building at door -1412 78 241
- goal met: enter the building with the door at -1420 81 286 - in after 5 s
- goal **NOT MET**: enter the building with the door at -1412 78 241 - came within 42.9 blocks in 45 s; stopped at -1421 82 283
- replay: `snaps/replay_village_424242_1.jsonl`

