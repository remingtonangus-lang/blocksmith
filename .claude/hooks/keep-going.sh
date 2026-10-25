#!/bin/bash
# Stop hook: in remote (cloud) sessions, keep working while an open item remains in docs/roadmap/backlog.md.
# Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
backlog="$dir/docs/roadmap/backlog.md"
open=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "CLAIMED" | grep -vc "ON HOLD")
if [ "${open:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "$open open item(s) remain in docs/roadmap/backlog.md. Its rules are at the top, including Remington's BLOOM, DON'T PATCH rule (Oct 25)."}
JSON
fi
exit 0
