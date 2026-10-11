#!/usr/bin/env python3
"""Torches and lanterns in the imported art style (run after tools/texderive.py).

These layers are tiny UV islands on model boxes (a torch is a 2x10 texel stick), so a painted sheet cell would not
survive the crop. Instead they are built at 128 px from imported art at the exact texel layout of the procedural
painters (Textures.swift, TexturesCircuit.swift, TexturesBuilding.swift, BlocksCopper.swift):
  * the stick: stripped oak's painted grain in torch-wood brown, lit from the left, dark 1-px edges;
  * the flame/head: a soft painted gradient (core -> glow) with glowstone's brush detail;
  * lanterns: a dark iron frame (or the copper stage's own metal) with glowstone-detailed glass in the flame colour.
A layer that already has its own imported (non-derived) PNG is never overwritten.

  python3 tools/lightderive.py [--dir Resources/Textures]
"""
import argparse, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N, S = 128, 8          # 128 px layer, 8 px per texel
WOOD = np.array([0x6B, 0x4F, 0x2C]) / 255
# name: (core, glow) flame colours
FLAMES = {'torch': (0xFFF6C8, 0xFFC43A), 'soul_torch': (0xD8FFFF, 0x3AD8E8), 'copper_torch': (0xE0FFC8, 0x6CE04A)}


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255]) / 255


def load(d, n):
    return np.asarray(Image.open(os.path.join(d, n + '.png')).convert('RGBA'), dtype=np.float32) / 255


