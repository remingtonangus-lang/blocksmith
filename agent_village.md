# Agent runs: village

agent village: 2 oracle violations, 2 unmet goals over 3 seeds x 1 runs in 10 s
Ticks per run 4800 (80 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: goal_failed 1; worst tick 266.6 ms; chunks visited 7
- **goal_failed** at tick 4254 (-274.7 74.9 -925.7): couldn't walk into the building at door -284 70 -990
- goal met: enter the building with the door at -296 71 -948 - in after 7 s
- goal met: enter the building with the door at -300 72 -928 - in after 7 s
- goal met: enter the building with the door at -276 73 -921 - in after 6 s
- goal met: enter the building with the door at -271 73 -921 - in after 0 s
- goal met: enter the building with the door at -271 73 -925 - in after 1 s
- goal met: enter the building with the door at -271 73 -917 - in after 1 s
- goal **NOT MET**: enter the building with the door at -284 70 -990 - came within 64.5 blocks in 45 s; stopped at -275 74 -926
- replay: `snaps/replay_village_12345_1.jsonl`

## seed 777, bot seed 1
- oracle counts: none; worst tick 49.4 ms; chunks visited 5
- goal met: enter the building with the door at 732 103 -1451 - in after 6 s
- goal met: enter the building with the door at 724 104 -1463 - in after 4 s
- goal met: enter the building with the door at 707 99 -1428 - in after 13 s

## seed 424242, bot seed 1
- oracle counts: goal_failed 1; worst tick 34.1 ms; chunks visited 3
- **goal_failed** at tick 3399 (232.3 81.4 163.7): couldn't walk into the building at door 185 81 187
- goal met: enter the building with the door at 219 80 172 - in after 4 s
- goal met: enter the building with the door at 219 80 164 - in after 2 s
- goal met: enter the building with the door at 235 80 164 - in after 4 s
- goal **NOT MET**: enter the building with the door at 185 81 187 - came within 53.0 blocks in 45 s; stopped at 232 81 163
- replay: `snaps/replay_village_424242_1.jsonl`

