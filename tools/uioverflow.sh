#!/bin/bash
# Renders every menu screen and the HUD at desktop and TV sizes with --uilog, then runs tools/uioverflow.py.
#   tools/uioverflow.sh   -> snaps/ui/*.json, snaps/ui/*.png, snaps/ui_overflow.md       (local tool, no CI job)
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
mkdir -p snaps/ui
MENUS="hud survival inventory crafting furnace brewing enchant anvil trade creative craftbook recipes invsearch craftsearch commands pause options advancements book loom title create death credits"
for size in "1280 800" "1920 1080 --couch --safe 5 --pad"; do
  set -- $size; tag="${1}x${2}"
  for m in $MENUS; do
    case $m in
      hud) extra="" ;; survival) extra="--survival 14" ;; *) extra="--menu $m" ;;
    esac
    # shellcheck disable=SC2086
    "$BIN" --snapshot "snaps/ui/${m}_$tag.png" --seed 12345 --yaw 30 --pitch -12 --time 0.2 --rd 2 --w $1 --h $2 ${@:3} $extra --uilog "snaps/ui/${m}_$tag.json" > /dev/null 2>&1 || echo "uioverflow: $m $tag failed"
  done
done
python3 tools/uioverflow.py snaps/ui/*.json --out snaps/ui_overflow.md
