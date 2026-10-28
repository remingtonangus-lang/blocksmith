#!/bin/bash
# Stop hook for cloud builder sessions. It blocks ending the turn while
#   1. a build or test this session started is still running (ending the turn then stalls the lane), or
#   2. an open item remains in docs/roadmap/backlog.md.
# Escape hatches: .claude/ALLOW_STOP, or a Mac session (local sessions are not meant to loop).
# Every run is logged to /tmp/keep-going-hook.log so a session can check that the hook fires at all.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
log=/tmp/keep-going-hook.log
if [ "$(uname)" = "Darwin" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then
  echo "$(date -u +%FT%TZ) skipped (Mac session or ALLOW_STOP)" >> "$log"; exit 0
fi

# 1. Work in flight: compilers, the headless check binary, build and test scripts.
# Looks only at the first four words of each process (bash script.sh, timeout 20m ./x), never inside a long command line.
inflight=$(ps -eo args= 2>/dev/null | awk '{for (i = 1; i <= 4 && i <= NF; i++) { n = $i; sub(/.*\//, "", n); print n }}' \
  | grep -xE 'swiftc|swift-frontend|swift-build|questcheck|linux-check\.sh|build-apk\.sh|quest-local\.sh|build\.sh|snap\.sh|smoke\.sh|ninja|gradle|clang|clang\+\+|Blocksmith' \
  | sort -u | tr '\n' ' ')
if [ -n "$inflight" ]; then
  echo "$(date -u +%FT%TZ) blocked: in flight: $inflight" >> "$log"
  cat <<JSON
{"decision": "block", "reason": "A build or test is still running (${inflight% }). Ending the turn now stops the lane until someone notices (three stalls on Oct 26-27 came from this). Either wait on it with one blocking command inside timeout 20m, or start the next open item in docs/roadmap/backlog.md while it runs and pick the result up after."}
JSON
  exit 0
fi

# 2. Open items: unclaimed ones, plus claimed ones whose tag still lists open parts ("Still open"),
#    unless they wait on Remington.
backlog="$dir/docs/roadmap/backlog.md"
items=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "ON HOLD")
unclaimed=$(printf '%s\n' "$items" | grep -E "^P" | grep -vc "CLAIMED")
partial=$(printf '%s\n' "$items" | grep "CLAIMED" | grep "Still open" | grep -v -E "BLOCKED|awaiting Remington" | grep -c .)
open=$(( ${unclaimed:-0} + ${partial:-0} ))
if [ "${open:-0}" -gt 0 ]; then
  echo "$(date -u +%FT%TZ) blocked: $open open item(s)" >> "$log"
  cat <<JSON
{"decision": "block", "reason": "$open open item(s) remain in docs/roadmap/backlog.md (claimed items whose tag says \"Still open\" count). Its rules are at the top, including Remington's BLOOM, DON'T PATCH rule (Oct 25)."}
JSON
  exit 0
fi
echo "$(date -u +%FT%TZ) allowed: nothing open, nothing in flight" >> "$log"
exit 0
