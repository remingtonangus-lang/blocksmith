#!/usr/bin/env python3
"""Split two-layer item icons (base + runtime-tinted overlay) out of single Gemini-painted icons.

The icon sheet paints the part the game tints (potion liquid, tipped arrow head, spawn egg shell, harness band) in
shaded pure green. Run after tools/iconslice.py has written the painted icon to Resources/Textures/<base>.png:
  * <overlay>.png: the green pixels as white-ish greyscale (shading kept, mean 0.9) so overlayColor tints it;
  * <base>.png: the same icon with those pixels cut out (the overlay is drawn on top in the same place).
Each bottle form has its own liquid layer (Potions.swift), so the three bottles can have different shapes.

  python3 tools/iconsplit.py [--dir Resources/Textures]
"""
import argparse, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAIRS = [('item_potion_bottle', 'item_potion_liquid'), ('item_splash_bottle', 'item_splash_liquid'),
         ('item_lingering_bottle', 'item_lingering_liquid'),
         ('item_tipped_arrow', 'item_tipped_arrow_head'), ('item_spawn_egg', 'item_spawn_egg_shell'),
         ('item_harness', 'item_harness_band')]


def green_mask(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return np.clip(((g - np.maximum(r, b)) - 0.08) * 4, 0, 1)  # muted greens (egg spots) count too * (a[..., 3] > 0.5)


def split(d, base, overlay):
    p = os.path.join(d, base + '.png')
    a = np.asarray(Image.open(p).convert('RGBA'), dtype=np.float32) / 255
    m = green_mask(a)
    hard = (m > 0.5).astype(np.float32)
    if hard.sum() < 4:
        # Already split (re-runs must not blank the overlay) or no green part painted.
        print(base, 'no green part found, left as is')
        return
    out = a.copy()
    out[..., 3] = a[..., 3] * (1 - hard)
    # De-spill: the green edge pixels left in the base drop to neutral so no green fringe rings the overlay.
    out[..., 1] = np.minimum(out[..., 1], np.maximum(out[..., 0], out[..., 2]) + 0.02)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(p)
    if overlay:  # written after the base: a newer overlay marks the pair as split
        L = a[..., 1] * hard
        mean = L.sum() / hard.sum()
        g = np.clip(L / max(mean, 1e-3) * 0.9, 0, 1)
        ov = np.stack([g, g, g, hard], -1)
        Image.fromarray((ov * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, overlay + '.png'))
    print(base, '->', overlay or '(cut out)', int(hard.sum()), 'px')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default=os.path.join(ROOT, 'Resources/Textures'))
    ap.add_argument('--only', help='only bases containing this substring')
    a = ap.parse_args()
    for b, o in PAIRS:
        if a.only and a.only not in b:
            continue
        bp, op = os.path.join(a.dir, b + '.png'), os.path.join(a.dir, o + '.png')
        # An overlay newer than its base means the base is already cut: splitting again would blank the overlay.
        if os.path.exists(bp) and not (os.path.exists(op) and os.path.getmtime(op) >= os.path.getmtime(bp)):
            split(a.dir, b, o)


if __name__ == '__main__':
    main()
