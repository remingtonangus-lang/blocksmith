#!/bin/bash
# One-shot character pipeline: venv with Blender-as-a-module, pinned sources, generation, optional Godot import/shots.
#   bash frontier/tools/characters/run.sh [--out DIR] [--import] [--shots DIR] [generate.py args...]
# Defaults: output frontier/assets/characters_out (gitignored), venv frontier/build/charvenv.
# Env: FRONTIER_CHAR_VENV, FRONTIER_CHAR_SRC, FRONTIER_MPFB / FRONTIER_MH_ASSETS / FRONTIER_MH_EXTRA / FRONTIER_CMU.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FRONTIER="$(cd "$HERE/../.." && pwd)"
VENV="${FRONTIER_CHAR_VENV:-$FRONTIER/build/charvenv}"
OUT="$FRONTIER/assets/characters_out"
DO_IMPORT=0
SHOTS=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --import) DO_IMPORT=1; shift;;
    --shots) SHOTS="$2"; DO_IMPORT=1; shift 2;;
    *) ARGS+=("$1"); shift;;
  esac
done
if [ ! -x "$VENV/bin/python" ]; then
  python3.11 -m venv "$VENV"
  "$VENV/bin/pip" install -q "bpy==5.0.1" "numpy<2" pillow
fi
bash "$HERE/fetch_sources.sh"
"$VENV/bin/python" "$HERE/generate.py" --out "$OUT" "${ARGS[@]+"${ARGS[@]}"}"
if [ "$DO_IMPORT" = 1 ]; then
  (cd "$FRONTIER" && godot --headless --import >/dev/null 2>&1 || true)
fi
if [ -n "$SHOTS" ]; then
  ids=$(python3 -c "import json;c=json.load(open('$OUT/characters.json'))['characters'];print(','.join(x['id'] for x in c[:8]))")
  (cd "$FRONTIER" && xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1280x540 \
     res://scenes/character_shots.tscn -- --out "$SHOTS" --ids "$ids" --mode all)
fi
