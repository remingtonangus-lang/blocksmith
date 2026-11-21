#!/usr/bin/env python3
"""Store covers (v3): each aspect's native render (questcheck --cine docs/store/cover-v3.json --still, drawn at 2x) scaled
to Meta's exact size, a soft dark radial pool behind the title zone, and the SUNDERFALL logo (tools/logo.py) inside the
safe zone: the inner 70% of every cover; on the Hero inside the central 1440x630 box (x 780..2220, y 135..765).
Usage: covers.py RENDER_DIR OUT_DIR"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from logo import logo

# name, W, H, logo cap height (fraction of H), logo centre y (fraction of H), max logo width (px), safe box (x0,y0,x1,y1)
SIZES = {"landscape": ("cover_landscape_2560x1440.png", 2560, 1440, 0.105, 0.70),
         "square": ("cover_square_1440x1440.png", 1440, 1440, 0.094, 0.75),
         "portrait": ("cover_portrait_1008x1440.png", 1008, 1440, 0.058, 0.75),
         "hero": ("hero_cover_3000x900.png", 3000, 900, 0.135, 0.66),
         "mini": ("mini_landscape_1080x360.png", 1080, 360, 0.30, 0.60)}


def safe_box(k, W, H):
    if k == "hero":
        return (780, 135, 2220, 765)
    return (int(W * 0.15), int(H * 0.15), int(W * 0.85), int(H * 0.85))


def compose(k, src):
    name, W, H, capf, yc = SIZES[k]
    img = Image.open(src).convert("RGB").resize((W, H), Image.LANCZOS)
    x0, y0, x1, y1 = safe_box(k, W, H)
    lg = logo(int(H * capf))
    maxw = int((x1 - x0) * 0.94)
    if lg.width > maxw:
        lg = lg.resize((maxw, int(lg.height * maxw / lg.width)), Image.LANCZOS)
    cx, cy = (x0 + x1) // 2, int(H * yc)
    lx, ly = cx - lg.width // 2, cy - lg.height // 2
    ly = max(y0, min(ly, y1 - lg.height))
    # A soft dark pool behind the title (about 35% at its heart), so it reads over cloud, sand or forest.
    pool = Image.new("L", (W, H), 0)
    pd = ImageDraw.Draw(pool)
    rx, ry = lg.width * 0.62, lg.height * 1.05
    pd.ellipse([cx - rx, ly + lg.height / 2 - ry, cx + rx, ly + lg.height / 2 + ry], fill=95)
    pool = pool.filter(ImageFilter.GaussianBlur(lg.height * 0.55))
    img = Image.composite(Image.new("RGB", (W, H), (10, 8, 6)), img, pool)
    img.paste(lg, (lx, ly), lg)
    # Check: the logo's opaque pixels sit inside the safe box.
    bb = lg.split()[3].point(lambda v: 255 if v > 40 else 0).getbbox()
    box = (lx + bb[0], ly + bb[1], lx + bb[2], ly + bb[3])
    ok = box[0] >= x0 and box[1] >= y0 and box[2] <= x1 and box[3] <= y1
    print(f"{name}: logo {box} in safe {x0, y0, x1, y1}: {'OK' if ok else 'OUTSIDE'}")
    return name, img


def main(src, out):
    os.makedirs(out, exist_ok=True)
    for k in SIZES:
        name, img = compose(k, os.path.join(src, f"cov_{k}.png"))
        img.save(os.path.join(out, name), optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
