#!/bin/bash
# Stop hook for the cloud lane: ending a turn stops the lane until someone writes to it, and no one watches it.
# So a cloud turn never ends on its own. Escape hatch: .claude/ALLOW_STOP (Remington, or the lane when he asks it to stop).
# Mac sessions are skipped. Each run is logged to /tmp/keep-going-hook.log.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
log=/tmp/keep-going-hook.log
if [ "$(uname)" = "Darwin" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then
  echo "$(date -u +%FT%TZ) allowed (Mac session or ALLOW_STOP)" >> "$log"; exit 0
fi
echo "$(date -u +%FT%TZ) blocked" >> "$log"
cat <<'JSON'
{"decision": "block", "reason": "Ending the turn stops the lane, and no one will restart it. Remington: \"Its goal is to make the game the best and do the most work per hour in getting that done. When it is waiting, it should realize that this is not the most efficient way to get work done.\" Keep going: the rule is at the top of docs/roadmap/backlog.md."}
JSON
exit 0
