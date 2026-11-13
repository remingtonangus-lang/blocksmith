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
# His reported spots (seed, x y z as the notes give them: --at takes the internal y, the note's + 64; yaw, pitch), then biomes on three seeds at several pitches.
SPOTS=(
  "7653607216494784574 -5571.9 77.4 2813.9 2 -58"
  "4256271160485884755 -3391.2 65.8 -2800.9 198 -56"
  "1091709452045888406 -4452.0 65.0 4603.8 136 -20"
  "1091709452045888406 -4425.7 113.0 -801.5 125 -37"
  "7653607216494784574 -9671.0 82.6 5294.6 229 -33"
  "7653607216494784574 -22251.7 96.4 15846.4 0 -30"
)
BIOMES=(plains forest jungle taiga desert savanna swamp beach river meadow badlands snowy_plains dark_forest birch_forest stony_peaks)
SEEDS=(7653607216494784574 1091709452045888406 4256271160485884755)
PITCHES=(-20 -35 -55 -80)
[ "$QUICK" = --quick ] && { BIOMES=(plains forest jungle); SEEDS=(7653607216494784574); PITCHES=(-35 -60); }
RD=6
run() {   # name, then questcheck's view arguments
  local name="$1"; shift
  local line
  line=$(timeout 300 "$QC" --view "$OUT/$name.png" --field --questlod --rd $RD --w 480 --h 480 --time 0.25 --voidcount "$@" 2>&1 | grep '^voidcount:' | head -1)
  [ -n "$line" ] && echo "$name $line" >> "$OUT/summary.txt" || echo "$name voidcount: none (no frame)" >> "$OUT/summary.txt"
  rm -f "$OUT/$name.png"
}
if [ "${VOIDSWEEP_CORNERS:-}" != only ]; then
i=0
for s in "${SPOTS[@]}"; do
  set -- $s
  for dyaw in 0 90 180 270; do
    run "spot$i-y$dyaw" --seed "$1" --at "$2,$(awk "BEGIN{print $3+64}"),$4" --look "$(awk "BEGIN{print -($5)+$dyaw}"),$6"
  done
  i=$((i+1))
done
for seed in "${SEEDS[@]}"; do for b in "${BIOMES[@]}"; do for p in "${PITCHES[@]}"; do for yaw in 0 120 240; do
  run "$b-$seed-p${p#-}-y$yaw" --seed "$seed" --at "0,100,0" --find "$b" --up 2 --look "$yaw,$p"
done; done; done; done
fi
# Nov 12 (FAILURES 4 again: sky triangles in the grass where four chunks meet, 3903.9 65.9 1025.2 and 3919 64.5 1041.4 on
# seed 632461258612199693): half-block ground (the ground round a built or dug block) beside whole-cell ground at a chunk
# corner. The eye stands over a corner of four chunks (--corner) and chunks round it are given half-block samples
# (--finechunks, offsets from the eye's chunk), in every layout of half-block and whole-cell sections round the corner
# (one of the four whole-cell, two side by side, one alone, two across), each turned four ways, looking down and along.
#   VOIDSWEEP_CORNERS=only: just these views.
LAYOUTS=("-1,1;1,-1" "-2,0" "-2,-2" "-2,-2;1,1" "-2,0;0,-2" "-2,1" "-3,0;-2,0")
CBIOMES=(plains forest desert taiga savanna meadow stony_peaks)
CSEEDS=(632461258612199693 7653607216494784574)
[ "$QUICK" = --quick ] && { CBIOMES=(plains forest); CSEEDS=(632461258612199693); }
rot() {   # a layout turned N quarter turns about the corner: chunk (dx, dz) -> (-dz - 1, dx)
  local l="$1" n="$2" out="" p
  for p in ${l//;/ }; do
    local dx=${p%,*} dz=${p#*,} i t
    for ((i = 0; i < n; i++)); do t=$dx; dx=$((-dz - 1)); dz=$t; done
    out="$out${out:+;}$dx,$dz"
  done
  echo "$out"
}
# (view 5, not 4: from a hilltop the top rows of a down view reached the loaded land's edge at view 4 and counted the
# floor past it as a hole, 67 pixels in seven forest views with or without half-block chunks.)
RD=5
[ "${VOIDSWEEP_CORNERS:-}" = only ] && : > "$OUT/summary.txt"
for seed in "${CSEEDS[@]}"; do for b in "${CBIOMES[@]}"; do li=0; for l in "${LAYOUTS[@]}"; do for n in 0 1 2 3; do
  fc=$(rot "$l" $n)
  run "corner-$b-$seed-l$li-r$n-down" --seed "$seed" --at "0,100,0" --find "$b" --corner --finechunks "$fc" --up 2.5 --look "$((n * 90 + 30)),-78" &
  run "corner-$b-$seed-l$li-r$n-along" --seed "$seed" --at "0,100,0" --find "$b" --corner --finechunks "$fc" --up 1.7 --look "$((n * 90 + 45)),-32" &
  wait
done; li=$((li + 1)); done; done; done
RD=6
# A corner view looking down sees ground only: any pixel of the fog floor under the ground (the count after "backstop")
# is a hole in it. (The plain count misses these: under a hole lies the floor, not the sky.)
holes() { awk '{ bad = ($0 !~ /: 0 of/); if ($1 ~ /^corner-.*-down$/ && match($0, /backstop [0-9]+/)) { if (substr($0, RSTART + 9, RLENGTH - 9) + 0 > 0) bad = 1 } if (bad) print }' "$OUT/summary.txt"; }
echo "== views with gaps, worst first"
holes | sort -k3 -rn | head -60
echo "== $(grep -c . "$OUT/summary.txt") views, $(( $(grep -c . "$OUT/summary.txt") - $(holes | grep -c .) )) clean"
