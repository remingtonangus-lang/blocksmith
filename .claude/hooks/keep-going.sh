#!/bin/bash
# Stop hook: in remote (cloud) sessions Blocksmith work never ends on its own: block the stop and point at the queue.
# Escape hatches: a .claude/ALLOW_STOP file in the repo, or any session that isn't remote (Remington's Mac).
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
cat <<'JSON'
{"decision": "block", "reason": "Do not stop: take the next unclaimed item in your lane of docs/roadmap/backlog.md (then the other cloud lane), claim it, write expanded objectives, build it thoroughly, check it compiles and run its one quick test, push, self-merge, mark it DONE, repeat. One and done: no review or verify rounds, no helper or subagent dispatches, one item per PR. Stop only when every item in docs/roadmap/backlog.md is DONE or claimed by a live thread."}
JSON
