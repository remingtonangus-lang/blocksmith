#!/bin/bash
# Stop hook (Oct 18): in remote (cloud) sessions, keep working while an open item remains in docs/roadmap/backlog.md.
# Oct 20: the lane works untagged items at medium; [HIGH AGENT] items belong to the one tough-builder agent. Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
backlog="$dir/docs/roadmap/backlog.md"
open=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "CLAIMED" | grep -vc "ON HOLD")
mine=$(grep -E "^P[0-9]+\. " "$backlog" 2>/dev/null | grep -v -E "\[DONE|DONE\]" | grep -v "CLAIMED" | grep -v "ON HOLD" | grep -vc "\[HIGH AGENT\]")
if [ "${mine:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "Do not stop: $mine open item(s) for the lane remain in docs/roadmap/backlog.md ($open counting [HIGH AGENT] items). Take the next untagged one top to bottom at medium effort (skip [HIGH AGENT] items; if the tough-builder agent has not been spawned yet, spawn it once first): steps if it has none, build every part, compile, one quick check, push, self-merge, mark it [DONE] with the PR number. Stop only when none is left."}
JSON
elif [ "${open:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "Only [HIGH AGENT] items remain ($open). If the tough-builder agent is running, wait for it with one long blocking wait (no polling), then stop. If it was never spawned or has died, spawn it once (background, isolation worktree)."}
JSON
fi
exit 0
