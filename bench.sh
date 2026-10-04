#!/bin/bash
# Performance benchmarks (headless). Writes snaps/bench.json and prints a summary; then compares with
# perf/baseline.json (snaps/bench.md) and fails on a gross regression.
#   ./bench.sh                     every scene (flights each in their own process, so memory numbers
#                                  aren't inflated by earlier scenes)
#   ./bench.sh --scenes gen,mesh   some scenes in one process (see Sources/Bench.swift)
#   ./bench.sh --quick             shorter flights
set -euo pipefail
cd "$(dirname "$0")"
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
# Each benchmark process gets 4 minutes (a hang shows which scene instead of a CI timeout with no logs).
run() { perl -e 'alarm shift; exec @ARGV' 240 "$@"; rc=$?; [ $rc -eq 142 ] && echo "bench: TIMEOUT after 240 s: $*"; return $rc; }
mkdir -p snaps
rm -f snaps/bench_part_*.json
if [[ " $* " == *" --scenes "* ]]; then
  run "$BIN" --bench snaps/bench_part_0.json "$@"
else
  run "$BIN" --bench snaps/bench_part_0.json --scenes gen,mesh,startup,frame,edit,mobs,save,tnt,fluids,weather,ships "$@"
  for f in flight8 flight16 flight24; do
    run "$BIN" --bench "snaps/bench_part_$f.json" --scenes "$f" "$@"
  done
fi
python3 - <<'PY'
import glob, json
merged = {}
for p in sorted(glob.glob("snaps/bench_part_*.json")):
    merged.update(json.load(open(p)))
json.dump(merged, open("snaps/bench.json", "w"), indent=2, sort_keys=True)
print(f"bench: merged {len(merged)} metrics into snaps/bench.json")
PY
python3 perf/compare.py snaps/bench.json perf/baseline.json snaps/bench.md
