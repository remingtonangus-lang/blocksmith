#!/bin/bash
# The six benchmark routes (Sources/BenchRoutes.swift), each in its own process so memory numbers stay separate.
#   tools/bench_routes.sh [--quest] [--secs N] [--rd N] [--seed N]   -> snaps/routes[_quest].json + .md table
# Local tool (not a CI job). Targets: docs/STORE_QUALITY.md objective 1.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
SUF=""; [[ " $* " == *" --quest "* ]] && SUF="_quest"
mkdir -p snaps; rm -f snaps/route_part_*.json
for r in plains forest village cave capital ashvault; do
  perl -e 'alarm shift; exec @ARGV' 300 "$BIN" --bench "snaps/route_part_$r.json" --scenes "route_$r" "$@" 2>&1 | grep "^bench route\|TIMEOUT\|error" || echo "route $r: no result (crash or timeout)"
done
python3 - "$SUF" <<'PY'
import glob, json, sys
suf = sys.argv[1]; m = {}
for p in sorted(glob.glob("snaps/route_part_*.json")): m.update({k: v for k, v in json.load(open(p)).items() if k.startswith("route_")})
json.dump(m, open(f"snaps/routes{suf}.json", "w"), indent=2, sort_keys=True)
rows = ["| route | p50 ms | p99 ms | max ms | budget | hitches/min | load ms | resident peak MB | growth % | mobs | pass |", "|---|---|---|---|---|---|---|---|---|---|---|"]
for r in ["plains", "forest", "village", "cave", "capital", "ashvault"]:
    k = f"route_{r}{suf}"; g = lambda n: m.get(f"{k}.{n}", float("nan"))
    rows.append(f"| {r} | {g('frame_ms_p50'):.1f} | {g('frame_ms_p99'):.1f} | {g('frame_ms_max'):.1f} | {g('budget_ms'):.1f} | {g('hitches_per_min'):.1f} | {g('load_ms'):.0f} | {g('resident_peak_mb'):.0f} | {g('resident_growth_pct'):.1f} | {g('mobs'):.0f} | {'PASS' if g('pass') == 1 else 'FAIL'} |")
open(f"snaps/routes{suf}.md", "w").write("\n".join(rows) + "\n"); print("\n".join(rows))
PY
