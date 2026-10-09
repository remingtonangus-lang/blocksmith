#!/bin/bash
# Golden shots (docs/STORE_QUALITY.md, objective 4): the fixed camera list rendered through the snapshot harness into a
# dated folder, plus a frame-diff flicker check on the world shots. Run after ./build.sh; local only (no CI job).
#   tools/golden.sh                 all shots -> shots/golden/<date>_<sha>/  (+ flicker.txt, index.txt)
#   tools/golden.sh OUT spawn dusk  only the named shots
#   GOLDEN_FLICKER=0 tools/golden.sh   skip the flicker pass
# Review: compare each PNG with the previous dated folder and docs/art/style-options/3-stylised-realism.png and
# score 1-5 with a written reason in docs/status/scorecard.md. The Quest copies come from questcheck --golden (quest.yml).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
OUT="${1:-shots/golden/$(date +%Y-%m-%d)_$(git rev-parse --short HEAD)}"; shift || true
ONLY=" $* "
mkdir -p "$OUT"
W="--w 1280 --h 800"
# name | snapshot flags (one shot each). Keep in step with STORE_QUALITY.md's list.
SHOTS=(
"spawn|--seed 12345 --yaw 30 --pitch -12 --time 0.2"
"forest|--seed 12345 --find forest --yaw 30 --pitch -8 --time 0.24 --up 12 --rd 10"
"village|--seed 12345 --structure village --frame --time 0.27 --rd 10"
"cave_torch|--seed 12345 --find plains --cavey 10 --yaw 40 --pitch -10 --time 0.75 --torches --rd 6"
"ore_closeup|--seed 12345 --find plains --cavey -40 --yaw 90 --pitch -20 --time 0.3 --rd 4 --torches"
"horse|--seed 12345 --find plains --yaw 30 --pitch -12 --time 0.3 --up 1 --spawn horse --saddled --stage"
"capital_city|--seed 12345 --structure capital_city --frame --time 0.27 --rd 16"
"base_battle|--seed 12345 --find plains --time 0.3 --rd 10 --ship battle"
"frigate|--seed 12345 --find plains --time 0.3 --rd 10 --ship frigate:side"
"the_deep|--seed 12345 --dim deep --hell --x 60 --z 60 --yaw 30 --pitch -10 --up 8 --rd 8"
"ash_vault|--seed 12345 --dim deep --x -80 --z 0 --yaw 270 --pitch 0 --up 14 --rd 8"
"inventory|--seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu inventory --slot 3"
"crafting|--seed 12345 --yaw 30 --pitch -12 --time 0.2 --menu crafting"
"options|--seed 12345 --menu options"
"dusk|--seed 12345 --find plains --yaw 270 --pitch -4 --time 0.49 --up 2 --rd 12"
"night|--seed 12345 --find plains --yaw 30 --pitch 10 --time 0.75 --up 2 --rd 12"
"rain|--seed 12345 --find plains --yaw 30 --pitch -5 --time 0.3 --up 1 --weather rain"
)
# World shots that get the flicker pass (menus and scripted scenes are skipped).
FLICKER="spawn forest cave_torch the_deep ash_vault dusk night"
: > "$OUT/index.txt"
for s in "${SHOTS[@]}"; do
  name="${s%%|*}"; flags="${s#*|}"
  [ "$ONLY" != "  " ] && [[ "$ONLY" != *" $name "* ]] && continue
  t0=$(date +%s)
  # shellcheck disable=SC2086
  if "$BIN" --snapshot "$OUT/$name.png" $flags $W > "$OUT/$name.log" 2>&1; then st=ok; else st=FAIL; fi
  echo "$name $st $(( $(date +%s) - t0 ))s  $flags" | tee -a "$OUT/index.txt"
  if [ "${GOLDEN_FLICKER:-1}" = 1 ] && [ $st = ok ] && [[ " $FLICKER " == *" $name "* ]]; then
    # The same view nudged by 0.02 degrees: real motion moves edges by under a pixel; z-fighting and unstable
    # shading flip whole flat areas (tools/flicker.py tells the two apart).
    yaw=$(echo "$flags" | sed -n 's/.*--yaw \([-0-9.]*\).*/\1/p')
    nudged=$(echo "$flags" | sed "s/--yaw $yaw/--yaw $(python3 -c "print(${yaw:-0} + 0.02)")/")
    [ -z "$yaw" ] && nudged="$flags --yaw 0.02"
    # shellcheck disable=SC2086
    "$BIN" --snapshot "$OUT/.$name.b.png" $nudged $W > /dev/null 2>&1 && \
      python3 tools/flicker.py "$OUT/$name.png" "$OUT/.$name.b.png" --name "$name" >> "$OUT/flicker.txt"
    rm -f "$OUT/.$name.b.png"
  fi
done
[ -f "$OUT/flicker.txt" ] && cat "$OUT/flicker.txt"
echo "golden: $(grep -c ' ok ' "$OUT/index.txt") ok, $(grep -c ' FAIL ' "$OUT/index.txt") failed -> $OUT"
