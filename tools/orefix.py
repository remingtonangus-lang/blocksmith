#!/usr/bin/env python3
"""Post-fixes on imported ore layers (run after tools/sheetslice.py; done audit 25b6).

  * gold: the sheet's gold specks were 1-2 texels at 16 px and read as copper at 7 m. Each speck grows into a
    nugget (dilated mask, rounded) painted in a bright warm gold ramp shaded by the stone's own detail, with a
    dark rim, so gold_ore / deepslate_gold_ore keep a clear yellow read when mipmapped.
  * wrap seams: nether_quartz_ore and deepslate_diamond_ore had a visible jump across the tile edge. The outer
    band is blended with the wrapped neighbour texels (left<->right, top<->bottom) so the edge pixels agree.

  python3 tools/orefix.py [--dir Resources/Textures]   (prints the seam ratio before/after)
"""
import argparse, os, sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from teximport import seam_ratio   # noqa: E402

GOLD = ('gold_ore', 'deepslate_gold_ore')
SEAMS = ('nether_quartz_ore', 'deepslate_diamond_ore')


def load(p):
    return np.asarray(Image.open(p).convert('RGBA'), dtype=np.float32) / 255


def save(a, p):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)


def gold_mask(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return ((r - b) > 0.18) & (r > 0.35) & (g > b + 0.08)


def wrap_filter(mask_img, flt, n):
    """Apply a PIL filter on a 3x3 tiled copy so nuggets wrap across the edges."""
    big = Image.new('L', (n * 3, n * 3))
    for y in range(3):
        for x in range(3):
            big.paste(mask_img, (x * n, y * n))
    return big.filter(flt).crop((n, n, 2 * n, 2 * n))


def fix_gold(path):
    a = load(path)
    n = a.shape[0]
    rgb = a[..., :3]
    m = Image.fromarray((gold_mask(rgb) * 255).astype(np.uint8))
    # grow each speck to a nugget about 2-3 texels across at 16 px (8 px per texel at 128 px)
    # thin vein lines drop out (erode), the round specks stay and grow
    specks = wrap_filter(m, ImageFilter.MinFilter(3), n)
    k = max(3, n // 32 + 5)
    grown = wrap_filter(specks, ImageFilter.MaxFilter(k), n)
    grown = wrap_filter(grown, ImageFilter.GaussianBlur(n / 128 * 1.2), n)
    core = np.asarray(grown, dtype=np.float32) / 255
    rim = np.asarray(wrap_filter(grown, ImageFilter.MaxFilter(3), n), dtype=np.float32) / 255
    L = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    rel = np.clip(L / max(float(L.mean()), 1e-3), 0.6, 1.5)
    # warm gold ramp: deep amber in the shade, pale yellow highlights
    lo, hi = np.array([0.72, 0.48, 0.08]), np.array([1.0, 0.90, 0.42])
    t = np.clip((rel - 0.6) / 0.9, 0, 1)[..., None]
    goldc = lo * (1 - t) + hi * t
    # a small highlight on the upper-left of each nugget
    hl = np.clip(core - np.roll(np.roll(core, 2, 0), 2, 1), 0, 1)[..., None]
    goldc = np.clip(goldc + hl * 0.25, 0, 1)
    edge = np.clip(rim - core, 0, 1)[..., None]
    out = rgb * (1 - edge * 0.45)                       # dark rim seats the nugget in the rock
    c = np.clip(core * 1.4, 0, 1)[..., None]
    out = out * (1 - c) + goldc * c
    a[..., :3] = out
    save(a, path)


def fix_seam(path):
    a = load(path)
    n = a.shape[0]
    before = seam_ratio(a)
    band = max(2, n // 16)
    out = a.copy()
    for i in range(band):
        w = 0.5 * (1 - i / band) ** 1.5             # 0.5 at the edge: both sides meet halfway
        out[:, i] = a[:, i] * (1 - w) + a[:, n - 1 - i] * w
        out[:, n - 1 - i] = a[:, n - 1 - i] * (1 - w) + a[:, i] * w
    b = out.copy()
    for i in range(band):
        w = 0.5 * (1 - i / band) ** 1.5
        out[i] = b[i] * (1 - w) + b[n - 1 - i] * w
        out[n - 1 - i] = b[n - 1 - i] * (1 - w) + b[i] * w
    save(out, path)
    return before, seam_ratio(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default=os.path.join(ROOT, 'Resources/Textures'))
    a = ap.parse_args()
    for g in GOLD:
        fix_gold(os.path.join(a.dir, g + '.png'))
        print(g, 'nuggets')
    for s in SEAMS:
        b, c = fix_seam(os.path.join(a.dir, s + '.png'))
        print(s, 'seam ratio %.2f -> %.2f' % (b, c))


if __name__ == '__main__':
    main()
