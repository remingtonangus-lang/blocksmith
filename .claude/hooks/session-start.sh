#!/bin/bash
# Cloud sessions: installs the Python packages the image tools use, and points at the work. Idempotent.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 -c "import PIL, numpy" 2>/dev/null || pip install -q pillow numpy >/dev/null 2>&1 || true
echo "The rule and the work: top of docs/roadmap/backlog.md."
