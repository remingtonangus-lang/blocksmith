#!/usr/bin/env python3
"""Store covers: each aspect's native render (questcheck --cine docs/store/cover-v2.json --still, drawn at 2x) scaled to
Meta's exact size, a soft dark band at the foot and the title "SUNDERFALL" in the trailer end card's serif, centred in the
lower safe area (nothing in the corners). Usage: covers.py RENDER_DIR OUT_DIR"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SIZES = {"landscape": ("cover_landscape_2560x1440.png", 2560, 1440, 0.115, 0.80),
         "square": ("cover_square_1440x1440.png", 1440, 1440, 0.095, 0.82),
         "portrait": ("cover_portrait_1008x1440.png", 1008, 1440, 0.072, 0.83),
         "hero": ("hero_cover_3000x900.png", 3000, 900, 0.17, 0.80),
         "mini": ("mini_landscape_1080x360.png", 1080, 360, 0.17, 0.80)}
TITLE = "SUNDERFALL"


def title(img, frac, ycen):
    W, H = img.size
    size = int(H * frac)
    font = ImageFont.truetype(FONT, size)
    track = int(size * 0.18)                       # letter spacing, as the end card's spaced title
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in TITLE]
    tw = sum(widths) + track * (len(TITLE) - 1)
    if tw > W * 0.72:                              # inside the central safe area
        return title(img, frac * W * 0.72 / tw, ycen)
    x0, y0 = (W - tw) // 2, int(H * ycen - size / 2)
    # A soft dark band behind the lower third, then a shadow, then the ivory letters.
    band = Image.new("L", (W, H), 0)
    bd = ImageDraw.Draw(band)
    top = int(H * ycen - size * 1.6)
    for y in range(top, H):
        bd.line([(0, y), (W, y)], fill=int(150 * min(1, (y - top) / (size * 1.2))))
    img = Image.composite(Image.new("RGB", (W, H), (12, 14, 18)), img, band.point(lambda v: v * 0.75))
    sh = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(sh)
    x = x0
    for c, w in zip(TITLE, widths):
        sd.text((x - font.getbbox(c)[0], y0 - font.getbbox(TITLE)[1]), c, font=font, fill=255)
        x += w + track
    sh = sh.filter(ImageFilter.GaussianBlur(max(2, size // 14)))
    img = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), img, sh.point(lambda v: int(v * 0.8)))
    d = ImageDraw.Draw(img)
    x = x0
    for c, w in zip(TITLE, widths):
        d.text((x - font.getbbox(c)[0], y0 - font.getbbox(TITLE)[1]), c, font=font, fill=(255, 253, 247))
        x += w + track
    return img


def main(src, out):
    os.makedirs(out, exist_ok=True)
    for k, (name, W, H, frac, ycen) in SIZES.items():
        img = Image.open(os.path.join(src, f"cov_{k}.png")).convert("RGB").resize((W, H), Image.LANCZOS)
        img = title(img, frac, ycen)
        img.save(os.path.join(out, name), optimize=True)
        print(name, img.size, img.mode)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