def detail(a):
    L = a[..., :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return L / max(float(L.mean()), 1e-3)


class Painter:
    def __init__(self, d):
        self.d = d
        self.grain = np.clip(detail(load(d, 'stripped_oak_log')), 0.75, 1.3)
        self.glowd = np.clip(detail(load(d, 'glowstone')), 0.8, 1.2)
        self.iron = np.clip(detail(load(d, 'iron_block')), 0.7, 1.3)

    def blank(self):
        return np.zeros((N, N, 4), dtype=np.float32)

    def stick(self, im, y0, y1, x0=7, w=2):
        px0, px1 = x0 * S, (x0 + w) * S
        for y in range(y0 * S, y1 * S):
            for x in range(px0, px1):
                t = (x - px0) / (px1 - px0)
                shade = 1.12 - 0.3 * t                          # light from the left
                if x == px0 or x == px1 - 1:
                    shade *= 0.72
                im[y, x, :3] = np.clip(WOOD * self.grain[y, x] * shade, 0, 1)
                im[y, x, 3] = 1

    def flame(self, im, y0, y1, core, glow, x0=7, w=2, bands=False):
        c, g = rgb(core), rgb(glow)
        px0, px1, py0, py1 = x0 * S, (x0 + w) * S, y0 * S, y1 * S
        for y in range(py0, py1):
            v = (y - py0) / max(1, py1 - py0 - 1)
            for x in range(px0, px1):
                t = (x - px0) / (px1 - px0)
                col = c * (1 - v) + g * v
                if bands:                                      # redstone coil: alternating bands per texel
                    col = c if (y // S) % 2 == 0 else g
                col = col * (1.08 - 0.18 * t) * self.glowd[y, x]
                im[y, x, :3] = np.clip(col, 0, 1)
                im[y, x, 3] = 1

    def full(self, colour_a, colour_b=None):
        im = self.blank()
        a = rgb(colour_a)
        b = a if colour_b is None else rgb(colour_b)
        yy, xx = np.mgrid[0:N, 0:N] / (N - 1)
        r = np.clip(np.hypot(xx - 0.5, yy - 0.5) * 2, 0, 1)[..., None]
        im[..., :3] = np.clip((a * (1 - r) + b * r) * self.glowd[..., None], 0, 1)
        im[..., 3] = 1
        return im

    def wood_full(self):
        im = self.blank()
        im[..., :3] = np.clip(WOOD * self.grain[..., None], 0, 1)
        im[..., 3] = 1
        return im

    def lantern(self, frame_rgb, frame_detail, core, glow, window):
        im = self.blank()
        im[..., :3] = np.clip(frame_rgb * frame_detail[..., None], 0, 1)
        im[..., 3] = 1
        (x0, x1, y0, y1) = window                              # texel bounds, inclusive
        c, g = rgb(core), rgb(glow)
        yy, xx = np.mgrid[0:N, 0:N]
        m = (xx >= x0 * S) & (xx < (x1 + 1) * S) & (yy >= y0 * S) & (yy < (y1 + 1) * S)
        cx, cy = (x0 + x1 + 1) * S / 2, (y0 + y1 + 1) * S / 2
        r = np.clip(np.hypot((xx - cx) / ((x1 - x0 + 1) * S / 2), (yy - cy) / ((y1 - y0 + 1) * S / 2)), 0, 1)[..., None]
        col = np.clip((c * (1 - r) + g * r) * np.clip(self.glowd, 0.93, 1.07)[..., None], 0, 1)
        im[m, :3] = col[m]
        # a thin dark bar across the middle of the glass and darker inner rim
        rim = m & ~((xx >= x0 * S + 3) & (xx < (x1 + 1) * S - 3) & (yy >= y0 * S + 3) & (yy < (y1 + 1) * S - 3))
        im[rim, :3] *= 0.6
        return im


def save(im, d, n):
    Image.fromarray((np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, n + '.png'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default=os.path.join(ROOT, 'Resources/Textures'))
    a = ap.parse_args()
    d = a.dir
    log = os.path.join(d, '.derived_light')   # own log: texderive rewrites .derived
    derived = set(open(log).read().split()) if os.path.exists(log) else set()
    have = {p[:-4] for p in os.listdir(d) if p.endswith('.png')} - derived
    p = Painter(d)
    out = {}
    for n, (core, glow) in FLAMES.items():
        im = p.blank(); p.flame(im, 6, 8, core, glow); p.stick(im, 8, 16); out[n] = im
        im = p.blank(); p.flame(im, 3, 5, core, glow); p.stick(im, 5, 13); out[n + '_wall'] = im
        out[n + '_top_full'] = p.full(core, glow)
    for n, core, glow in (('torch_top', 0xFFF6C8, 0xFFC43A), ('copper_torch_top', 0xE0FFC8, 0x6CE04A)):
        im = p.blank(); p.flame(im, 7, 9, core, glow); out[n] = im
    out['torch_bottom'] = p.wood_full()
    for n, lit in (('redstone_torch', True), ('redstone_torch_off', False)):
        im = p.blank()
        p.flame(im, 4, 8, 0xFFC080 if lit else 0x7A4A2C, 0xF08A40 if lit else 0x5E3420, bands=True)
        p.stick(im, 8, 16); out[n] = im
    dark = rgb(0x3A3A40)
    out['lantern'] = p.lantern(dark, p.iron, 0xFFE8A0, 0xF8A83A, (3, 12, 3, 13))
    out['soul_lantern'] = p.lantern(dark, p.iron, 0xD8FFFF, 0x3AD8E8, (4, 10, 4, 12))
    for st, metal in (('', 'copper_block'), ('exposed_', 'exposed_copper'), ('weathered_', 'weathered_copper'),
                      ('oxidized_', 'oxidized_copper')):
        if os.path.exists(os.path.join(d, metal + '.png')):
            m = load(d, metal)
            mean = m[..., :3].reshape(-1, 3).mean(0) * 0.62
            out[st + 'copper_lantern'] = p.lantern(mean, np.clip(detail(m), 0.7, 1.3), 0xE0FFC8, 0x6CE04A, (3, 12, 3, 13))
    n = 0
    for name, im in out.items():
        if name in have:
            continue
        save(im, d, name)
        derived.add(name)
        n += 1
    open(log, 'w').write('\n'.join(sorted(derived)) + '\n')
    print('lightderive:', n, 'layers')


if __name__ == '__main__':
    main()
