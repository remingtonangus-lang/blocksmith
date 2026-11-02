#!/bin/bash
# FAILURES 4: the see-through void sweep. Renders many headset-style views (field world, the Quest's LOD rings) with the
# frame cleared to magenta and no sky (QUEST_VOIDPROBE=1 QUEST_SKIP=sky), and counts the magenta pixels where the view
# looks more than 12 degrees down (questcheck --view ... --voidcount): every gap the sky shows through. Marked shots of
# the bad views land in OUT/ as NAME-void.png; the summary lists them worst first.
#   tools/voidsweep.sh QUESTCHECK [OUT] [--quick]
# Run from the repo (Resources/texpack.bin). Never commit the PNGs.
set -uo pipefail
QC="${1:?questcheck binary}"; OUT="${2:-/tmp/voidsweep}"; QUICK="${3:-}"
mkdir -p "$OUT"; : > "$OUT/summary.txt"
export QUEST_VOIDPROBE=1 QUEST_SKIP=sky
# His reported spots (seed, x y z as the notes give them, yaw, pitch), then biomes on three seeds at several pitches.
SPOTS=(
  "7653607216494784574 -5571.9 77.4 2813.9 2 -58"
  "4256271160485884755 -3391.2 65.8 -2800.9 198 -56"
  "1091709452045888406 -4452.0 65.0 4603.8 136 -20"
  "1091709452045888406 -4425.7 113.0 -801.5 125 -37"
  "7653607216494784574 -9671.0 82.6 5294.6 229 -33"
  "7653607216494784574 -22251.7 160.4 15846.4 0 -30"
)
BIOMES=(plains forest jungle taiga desert savanna swamp beach river meadow badlands snowy_plains dark_forest birch_forest stony_peaks)
SEEDS=(7653607216494784574 1091709452045888406 4256271160485884755)
PITCHES=(-20 -35 -55 -80)
[ "$QUICK" = --quick ] && { BIOMES=(plains forest jungle); SEEDS=(7653607216494784574); PITCHES=(-35 -60); }
run() {   # name, then questcheck's view arguments
  local name="$1"; shift
  local line
  line=$(timeout 300 "$QC" --view "$OUT/$name.png" --field --questlod --rd 6 --w 480 --h 480 --time 0.25 --voidcount "$@" 2>&1 | grep '^voidcount:' | head -1)
  [ -n "$line" ] && echo "$name $line" >> "$OUT/summary.txt" || echo "$name voidcount: none (no frame)" >> "$OUT/summary.txt"
  rm -f "$OUT/$name.png"
}
i=0
for s in "${SPOTS[@]}"; do
  set -- $s
  for dyaw in 0 90 180 270; do
    run "spot$i-y$dyaw" --seed "$1" --at "$2,$(awk "BEGIN{print $3-64}"),$4" --look "$(awk "BEGIN{print -($5)+$dyaw}"),$6"
  done
  i=$((i+1))
done
for seed in "${SEEDS[@]}"; do for b in "${BIOMES[@]}"; do for p in "${PITCHES[@]}"; do for yaw in 0 120 240; do
  run "$b-$seed-p${p#-}-y$yaw" --seed "$seed" --at "0,100,0" --find "$b" --up 2 --look "$yaw,$p"
done; done; done; done
echo "== views with gaps, worst first"
grep -v ": 0 of" "$OUT/summary.txt" | sort -t: -k2 -rn | awk '{print}' | sort -k3 -rn | head -60
echo "== $(grep -c . "$OUT/summary.txt") views, $(grep -c ': 0 of' "$OUT/summary.txt") clean"
