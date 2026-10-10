#!/bin/bash
# Quest performance gate on the Mac proxy (docs/STORE_QUALITY.md objective 1): the bench routes in --quest mode
# (two eye views at 1440x1584 a tick, 72 Hz ticks) at the Quest's default render distance, read from
# quest/src/app/QuestSettings.swift.
#  1. Auto Render Distance controller (--rdgovernortest): synthetic frame-time traces go down on sustained misses and
#     back up to the player's choice without see-sawing; the save keeps the choice (Oct 10 playtest: 16 -> 13 for good).
#  2. The six routes: frame p99 <= 13.9 ms and at most one hitch (> 25 ms) a minute.
#  3. The Oct 10 playtest routes (seed 2943808052895834412) on counted work, which a shared Mac's load does not move:
#     taiga (the taiga village, 53 fps on the headset): terrain quads drawn, tick p99, streaming hand-over p99;
#     flyover (fast flight 50 blocks up, where the guard stepped down): hand-over p99 and chunks not meshed in view.
# Local check (~9 min at 60 s a route, needs build/Blocksmith.app): tools/quest_perf_gate.sh [--secs N] [--rd N]
#   [--routes "village taiga"]. Run it on a quiet Mac: other builds on the machine show up as hitches. Device numbers
#   come from the `perf:` lines (tools/quest_perf_log.py on adb logcat output).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=${BIN:-build/Blocksmith.app/Contents/MacOS/Blocksmith}
RD=$(sed -n "s/.*== nil ? \([0-9][0-9]*\) : d.integer(forKey: \"renderDistance\").*/\1/p" quest/src/app/QuestSettings.swift | head -1)
SECS=60
ROUTES="plains forest village cave capital ashvault taiga flyover"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rd) RD="$2"; shift 2 ;;
    --secs) SECS="$2"; shift 2 ;;
    --routes) ROUTES="$2"; shift 2 ;;
    *) echo "usage: $0 [--secs N] [--rd N] [--routes \"r1 r2\"]"; exit 2 ;;
  esac
done
[[ -n "$RD" ]] || { echo "quest_perf_gate: could not read the Quest default render distance"; exit 2; }
GOV=0
perl -e 'alarm shift; exec @ARGV' 300 "$BIN" --snapshot /tmp/quest_perf_gate_rd.png --seed 12345 --find plains --time 0.3 --rd 4 --rdgovernortest > /tmp/quest_perf_gate_rd.log 2>&1 || GOV=1
grep "^trace\|FAIL\|rdgovernor" /tmp/quest_perf_gate_rd.log | cut -c1-200
echo "quest_perf_gate: render distance $RD, $SECS s a route ($ROUTES)"
ROUTES="$ROUTES" BIN="$BIN" tools/bench_routes.sh --quest --rd "$RD" --secs "$SECS" | grep "tick spikes\|world.update mean" | cut -c1-220
python3 - "$RD" "$GOV" "$ROUTES" <<'PY'
import json, sys
m = json.load(open("snaps/routes_quest.json"))
bad = int(sys.argv[2])
# Counted-work budgets for the playtest routes at rd 16 (measured Oct 10 after the fixes, plus ~10% headroom).
counted = {
    "taiga":   {"quads": 500000, "tick_cpu_ms_p99": 4.0},
    "flyover": {"tick_cpu_ms_p99": 4.0, "unmeshed_pct": 25.0},
}
for r in sys.argv[3].split():
    k = f"route_{r}_quest"
    p99, hpm = m.get(f"{k}.frame_ms_p99"), m.get(f"{k}.hitches_per_min")
    if p99 is None:
        print(f"  {r:9s} no result (crash or timeout)"); bad += 1; continue
    if r in counted:
        fails = [f"{n} {m.get(f'{k}.{n}', 1e9):.1f} > {lim}" for n, lim in counted[r].items() if m.get(f"{k}.{n}", 1e9) > lim]
        bad += 1 if fails else 0
        print(f"  {r:9s} quads {m.get(f'{k}.quads', 0) / 1000:.0f}k, tick CPU p99 {m.get(f'{k}.tick_cpu_ms_p99', 0):.1f}, hand-over p99 {m.get(f'{k}.update_ms_p99', 0):.1f} ms, "
              f"not meshed {m.get(f'{k}.unmeshed_pct', 0):.1f}% (frame p99 {p99:.1f} ms, info)  {'PASS' if not fails else 'FAIL: ' + ', '.join(fails)}")
        continue
    ok = p99 <= 13.9 and hpm <= 1
    bad += 0 if ok else 1
    print(f"  {r:9s} p99 {p99:5.1f} ms (<= 13.9)  hitches {hpm:4.1f}/min (<= 1)  {'PASS' if ok else 'FAIL'}")
print(f"quest_perf_gate: {'PASS' if bad == 0 else f'FAIL ({bad})'} at render distance {sys.argv[1]}{' (controller test FAILED)' if sys.argv[2] != '0' else ''}")
sys.exit(1 if bad else 0)
PY
