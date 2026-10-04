#!/bin/bash
# SessionStart (Claude Code on the web): prints Remington's current priorities from STATUS.md into the session's
# context and installs the Python packages the image oracles and texture tools use. Idempotent.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 -c "import PIL, numpy" 2>/dev/null || pip install -q pillow numpy >/dev/null 2>&1 || true
if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "claude/frontier-game" ]; then
  bash frontier/tools/session_setup.sh >/dev/null 2>&1 || true
  echo "Frontier session (branch claude/frontier-game). Ranked gap list from docs/status/frontier.md:"
  awk '/^## Ranked gaps/{p=1} p&&/^## /&&!/^## Ranked gaps/{exit} p' docs/status/frontier.md | head -40
  echo; echo "Bar: frontier/QUALITY_BAR.md. Tools: godot 4.7.1 at /usr/local/bin/godot (frontier/tools/session_setup.sh)."
  exit 0
fi
echo "Blocksmith priorities (STATUS.md 'Playtest feedback'):"
awk '/^## Playtest feedback/{p=1} p&&/^## /&&!/^## Playtest feedback/{exit} p' STATUS.md | head -40
if [ -f BUGS.md ]; then echo; echo "Open bug classes (BUGS.md):"; grep -E "^\| .*\| open" BUGS.md | head -15 || true; fi
echo
echo "Loop: .claude/skills/blocksmith-qa/SKILL.md. CI is the compile/test loop (ci-snaps-claude-blocksmith-playtest)."
