#!/bin/bash
# Performance benchmarks (headless). Writes snaps/bench.json and prints a summary; then compares with
# perf/baseline.json (snaps/bench.md) and fails on a gross regression.
#   ./bench.sh                     every scene
#   ./bench.sh --scenes gen,mesh   some scenes (see Sources/Bench.swift)
#   ./bench.sh --quick             shorter flights
set -euo pipefail
cd "$(dirname "$0")"
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
mkdir -p snaps
"$BIN" --bench snaps/bench.json "$@"
python3 perf/compare.py snaps/bench.json perf/baseline.json snaps/bench.md
