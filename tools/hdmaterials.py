"""HD material designs (prototypes for Sources/TexturesHD.swift; see hdpreview.py)."""
import numpy as np
from hdpreview import gen, vnoise, fbm, warp, voronoi, ramp, light, rgba, hexc, h2, GEN

STONE = [(0, 0x5C5C60), (0.45, 0x7C7C80), (0.75, 0x929192), (1, 0xACAAA8)]
DEEP = [(0, 0x2E2E34), (0.5, 0x48484E), (1, 0x64646A)]
DIRT = [(0, 0x4A3222), (0.5, 0x6E4E34), (1, 0x8C6646)]


def shade(c, lt):
    return c * lt[..., None]


def stone2(pal, veins=1.0, strata=0.04, streak=0.0):
    def g(n, s):
        base = fbm(n, n // 2, 6, s)
        wx = fbm(n, n // 4, 3, s + 9); wy = fbm(n, n // 4, 3, s + 7)
        h = warp(base, n, wx, wy, n * 0.18)
        mottle = fbm(n, n // 8, 3, s + 11)
        grain = vnoise(n, max(1, n // 64), s + 5)
        Y = np.mgrid[0:n, 0:n][0].astype(np.float32)
        band = np.sin((Y + (wx - 0.5) * n * 0.4) / n * 2 * np.pi * 3) * strata
        # Veins: thin wandering ridges of a warped fbm, only where a mask allows (not a network).
        rf = warp(fbm(n, n // 4, 4, s + 20), n, wy, wx, n * 0.1)
        ridge = 1 - np.abs(2 * rf - 1)
        mask = fbm(n, n // 4, 2, s + 4)
        v = np.clip((ridge - 0.90) / 0.10, 0, 1) ** 2 * np.clip((mask - 0.55) * 5, 0, 1) * veins
        # Streaks (deepslate): fbm along x stretched vertically through the warp.
        st = warp(np.tile(vnoise(n, max(1, n // 32), s + 30)[:1], (n, 1)), n, wx, wy, n * 0.08)
        cells = voronoi(n, 6, s + 50, 1.0)
        fine2 = vnoise(n, max(1, n // 32), s + 51)
        patch = (cells[2] - 0.5) * 0.10 * np.clip((cells[1] - cells[0]) / (n / 24), 0, 1)
        t = h * 0.7 + (mottle - 0.5) * 0.3 + (grain - 0.5) * 0.14 + (fine2 - 0.5) * 0.16 + 0.14 + band - v * 0.10
        t = t + (st - 0.5) * streak + patch
        t = np.where(grain > 0.97, t + 0.07, t)
        hh = h * 0.5 + mottle * 0.2 + st * streak * 0.6 + fine2 * 0.15 + patch
        c = ramp(t, pal)
        return rgba(shade(c, light(hh, n, 1.4 * n / 128)))
    return g


def soil2(pal, pebble, pebbles=10, clods=7):
    def g(n, s):
        h = fbm(n, n // 4, 5, s)
        fine = vnoise(n, max(1, n // 64), s + 1)
        cl = voronoi(n, clods, s + 7, 1.0)
        f1, f2, pid = voronoi(n, pebbles, s + 3, 1.0)
        pr = n / 64
        rad = pr * (1 + pid * 1.2)
        isp = (pid > 0.8) & (f1 < rad * (0.6 + 0.7 * fine))
        t = h + (fine - 0.5) * 0.18 + (cl[2] - 0.5) * 0.10
        t = np.where(fine < 0.04, t - 0.18, t)
        col = ramp(t, pal)
        clod_edge = np.clip(1 - (cl[1] - cl[0]) / (n / 40), 0, 1)
        hh = h * 0.4 + fine * 0.12 - clod_edge * 0.03
        pc = hexc(pebble) * (0.82 + pid[..., None] * 0.18) * (0.92 + fine[..., None] * 0.1)
        col = np.where(isp[..., None], pc, col)
        hh = np.where(isp, hh + 0.12, hh)
        return rgba(shade(col, light(hh, n, 1.0 * n / 128)))
    return g


GEN['stone'] = stone2(STONE)
GEN['deepslate'] = stone2(DEEP, veins=0.4, strata=0.03, streak=0.35)
GEN['dirt'] = soil2(DIRT, 0x8A7662, pebbles=9)


def grass_top(n, s):
    base = fbm(n, n // 8, 4, s)
    g = 0.5 + (base - 0.5) * 0.25
    rng = np.random.default_rng(s)
    blades = n * n // 6; ln = max(2, n // 24)
    cx = rng.integers(0, n, blades); cy = rng.integers(0, n, blades)
    ang = rng.random(blades) * np.pi; v = 0.6 + rng.random(blades) * 0.4
    L = rng.integers(ln, ln * 2 + 1, blades)
    for t in range(ln * 2):
        m = t < L
        px = (cx + np.cos(ang) * t).astype(int) % n; py = (cy + np.sin(ang) * t).astype(int) % n
        g[py[m], px[m]] = (v * (0.85 + 0.15 * t / L))[m]
    lt = light(g * 0.5, n, n / 128)
    k = g * lt
    return rgba(np.stack([k, k, k], -1))


GEN['grass_block_top'] = grass_top


def fringe(n, s, depth, spikes, spikeH, width):
    """Per column fringe depth: a wavy base with tapered spikes (blades / snow drips)."""
    x = np.arange(n)
    d = depth * n + (vnoise(n, max(1, n // 8), s)[0] - 0.5) * n * 0.05
    rng = np.random.default_rng(s + 1)
    for _ in range(spikes):
        c = rng.integers(0, n); w = width * n * (0.5 + rng.random()); hgt = spikeH * n * (0.3 + rng.random() * 0.7)
        dx = np.minimum((x - c) % n, (c - x) % n)
        d = np.maximum(d, depth * n + hgt * np.clip(1 - dx / w, 0, 1) ** 1.5)
    return d


def grass_side(n, s):
    dirt = GEN['dirt'](n, s)
    top = grass_top(n, s + 3)
    d = fringe(n, s + 5, 0.14, n // 2, 0.18, 0.012)
    Y = np.mgrid[0:n, 0:n][0].astype(np.float32)
    inside = Y < d[None, :]
    gv = top[..., 0] * (1 - 0.25 * np.clip(Y / np.maximum(d[None, :], 1), 0, 1))
    # Shadow on the dirt just under the grass.
    sh = 1 - 0.35 * np.clip(1 - (Y - d[None, :]) / (n * 0.04), 0, 1)
    out = dirt.copy()
    out[..., :3] *= np.where(inside, 1, sh)[..., None]
    g3 = np.stack([gv, gv, gv, np.full_like(gv, 0.9)], -1)
    return np.where(inside[..., None], g3, out)


GEN['grass_block_side'] = grass_side


def snow(n, s):
    sh = fbm(n, n // 2, 5, s)
    fine = vnoise(n, max(1, n // 64), s + 1)
    hh = sh * 0.6 + fine * 0.08
    t = np.clip((sh - 0.3) * 1.4, 0, 1)
    c = hexc(0xC9D6EA) * (1 - t[..., None]) + hexc(0xF6F9FF) * t[..., None]
    c = shade(c, light(hh, n, 0.9 * n / 128))
    sp = vnoise(n, 1, s + 2) > 0.995
    c = np.where(sp[..., None], 1.0, c)
    return rgba(np.clip(c, 0, 1))


GEN['snow'] = snow


def grass_snow(n, s):
    dirt = GEN['dirt'](n, s)
    sn = snow(n, s + 1)
    d = fringe(n, s + 5, 0.20, n // 10, 0.12, 0.05)
    Y = np.mgrid[0:n, 0:n][0].astype(np.float32)
    inside = Y < d[None, :]
    rim = np.clip(1 - (d[None, :] - Y) / (n * 0.03), 0, 1)
    snc = sn.copy(); snc[..., :3] *= (1 - 0.18 * rim)[..., None]
    sh = 1 - 0.35 * np.clip(1 - (Y - d[None, :]) / (n * 0.04), 0, 1)
    out = dirt.copy(); out[..., :3] *= np.where(inside, 1, sh)[..., None]
    return np.where(inside[..., None], snc, out)


GEN['grass_block_snow'] = grass_snow


def masonry(rows, per_row, offset, mortar_w, pal, mortar, fill='stone', chips=1.0, bevel=0.03, tone=0.18):
    """Blocks in courses: per-block tone, rounded bevel, eroded corners, rough mortar."""
    def g(n, s):
        Y, X = np.mgrid[0:n, 0:n]
        rh = n / rows; bw = n / per_row
        row = (Y // rh).astype(int)
        xo = (X + (row % 2) * offset * n) % n
        col = (xo // bw).astype(int)
        lx = xo - col * bw; ly = Y - row * rh
        wob = fbm(n, max(1, n // 16), 3, s + 40)
        mw = mortar_w * n * (0.9 + (wob - 0.5) * 0.4)
        de = np.minimum(np.minimum(lx, bw - 1 - lx), np.minimum(ly, rh - 1 - ly)) - mw / 2
        erode = (fbm(n, max(1, n // 8), 3, s + 41) - 0.5) * n * 0.018 * chips
        de = de + erode * np.clip(1 - de / (n * 0.05), 0, 1)
        isM = de < 0
        bid = h2(col + row * 31, row, s)
        if fill == 'stone':
            inner = fbm(n, n // 4, 5, s + 2); fine = vnoise(n, max(1, n // 64), s + 3)
            t = 0.5 + (bid - 0.5) * tone + (inner - 0.5) * 0.45 + (fine - 0.5) * 0.12
        else:  # clay brick: mottled, burnt spots, sandy specks
            inner = fbm(n, n // 8, 4, s + 2); fine = vnoise(n, max(1, n // 128), s + 3)
            t = 0.5 + (bid - 0.5) * tone + (inner - 0.5) * 0.35 + (fine - 0.5) * 0.15
            t = np.where(fine > 0.93, t + 0.15, t)
        dome = np.clip(de / (bevel * n), 0, 1)
        hh = np.where(isM, -0.3, dome * 0.5 + inner * 0.1)
        c = ramp(t, pal)
        mf = vnoise(n, max(1, n // 64), s + 9)
        mc = hexc(mortar) * (0.85 + mf[..., None] * 0.3)
        c = np.where(isM[..., None], mc, c)
        return rgba(shade(c, light(hh, n, 0.8 * n / 128)))
    return g


GEN['stone_bricks'] = masonry(2, 1, 0.5, 1 / 22, [(0, 0x5E5E60), (0.5, 0x7E7E80), (1, 0x9C9C9C)], 0x48484A)
GEN['bricks'] = masonry(4, 2, 0.25, 1 / 18, [(0, 0x7A3A2C), (0.5, 0x985040), (1, 0xB4705A)], 0xB0AAA0, fill='clay', chips=1.4)
GEN['deepslate_bricks'] = masonry(4, 2, 0.25, 1 / 26, [(0, 0x343436), (0.5, 0x4A4A4C), (1, 0x626264)], 0x202022, chips=1.2)
GEN['deepslate_tiles'] = masonry(4, 4, 0, 1 / 26, [(0, 0x262628), (0.5, 0x363638), (1, 0x4C4C4E)], 0x161618, chips=0.8)
GEN['nether_bricks'] = masonry(4, 2, 0.25, 1 / 20, [(0, 0x2A1014), (0.5, 0x3E181C), (1, 0x5A2428)], 0x1A0A0C, fill='clay', chips=1.2)
GEN['mud_bricks'] = masonry(4, 2, 0.25, 1 / 18, [(0, 0x6E5240), (0.5, 0x89684F), (1, 0xA48262)], 0x5A4234, fill='clay', chips=0.8)


def sandstone_side(n, s):
    w = fbm(n, n // 4, 3, s)
    fine = vnoise(n, max(1, n // 128), s + 1)
    Y = np.mgrid[0:n, 0:n][0].astype(np.float32)
    yy = Y + (w - 0.5) * n * 0.06
    layers = np.sin(yy / n * 2 * np.pi * 5) * 0.06 + np.sin(yy / n * 2 * np.pi * 13) * 0.03
    band = (np.abs(yy - n * 0.25) < n * 0.035) * -0.12
    top = (Y > n * 0.84) * -0.06
    t = 0.55 + layers + band + top + (fine - 0.5) * 0.16
    hh = layers * 2 + band
    c = ramp(t, [(0, 0xB8A878), (0.5, 0xD9CE9E), (1, 0xEEE4BC)])
    return rgba(shade(c, light(hh, n, n / 128)))


GEN['sandstone'] = sandstone_side


def rings_top(bark, wood):
    def g(n, s):
        Y, X = np.mgrid[0:n, 0:n].astype(np.float32)
        dx = X - n / 2 + 0.5; dy = Y - n / 2 + 0.5
        ang = np.arctan2(dy, dx)
        w = fbm(n, n // 4, 3, s)
        d = np.sqrt(dx * dx + dy * dy) + (w - 0.5) * n * 0.03 + np.sin(ang * 3 + 1.3) * n * 0.008
        ph = d / n * 13 + (vnoise(n, max(1, n // 8), s + 6) - 0.5) * 0.5
        fr = ph - np.floor(ph)
        rings = 1 - np.clip((fr - 0.72) / 0.12, 0, 1) * np.clip((1 - fr) / 0.08, 0, 1)
        fine = vnoise(n, max(1, n // 64), s + 1)
        t = 0.62 + (rings - 0.5) * 0.4 - d / n * 0.3 + (fine - 0.5) * 0.08
        # Radial drying cracks.
        a0 = h2(1, 2, s) * 2 * np.pi
        da = np.abs(((ang - a0 + (w - 0.5) * 0.3) + np.pi) % (2 * np.pi) - np.pi)
        crack = (da * d < n * 0.002 + d * 0.02) & (d < n * 0.3) & (d > n * 0.06)
        t = np.where(crack, t - 0.45, t)
        c = ramp(t, [(0, wood[0]), (0.5, wood[1]), (1, wood[2])])
        # Bark rim (wavy).
        edge = np.minimum(np.minimum(X, n - 1 - X), np.minimum(Y, n - 1 - Y))
        rimw = n * 0.07 + (vnoise(n, max(1, n // 16), s + 3) - 0.5) * n * 0.04
        bc = ramp(0.4 + (fine - 0.5) * 0.4 + (w - 0.5) * 0.3, [(0, bark[0]), (0.5, bark[1]), (1, bark[2])])
        isb = edge < rimw
        c = np.where(isb[..., None], bc, c)
        hh = np.where(isb, 0.3 + fine * 0.2, rings * 0.12) - crack * 0.15
        return rgba(shade(c, light(hh, n, 1.1 * n / 128)))
    return g


GEN['oak_log_top'] = rings_top([0x3C2C1C, 0x60482C, 0x80623E], [0x8A6C40, 0xB0915B, 0xC8AA72])


def birch_log(n, s):
    w = fbm(n, n // 4, 3, s)
    fine = vnoise(n, max(1, n // 64), s + 1)
    Y, X = np.mgrid[0:n, 0:n].astype(np.float32)
    t = 0.7 + (fbm(n, n // 8, 3, s + 2) - 0.5) * 0.25 + (fine - 0.5) * 0.08
    # Horizontal lenticels: dark dashes, a few long scars.
    rng = np.random.default_rng(s)
    dark = np.zeros((n, n), bool)
    for _ in range(n // 6):
        cx = rng.integers(0, n); cy = rng.integers(0, n)
        L = n * (0.03 + rng.random() * 0.10); hgt = max(1, int(n * (0.012 + rng.random() * 0.02)))
        dxx = np.minimum((X - cx) % n, (cx - X) % n); dyy = (Y - cy) % n
        wv = (w - 0.5) * n * 0.02
        dark |= (dxx < L * (0.6 + 0.4 * fine)) & ((dyy + wv) % n < hgt)
    c = ramp(t, [(0, 0xBEB8AA), (0.5, 0xDCD8CC), (1, 0xF0EEE6)])
    dc = hexc(0x2E2B26) * (0.8 + fine[..., None] * 0.4)
    c = np.where(dark[..., None], dc, c)
    hh = np.where(dark, -0.2, 0)
    return rgba(shade(c, light(hh, n, n / 128)))


GEN['birch_log'] = birch_log


def wool(n, s, col=0xD8D8D8):
    Y, X = np.mgrid[0:n, 0:n].astype(np.float32)
    k = n / 16
    u = (X + (np.floor(Y / k) % 2) * k * 0.5) / k; v = Y / k
    fu = u - np.floor(u); fv = v - np.floor(v)
    loop = np.exp(-(((fu - 0.5) / 0.38) ** 2 + ((fv - 0.5) / 0.6) ** 2))
    fuzz = vnoise(n, 1, s) * 0.5 + vnoise(n, 2, s + 1) * 0.5
    blot = fbm(n, n // 4, 3, s + 2)
    t = 0.5 + loop * 0.14 + (fuzz - 0.5) * 0.3 + (blot - 0.5) * 0.12
    hh = loop * 0.25 + fuzz * 0.25
    c = hexc(col) * (0.62 + t[..., None] * 0.55)
    return rgba(shade(c, light(hh, n, 0.8 * n / 128)))


GEN['white_wool'] = wool
GEN['red_wool'] = lambda n, s: wool(n, s, 0xA02722)
