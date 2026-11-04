# Agent runs: cave

agent cave: 2 oracle violations, 6 unmet goals over 3 seeds x 1 runs in 19 s
Ticks per run 14400 (240 s of game time), walking only.

## seed 12345, bot seed 1
- oracle counts: tick_spikes 2; worst tick 55.5 ms; chunks visited 6
- goal **NOT MET**: walk down into a cave (10+ blocks under the surface) - no cave floor within 64 blocks; walking on to 4651 1751 to look again (1)
- goal **NOT MET**: walk back up out of it - never got down
- replay: `snaps/replay_cave_12345_1.jsonl`

## seed 777, bot seed 1
- oracle counts: inside_solid 2, tick_spikes 4; worst tick 69.7 ms; chunks visited 12
- **inside_solid** at tick 2075 (3852.5 106.4 -4130.9): player overlaps a solid block (air at head height)
- **inside_solid** at tick 2250 (3856.6 109.4 -4137.6): player overlaps a solid block (air at head height)
- goal **NOT MET**: walk down into a cave (10+ blocks under the surface) - no cave floor within 64 blocks; walking on to 3859 -4142 to look again (4)
- goal **NOT MET**: walk back up out of it - never got down
- replay: `snaps/replay_cave_777_1.jsonl`

## seed 424242, bot seed 1
- oracle counts: tick_spikes 4; worst tick 53.3 ms; chunks visited 12
- goal **NOT MET**: walk down into a cave (10+ blocks under the surface) - no cave floor within 64 blocks; walking on to -5690 -2008 to look again (4)
- goal **NOT MET**: walk back up out of it - never got down
- replay: `snaps/replay_cave_424242_1.jsonl`

