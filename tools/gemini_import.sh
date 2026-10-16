#!/bin/bash
# Imports the Gemini textures uploaded to assets/gemini/<name>.png (list and modes: docs/texture_requests.md) through
# tools/teximport.py. Default output: build/texgen/out (a trial set for side-by-side checks with --texdir); pass
# Resources/Textures to adopt them.
#   tools/gemini_import.sh [OUT_DIR]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/texgen/out}"
mkdir -p "$OUT"
grep -E '^\| [0-9]+ \| `' docs/texture_requests.md | while IFS='|' read -r _ num name face mode rest; do
  name=$(echo "$name" | tr -d ' `'); mode=$(echo "$mode" | sed 's/^ *//; s/ *$//')
  case "$mode" in "cutout + tint") m=cutout_tint;; tint|overlay|cutout|plain) m="$mode";; *) m=plain;; esac
  src="assets/gemini/$name.png"
  [ -f "$src" ] || continue
  echo "import $name ($m)"
  python3 tools/teximport.py "$src" "$name" --out "$OUT" --mode "$m"
done
