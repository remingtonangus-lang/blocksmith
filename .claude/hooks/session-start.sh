#!/bin/bash
# context and installs the Python packages the image oracles and texture tools use. Idempotent.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 -c "import PIL, numpy" 2>/dev/null || pip install -q pillow numpy >/dev/null 2>&1 || true
echo "Work queue: the Open section of docs/roadmap/backlog.md (rules at its top). Medium effort, one item at a time."
