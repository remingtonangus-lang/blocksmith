#!/usr/bin/env python3
"""Preview of the HD texture generators (Sources/TexturesHD.swift) without a Swift compiler.

A numpy port of HDTex's primitives (same hash, value noise, fbm, warp, Voronoi, ramp, relief light) used to
design new materials and check them by eye before porting them to Swift. `python3 tools/hdpreview.py OUT.png
[names...]` writes a labelled sheet (3x3 tiling per material to show seams)."""
import sys
import numpy as np
from PIL import Image, ImageDraw

M32 = 0xFFFFFFFF


def h2(x, y, s):
    x = np.asarray(x, dtype=np.int64); y = np.asarray(y, dtype=np.int64)
    h = (x * 374761393 + y * 668265263 + int(s) * -2048144789) & M32
    h = ((h ^ (h >> 13)) * 1274126177) & M32
    h ^= h >> 16
    return (h & 0xFFFF).astype(np.float32) / 65535


def vnoise(n, cell, s):
    c = max(1, min(n, cell)); g = max(1, n // c)
    ar = np.arange(n, dtype=np.float32) / c
    i0 = ar.astype(np.int64); t = ar - i0; t = t * t * (3 - 2 * t)
    X0, Y0 = np.meshgrid(i0, i0); TX, TY = np.meshgrid(t, t)
    a0 = h2(X0 % g, Y0 % g, s); a1 = h2((X0 + 1) % g, Y0 % g, s)
    b0 = h2(X0 % g, (Y0 + 1) % g, s); b1 = h2((X0 + 1) % g, (Y0 + 1) % g, s)
    a = a0 + (a1 - a0) * TX; b = b0 + (b1 - b0) * TX
    return a + (b - a) * TY


def fbm(n, base, octaves, s, gain=0.5):
    out = np.zeros((n, n), np.float32); amp = 1.0; tot = 0.0; cell = max(1, base)
    for o in range(octaves):
        out += vnoise(n, cell, s + o * 17) * amp; tot += amp; amp *= gain; cell = max(1, cell // 2)
    return out / tot


def warp(f, n, dx, dy, amount):
    Y, X = np.mgrid[0:n, 0:n]
    sx = (X + ((dx - 0.5) * amount).astype(np.int64)) % n
    sy = (Y + ((dy - 0.5) * amount).astype(np.int64)) % n
    return f[sy, sx]


def voronoi(n, cells, s, jitter=0.9):
    c = n / cells
    Y, X = np.mgrid[0:n, 0:n].astype(np.float32)
    cx = (X / c).astype(np.int64); cy = (Y / c).astype(np.int64)
    d1 = np.full((n, n), 1e9, np.float32); d2 = d1.copy(); best = np.zeros((n, n), np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            gx = cx + dx; gy = cy + dy; wx = gx % cells; wy = gy % cells
            jx = (h2(wx, wy, s) - 0.5) * jitter; jy = (h2(wx, wy, s + 1) - 0.5) * jitter
            px = (gx + 0.5 + jx) * c; py = (gy + 0.5 + jy) * c
            d = np.sqrt((X - px) ** 2 + (Y - py) ** 2)
            idv = h2(wx, wy, s + 2)
            closer = d < d1
            d2 = np.where(closer, d1, np.where(d < d2, d, d2))
            best = np.where(closer, idv, best)
            d1 = np.where(closer, d, d1)
    return d1, d2, best


def hexc(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], np.float32) / 255


def ramp(t, stops):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    out[...] = hexc(stops[-1][1])
    for i in range(len(stops) - 1, 0, -1):
        p0, c0 = stops[i - 1]; p1, c1 = stops[i]
        m = (t <= p1)
        f = np.clip((t - p0) / max(p1 - p0, 1e-6), 0, 1)[..., None]
        out = np.where(m[..., None], hexc(c0) * (1 - f) + hexc(c1) * f, out)
    m = t <= stops[0][0]
    out = np.where(m[..., None], hexc(stops[0][1]), out)
    return out


def light(h, n, k):
    l = np.roll(h, 1, axis=1); r = np.roll(h, -1, axis=1)
    u = np.roll(h, 1, axis=0); d = np.roll(h, -1, axis=0)
    return 1 - ((r - l) + (d - u)) * k


def rgba(c, a=None):
    a = np.ones(c.shape[:2], np.float32) if a is None else a
    return np.concatenate([c, a[..., None]], axis=2)


GEN = {}


def gen(name):
    def deco(f):
        GEN[name] = f
        return f
    return deco


def sheet(names, out, n=128, scale=1, tile=2):
    cols = min(6, len(names)); rows = (len(names) + cols - 1) // cols
    cw = n * tile * scale + 8; chh = n * tile * scale + 22
    im = Image.new('RGB', (cols * cw, rows * chh), (40, 40, 44))
    dr = ImageDraw.Draw(im)
    for k, name in enumerate(names):
        import hdpreview
        img = hdpreview.GEN[name](n, 1234 + k * 7)
        c = np.clip(img, 0, 1)
        rgb = c[..., :3]; a = c[..., 3:4]
        chk = ((np.indices((n, n)).sum(0) // 8) % 2)[..., None] * 0.15 + 0.35
        rgb = rgb * a + chk * (1 - a)
        t = np.tile(rgb, (tile, tile, 1))
        p = Image.fromarray((t * 255).astype(np.uint8))
        if scale != 1:
            p = p.resize((p.width * scale, p.height * scale), Image.NEAREST)
        x0 = (k % cols) * cw + 4; y0 = (k // cols) * chh + 18
        im.paste(p, (x0, y0)); dr.text((x0, y0 - 15), name, fill=(230, 230, 230))
    im.save(out)


if __name__ == '__main__':
    import hdpreview
    import hdmaterials  # noqa: F401  (registers materials in hdpreview.GEN)
    out = sys.argv[1] if len(sys.argv) > 1 else 'hdpreview.png'
    names = sys.argv[2:] or list(hdpreview.GEN)
    hdpreview.sheet(names, out)
