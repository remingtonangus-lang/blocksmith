#!/bin/bash
# Proves a change with one named check: builds questcheck incrementally (-O, file by file) if any source changed since the last
# build (tools/qbuild.sh), runs `questcheck --NAME-only` from the repo dir at BLOCKSMITH_TEXRES=32 and prints only the FAIL
# lines, the lines that mention NAME, the final pass/fail line and the wall time. Exit code = number of failures.
#
#   tools/prove.sh NAME [ENV=VAL ...] [-- EXTRA QUESTCHECK ARGS]
#   tools/prove.sh --both SWITCH NAME [ENV=VAL ...]   runs it twice: SWITCH unset, then SWITCH=1, and prints both
#   PROVE_OPT=onone tools/prove.sh NAME               build -Onone instead of -O (onone|o|ounchecked; see qbuild.sh):
#                                                      builds faster, but checks run ~9x slower
#   NAME may also be a run without -only (placerow -> --placerow) or a whole flag (--rail-only).
#   PROVE_BIN=/path/questcheck tools/prove.sh NAME     use that binary, no build (e.g. the full optimized build)
#   PROVE_ALL=1                                        print every line, not just the filtered ones
#
# Names: `questcheck --list-checks`. The full optimized build + whole suite is still the merge gate.
set -uo pipefail
cd "$(dirname "$0")/.."
both=""
if [ "${1:-}" = "--both" ]; then both="$2"; shift 2; fi
NAME="${1:?usage: tools/prove.sh [--both SWITCH] NAME [ENV=VAL ...] [-- ARGS]}"; shift
envs=(); extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; extra=("$@"); break ;;
    *=*) envs+=("$1"); shift ;;
    *) extra+=("$1"); shift ;;
  esac
done
t0=$SECONDS
# The flag: --NAME-only if main.swift has it, else --NAME (quest/tools/listchecks.py lists them all).
case "$NAME" in
  --*) FLAG="$NAME"; NAME="${NAME#--}"; NAME="${NAME%-only}" ;;
  *) list=$(python3 quest/tools/listchecks.py | awk '{print $1}')
     if echo "$list" | grep -qx -- "--$NAME-only"; then FLAG="--$NAME-only"
     elif echo "$list" | grep -qx -- "--$NAME"; then FLAG="--$NAME"
     else echo "prove: no run --$NAME-only or --$NAME in main.swift (quest/tools/listchecks.py lists them)"; exit 101; fi ;;
esac
if [ -n "${PROVE_BIN:-}" ]; then BIN="$PROVE_BIN"
else
  if ! out=$(tools/qbuild.sh "${PROVE_OPT:-o}" 2>&1); then
    echo "$out" | grep -E 'error:|qbuild' | head -40; echo "prove: BUILD FAILED"; exit 100
  fi
  BIN=$(echo "$out" | tail -1); echo "$out" | grep '^qbuild:'
fi
run() {  # run LABEL [ENV=VAL ...]: one run, filtered; sets $fails
  local label=$1; shift; local t1=$SECONDS log
  log=$(mktemp)
  env "$@" BLOCKSMITH_TEXRES=32 "${envs[@]}" "$BIN" "$FLAG" "${extra[@]}" > "$log" 2>&1; local status=$?
  if [ "${PROVE_ALL:-0}" = 1 ]; then cat "$log"
  else grep -E "^FAIL |$NAME|all checks passed|FAILED|Fatal error|fatal error|Segmentation|Illegal instruction" "$log"; fi
  fails=$(grep -c '^FAIL ' "$log"); local oks; oks=$(grep -c '^ok   ' "$log")
  [ "$status" != 0 ] && [ "$fails" = 0 ] && { fails=1; echo "prove: exit $status with no FAIL line (crash?); last lines:"; tail -5 "$log"; }
  echo "prove: $label $FLAG: $oks ok, $fails FAIL, exit $status, $((SECONDS - t1)) s"
  rm -f "$log"
}
if [ -n "$both" ]; then
  run "$both unset" -u "$both"; f1=$fails
  run "$both=1" "$both=1"; f2=$fails
  total=$((f1 + f2))
  echo "prove: --both $both: unset $f1 FAIL, =1 $f2 FAIL"
else
  run "${NAME}"; total=$fails
fi
echo "prove: wall $((SECONDS - t0)) s"
exit $(( total > 99 ? 99 : total ))
