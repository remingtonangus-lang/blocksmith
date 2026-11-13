#!/usr/bin/env python3
"""Zoom and mark.
  mark.py zoom VIDEO SECONDS x0 y0 x1 y1 OUT.png     full-resolution crop of one exact moment (scaled up if small)
  mark.py box  VIDEO SECONDS OUT.jpg "label" x0 y0 x1 y1 [x0 y0 x1 y1 ...]   full frame with red boxes and a label
Coordinates are full-resolution pixels."""
import sys, subprocess
from PIL import Image, ImageDraw, ImageFont
cmd, vid, t = sys.argv[1], sys.argv[2], float(sys.argv[3])
import tempfile, os; tmp = os.path.join(tempfile.mkdtemp(), 'frame.png')
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.3f}', '-i', vid, '-frames:v', '1', tmp], check=True)
im = Image.open(tmp).convert('RGB')
if cmd == 'zoom':
    x0, y0, x1, y1 = map(int, sys.argv[4:8]); c = im.crop((x0, y0, x1, y1)); s = max(1, 900 // max(c.size))
    c.resize((c.width * s, c.height * s), Image.LANCZOS).save(sys.argv[8])
else:
    out, label, nums = sys.argv[4], sys.argv[5], list(map(int, sys.argv[6:]))
    d = ImageDraw.Draw(im)
    for k in range(0, len(nums), 4): d.rectangle(nums[k:k + 4], outline=(255, 0, 0), width=6)
    try: f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 30)
    except Exception: f = ImageFont.load_default()
    lab = f'{t:.2f}s {label}'; d.rectangle([0, 0, d.textlength(lab, font=f) + 24, 48], fill=(0, 0, 0)); d.text((12, 8), lab, fill=(255, 255, 0), font=f)
    im.save(out, quality=88)
