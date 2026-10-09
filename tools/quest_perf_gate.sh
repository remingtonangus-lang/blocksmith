#!/bin/bash
# Quest performance gate on the Mac proxy (docs/STORE_QUALITY.md objective 1): the six bench routes in --quest mode
# (two eye views at 1440x1584 a tick, 72 Hz ticks) at the Quest's default render distance, read from
# quest/src/app/QuestSettings.swift. Fails (exit 1) when any route's frame p99 is over 13.9 ms or it has more than one
# hitch (> 25 ms) a minute. Local check (~7 min at 60 s a route so one hitch reads as 1/min, needs build/Blocksmith.app): tools/quest_perf_gate.sh [--secs N] [--rd N]
# Run it on a quiet Mac: other builds on the machine show up as hitches. Device numbers come from the `perf:` lines
# (tools/quest_perf_log.py on adb logcat output).
set -uo pipefail
cd "$(dirname "$0")/.."
RD=$(sed -n "s/.*== nil ? \([0-9][0-9]*\) : d.integer(forKey: \"renderDistance\").*/\1/p" quest/src/app/QuestSettings.swift | head -1)
SECS=60
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rd) RD="$2"; shift 2 ;;
    --secs) SECS="$2"; shift 2 ;;
    *) echo "usage: $0 [--secs N] [--rd N]"; exit 2 ;;
  esac
done
[[ -n "$RD" ]] || { echo "quest_perf_gate: could not read the Quest default render distance"; exit 2; }
echo "quest_perf_gate: render distance $RD, $SECS s a route"
tools/bench_routes.sh --quest --rd "$RD" --secs "$SECS" | grep "tick spikes" | cut -c1-220
python3 - "$RD" <<'PY'
import json, sys
m = json.load(open("snaps/routes_quest.json"))
bad = 0
for r in ["plains", "forest", "village", "cave", "capital", "ashvault"]:
    k = f"route_{r}_quest"
    p99, hpm = m.get(f"{k}.frame_ms_p99"), m.get(f"{k}.hitches_per_min")
    if p99 is None:
        print(f"  {r:9s} no result (crash or timeout)"); bad += 1; continue
    ok = p99 <= 13.9 and hpm <= 1
    bad += 0 if ok else 1
    print(f"  {r:9s} p99 {p99:5.1f} ms (<= 13.9)  hitches {hpm:4.1f}/min (<= 1)  {'PASS' if ok else 'FAIL'}")
print(f"quest_perf_gate: {'PASS' if bad == 0 else f'FAIL ({bad} of 6 routes)'} at render distance {sys.argv[1]}")
sys.exit(1 if bad else 0)
PY
