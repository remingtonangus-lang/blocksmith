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
# Regression gate (tools/perf_baseline.json, section "local" or "ci"): every route fails when its terrain quads pass the
#   pinned count + 5% or its frame p99 passes the pinned p99 x 1.25 (local runs) / the local pin x 2 (CI, which pins
#   quads only). After an intended
#   change, re-pin with --rebaseline (writes this run's quads and p99 into the section) and commit the json.
# CI (snap.sh checks shard, heavy lane: --secs 20 --routes "taiga flyover"): PERF_GATE_CI=1 gates on the controller
# test, the quads / unmeshed budgets and a frame p99 under twice the local pin; tick CPU is printed for the record (a
# shared CI VM is not a Quest and its timings swing run to run). The CI routes are 20 s, the budgets come from 60 s local runs.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=${BIN:-build/Blocksmith.app/Contents/MacOS/Blocksmith}
RD=$(sed -n "s/.*== nil ? \([0-9][0-9]*\) : d.integer(forKey: \"renderDistance\").*/\1/p" quest/src/app/QuestSettings.swift | head -1)
SECS=60
REBASE=0
ROUTES="plains forest village cave capital ashvault taiga flyover"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rd) RD="$2"; shift 2 ;;
    --secs) SECS="$2"; shift 2 ;;
    --routes) ROUTES="$2"; shift 2 ;;
    --rebaseline) REBASE=1; shift ;;
    *) echo "usage: $0 [--secs N] [--rd N] [--routes \"r1 r2\"] [--rebaseline]"; exit 2 ;;
  esac
done
[[ -n "$RD" ]] || { echo "quest_perf_gate: could not read the Quest default render distance"; exit 2; }
GOV=0
perl -e 'alarm shift; exec @ARGV' 300 "$BIN" --snapshot /tmp/quest_perf_gate_rd.png --seed 12345 --find plains --time 0.3 --rd 4 --rdgovernortest > /tmp/quest_perf_gate_rd.log 2>&1 || GOV=1
grep "^trace\|FAIL\|rdgovernor" /tmp/quest_perf_gate_rd.log | cut -c1-200
echo "quest_perf_gate: render distance $RD, $SECS s a route ($ROUTES)"
ROUTES="$ROUTES" BIN="$BIN" tools/bench_routes.sh --quest --rd "$RD" --secs "$SECS" | grep "tick spikes\|world.update mean" | cut -c1-220
python3 - "$RD" "$GOV" "$ROUTES" "$REBASE" <<'PY'
import json, os, sys
ci = os.environ.get("PERF_GATE_CI") == "1"
m = json.load(open("snaps/routes_quest.json"))
bad = int(sys.argv[2])
BASE = "tools/perf_baseline.json"
base = json.load(open(BASE)) if os.path.exists(BASE) else {}
sect = base.setdefault("ci" if ci else "local", {})
P99_TOL = 1.25
CI_P99_TOL = 2.0
if sys.argv[4] == "1":
    for r in sys.argv[3].split():
        k = f"route_{r}_quest"
        if m.get(f"{k}.frame_ms_p99") is not None:
            # CI pins counted work only: a shared VM's frame times are not this Mac's and swing run to run.
            sect[r] = {"quads": int(m.get(f"{k}.quads", 0))} | ({} if ci else {"frame_ms_p99": round(m[f"{k}.frame_ms_p99"], 2)})
    json.dump(base, open(BASE, "w"), indent=1, sort_keys=True)
    print(f"quest_perf_gate: re-pinned {sys.argv[3]} in {BASE} ({'ci' if ci else 'local'})")
def regress(r, k):
    # Pinned counted work and frame time: quads over pin + 5% or p99 over pin x tolerance is a regression.
    b, out = sect.get(r), []
    if not b: return [f"no baseline for {r} (run --rebaseline)"]
    q, p = m.get(f"{k}.quads", 0), m.get(f"{k}.frame_ms_p99", 1e9)
    if b.get("quads") and q > b["quads"] * 1.05: out.append(f"quads {q / 1000:.0f}k > pinned {b['quads'] / 1000:.0f}k + 5%")
    if b.get("frame_ms_p99") and p > b["frame_ms_p99"] * P99_TOL: out.append(f"frame p99 {p:.1f} > pinned {b['frame_ms_p99']:.1f} x {P99_TOL}")
    # CI: no frame-time pins of its own (a VM swings run to run); a frame p99 over twice the local pin is still a
    # regression nobody should ship (catches a doubled frame, not a few percent).
    lb = base.get("local", {}).get(r, {})
    if ci and lb.get("frame_ms_p99") and p > lb["frame_ms_p99"] * CI_P99_TOL:
        out.append(f"frame p99 {p:.1f} > local pin {lb['frame_ms_p99']:.1f} x {CI_P99_TOL}")
    return out
# Counted-work budgets for the playtest routes at rd 16 (Oct 10 after the fixes: taiga 460k quads, tick CPU p99 2.6-3.6 ms;
# flyover 320k quads, tick CPU p99 3.5-5.0 ms, 0.6-1.0% not meshed; before: taiga 512k quads). Thread CPU, not wall time.
counted = {
    "taiga":   {"tick_cpu_ms_p99": 4.5},
    # flyover: 372k from bad1cbfb on (Oct 10 worldgen: volcano siting, capitals >= 1,200 from spawn, wild camps; the
    # route now crosses other land; bisected in task 25b4zxxxx, performance.md); 310k before. ~+2% headroom.
    "flyover": {"tick_cpu_ms_p99": 6.0, "unmeshed_pct": 30.0},
}
for r in sys.argv[3].split():
    k = f"route_{r}_quest"
    p99, hpm = m.get(f"{k}.frame_ms_p99"), m.get(f"{k}.hitches_per_min")
    if p99 is None:
        print(f"  {r:9s} no result (crash or timeout)"); bad += 1; continue
    if r in counted:
        fails = [f"{n} {m.get(f'{k}.{n}', 1e9):.1f} > {lim}" for n, lim in counted[r].items()
                 if m.get(f"{k}.{n}", 1e9) > lim and not (ci and n == "tick_cpu_ms_p99")]   # CI: a shared VM's CPU time swings
        fails += regress(r, k)
        bad += 1 if fails else 0
        print(f"  {r:9s} quads {m.get(f'{k}.quads', 0) / 1000:.0f}k, tick CPU p99 {m.get(f'{k}.tick_cpu_ms_p99', 0):.1f}, hand-over p99 {m.get(f'{k}.update_ms_p99', 0):.1f} ms, "
              f"not meshed {m.get(f'{k}.unmeshed_pct', 0):.1f}% (frame p99 {p99:.1f} ms)  {'PASS' if not fails else 'FAIL: ' + ', '.join(fails)}")
        continue
    ok = p99 <= 13.9 and hpm <= 1
    reg = regress(r, k)
    bad += 0 if (ok or ci) and not reg else 1
    print(f"  {r:9s} p99 {p99:5.1f} ms (<= 13.9)  hitches {hpm:4.1f}/min (<= 1)  quads {m.get(f'{k}.quads', 0) / 1000:.0f}k  "
          f"{'FAIL: ' + ', '.join(reg) if reg else ('PASS' if ok else ('over (info on CI)' if ci else 'FAIL'))}")
print(f"quest_perf_gate: {'PASS' if bad == 0 else f'FAIL ({bad})'} at render distance {sys.argv[1]}{' (controller test FAILED)' if sys.argv[2] != '0' else ''}")
sys.exit(1 if bad else 0)
PY
