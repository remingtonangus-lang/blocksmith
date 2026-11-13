#!/usr/bin/env python3
"""The SUNDERFALL title as an RGBA logo: a heavy face, tight tracking, an ivory-to-amber fill with a chiselled top light
and lower shade, a dark outer stroke and a soft dark glow so it reads over white cloud and dark forest alike.
logo(cap_height_px, font) -> PIL RGBA image trimmed to its glow."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

FONTS = {"serif": "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf",
         "slab": "/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf",
         "sans": "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"}
TEXT = "SUNDERFALL"


def logo(cap, face="serif", track=0.06):
    font = ImageFont.truetype(FONTS[face], int(cap * 1.42))
    asc = font.getbbox("S")
    ch = asc[3] - asc[1]
    font = ImageFont.truetype(FONTS[face], int(cap * 1.42 * cap / ch))
    sz = font.size
    adv = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in TEXT]
    tr = int(sz * track)
    pad = int(cap * 0.6)
    W = sum(adv) + tr * (len(TEXT) - 1) + 2 * pad
    H = cap + 2 * pad
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    x, top = pad, pad - font.getbbox("S")[1]
    for c, a in zip(TEXT, adv):
        d.text((x - font.getbbox(c)[0], top), c, font=font, fill=255)
        x += a + tr
    # Fill: ivory at the top to warm amber at the foot.
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = min(1, max(0, (y - pad) / cap))
        a, b = (255, 248, 228), (226, 160, 62)
        grad.putpixel((0, y), tuple(int(a[i] + (b[i] - a[i]) * t ** 1.2) for i in range(3)))
    fill = grad.resize((W, H))
    # Chisel: light on edges facing up, shade on edges facing down.
    k = max(2, cap // 22)
    up = ImageChops.subtract(m, ImageChops.offset(m, 0, k)).filter(ImageFilter.GaussianBlur(k * 0.6))
    dn = ImageChops.subtract(m, ImageChops.offset(m, 0, -k)).filter(ImageFilter.GaussianBlur(k * 0.6))
    fill = Image.composite(Image.new("RGB", (W, H), (255, 255, 250)), fill, up.point(lambda v: int(v * 0.85)))
    fill = Image.composite(Image.new("RGB", (W, H), (120, 62, 18)), fill, dn.point(lambda v: int(v * 0.75)))
    # Stroke and glow.
    sw = max(2, int(cap * 0.07))
    stroke = m.filter(ImageFilter.MaxFilter(2 * (sw // 2) + 1))
    for _ in range(max(0, sw // 2 - 1)):
        stroke = stroke.filter(ImageFilter.MaxFilter(3))
    glow = stroke.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(cap * 0.22))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out = Image.alpha_composite(out, Image.merge("RGBA", (*Image.new("RGB", (W, H), (8, 6, 4)).split(), glow.point(lambda v: int(v * 0.8)))))
    out = Image.alpha_composite(out, Image.merge("RGBA", (*Image.new("RGB", (W, H), (22, 14, 8)).split(), stroke)))
    out = Image.alpha_composite(out, Image.merge("RGBA", (*fill.split(), m)))
    return out.crop(out.getbbox())


if __name__ == "__main__":
    bg = Image.new("RGB", (1600, 900))
    for i, f in enumerate(["serif", "slab", "sans"]):
        for j, col in enumerate([(235, 240, 245), (40, 70, 30)]):
            tile = Image.new("RGB", (800, 300), col)
            l = logo(110, f)
            l = l.resize((min(780, l.width), int(l.height * min(780, l.width) / l.width)))
            tile.paste(l, ((800 - l.width) // 2, (300 - l.height) // 2), l)
            bg.paste(tile, (j * 800, i * 300))
    bg.save(sys.argv[1])
