#!/bin/bash
# Type-check time report from a build log built with -warn-long-expression-type-checking: every expression over
# 150 ms, slowest first, as GitHub warning annotations (over 300 ms). Never fails: slow expressions are fixed in
# batches (split into typed lets), not by failing the build (the old 600 ms gate failed most CI runs).
#   tools/typecheck_report.sh build.log typecheck.log
LOG="${1:-build.log}"; OUT="${2:-typecheck.log}"
grep -E "warning: expression took [0-9]+ms to type-check" "$LOG" 2>/dev/null \
  | sed -nE 's#^.*(Sources/[^:]+):([0-9]+):[0-9]+: warning: expression took ([0-9]+)ms.*#\3 \1:\2#p' \
  | sort -u | sort -rn > "$OUT" || true
awk '$1 >= 300 { split($2, a, ":"); printf "::warning file=%s,line=%s::type-check %s ms\n", a[1], a[2], $1 }' "$OUT" || true
n=$(wc -l < "$OUT" | tr -d ' '); slow=$(awk '$1 >= 600' "$OUT" | wc -l | tr -d ' ')
echo "type-check: $n expressions over 150 ms, $slow over 600 ms (warnings only)"
head -20 "$OUT"
exit 0
