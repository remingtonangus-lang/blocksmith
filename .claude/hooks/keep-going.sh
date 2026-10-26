#!/bin/bash
# Stop hook: in remote (cloud) sessions, keep working while an open item remains in docs/roadmap/backlog.md.
# Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
backlog="$dir/docs/roadmap/backlog.md"
items=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "ON HOLD")
# Unclaimed items, plus claimed items whose tag still lists open parts ("Still open"), unless they wait on Remington.
unclaimed=$(printf '%s\n' "$items" | grep -E "^P" | grep -vc "CLAIMED")
partial=$(printf '%s\n' "$items" | grep "CLAIMED" | grep "Still open" | grep -v -E "BLOCKED|awaiting Remington" | grep -c .)
open=$(( ${unclaimed:-0} + ${partial:-0} ))
if [ "${open:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "$open open item(s) remain in docs/roadmap/backlog.md (claimed items whose tag says \"Still open\" count). Its rules are at the top, including Remington's BLOOM, DON'T PATCH rule (Oct 25)."}
JSON
fi
exit 0
