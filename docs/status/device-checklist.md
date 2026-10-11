# Device checklist (run first when the Quest 3 is on adb)

Things only the headset can prove. Run them in order the next time `adb devices` lists the Quest.

## 1. Frame-rate proof at render distance 16 (from task 25b4zxxx item 1; still open)

1. Build and install a default (optimized) build, not `--fast`. Frame times only count on a default build:
   `tools/quest-local.sh --log 1500 > /tmp/quest-perf.log` (follows `adb logcat -s Blocksmith` for 25 min).
2. In the headset: render distance 16, Auto Render Distance on. Play about 10 minutes in the busiest town (a capital city
   with the most townsfolk), then about 10 minutes in a taiga (`--find taiga` biome; walk and fly, look around).
3. Read the log: `python3 tools/quest_perf_log.py /tmp/quest-perf.log --windows`.
4. Write down in docs/status/performance.md (new "Device proof" section), once for the town and once for the taiga:
   - share of time holding 72 Hz, and missed (dropped) frames per minute
   - CPU ms and GPU ms (median and worst window), plus the `record ms` split on the `perf:` line
   - whether Auto Render Distance stepped down, and whether it climbed back to 16 after the busy part
5. If either place misses 72 Hz for long stretches: the biggest `record ms` part is the next perf item (mobs, terrain,
   HUD, ships). Note it in the STATUS.md Work queue.

The Mac `--quest` proxy numbers (gate in `snap.sh` checks shard, budgets in performance.md) are the stand-in until then.
Aniso 8 vs 4 was A/B'd only on the Mac proxy (no difference); recheck GPU ms on device with aniso 4 if GPU is the
limit in step 4.

## 2. Polygon terrain walk (task 25b5a, docs/status/polygon-test.md)

1. Default build (`tools/quest-local.sh`), then Create New World > Terrain: Smooth (Test), seed 12345.
2. Walk the spawn hills and a beach for 5 minutes; then Options > Video > Smooth Terrain off and walk the same spot.
3. Note: comfort of the eased step-ups, any see-through gaps at chunk edges, how steep stone/snow looks up close.
4. Frame rate: `tools/quest-local.sh --log 600 > /tmp/quest-smooth.log`, read with
   `python3 tools/quest_perf_log.py /tmp/quest-smooth.log --windows`, once per mode at rd 16. Add both rows to polygon-test.md.

## 3. Device feel for merged lane features (backlog M3)

- Six-iron (B1, docs/status/six-iron.md): shoot and reload it in VR: does the aim line up with the barrel, is recoil readable.
- Hunting (B3, docs/status/hunting.md): a clean kill, skinning, and the fishing fight: do they feel physical in VR, not menu-like.
- Not merged yet (check when they land): flying vehicles and the crawler (A4), frigate radar (A5), VR melee vs knights (B6).
