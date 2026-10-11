#!/usr/bin/env python3
"""Lays the Tidebreaker shot sequence (questcheck --render with BLOCKSMITH_SHOT_SEQUENCE=1: maingun_seq_NN_<when>.png,
stereo side by side) out as one contact sheet of left-eye frames, labelled, in order.

    tools/shot_sheet.py build/quest-out docs/qa/tidebreaker_sequence.jpg
"""
import glob, os, sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(src, "maingun_seq_*.png")))
if not files:
    sys.exit("no maingun_seq_*.png in " + src)
cols = 4
tiles = []
for f in files:
    im = Image.open(f).convert("RGB")
    left = im.crop((0, 0, im.width // 2, im.height))
    left.thumbnail((480, 480))
    label = os.path.basename(f)[len("maingun_seq_"):-4].split("_", 1)[-1]
    tiles.append((left, label))
w, h = tiles[0][0].size
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 22)), (16, 16, 18))
d = ImageDraw.Draw(sheet)
for i, (t, label) in enumerate(tiles):
    x, y = (i % cols) * w, (i // cols) * (h + 22)
    sheet.paste(t, (x, y + 22))
    d.text((x + 6, y + 5), f"{i + 1}. {label}", fill=(230, 230, 230))
sheet.save(out, quality=85) if out.lower().endswith((".jpg", ".jpeg")) else sheet.save(out)
print(f"{out}: {len(tiles)} frames, {sheet.width}x{sheet.height}")
