#!/bin/bash
# Stop hook: in remote (cloud) sessions Blocksmith work never ends on its own: block the stop and point at the queue.
# Escape hatches: a .claude/ALLOW_STOP file in the repo, or any session that isn't remote (Remington's Mac).
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ "$branch" = "claude/frontier-game" ]; then
cat <<'JSON'
{"decision": "block", "reason": "Frontier is never done. Take the biggest gap from the ranked gap list in docs/status/frontier.md (scored against frontier/QUALITY_BAR.md by blind critic rounds) and close it. Never idle on CI: work locally (godot + xvfb llvmpipe screenshots) while a run is going; push batched commits on claude/frontier-game only."}
JSON
exit 0
fi
cat <<'JSON'
{"decision": "block", "reason": "Continue with the next highest-value item in STATUS.md (Playtest feedback queue) / BUGS.md; you are not done until usage runs out. Never idle on CI: work locally while a run is going, push when it has published. Keep CI green and PR #9 current."}
JSON
