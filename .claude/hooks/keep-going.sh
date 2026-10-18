#!/bin/bash
# Stop hook (Oct 18): in remote (cloud) sessions, keep working while an open item remains in docs/roadmap/backlog.md.
# No tiers; every item is worked at medium effort. Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
backlog="$dir/docs/roadmap/backlog.md"
open=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "CLAIMED" | grep -vc "ON HOLD")
if [ "${open:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "Do not stop: $open open item(s) remain in docs/roadmap/backlog.md. Take the next one top to bottom at medium effort: steps if it has none, build every part, compile, one quick check, push, self-merge, mark it [DONE] with the PR number. Stop only when none is left."}
JSON
fi
exit 0
