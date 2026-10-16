#!/usr/bin/env python3
"""Material lab: prototypes of the 128x128 procedural material generators (numpy), to iterate on the look before
porting to Swift (Sources/TexturesHD.swift). Every function returns an (n, n, 4) float RGBA array, tileable.
Usage: matlab.py OUT_PNG [names...]"""
import sys, numpy as np
from PIL import Image, ImageDraw

N = 128

def h2(x, y, s):
    x = np.asarray(x, dtype=np.int64); y = np.asarray(y, dtype=np.int64)
    h = (x * 374761393 + y * 668265263 + s * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

def vnoise(cell, s, n=N):
    g = max(1, n // cell)
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    fx, fy = x / cell, y / cell
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    def g_(a, b): return h2(a % g, b % g, s)
    a = g_(x0, y0) + (g_(x0 + 1, y0) - g_(x0, y0)) * tx
    b = g_(x0, y0 + 1) + (g_(x0 + 1, y0 + 1) - g_(x0, y0 + 1)) * tx
    return a + (b - a) * ty

def fbm(base, octaves, s, gain=0.5):
    out = np.zeros((N, N)); amp = 1.0; tot = 0; cell = base
    for o in range(octaves):
        out += vnoise(max(1, cell), s + o * 17) * amp; tot += amp; amp *= gain; cell //= 2
    return out / tot

def warp_sample(f, dx, dy):
    y, x = np.mgrid[0:N, 0:N]
    return f[(y + dy.astype(int)) % N, (x + dx.astype(int)) % N]

def voronoi(cells, s, jitter=0.9):
    """F1, F2 distances (in pixels) and the cell id, tileable."""
    c = N / cells
    y, x = np.mgrid[0:N, 0:N].astype(np.float64)
    cx, cy = np.floor(x / c).astype(int), np.floor(y / c).astype(int)
    f1 = np.full((N, N), 1e9); f2 = np.full((N, N), 1e9); cid = np.zeros((N, N))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            gx, gy = cx + dx, cy + dy
            px = (gx + 0.5 + (h2(gx % cells, gy % cells, s) - 0.5) * jitter) * c
            py = (gy + 0.5 + (h2(gx % cells, gy % cells, s + 1) - 0.5) * jitter) * c
            d = np.sqrt((x - px) ** 2 + (y - py) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, h2(gx % cells, gy % cells, s + 2), cid)
            f1 = np.where(closer, d, f1)
    return f1, f2, cid

def ramp(t, stops):
    """Palette ramp: stops = [(pos, (r,g,b)), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(1e-6, p1 - p0))[..., None]
        out = np.where(m[..., None], np.array(c0) / 255 * (1 - k) + np.array(c1) / 255 * k, out)
    return out

def light(h, k=1.2):
    """Top-left relief lighting from a height field."""
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1); gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return 1 - (gx + gy) * k

def rgba(c, a=None):
    a = np.ones(c.shape[:2]) if a is None else a
    return np.dstack([np.clip(c, 0, 1), a])

# ---- materials ----
def stone(s=1, pal=None):
    pal = pal or [(0, (92, 92, 96)), (0.45, (124, 124, 128)), (0.75, (146, 145, 146)), (1, (172, 170, 168))]
    base = fbm(64, 6, s)
    w = fbm(32, 3, s + 9)
    h = warp_sample(base, (w - 0.5) * 22, (fbm(32, 3, s + 7) - 0.5) * 22)
    f1, f2, _ = voronoi(5, s + 3)
    crack = np.clip(1 - (f2 - f1) / 2.2, 0, 1) * (fbm(16, 2, s + 4) > 0.55)
    grain = (vnoise(2, s + 5) - 0.5) * 0.10
    t = h * 0.9 + grain - crack * 0.35
    col = ramp(t, pal) * light(h * 0.6 - crack * 0.25, 1.4)[..., None]
    return rgba(col)

def dirt(s=2):
    pal = [(0, (74, 50, 34)), (0.5, (110, 78, 52)), (1, (140, 102, 70))]
    h = fbm(32, 5, s)
    f1, f2, cid = voronoi(14, s + 3, 1.0)
    pebble = (f1 < 3.2 + cid * 2.0) & (cid > 0.62)
    t = h + (vnoise(2, s + 1) - 0.5) * 0.18
    col = ramp(t, pal)
    pc = ramp(cid * 0.8 + 0.2, [(0, (96, 84, 72)), (1, (150, 136, 118))])
    hh = h * 0.3 + np.where(pebble, (3.6 + cid * 2 - f1) / 6, 0)
    col = np.where(pebble[..., None], pc, col) * light(hh, 1.8)[..., None]
    return rgba(col)

def grass_top(s=3):
    # Greyscale (biome-tinted at runtime): many short blades at random angles over a darker mat.
    y, x = np.mgrid[0:N, 0:N]
    base = 0.55 + (fbm(16, 4, s) - 0.5) * 0.25
    img = base.copy()
    rng = np.random.default_rng(s)
    for i in range(2600):
        cx, cy = rng.integers(0, N, 2); ang = rng.uniform(0, np.pi); L = rng.integers(3, 7); v = rng.uniform(0.62, 1.0)
        for t in range(L):
            px = int(cx + np.cos(ang) * t) % N; py = int(cy + np.sin(ang) * t) % N
            img[py, px] = v * (0.85 + 0.15 * t / L)
    img = img * light(img * 0.5, 1.0)
    c = np.dstack([img, img, img])
    return rgba(c)

def log_side(s=4):
    pal = [(0, (60, 44, 28)), (0.5, (96, 72, 44)), (1, (128, 98, 62))]
    y, x = np.mgrid[0:N, 0:N]
    w = (fbm(32, 3, s) - 0.5) * 14
    ridges = 0.5 + 0.5 * np.sin((x + w) / N * 2 * np.pi * 9 + fbm(64, 2, s + 1) * 6)
    fine = fbm(4, 2, s + 2)
    stretch = vnoise(16, s + 3)[:, :] * 0.3
    t = ridges * 0.6 + fine * 0.25 + stretch
    col = ramp(t, pal) * light(ridges * 0.4 + fine * 0.2, 1.2)[..., None]
    return rgba(col)

def planks(s=5):
    pal = [(0, (126, 92, 52)), (0.5, (166, 126, 76)), (1, (196, 156, 98))]
    y, x = np.mgrid[0:N, 0:N]
    board = y // 32
    off = (h2(board, 0, s) * 64).astype(int)
    seamx = ((x + off) % 64) < 2
    seamy = (y % 32) < 2
    grain = 0.5 + 0.5 * np.sin((y + fbm(32, 3, s + board.astype(int) % 4) * 18) / 3.2)
    shade = h2(board * 7 + ((x + off) // 64), 1, s) * 0.18
    t = grain * 0.35 + fbm(8, 3, s + 1) * 0.25 + shade + 0.25
    col = ramp(t, pal)
    hh = np.where(seamx | seamy, -0.3, 0.0) + grain * 0.05
    col = col * light(hh, 1.6)[..., None]
    col = np.where((seamx | seamy)[..., None], col * 0.62, col)
    return rgba(col)

def cobble(s=6):
    f1, f2, cid = voronoi(5, s, 0.8)
    edge = f2 - f1
    mortar = edge < 2.4
    dome = np.clip(edge / 12, 0, 1)
    h = dome * 0.7 + fbm(16, 3, s + 1) * 0.3
    stonec = ramp(cid * 0.5 + fbm(32, 4, s + 2) * 0.5, [(0, (88, 88, 90)), (0.5, (128, 128, 130)), (1, (160, 158, 156))])
    col = np.where(mortar[..., None], np.array([60, 58, 58]) / 255 * (0.8 + fbm(4, 2, s + 3)[..., None] * 0.4), stonec)
    col = col * light(np.where(mortar, -0.2, h), 1.3)[..., None]
    return rgba(col)

def sand(s=7):
    y, x = np.mgrid[0:N, 0:N]
    rip = 0.5 + 0.5 * np.sin((y + fbm(64, 3, s) * 30) / N * 2 * np.pi * 6)
    t = 0.55 + (vnoise(1, s + 1) - 0.5) * 0.22 + (rip - 0.5) * 0.12 + (fbm(32, 3, s + 2) - 0.5) * 0.15
    col = ramp(t, [(0, (196, 178, 128)), (0.5, (220, 204, 150)), (1, (240, 228, 180))])
    return rgba(col * light(rip * 0.08, 1)[..., None])

def gravel(s=8):
    f1, f2, cid = voronoi(11, s, 1.0)
    edge = f2 - f1
    dome = np.clip(edge / 5, 0, 1)
    tone = cid
    col = ramp(tone * 0.7 + fbm(8, 2, s + 1) * 0.3, [(0, (92, 86, 84)), (0.4, (124, 118, 114)), (0.7, (150, 140, 128)), (1, (176, 168, 160))])
    col = np.where((edge < 1.2)[..., None], col * 0.55, col) * light(dome * 0.6, 1.3)[..., None]
    return rgba(col)

def leaves(s=9):
    # Greyscale (tinted): overlapping leaf ellipses with holes for the cutout.
    img = np.zeros((N, N)); a = np.zeros((N, N))
    rng = np.random.default_rng(s)
    y, x = np.mgrid[0:N, 0:N]
    for i in range(420):
        cx, cy = rng.uniform(0, N, 2); ang = rng.uniform(0, np.pi); L = rng.uniform(5, 9); W = L * 0.45; v = rng.uniform(0.45, 1.0)
        dx = (x - cx + N / 2) % N - N / 2; dy = (y - cy + N / 2) % N - N / 2
        u = dx * np.cos(ang) + dy * np.sin(ang); w = -dx * np.sin(ang) + dy * np.cos(ang)
        m = (u / L) ** 2 + (w / W) ** 2 < 1
        shade = v * (0.8 + 0.2 * (u / L)) * (0.75 + 0.25 * (np.abs(w) > W * 0.15))
        img = np.where(m, shade, img); a = np.where(m, 1, a)
    c = np.dstack([img, img, img])
    return rgba(c, a)

def ore(base_fn, crystal, s=10, count=7):
    b = base_fn(s)
    col = b[..., :3].copy()
    rng = np.random.default_rng(s)
    y, x = np.mgrid[0:N, 0:N]
    for i in range(count):
        cx, cy = rng.uniform(8, N - 8, 2); r = rng.uniform(5, 9)
        f1, f2, cid = voronoi(24, s + i * 3, 1.0)
        dx = (x - cx); dy = (y - cy)
        d = np.sqrt(dx * dx + dy * dy) + (fbm(8, 2, s + i)) * 4
        m = (d < r) & (cid > 0.35)
        facet = np.clip((cid - 0.35) / 0.65, 0, 1)
        cc = np.array(crystal[0]) / 255 * (1 - facet[..., None]) + np.array(crystal[1]) / 255 * facet[..., None]
        hi = (f2 - f1 < 1.5)
        cc = np.where(hi[..., None], cc * 0.6, cc)
        rim = (d >= r) & (d < r + 1.6)
        col = np.where(m[..., None], cc, np.where(rim[..., None], col * 0.7, col))
    return rgba(col)

MATS = {
    'stone': lambda: stone(), 'dirt': lambda: dirt(), 'grass_block_top': lambda: grass_top(), 'oak_log': lambda: log_side(),
    'oak_planks': lambda: planks(), 'cobblestone': lambda: cobble(), 'sand': lambda: sand(), 'gravel': lambda: gravel(),
    'oak_leaves': lambda: leaves(), 'coal_ore': lambda: ore(stone, [(30, 30, 32), (70, 70, 74)]),
    'iron_ore': lambda: ore(stone, [(196, 150, 110), (236, 204, 170)]), 'diamond_ore': lambda: ore(stone, [(60, 200, 210), (190, 250, 250)]),
}

if __name__ == '__main__':
    out = sys.argv[1]
    names = sys.argv[2:] or list(MATS)
    cols = 4
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 266 + 10, rows * 290 + 10), (24, 24, 28)); d = ImageDraw.Draw(sheet)
    tint = {'grass_block_top': (124, 189, 107), 'oak_leaves': (90, 160, 60)}
    for i, n in enumerate(names):
        a = MATS[n]()
        rgb = a[..., :3]
        if n in tint: rgb = rgb * np.array(tint[n]) / 255
        bg = np.where((np.indices((N, N)).sum(0) // 8) % 2 == 0, 0.25, 0.32)[..., None]
        rgb = rgb * a[..., 3:4] + bg * (1 - a[..., 3:4])
        im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).resize((256, 256), Image.NEAREST)
        x, y = 10 + (i % cols) * 266, 10 + (i // cols) * 290
        d.text((x, y), n, fill=(220, 220, 140)); sheet.paste(im, (x, y + 16))
    sheet.save(out); print('wrote', out)
