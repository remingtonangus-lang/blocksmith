#!/bin/bash
# SessionStart (Claude Code on the web): prints Remington's current priorities from STATUS.md into the session's
# context and installs the Python packages the image oracles and texture tools use. Idempotent.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 -c "import PIL, numpy" 2>/dev/null || pip install -q pillow numpy >/dev/null 2>&1 || true
echo "Blocksmith priorities (STATUS.md 'Playtest feedback'):"
awk '/^## Playtest feedback/{p=1} p&&/^## /&&!/^## Playtest feedback/{exit} p' STATUS.md | head -40
if [ -f BUGS.md ]; then echo; echo "Open bug classes (BUGS.md):"; grep -E "^\| .*\| open" BUGS.md | head -15 || true; fi
echo
echo "Loop: .claude/skills/blocksmith-qa/SKILL.md. CI is the compile/test loop (ci-snaps-claude-blocksmith-playtest)."
