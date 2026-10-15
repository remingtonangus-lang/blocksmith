#!/bin/bash
# Stop hook (TIERS, Oct 15): in remote (cloud) sessions, block a stop while an open item of the current tier remains.
# The current tier is in docs/roadmap/TIER; the overseer's scheduler advances it. Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
tier=$(sed -n 's/^current: *//p' "$dir/docs/roadmap/TIER" 2>/dev/null | head -1)
[ -z "$tier" ] && exit 0
open=$(grep -E "^[A-Z][A-Za-z0-9-]*\. " "$dir/docs/roadmap/backlog.md" 2>/dev/null | grep -F "[T:$tier]" | grep -v -E "\[DONE|DONE\]" | grep -vc "CLAIMED")
if [ "${open:-0}" -eq 0 ]; then exit 0; fi
cat <<JSON
{"decision": "block", "reason": "Do not stop: $open open [T:$tier] item(s) remain in docs/roadmap/backlog.md. Take the next one top to bottom, claim it, write its lettered parts, build every part, compile, run its one quick check, push, self-merge, mark DONE naming each part. One and done, no helper agents. When no [T:$tier] item is left, end with: TIER EMPTY: $tier"}
JSON
