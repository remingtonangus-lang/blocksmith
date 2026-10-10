#!/bin/bash
# Smooth terrain prototype (docs/proposals/smooth-terrain.md): the same 6 places rendered cubic and smooth,
# plus a side-by-side sheet. Usage: tools/smooth_shots.sh [OUT]   (default docs/proposals/smooth-terrain)
set -u
cd "$(dirname "$0")/.."
BIN=build/Blocksmith.app/Contents/MacOS/Blocksmith
OUT=${1:-docs/proposals/smooth-terrain}
mkdir -p "$OUT/raw"
SHOTS=(
"spawn|--seed 12345 --yaw 30 --pitch -12 --time 0.2"
"hills|--seed 12345 --find windswept_hills --yaw 60 --pitch -15 --time 0.27 --up 6 --rd 10"
"peaks|--seed 12345 --find stony_peaks --yaw 200 --pitch -10 --time 0.3 --up 4 --rd 10"
"beach|--seed 12345 --find beach --yaw 90 --pitch -18 --time 0.27 --up 3 --rd 8"
"village|--seed 12345 --structure village --frame --time 0.27 --rd 10"
"cave_torch|--seed 12345 --find plains --cavey 10 --yaw 40 --pitch -10 --time 0.75 --torches --rd 6"
)
for s in "${SHOTS[@]}"; do
  name=${s%%|*}; flags=${s#*|}
  for m in cubic smooth; do
    "$BIN" --snapshot "$OUT/raw/${name}_$m.png" $flags --w 960 --h 600 --$m > "$OUT/raw/${name}_$m.log" 2>&1 || echo "FAIL $name $m"
  done
  echo "$name: $(grep -o 'mesh(1 section) [0-9.]* ms' "$OUT/raw/${name}_cubic.log") -> $(grep -o 'mesh(1 section) [0-9.]* ms' "$OUT/raw/${name}_smooth.log")"
done
python3 - "$OUT" <<'EOF'
import sys, os
from PIL import Image, ImageDraw
out = sys.argv[1]
names = ["spawn", "hills", "peaks", "beach", "village", "cave_torch"]
W, H = 640, 400
sheet = Image.new("RGB", (W * 2 + 12, (H + 8) * len(names)), (20, 20, 20))
for r, n in enumerate(names):
    for c, m in enumerate(["cubic", "smooth"]):
        p = f"{out}/raw/{n}_{m}.png"
        if not os.path.exists(p): continue
        im = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS)
        ImageDraw.Draw(im).text((8, 6), f"{n} - {m}", fill=(255, 255, 255))
        sheet.paste(im, (c * (W + 12), r * (H + 8)))
    pair = Image.new("RGB", (W * 2 + 12, H), (20, 20, 20))
    for c, m in enumerate(["cubic", "smooth"]):
        p = f"{out}/raw/{n}_{m}.png"
        if os.path.exists(p): pair.paste(Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS), (c * (W + 12), 0))
    pair.save(f"{out}/{n}.jpg", quality=82)
sheet.save(f"{out}/sheet.jpg", quality=78)
EOF
echo "sheet: $OUT/sheet.jpg"
