#!/usr/bin/env python3
"""Item art lab: a numpy mirror of Sources/ItemHD.swift (signed-distance item designs, bevel shading, outline,
drop shadow) for previewing designs without a Mac. Not used by the game; keep it in step with ItemHD.swift by hand.

  python3 tools/itemlab.py OUT.png [--n 128] [--scale 1] [--names a,b,c] [--bg dark|slot]
"""
import argparse
import math
import numpy as np
from PIL import Image


def hexc(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32) / 255


MATS = {}


def mat(name, kind, base, dark, light):
    MATS[name] = (kind, hexc(base), hexc(dark), hexc(light))


for row in [
    ("wood", "wood", 0xB98E58, 0x6A4A26, 0xE6C690), ("handle", "wood", 0x7A5530, 0x3E2914, 0xB08250),
    ("stone", "stone", 0x767C86, 0x363A44, 0xAEB4BE), ("iron", "metal", 0xC9CED6, 0x5E646E, 0xFFFFFF),
    ("golden", "metal", 0xF0C33C, 0x8A5A10, 0xFFF4B0), ("diamond", "gem", 0x46D8E0, 0x146A7A, 0xD8FFFF),
    ("netherite", "dusk", 0x4A4450, 0x18151C, 0xB59AD8), ("copper", "copper", 0xDA7240, 0x6E2E12, 0xFFC29A),
    ("leather", "leather", 0x8E5430, 0x4A2812, 0xC08458), ("grip", "leather", 0x5A3A26, 0x2A1A10, 0x8A6040),
    ("chainmail", "chain", 0xA0A4AA, 0x4A4C52, 0xE8EAEE), ("turtle", "leather", 0x4FA046, 0x1F4A1C, 0x9AD88A),
    ("apple", "soft", 0xD8282A, 0x6A0E12, 0xFF9A8A), ("leaf", "soft", 0x52A63A, 0x1E4A16, 0xA8E08A),
    ("stem", "wood", 0x6A4A2A, 0x2E1E10, 0x9A7448), ("crust", "soft", 0xC8883E, 0x6A3A12, 0xF0C27A),
    ("emerald", "gem", 0x2ECC5A, 0x0A5A22, 0xC8FFD8), ("coal", "stone", 0x34343A, 0x101012, 0x8A8A96),
    ("bone", "soft", 0xE8E2CC, 0x8A8270, 0xFFFFF4), ("white", "soft", 0xEDEDED, 0x9A9AA4, 0xFFFFFF),
    ("flint", "stone", 0x4C4C54, 0x1A1A1E, 0x9A9AA8), ("water", "soft", 0x3A6EE0, 0x142A70, 0xA8C8FF),
    ("lava", "soft", 0xFF7A1A, 0xA02A08, 0xFFE07A), ("milk", "soft", 0xF4F4F0, 0xB0B0AA, 0xFFFFFF),
    ("meat", "soft", 0xC8383A, 0x6A1416, 0xF29A90), ("cooked", "soft", 0x8A4A24, 0x3A1C0A, 0xC8885A),
    ("fat", "soft", 0xF0D8C8, 0xA08878, 0xFFF4EE), ("pearl", "gem", 0x1E8A7A, 0x0A3A34, 0x9AF0DA),
    ("redstone", "soft", 0xE01818, 0x700808, 0xFF8A70), ("glow", "soft", 0xF8D040, 0xA07010, 0xFFF8C0),
    ("gunpowder", "stone", 0x6A6A6E, 0x2A2A2E, 0xB4B4BA), ("sugar", "soft", 0xF4F4F8, 0xB8B8C4, 0xFFFFFF),
    ("paper", "soft", 0xF2EEDC, 0xB4AC94, 0xFFFFFF), ("book", "leather", 0x8A3A26, 0x3E160C, 0xC8705A),
    ("wheat", "soft", 0xDCB850, 0x7A5A1A, 0xFFF0A0), ("carrot", "soft", 0xF07A1A, 0x8A3A08, 0xFFC07A),
    ("egg", "soft", 0xE8DCC4, 0x9A8A6E, 0xFFFFF8), ("slime", "soft", 0x6ACC4A, 0x2A6A1A, 0xD0FFB0),
    ("blaze", "soft", 0xF8B02A, 0xA0520A, 0xFFF4B0), ("string", "soft", 0xE4E4E8, 0x8A8A94, 0xFFFFFF),
    ("tint", "soft", 0xF2F2F2, 0x8A8A8A, 0xFFFFFF), ("glass", "soft", 0xD4E2F2, 0x7A8AA0, 0xFFFFFF),
]:
    mat(*row)

TIERS = ["wooden", "stone", "iron", "golden", "diamond", "netherite", "copper"]
TOOLS = ["sword", "pickaxe", "axe", "shovel", "hoe", "spear"]
ARMOR_SETS = ["leather", "chainmail", "iron", "golden", "diamond", "netherite", "copper"]
ARMOR = ["helmet", "chestplate", "leggings", "boots"]


def V(x, y):
    return np.array([x, y], dtype=np.float32)


def norm(v):
    return v / max(1e-9, float(np.linalg.norm(v)))


class Canvas:
    def __init__(self, n, tilt=0.0, zoom=1.0):
        self.n = n
        c = (np.arange(n, dtype=np.float32) + 0.5) / n
        X, Y = np.meshgrid(c, c)
        # Design space seen through a turn (radians, positive lifts the right side) and a zoom about the centre.
        co, si = math.cos(tilt), math.sin(tilt)
        dx, dy = (X - 0.5) / zoom, (Y - 0.5) / zoom
        self.X, self.Y = (0.5 + dx * co - dy * si).astype(np.float32), (0.5 + dx * si + dy * co).astype(np.float32)
        self.parts = []

    def seg(self, a, b):
        ab = b - a
        t = ((self.X - a[0]) * ab[0] + (self.Y - a[1]) * ab[1]) / max(1e-9, float(ab @ ab))
        t = np.clip(t, 0, 1)
        dx = self.X - (a[0] + ab[0] * t)
        dy = self.Y - (a[1] + ab[1] * t)
        return np.sqrt(dx * dx + dy * dy), t

    def capsule(self, a, b, r0, r1=None):
        d, t = self.seg(a, b)
        r1 = r0 if r1 is None else r1
        return d - (r0 + (r1 - r0) * t), t

    def circle(self, c, r):
        return np.sqrt((self.X - c[0]) ** 2 + (self.Y - c[1]) ** 2) - r

    def ellipse(self, c, a, b):
        return (np.sqrt(((self.X - c[0]) / a) ** 2 + ((self.Y - c[1]) / b) ** 2) - 1) * min(a, b)

    def poly(self, pts):
        best = np.full(self.X.shape, 9.0, dtype=np.float32)
        inside = np.zeros(self.X.shape, dtype=bool)
        m = len(pts)
        for e in range(m):
            a, b = pts[e], pts[(e + 1) % m]
            best = np.minimum(best, self.seg(a, b)[0])
            cond = (a[1] > self.Y) != (b[1] > self.Y)
            with np.errstate(divide="ignore", invalid="ignore"):
                xi = (b[0] - a[0]) * (self.Y - a[1]) / (b[1] - a[1]) + a[0]
            inside ^= cond & (self.X < xi)
        return np.where(inside, -best, best)

    def axis(self, a, b):
        return self.seg(a, b)[1]

    def below(self, y):
        return self.Y - y

    def add(self, d, t, m, r=None, prof="round"):
        self.parts.append((d, t, m, r, prof))


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def union(a, b):
    return np.minimum(a, b)


def intersect(a, b):
    return np.maximum(a, b)


def bez(p0, c, p1, k):
    out = []
    for i in range(k):
        t = i / (k - 1)
        u = 1 - t
        out.append(p0 * (u * u) + c * (2 * u * t) + p1 * (t * t))
    return out


def band(p0, c, p1, w0, w1, k=14):
    pts = bez(p0, c, p1, k)
    left, right = [], []
    for i in range(k):
        tg = pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)]
        tg = norm(tg)
        nr = V(-tg[1], tg[0])
        w = (w0 + (w1 - w0) * i / (k - 1)) / 2
        left.append(pts[i] + nr * w)
        right.append(pts[i] - nr * w)
    return left + right[::-1]


def hashf(x, y, seed):
    x = x.astype(np.int64) & 0xFFFFFFFF
    y = y.astype(np.int64) & 0xFFFFFFFF
    h = (x * 0x8da6b343) & 0xFFFFFFFF
    h ^= (y * 0xd8163841) & 0xFFFFFFFF
    h ^= seed
    h ^= h >> 13
    h = (h * 0x5bd1e995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFFFF).astype(np.float32) / float(0x1000000)


def vnoise(X, Y, s, seed):
    fx, fy = X * s, Y * s
    x0, y0 = np.floor(fx), np.floor(fy)
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a, b = hashf(x0, y0, seed), hashf(x0 + 1, y0, seed)
    c, d = hashf(x0, y0 + 1, seed), hashf(x0 + 1, y0 + 1, seed)
    top = a + (b - a) * tx
    bot = c + (d - c) * tx
    return top + (bot - top) * ty


LIGHT = np.array([-0.55, -0.7, 0.75], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)


def env(ry):
    """Studio environment seen in a reflection (y down: ry < 0 looks up): bright sky, dark horizon band, mid ground."""
    up = np.clip(-ry, 0, 1)
    dn = np.clip(ry, 0, 1)
    sky = 0.55 + 0.45 * up ** 0.6
    hor = 1 - np.exp(-((ry + 0.08) ** 2) / 0.012)          # the dark horizon line just above the middle
    ground = 0.42 + 0.18 * dn
    v = np.where(ry < -0.08, sky, ground)
    return v * (1 - 0.55 * hor)


def shade(m, N, X, Y, T, H):
    kind, base, dark, light = MATS[m]
    ndl = np.maximum(0, N @ LIGHT)
    lam = (ndl * 0.85 + 0.15 + 0.12 * H)[..., None]          # lambert + a little height (raised parts read nearer)
    refl = N * (2 * (N @ LIGHT))[..., None] - LIGHT
    view_r = N * (2 * N[..., 2])[..., None] - np.array([0, 0, 1.0])    # view vector reflected (for the environment)
    rz = refl[..., 2]
    nx, ny, nz = N[..., 0], N[..., 1], N[..., 2]
    t = np.clip(lam, 0, 1.2)
    col = dark + (base - dark) * np.minimum(t, 1) + (light - base) * np.maximum(0, t - 1) * 2
    if kind in ("metal", "copper", "dusk"):
        e = env(view_r[..., 1])[..., None]
        refl_col = dark + (light - dark) * e
        col = col * 0.35 + refl_col * 0.65
        spec = np.maximum(0, rz) ** (40 if kind != "dusk" else 30)
        col = col + (np.array([1, 1, 1]) - col) * (spec * 0.9)[..., None]
        if kind == "copper":
            pat = vnoise(X, Y, 7, 11) * 0.7 + vnoise(X, Y, 23, 12) * 0.3
            k = np.clip((pat - 0.66) * 6, 0, 1)[..., None] * 0.75
            col = col * (1 - k) + np.array([0.33, 0.7, 0.6]) * (0.6 + 0.4 * lam) * k
        if kind == "dusk":
            rim = np.clip(1 - nz, 0, 1) * np.maximum(0, -nx - ny)
            col = col + np.array([0.5, 0.28, 0.8]) * (rim * 1.1)[..., None]
    elif kind == "gem":
        # Crystal: flat facets from a Voronoi-like cell field, each its own brightness, plus sparkles.
        cell = vnoise(X, Y, 9, 31)
        q = np.floor(cell * 6) / 6
        ang = np.arctan2(ny, nx)
        fq = np.round(ang / (math.pi / 3))
        facet = 0.5 + 0.35 * np.cos(fq * math.pi / 3 + 2.2) + (q - 0.5) * 0.35
        facet = np.where(np.sqrt(nx * nx + ny * ny) < 0.2, 0.72 + (q - 0.5) * 0.4, facet)
        col = dark + (light - dark) * np.clip(facet * (0.6 + 0.5 * lam[..., 0]), 0, 1)[..., None]
        spec = np.maximum(0, rz) ** 30
        col = col + (1 - col) * (spec * 0.9)[..., None]
        sp = (vnoise(X, Y, 48, 33) > 0.93)[..., None]
        col = np.where(sp, col + (1 - col) * 0.7, col)
    elif kind == "wood":
        g = 0.5 + 0.5 * np.sin(T * 70 + vnoise(X, Y, 8, 3) * 7)
        col = col * (0.84 + 0.22 * g)[..., None]
        spec = np.maximum(0, rz) ** 12
        col = col + (light - col) * (spec * 0.35)[..., None]
    elif kind == "stone":
        nn = vnoise(X, Y, 22, 7) * 0.65 + vnoise(X, Y, 60, 8) * 0.35
        col = col * (0.78 + 0.42 * nn)[..., None]
        chips = (vnoise(X, Y, 14, 9) > 0.8)[..., None]
        col = np.where(chips, col * 0.8, col)
    elif kind == "leather":
        col = col * (0.9 + 0.14 * vnoise(X, Y, 40, 5))[..., None]
        spec = np.maximum(0, rz) ** 10
        col = col + (light - col) * (spec * 0.25)[..., None]
    elif kind == "soft":
        spec = np.maximum(0, rz) ** 18
        col = col + (light - col) * (spec * 0.7)[..., None]
    elif kind == "chain":
        cx = X * 13
        cy = Y * 13 + 0.5 * np.mod(np.floor(X * 13), 2)
        rx = cx - np.floor(cx) - 0.5
        ry = cy - np.floor(cy) - 0.5
        rr = np.sqrt(rx * rx + ry * ry)
        ring = np.clip(1 - np.abs(rr - 0.3) / 0.13, 0, 1)
        e = env(view_r[..., 1])[..., None]
        metal = dark + (light - dark) * e
        col = col * 0.45 + metal * 0.55
        col = col * (0.62 + 0.5 * ring)[..., None] + (light - col) * (ring * (ry < -0.1) * 0.3)[..., None]
        col = col * (0.55 + 0.55 * np.clip(lam, 0, 1.2))
    return np.clip(col, 0, 1)


def shift(a, dx, dy, fill):
    out = np.full_like(a, fill)
    n = a.shape[0]
    out[dy:, dx:] = a[: n - dy, : n - dx]
    return out


def render(cv, bevel=0.03, split=False):
    n = cv.n
    tint = np.zeros((n, n), dtype=np.float32)
    aa = 1 / n
    ow = max(1.6 / n, 0.012)
    col = np.zeros((n, n, 3), dtype=np.float32)
    cov = np.zeros((n, n), dtype=np.float32)
    uni = np.full((n, n), 9.0, dtype=np.float32)
    for d, t, m, r, prof in cv.parts:
        r = r if r is not None else 0.06
        # Height: a sharp bevel at the rim plus a broad body: rounded (circle profile of radius r) or chamfered
        # (linear up to r: flat facets meeting at the medial axis, a blade's ridge).
        v = np.clip(-d / bevel, 0, 1)
        hb = v * v * (3 - 2 * v)
        w = np.clip(-d / r, 0, 1)
        hr = w if prof == "chamfer" else np.sqrt(np.maximum(0, 1 - (1 - w) ** 2))
        h = hb * 0.45 * bevel + hr * 0.55 * r
        hn = hb * 0.5 + hr * 0.5
        hp = np.pad(h, 1, mode="edge")
        gx = -(hp[1:-1, 2:] - hp[1:-1, :-2]) * n * 0.5
        gy = -(hp[2:, 1:-1] - hp[:-2, 1:-1]) * n * 0.5
        N = np.stack([gx * 1.6, gy * 1.6, np.ones_like(gx)], -1)
        N /= np.linalg.norm(N, axis=-1, keepdims=True)
        t = t if np.ndim(t) else np.zeros_like(d)
        c = shade(m, N, cv.X, cv.Y, t, hn)
        a = np.clip(0.5 - d / aa, 0, 1)
        # Contact shadow this part throws on what is already drawn (down-right, soft).
        so = max(1, int(round(0.018 * n)))
        sd = shift(d, so, so, 9.0)
        sa = np.clip(0.5 - sd / (aa * 5), 0, 1) * 0.45 * cov
        col = col * (1 - sa[..., None])
        # Thin dark seam where this part overlaps another (separates the pieces at TV distance).
        seam = np.clip(1 - np.abs(d + 0.6 * aa) / (1.1 * aa), 0, 1) * cov * 0.55
        col = col * (1 - a[..., None]) + c * a[..., None]
        col = col * (1 - seam[..., None])
        tint = tint * (1 - a) + (a if m == "tint" else 0)
        cov = np.maximum(cov, a)
        uni = np.minimum(uni, d)
    outline = np.array([0.05, 0.04, 0.06])
    sx, sy = int(round(0.02 * n)), int(round(0.03 * n))
    alpha = np.clip(0.5 - (uni - ow) / aa, 0, 1)
    inner = np.clip(0.5 - uni / aa, 0, 1)
    sh = np.zeros((n, n), dtype=np.float32)
    sh[sy:, sx:] = np.clip(0.5 - (uni[: n - sy, : n - sx] - ow) / (aa * 3), 0, 1) * 0.35
    rgb = outline * (1 - inner[..., None]) + col * inner[..., None]
    a = np.maximum(alpha, sh * (1 - alpha))
    rgb = np.where((alpha > 0)[..., None], rgb, 0)
    if split:
        # Base layer without the tinted parts, overlay layer with only them (drawn tinted on top).
        ov = np.concatenate([col, (tint * inner)[..., None]], -1)
        base = np.concatenate([rgb, np.where(alpha > 0, alpha * (1 - tint * inner), a)[..., None]], -1)
        return base, ov
    return np.concatenate([rgb, a[..., None]], -1)


# MARK: designs (mirror ItemHD.tool / armor / common)

def handle(cv, a, b, r=0.04, m="handle"):
    r = r * 1.2
    d, t = cv.capsule(a, b, r)
    cv.add(d, t, m, r)


def wraps(cv, a, b, r, k, m="grip"):
    """A leather-wrapped grip: k bands across the a->b handle."""
    dr = norm(b - a)
    nr = V(-dr[1], dr[0])
    ln = float(np.linalg.norm(b - a))
    for i in range(k):
        c = a + dr * (ln * (i + 0.5) / k)
        d, t = cv.capsule(c - nr * r * 0.9 - dr * (ln / k * 0.18), c + nr * r * 0.9 + dr * (ln / k * 0.18), r * 0.62)
        cv.add(d, t, m, r * 0.6)


def tool(cv, kind, head):
    accent = "golden" if head in ("diamond", "netherite") else ("handle" if head == "wood" else head)
    edge_m = "iron" if head in ("wood", "stone") else head
    up, rt = V(0.707, -0.707), V(0.707, 0.707)        # along the handle (toward the head), across it
    if kind == "sword":
        tip, g0 = V(0.9, 0.1), V(0.36, 0.64)
        dr = norm(tip - g0)
        ln = float(np.linalg.norm(tip - g0))
        nr = V(-dr[1], dr[0])
        w = 0.072
        blade = [g0 + nr * w, g0 + dr * (ln * 0.74) + nr * (w * 0.92), tip, g0 + dr * (ln * 0.74) - nr * (w * 0.92), g0 - nr * w]
        t = cv.axis(g0, tip)
        handle(cv, V(0.15, 0.85), V(0.37, 0.63), 0.036, "grip")
        wraps(cv, V(0.16, 0.84), V(0.34, 0.66), 0.036, 3)
        cv.add(cv.circle(V(0.12, 0.88), 0.052), t, accent, 0.05)
        bd = tier_shape(cv, cv.poly(blade), head)
        cv.add(bd, t, head, 0.09, "chamfer")
        guard(cv, head, accent, g0, dr, nr)
    elif kind == "pickaxe":
        top = V(0.66, 0.34)
        handle(cv, V(0.12, 0.9), top + up * 0.02, 0.038)
        ctrl1, ctrl2 = top - rt * 0.2 + up * 0.1, top + rt * 0.2 + up * 0.1
        e1, e2 = top - rt * 0.42 - up * 0.06, top + rt * 0.42 - up * 0.06
        d = union(cv.poly(band(top + up * 0.02, ctrl1, e1, 0.16, 0.03, 16)), cv.poly(band(top + up * 0.02, ctrl2, e2, 0.16, 0.03, 16)))
        t = cv.axis(e1, e2)
        cv.add(tier_shape(cv, d, head), t, head, 0.06, "chamfer")
        cd, ct = cv.capsule(top - rt * 0.05 + up * 0.02, top + rt * 0.05 + up * 0.02, 0.06)
        cv.add(cd, ct, accent if head != "wood" else "handle", 0.06)
        adorn(cv, head, top + up * 0.02, up, rt)
    elif kind == "axe":
        top = V(0.62, 0.3)
        handle(cv, V(0.16, 0.9), top + up * 0.06, 0.04)
        edge = bez(V(0.70, 0.02), V(1.0, 0.16), V(0.84, 0.56), 12)
        pts = [V(0.52, 0.24), V(0.6, 0.16)] + edge + [V(0.7, 0.44), V(0.6, 0.38)]
        d = cv.poly(pts)
        t = cv.axis(V(0.55, 0.3), V(0.95, 0.3))
        d = tier_shape(cv, d, head)
        cv.add(d, t, head, 0.05, "chamfer")
        inner = bez(V(0.73, 0.08), V(0.93, 0.19), V(0.81, 0.48), 12)
        strip = cv.poly(edge + inner[::-1])
        cv.add(intersect(strip, d + 0.004), t, edge_m, 0.03, "chamfer")
        # Butt (poll) behind the handle and the eye ring.
        cv.add(cv.poly([V(0.44, 0.22), V(0.52, 0.14), V(0.6, 0.22), V(0.52, 0.3)]), t, head, 0.04)
        cv.add(cv.circle(V(0.565, 0.255), 0.05), t, accent if head != "wood" else "handle", 0.05)
        adorn(cv, head, V(0.565, 0.255), up, rt)
    elif kind == "shovel":
        handle(cv, V(0.13, 0.9), V(0.62, 0.42), 0.036)
        cv.add(*cv.capsule(V(0.07, 0.86), V(0.19, 0.97), 0.032), "handle", 0.03)
        c = V(0.72, 0.29)
        pts = [c - up * 0.13 + rt * 0.12]
        pts += bez(c + rt * 0.16, c + up * 0.2 + rt * 0.15, c + up * 0.28, 7)
        pts += bez(c + up * 0.28, c + up * 0.2 - rt * 0.15, c - rt * 0.16, 7)
        pts.append(c - up * 0.13 - rt * 0.12)
        bd = tier_shape(cv, cv.poly(pts), head)
        cv.add(bd, cv.axis(V(0.6, 0.4), V(0.9, 0.1)), head, 0.08)
        cv.add(intersect(cv.capsule(c - up * 0.12, c + up * 0.14, 0.012)[0], bd + 0.02), cv.axis(V(0.6, 0.4), V(0.9, 0.1)), head, 0.012)
        cd, ct = cv.capsule(c - up * 0.17, c - up * 0.1, 0.045)
        cv.add(cd, ct, accent if head != "wood" else "handle", 0.045)
        adorn(cv, head, c - up * 0.135, up, rt)
    elif kind == "hoe":
        top = V(0.68, 0.26)
        handle(cv, V(0.14, 0.9), top, 0.036)
        bd, bt = cv.capsule(top + V(0.02, -0.01), V(0.42, 0.14), 0.04)
        cv.add(bd, bt, head, 0.04)
        blade = cv.poly([V(0.27, 0.06), V(0.48, 0.09), V(0.46, 0.25), V(0.32, 0.52), V(0.16, 0.46), V(0.25, 0.22)])
        blade = tier_shape(cv, blade, head)
        cv.add(blade, cv.axis(V(0.38, 0.08), V(0.26, 0.45)), head, 0.06, "chamfer")
        cv.add(intersect(cv.capsule(V(0.16, 0.46), V(0.32, 0.52), 0.035)[0], blade + 0.004), bt, edge_m, 0.02, "chamfer")
        cv.add(cv.circle(top, 0.05), bt, accent if head != "wood" else "handle", 0.05)
        adorn(cv, head, top, up, rt)
    else:
        b0 = V(0.68, 0.32)
        handle(cv, V(0.07, 0.95), b0, 0.03)
        tip = V(0.95, 0.05)
        b0 = V(0.6, 0.4)
        sides1 = bez(b0, b0 + up * 0.1 + rt * 0.16, tip, 10)
        sides2 = bez(tip, b0 + up * 0.1 - rt * 0.16, b0, 10)
        cv.add(tier_shape(cv, cv.poly(sides1 + sides2[1:-1]), head), cv.axis(b0, tip), head, 0.06, "chamfer")
        lug = cv.capsule(b0 - rt * 0.07, b0 + rt * 0.07, 0.022)
        cv.add(lug[0], lug[1], accent if head != "wood" else "handle", 0.02)
        wraps(cv, b0 - up * 0.14, b0 - up * 0.02, 0.032, 3)


def tier_shape(cv, d, head):
    """Tier silhouettes: stone heads knapped (a rough, chipped outline); the others clean."""
    if head == "stone":
        return d + (vnoise(cv.X, cv.Y, 13, 5) - 0.5) * 0.024
    return d


def adorn(cv, head, c, up, rt):
    """Tier details at the head's socket: stone lashed on with cord, gold set with a ruby, copper riveted, duskium
    spiked; wood, iron and diamond plain."""
    zero = np.zeros_like(cv.X)
    if head == "stone":
        for o in (-0.022, 0.022):
            a, b = c - rt * 0.07 + up * (o - 0.03), c + rt * 0.07 + up * (o + 0.03)
            cv.add(cap(cv, a, b, 0.017), zero, M("leather", 0xA88A5A), 0.017)
    elif head == "golden":
        cv.add(cv.circle(c, 0.032), zero, M("gem", 0xE0303A), 0.03)
    elif head == "copper":
        for o in (-0.045, 0.045):
            cv.add(cv.circle(c + rt * o, 0.016), zero, "iron", 0.016)
    elif head == "netherite":
        tip = c - up * 0.02 - rt * 0.17
        cv.add(cv.poly([c - rt * 0.05 + up * 0.03, tip, c - rt * 0.05 - up * 0.05]), zero, head, 0.03, "chamfer")


def guard(cv, head, accent, g0, dr, nr):
    """A sword's crossguard, shaped by tier."""
    zero = np.zeros_like(cv.X)
    if head == "wood":
        d, t = cv.capsule(g0 - nr * 0.11, g0 + nr * 0.11, 0.032)
        cv.add(d, t, "handle", 0.03)
    elif head == "stone":
        d = cv.poly([g0 - nr * 0.14 - dr * 0.04, g0 + nr * 0.14 - dr * 0.04, g0 + nr * 0.14 + dr * 0.035, g0 - nr * 0.14 + dr * 0.035])
        cv.add(tier_shape(cv, d, "stone"), zero, "stone", 0.04, "chamfer")
        adorn(cv, "stone", g0 - dr * 0.08, dr, nr)
    elif head == "golden":
        for sg in (-1, 1):
            cv.add(cv.poly(band(g0, g0 + nr * (0.12 * sg), g0 + nr * (0.17 * sg) + dr * 0.08, 0.06, 0.025, 10)), zero, "golden", 0.03)
        cv.add(cv.circle(g0, 0.045), zero, "golden", 0.04)
        cv.add(cv.circle(g0, 0.026), zero, M("gem", 0xE0303A), 0.025)
    elif head == "diamond":
        cv.add(cv.poly([g0 - nr * 0.18, g0 - dr * 0.05, g0 + nr * 0.18, g0 + dr * 0.06]), zero, "golden", 0.04, "chamfer")
        cv.add(cv.poly([g0 - nr * 0.05, g0 - dr * 0.025, g0 + nr * 0.05, g0 + dr * 0.03]), zero, "diamond", 0.02, "chamfer")
    elif head == "netherite":
        for sg in (-1, 1):
            cv.add(cv.poly([g0 - dr * 0.035, g0 + nr * (0.2 * sg) + dr * 0.07, g0 + dr * 0.035]), zero, "netherite", 0.03, "chamfer")
        cv.add(cv.circle(g0, 0.04), zero, "golden", 0.04)
    elif head == "copper":
        cv.add(cv.ellipse(g0, 0.1, 0.1), zero, "copper", 0.05)
        cv.add(cv.circle(g0, 0.03), zero, "iron", 0.03)
    else:
        gd, gt = cv.capsule(g0 - nr * 0.15, g0 + nr * 0.15, 0.03)
        gd = union(gd, union(cv.circle(g0 - nr * 0.15, 0.042), cv.circle(g0 + nr * 0.15, 0.042)))
        cv.add(gd, gt, accent, 0.04)
        cv.add(cv.circle(g0, 0.04), gt, accent, 0.04)


def armor(cv, kind, m):
    ys, xs = cv.axis(V(0.5, 0), V(0.5, 1)), cv.axis(V(0, 0.5), V(1, 0.5))
    soft = m in ("leather", "turtle")
    trim = "golden" if m in ("diamond", "netherite") else m
    if kind == "helmet":
        d = intersect(cv.circle(V(0.5, 0.58), 0.37), cv.below(0.64))
        cheeks = union(cv.poly([V(0.13, 0.56), V(0.31, 0.56), V(0.31, 0.88), V(0.19, 0.86)]),
                       cv.poly([V(0.69, 0.56), V(0.87, 0.56), V(0.81, 0.86), V(0.69, 0.88)]))
        d = union(d, cheeks)
        if not soft:
            d = intersect(d, -cv.poly([V(0.33, 0.58), V(0.67, 0.58), V(0.65, 0.66), V(0.35, 0.66)]))
        cv.add(d, ys, m, 0.3)
        cv.add(intersect(cv.capsule(V(0.15, 0.56), V(0.85, 0.56), 0.032)[0], d), xs, trim, 0.03)
        if not soft:
            cv.add(cv.capsule(V(0.5, 0.2), V(0.5, 0.52), 0.026)[0], ys, trim, 0.026)
            cv.add(cv.capsule(V(0.5, 0.56), V(0.5, 0.74), 0.03)[0], ys, m, 0.03)
            for x in (0.22, 0.78):
                cv.add(cv.circle(V(x, 0.7), 0.022), ys, trim, 0.02)
        elif m == "turtle":
            for c in (V(0.5, 0.36), V(0.34, 0.44), V(0.66, 0.44)):
                hexp = [c + V(math.cos(a) * 0.09, math.sin(a) * 0.09) for a in np.arange(6) * math.pi / 3]
                cv.add(intersect(abs(cv.poly(hexp)) - 0.012, d + 0.02), ys, M("leather", 0x2A5A22), 0.012)
        else:
            cv.add(intersect(cv.capsule(V(0.2, 0.4), V(0.8, 0.4), 0.006)[0], d + 0.03), xs, "grip", 0.006)
            cv.add(cap(cv, V(0.1, 0.58), V(0.9, 0.58), 0.035), xs, M("leather", 0x6A3E20), 0.035)
            cv.add(cap(cv, V(0.24, 0.6), V(0.4, 0.9), 0.016), ys, "grip", 0.016)
            cv.add(cv.circle(V(0.4, 0.9), 0.025), ys, "iron", 0.02)
    elif kind == "chestplate":
        torso = cv.poly([V(0.26, 0.2), V(0.4, 0.16), V(0.5, 0.28), V(0.6, 0.16), V(0.74, 0.2), V(0.76, 0.86), V(0.5, 0.92), V(0.24, 0.86)])
        cv.add(torso, ys, m, 0.3) if soft else cv.add(torso, ys, m, 0.12, "chamfer")
        cv.add(cv.poly(band(V(0.1, 0.44), V(0.11, 0.16), V(0.36, 0.16), 0.14, 0.11, 10)), xs, m, 0.07)
        cv.add(cv.poly(band(V(0.9, 0.44), V(0.89, 0.16), V(0.64, 0.16), 0.14, 0.11, 10)), xs, m, 0.07)
        cv.add(intersect(cv.poly(band(V(0.36, 0.17), V(0.5, 0.4), V(0.64, 0.17), 0.04, 0.04, 12)), torso + 0.0), xs, trim, 0.03)
        if not soft:
            cv.add(intersect(cv.capsule(V(0.5, 0.36), V(0.5, 0.86), 0.012)[0], torso + 0.03), ys, m, 0.012)
        for yy in (0.62, 0.76):
            cv.add(intersect(cv.capsule(V(0.24, yy), V(0.76, yy), 0.016)[0], torso), xs, trim if not soft else "grip", 0.016)
    elif kind == "leggings":
        d = cv.poly([V(0.22, 0.14), V(0.78, 0.14), V(0.82, 0.9), V(0.6, 0.9), V(0.5, 0.42), V(0.4, 0.9), V(0.18, 0.9)])
        cv.add(d, ys, m, 0.2) if soft else cv.add(d, ys, m, 0.1, "chamfer")
        cv.add(intersect(cv.capsule(V(0.2, 0.2), V(0.8, 0.2), 0.045)[0], d), xs, trim if not soft else "grip", 0.04)
        if not soft:
            for c in (V(0.3, 0.6), V(0.7, 0.6)):
                cv.add(intersect(cv.ellipse(c, 0.08, 0.07), d + 0.02), ys, trim, 0.06)
    else:
        for k, (ox, oy) in enumerate(((0.0, 0.0), (0.3, 0.1))):
            o = V(ox, oy)
            shaft = cv.poly([V(0.14, 0.18) + o, V(0.38, 0.18) + o, V(0.38, 0.56) + o, V(0.14, 0.62) + o])
            foot = union(cv.capsule(V(0.2, 0.7) + o, V(0.5, 0.7) + o, 0.1)[0], cv.poly([V(0.14, 0.5) + o, V(0.38, 0.5) + o, V(0.4, 0.78) + o, V(0.12, 0.8) + o]))
            d = union(shaft, intersect(foot, cv.below(0.8 + oy)))
            cv.add(d, ys, m, 0.12)
            cv.add(intersect(cv.capsule(V(0.1, 0.78) + o, V(0.62, 0.78) + o, 0.03)[0], d + 0.01), xs, "grip" if soft else trim, 0.02)
            cv.add(intersect(cv.capsule(V(0.12, 0.22) + o, V(0.4, 0.22) + o, 0.04)[0], d + 0.015), xs, trim if not soft else "grip", 0.035)


def item_names():
    names = []
    for k in TOOLS:
        for t in TIERS:
            names.append(f"{t}_{k}")
    for k in ARMOR:
        for a in ARMOR_SETS:
            names.append(f"{a}_{k}")
    return names


def design(name):
    for t in TIERS:
        for k in TOOLS:
            if name == f"{t}_{k}":
                return ("tool", k, "wood" if t == "wooden" else t)
    for a in ARMOR_SETS:
        for k in ARMOR:
            if name == f"{a}_{k}":
                return ("armor", k, a)
    return None


def draw(name, n):
    cv = Canvas(n)
    ds = design(name)
    if ds is None:
        return None
    if ds[0] == "tool":
        tool(cv, ds[1], ds[2])
    else:
        armor(cv, ds[1], ds[2])
    return render(cv)


def sheet(names, n, scale, bg, cols=7):
    cell = n * scale + 8
    rows = (len(names) + cols - 1) // cols
    out = np.zeros((rows * cell + 8, cols * cell + 8, 3), dtype=np.float32)
    out[:] = np.array([0.12, 0.13, 0.16] if bg == "dark" else [0.55, 0.55, 0.58])
    for i, nm in enumerate(names):
        img = draw(nm, n)
        if img is None:
            continue
        if scale != 1:
            img = np.kron(img, np.ones((scale, scale, 1)))
        y0, x0 = 8 + (i // cols) * cell, 8 + (i % cols) * cell
        slot = out[y0:y0 + n * scale, x0:x0 + n * scale]
        slot[:] = slot * 0.85 + 0.03
        a = img[..., 3:4]
        slot[:] = slot * (1 - a) + img[..., :3] * a
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


# MARK: pixel art upscale (mirror ItemHD.upscaled)

def same(a, b):
    ta, tb = a[..., 3] < 0.5, b[..., 3] < 0.5
    d = np.abs(a[..., :3] - b[..., :3]).sum(-1) < 0.09
    return np.where(ta & tb, True, np.where(ta != tb, False, d))


def scale2x(s):
    n = s.shape[0]
    z = np.zeros_like(s[:1])
    A = np.concatenate([np.zeros_like(s[:1]), s[:-1]], 0)            # up
    D = np.concatenate([s[1:], np.zeros_like(s[:1])], 0)             # down
    C = np.concatenate([np.zeros_like(s[:, :1]), s[:, :-1]], 1)      # left
    B = np.concatenate([s[:, 1:], np.zeros_like(s[:, :1])], 1)       # right
    o = np.zeros((2 * n, 2 * n, 4), dtype=s.dtype)
    ca, cd, ab, bd, dc = same(C, A), same(C, D), same(A, B), same(B, D), same(D, C)
    o[0::2, 0::2] = np.where((ca & ~cd & ~ab)[..., None], A, s)
    o[0::2, 1::2] = np.where((ab & ~ca & ~bd)[..., None], B, s)
    o[1::2, 0::2] = np.where((dc & ~bd & ~ca)[..., None], C, s)
    o[1::2, 1::2] = np.where((bd & ~ab & ~dc)[..., None], D, s)
    return o


def chamfer(mask):
    """Approximate Euclidean distance (pixels) from each pixel to the nearest pixel where mask is False."""
    n = mask.shape[0]
    big = 1e4
    d = np.where(mask, big, 0.0).astype(np.float32)
    a, b = 1.0, 1.4142
    for y in range(n):
        if y > 0:
            d[y] = np.minimum(d[y], d[y - 1] + a)
            d[y, 1:] = np.minimum(d[y, 1:], d[y - 1, :-1] + b)
            d[y, :-1] = np.minimum(d[y, :-1], d[y - 1, 1:] + b)
        for x in range(1, n):
            d[y, x] = min(d[y, x], d[y, x - 1] + a)
    for y in range(n - 1, -1, -1):
        if y < n - 1:
            d[y] = np.minimum(d[y], d[y + 1] + a)
            d[y, 1:] = np.minimum(d[y, 1:], d[y + 1, :-1] + b)
            d[y, :-1] = np.minimum(d[y, :-1], d[y + 1, 1:] + b)
        for x in range(n - 2, -1, -1):
            d[y, x] = min(d[y, x], d[y, x + 1] + a)
    return d


def upscaled(src, n=128):
    img = src.copy()
    while img.shape[0] * 2 <= n:
        img = scale2x(img)
    m = img[..., 3] >= 0.5
    # Soften the big pixel blocks inside the shape (a masked box blur mixed in), keeping the silhouette crisp.
    rr = max(1, n // 48)
    acc = np.zeros_like(img[..., :3]); wsum = np.zeros(img.shape[:2], np.float32)
    mp = np.pad(m.astype(np.float32), rr); cp = np.pad(img[..., :3] * m[..., None], ((rr, rr), (rr, rr), (0, 0)))
    for dy in range(-rr, rr + 1):
        for dx in range(-rr, rr + 1):
            acc += cp[rr + dy: rr + dy + n, rr + dx: rr + dx + n]
            wsum += mp[rr + dy: rr + dy + n, rr + dx: rr + dx + n]
    blur = acc / np.maximum(wsum, 1e-6)[..., None]
    img = img.copy()
    img[..., :3] = np.where(m[..., None], img[..., :3] * 0.5 + blur * 0.5, img[..., :3])
    din = chamfer(m)                 # inside: distance to the edge
    dout = chamfer(~m)               # outside: distance to the shape
    sd = np.where(m, -(din - 0.5), dout - 0.5) / n      # signed distance, icon units
    # Height: bevel + rounded body, as the vector parts.
    bevel, r = 0.03, 0.07
    v = np.clip(-sd / bevel, 0, 1)
    hb = v * v * (3 - 2 * v)
    w = np.clip(-sd / r, 0, 1)
    hr = np.sqrt(np.maximum(0, 1 - (1 - w) ** 2))
    h = hb * 0.45 * bevel + hr * 0.55 * r
    hp = np.pad(h, 1, mode="edge")
    k = n * 0.5 * 1.6
    gx = -(hp[1:-1, 2:] - hp[1:-1, :-2]) * k
    gy = -(hp[2:, 1:-1] - hp[:-2, 1:-1]) * k
    N = np.stack([gx, gy, np.ones_like(gx)], -1)
    N /= np.linalg.norm(N, axis=-1, keepdims=True)
    ndl = np.maximum(0, N @ LIGHT)
    flat = LIGHT[2] * 0.85 + 0.15
    f = np.clip((ndl * 0.85 + 0.15) / flat, 0.5, 1.35)
    refl = N * (2 * (N @ LIGHT))[..., None] - LIGHT
    spec = np.maximum(0, refl[..., 2]) ** 18 * 0.3
    rgb = np.clip(img[..., :3] * f[..., None] + spec[..., None], 0, 1)
    aa = 1 / n
    ow = max(1.6 / n, 0.012)
    alpha = np.clip(0.5 - (sd - ow) / aa, 0, 1)
    inner = np.clip(0.5 - sd / aa, 0, 1)
    outline = np.array([0.05, 0.04, 0.06])
    rgb = outline * (1 - inner[..., None]) + rgb * inner[..., None]
    sx, sy = int(round(0.02 * n)), int(round(0.03 * n))
    sh = np.zeros((n, n), dtype=np.float32)
    sh[sy:, sx:] = np.clip(0.5 - (sd[: n - sy, : n - sx] - ow) / (aa * 3), 0, 1) * 0.35
    a = np.maximum(alpha, sh * (1 - alpha))
    rgb = np.where((alpha > 0)[..., None], rgb, 0)
    return np.concatenate([rgb, a[..., None]], -1)


def art_sheet(arts, n, scale, cols, out):
    cell = n * scale + 8
    rows = (len(arts) + cols - 1) // cols
    o = np.zeros((rows * cell + 8, cols * cell + 8, 3), dtype=np.float32)
    o[:] = np.array([0.12, 0.13, 0.16])
    for i, art in enumerate(arts):
        img = art if art.shape[0] == n else upscaled(art, n)
        if scale != 1:
            img = np.kron(img, np.ones((scale, scale, 1)))
        y0, x0 = 8 + (i // cols) * cell, 8 + (i % cols) * cell
        slot = o[y0:y0 + n * scale, x0:x0 + n * scale]
        slot[:] = slot * 0.85 + 0.03
        a = img[..., 3:4]
        slot[:] = slot * (1 - a) + img[..., :3] * a
    Image.fromarray((np.clip(o, 0, 1) * 255).astype(np.uint8)).save(out)


# MARK: families (mirror ItemHD.family): designs per Sprite mask, coloured by the sprite's base / extras

def dynmat(spec):
    """'kind:RRGGBB' -> a material with dark / light derived from the base colour."""
    kind, hx = spec.split(":")
    base = hexc(int(hx, 16))
    dark = base * 0.42 + np.array([0.01, 0.0, 0.03], dtype=np.float32)
    light = base + (1 - base) * 0.6
    return (kind, base, dark, light)


_orig_shade = shade


def shade(m, N, X, Y, T, H):  # noqa: F811
    if m not in MATS and ":" in m:
        MATS[m] = dynmat(m)
    return _orig_shade(m, N, X, Y, T, H)


def darker(h, k):
    r, g, b = (h >> 16) & 255, (h >> 8) & 255, h & 255
    return (int(r * k) << 16) | (int(g * k) << 8) | int(b * k)


def lighter(h, k):
    r, g, b = (h >> 16) & 255, (h >> 8) & 255, h & 255
    f = lambda c: int(c + (255 - c) * k)
    return (f(r) << 16) | (f(g) << 8) | f(b)


def soft_light(h):
    return M("soft", lighter(h, 0.35))


def emblem(cv, name, c, r, m):
    """A small motif chosen by the item's name (sherds, templates, banner patterns): one of eight shapes."""
    k = sum(ord(ch) * (i + 1) for i, ch in enumerate(name)) % 8
    zero = np.zeros_like(cv.X)
    if k == 0:
        cv.add(abs(cv.circle(c, r)) - r * 0.22, zero, m, r * 0.2)
    elif k == 1:
        cv.add(cv.poly([c + V(0, -r), c + V(r, 0), c + V(0, r), c + V(-r, 0)]), zero, m, r * 0.4, "chamfer")
    elif k == 2:
        pts = [c + V(math.cos(a) * (r if i % 2 == 0 else r * 0.45), math.sin(a) * (r if i % 2 == 0 else r * 0.45)) for i, a in enumerate(np.arange(10) * math.pi / 5 - math.pi / 2)]
        cv.add(cv.poly(pts), zero, m, r * 0.4, "chamfer")
    elif k == 3:
        cv.add(union(cap(cv, c - V(r, 0), c + V(r, 0), r * 0.25), cap(cv, c - V(0, r), c + V(0, r), r * 0.25)), zero, m, r * 0.2)
    elif k == 4:
        cv.add(cv.poly([c + V(0, -r), c + V(r, r * 0.8), c + V(-r, r * 0.8)]), zero, m, r * 0.4, "chamfer")
    elif k == 5:
        cv.add(smin(cv.circle(c + V(-r * 0.45, -r * 0.2), r * 0.5), smin(cv.circle(c + V(r * 0.45, -r * 0.2), r * 0.5), cv.poly([c + V(-r * 0.9, 0), c + V(r * 0.9, 0), c + V(0, r)]), 0.02), 0.02), zero, m, r * 0.4)
    elif k == 6:
        cv.add(cv.poly(band(c + V(-r, r * 0.5), c + V(0, -r * 1.2), c + V(r, r * 0.5), r * 0.4, r * 0.4, 10)), zero, m, r * 0.2)
    else:
        for dx in (-0.5, 0.5):
            cv.add(cv.circle(c + V(dx * r, 0), r * 0.42), zero, m, r * 0.3)


def M(kind, h):
    return f"{kind}:{h:06X}"


def ys_xs(cv):
    return cv.axis(V(0.5, 0), V(0.5, 1)), cv.axis(V(0, 0.5), V(1, 0.5))


def cap(cv, a, b, r):
    return cv.capsule(a, b, r)[0]


def rot(p, c, ang):
    s, co = math.sin(ang), math.cos(ang)
    q = p - c
    return c + V(q[0] * co - q[1] * s, q[0] * s + q[1] * co)


def family(cv, name, mask, base, ex):
    ys, xs = ys_xs(cv)
    if mask == "ingot":
        brick = "brick" in name
        m = METAL_BY_NAME.get(name.split("_")[0], M("stone" if brick else "metal", base))
        # A bar in three-quarter view: a bright sloped top, a darker front, a lit end.
        top = cv.poly([V(0.28, 0.38), V(0.68, 0.29), V(0.8, 0.36), V(0.42, 0.46)])
        front = cv.poly([V(0.42, 0.46), V(0.8, 0.36), V(0.92, 0.56), V(0.44, 0.72)])
        end = cv.poly([V(0.28, 0.38), V(0.42, 0.46), V(0.44, 0.72), V(0.12, 0.56)])
        cv.add(end, xs, m, 0.03, "chamfer")
        cv.add(front, xs, m, 0.03, "chamfer")
        cv.add(top, xs, m, 0.03, "chamfer")
        if not brick:
            cv.add(cv.poly(band(V(0.4, 0.38), V(0.52, 0.35), V(0.68, 0.33), 0.022, 0.01, 8)), xs, M("soft", 0xFFFFFF), 0.01)
    elif mask == "nugget":
        m = METAL_BY_NAME.get(name.split("_")[0], M("metal", base))
        for c, r in ((V(0.36, 0.6), 0.15), (V(0.62, 0.66), 0.13), (V(0.52, 0.4), 0.12)):
            pts = [c + V(math.cos(a) * r * (1 + 0.18 * math.sin(a * 3 + c[0] * 9)), math.sin(a) * r) for a in np.linspace(0, 2 * math.pi, 9)[:-1]]
            cv.add(cv.poly(pts), ys, m, 0.08, "chamfer")
    elif mask == "lump":
        kind = "stone" if name in ("coal", "charcoal", "flint", "netherite_scrap") else "stone"
        m = M(kind, base)
        pts = [V(0.22, 0.34), V(0.4, 0.2), V(0.62, 0.22), V(0.8, 0.36), V(0.84, 0.58), V(0.7, 0.8), V(0.42, 0.84), V(0.2, 0.68)]
        d = cv.poly(pts)
        cv.add(d, ys, m, 0.2, "chamfer")
        if name.startswith("raw_"):
            mm = METAL_BY_NAME.get(name[4:], M("metal", base))
            for c, r, a in ((V(0.4, 0.42), 0.08, 0.3), (V(0.63, 0.58), 0.07, 1.2), (V(0.38, 0.67), 0.06, 2.0)):
                pts = [c + V(math.cos(t + a) * r * (1 + 0.3 * math.sin(t * 2 + a)), math.sin(t + a) * r * 0.8) for t in np.linspace(0, 2 * math.pi, 8)[:-1]]
                cv.add(intersect(cv.poly(pts), d + 0.03), ys, mm, 0.05, "chamfer")
    elif mask == "gem":
        gem(cv, name, base, ys, xs)
    elif mask == "dust":
        m = M("soft", base)
        # A lumpy heap of three mounds.
        mound = smin(smin(cv.circle(V(0.36, 0.78), 0.22), cv.circle(V(0.62, 0.76), 0.24), 0.08), cv.circle(V(0.5, 0.6), 0.2), 0.08)
        heap = intersect(mound, cv.below(0.84))
        cv.add(heap, ys, m, 0.12)
    elif mask == "ball":
        m = M("gem" if name == "heart_of_the_sea" else "soft", base)
        d = cv.circle(V(0.5, 0.54), 0.31)
        cv.add(d, ys, m, 0.31)
        if name == "slime_ball":
            cv.add(cv.circle(V(0.55, 0.6), 0.13), ys, M("soft", darker(base, 0.6)), 0.13)
        if name == "magma_cream":
            cv.add(intersect(cv.poly(band(V(0.28, 0.56), V(0.5, 0.3), V(0.72, 0.56), 0.06, 0.06, 12)), d), ys, M("soft", 0xF8C030), 0.03)
        if name == "wind_charge":
            cv.add(intersect(cv.poly(band(V(0.3, 0.64), V(0.5, 0.2), V(0.72, 0.5), 0.05, 0.02, 12)), d + 0.02), ys, M("soft", 0xF4F8FF), 0.03)
    elif mask == "seeds":
        m = M("soft", base)
        for i, (x, y, a) in enumerate(((0.32, 0.36, 0.5), (0.58, 0.3, -0.4), (0.7, 0.56, 0.9), (0.42, 0.6, -0.2), (0.28, 0.78, 0.3), (0.58, 0.8, -0.8))):
            c = V(x, y)
            e = [c + V(math.cos(t) * 0.09 * math.cos(a) - math.sin(t) * 0.055 * math.sin(a), math.cos(t) * 0.09 * math.sin(a) + math.sin(t) * 0.055 * math.cos(a)) for t in np.linspace(0, 2 * math.pi, 13)[:-1]]
            cv.add(cv.poly(e), ys, m, 0.05)
    elif mask == "egg":
        cv.add(cv.ellipse(V(0.5, 0.55), 0.27, 0.35), ys, M("soft", base), 0.3)
        dots = darker(base, 0.75)
        for c in (V(0.42, 0.4), V(0.6, 0.5), V(0.46, 0.66), V(0.62, 0.72), V(0.36, 0.56)):
            cv.add(intersect(cv.circle(c, 0.026), cv.ellipse(V(0.5, 0.55), 0.24, 0.32)), ys, M("soft", dots), 0.02)
    elif mask == "bucket":
        bucket(cv, name, ex, xs)
    elif mask == "bottle":
        bottle(cv, base, ex.get("c"), ys, xs)
    elif mask == "fish":
        m = M("soft", base)
        body = cv.ellipse(V(0.46, 0.52), 0.3, 0.17)
        tail = cv.poly([V(0.72, 0.52), V(0.92, 0.34), V(0.88, 0.52), V(0.92, 0.7)])
        cv.add(tail, xs, m, 0.05)
        cv.add(body, xs, m, 0.17)
        cv.parts.insert(0, (cv.poly([V(0.34, 0.42), V(0.48, 0.26), V(0.62, 0.4)]), xs, M("soft", darker(base, 0.8)), 0.03, "round"))
        cv.add(cv.circle(V(0.27, 0.48), 0.035), xs, M("soft", 0x18181C), 0.03)
        cv.add(intersect(cap(cv, V(0.3, 0.6), V(0.64, 0.58), 0.012), body + 0.03), xs, M("soft", lighter(base, 0.4)), 0.01)
    elif not family2(cv, name, mask, base, ex, ys, xs):
        return False
    return True


METAL_BY_NAME = {"iron": "iron", "gold": "golden", "copper": "copper", "netherite": "netherite"}


def gem(cv, name, base, ys, xs):
    m = M("gem", base)
    if name == "diamond":
        pts = [V(0.28, 0.2), V(0.72, 0.2), V(0.9, 0.4), V(0.5, 0.9), V(0.1, 0.4)]
        d = cv.poly(pts)
        cv.add(d, ys, m, 0.1, "chamfer")
        cv.add(cv.poly([V(0.28, 0.2), V(0.72, 0.2), V(0.62, 0.4), V(0.38, 0.4)]), ys, m, 0.06, "chamfer")
    elif name == "emerald":
        pts = [V(0.5, 0.08), V(0.78, 0.26), V(0.78, 0.7), V(0.5, 0.92), V(0.22, 0.7), V(0.22, 0.26)]
        cv.add(cv.poly(pts), ys, m, 0.12, "chamfer")
        cv.add(cv.poly([V(0.5, 0.24), V(0.64, 0.34), V(0.64, 0.62), V(0.5, 0.74), V(0.36, 0.62), V(0.36, 0.34)]), ys, m, 0.06, "chamfer")
    elif name == "lapis_lazuli":
        pts = [V(0.24, 0.3), V(0.5, 0.18), V(0.8, 0.32), V(0.78, 0.66), V(0.5, 0.84), V(0.2, 0.68)]
        d = cv.poly(pts)
        cv.add(d, ys, M("stone", base), 0.14, "chamfer")
        for c in (V(0.4, 0.4), V(0.6, 0.6), V(0.38, 0.64)):
            cv.add(intersect(cv.circle(c, 0.035), d + 0.05), ys, M("metal", 0xE8C040), 0.03)
    else:
        # Crystal shards: two or three hexagonal prisms with pointed tips.
        for (a, b, w) in ((V(0.3, 0.86), V(0.42, 0.14), 0.13), (V(0.56, 0.86), V(0.76, 0.3), 0.11), (V(0.3, 0.86), V(0.18, 0.42), 0.08)):
            dr = norm(b - a)
            nr = V(-dr[1], dr[0])
            ln = float(np.linalg.norm(b - a))
            pts = [a + nr * w / 2, a + dr * ln * 0.78 + nr * w / 2, b, a + dr * ln * 0.78 - nr * w / 2, a - nr * w / 2]
            cv.add(cv.poly(pts), cv.axis(a, b), m, w / 2, "chamfer")


def bucket(cv, name, ex, xs):
    iron = "iron"
    body = cv.poly([V(0.2, 0.38), V(0.8, 0.38), V(0.72, 0.86), V(0.28, 0.86)])
    cv.add(intersect(abs(cv.ellipse(V(0.5, 0.38), 0.33, 0.3)) - 0.014, cv.below(0.38)), xs, iron, 0.014)   # the handle
    cv.add(body, xs, iron, 0.22)
    for yy in (0.52, 0.74):
        cv.add(intersect(cap(cv, V(0.18, yy), V(0.82, yy), 0.012), body), xs, iron, 0.012)
    rim = abs(cv.ellipse(V(0.5, 0.38), 0.3, 0.075)) - 0.016
    c = ex.get("c", 0x5A5A5A)
    if name == "bucket":
        cv.add(cv.ellipse(V(0.5, 0.38), 0.29, 0.065), xs, M("soft", 0x3A3A40), 0.03)
    elif name in ("water_bucket", "lava_bucket", "milk_bucket", "powder_snow_bucket"):
        cv.add(cv.ellipse(V(0.5, 0.38), 0.29, 0.065), xs, M("soft", c), 0.03)
    else:
        cv.add(cv.ellipse(V(0.5, 0.38), 0.29, 0.065), xs, M("soft", 0x3F76E4), 0.03)
        fish = union(cv.ellipse(V(0.46, 0.26), 0.17, 0.1), cv.poly([V(0.6, 0.26), V(0.76, 0.12), V(0.74, 0.36)]))
        cv.add(intersect(fish, cv.below(0.4)), xs, M("soft", c), 0.08)
        cv.add(cv.circle(V(0.36, 0.23), 0.022), xs, M("soft", 0x101014), 0.02)
    cv.add(rim, xs, iron, 0.016)


def bottle(cv, base, liquid, ys, xs):
    glass = M("soft", 0xC8D8EE)
    body = union(cv.circle(V(0.5, 0.62), 0.27), cap(cv, V(0.5, 0.2), V(0.5, 0.45), 0.08))
    cv.add(body, ys, glass, 0.25)
    if liquid is not None:
        cv.add(intersect(cv.circle(V(0.5, 0.62), 0.23), -cv.below(0.52)), ys, M("soft", liquid), 0.2)
    cv.add(cap(cv, V(0.42, 0.22), V(0.58, 0.22), 0.03), ys, glass, 0.03)
    cv.add(cv.poly([V(0.43, 0.08), V(0.57, 0.08), V(0.56, 0.2), V(0.44, 0.2)]), ys, M("wood", 0xA87A4A), 0.04)
    # Glass highlight.
    cv.add(intersect(cv.poly(band(V(0.34, 0.74), V(0.3, 0.56), V(0.4, 0.44), 0.04, 0.02, 10)), body + 0.03), ys, M("soft", 0xFFFFFF), 0.02)


def catalogue():
    import re
    src = open("Sources/Items.swift").read()
    out = []
    for m in re.finditer(r'(?:item|food)\("([a-z_0-9]+)", "[^"]*", "([a-z_0-9]+)", (0x[0-9A-Fa-f]+)(?:, [0-9.]+, [0-9.]+)?(?:, \[([^\]]*)\])?', src):
        ex = {}
        if m.group(4):
            for k, v in re.findall(r'"(.)": (0x[0-9A-Fa-f]+)', m.group(4)):
                ex[k] = int(v, 16)
        out.append((m.group(1), m.group(2), int(m.group(3), 16), ex))
    return out


def draw_family(entry, n):
    name, mask, base, ex = entry
    cv = Canvas(n)
    if not family(cv, name, mask, base, ex):
        return None
    return render(cv)


def family_sheet(out, masks=None, n=128, cols=10):
    ents = [e for e in catalogue() if masks is None or e[1] in masks]
    imgs = [(e, draw_family(e, n)) for e in ents]
    imgs = [(e, i) for e, i in imgs if i is not None]
    cell = n + 8
    rows = (len(imgs) + cols - 1) // cols
    o = np.zeros((rows * cell + 8, cols * cell + 8, 3), dtype=np.float32)
    o[:] = np.array([0.12, 0.13, 0.16])
    for k, (e, img) in enumerate(imgs):
        y0, x0 = 8 + (k // cols) * cell, 8 + (k % cols) * cell
        sl = o[y0:y0 + n, x0:x0 + n]
        sl[:] = sl * 0.85 + 0.03
        a = img[..., 3:4]
        sl[:] = sl * (1 - a) + img[..., :3] * a
    Image.fromarray((np.clip(o, 0, 1) * 255).astype(np.uint8)).save(out)
    return [e[0] for e, _ in imgs]


def family2(cv, name, mask, base, ex, ys, xs):
    soft = lambda h: M("soft", h)
    if mask == "apple_shape":
        m = METAL_BY_NAME["gold"] if "golden" in name else soft(base)
        body = smin(cv.circle(V(0.38, 0.58), 0.27), cv.circle(V(0.62, 0.58), 0.27), 0.12)
        body = smax(body, -cv.circle(V(0.5, 0.29), 0.07), 0.05)
        cv.add(body, ys, m, 0.27)
        cv.add(cap(cv, V(0.5, 0.36), V(0.55, 0.15), 0.028), ys, "stem", 0.028)
        leaf = band(V(0.55, 0.23), V(0.68, 0.09), V(0.84, 0.18), 0.02, 0.02, 8) + band(V(0.84, 0.18), V(0.7, 0.3), V(0.55, 0.23), 0.02, 0.02, 8)
        cv.add(cv.poly(leaf), xs, "leaf", 0.04)
    elif mask == "carrot":
        m = METAL_BY_NAME["gold"] if "golden" in name else soft(base)
        d = cv.poly(band(V(0.3, 0.3), V(0.5, 0.5), V(0.84, 0.86), 0.2, 0.02, 14))
        cv.add(d, xs, m, 0.1)
        for a, b in ((V(0.42, 0.42), V(0.48, 0.36)), (V(0.56, 0.6), V(0.63, 0.55)), (V(0.68, 0.72), V(0.73, 0.68))):
            cv.add(intersect(cap(cv, a, b, 0.01), d + 0.02), xs, soft(darker(base, 0.7)), 0.01)
        for a in (V(0.12, 0.1), V(0.22, 0.05), V(0.08, 0.24), V(0.3, 0.08)):
            cv.add(cv.poly(band(V(0.31, 0.31), (V(0.31, 0.31) + a) * 0.5 + V(0.02, -0.02), a, 0.06, 0.01, 8)), xs, "leaf", 0.03)
    elif mask == "potato":
        m = soft(base)
        d = cv.ellipse(V(0.5, 0.54), 0.34, 0.26)
        if name == "beetroot":
            d = cv.poly(band(V(0.5, 0.3), V(0.56, 0.62), V(0.5, 0.92), 0.5, 0.02, 14))
            cv.add(d, ys, m, 0.2)
            for a in (V(0.36, 0.06), V(0.5, 0.04), V(0.64, 0.08)):
                cv.add(cv.poly(band(V(0.5, 0.26), V(0.5, 0.16), a, 0.06, 0.02, 8)), ys, "leaf", 0.03)
        else:
            cv.add(d, xs, m, 0.24)
            for c in (V(0.36, 0.48), V(0.58, 0.44), V(0.5, 0.64), V(0.7, 0.6)):
                cv.add(intersect(cv.circle(c, 0.022), d + 0.03), xs, soft(darker(base, 0.6)), 0.02)
            if name == "baked_potato":
                cv.add(intersect(cv.poly(band(V(0.3, 0.46), V(0.5, 0.36), V(0.72, 0.46), 0.08, 0.06, 12)), d + 0.02), xs, soft(0xF8E8A0), 0.03)
    elif mask == "berries":
        m = soft(base)
        if "chorus" in name:
            d = cv.circle(V(0.5, 0.56), 0.3)
            cv.add(d, ys, M("leather", base), 0.3)
            for c in (V(0.38, 0.46), V(0.6, 0.48), V(0.5, 0.68)):
                cv.add(intersect(cv.circle(c, 0.07), d + 0.03), ys, soft(lighter(base, 0.3)), 0.05)
        else:
            pts = (V(0.36, 0.5), V(0.6, 0.48), V(0.48, 0.7), V(0.7, 0.7), V(0.3, 0.72))
            cv.add(cap(cv, V(0.5, 0.14), V(0.36, 0.46), 0.018), ys, "stem", 0.018)
            cv.add(cap(cv, V(0.5, 0.14), V(0.62, 0.44), 0.018), ys, "stem", 0.018)
            for c in pts:
                cv.add(cv.circle(c, 0.12), ys, m, 0.12)
            cv.add(cv.poly(band(V(0.5, 0.16), V(0.66, 0.08), V(0.78, 0.18), 0.08, 0.01, 8)), xs, "leaf", 0.03)
    elif mask in ("steak", "chop"):
        m = soft(base)
        fat = soft(ex.get("c", 0xF0E0D0))
        if mask == "steak":
            d = smin(cv.ellipse(V(0.42, 0.5), 0.3, 0.26), cv.ellipse(V(0.66, 0.6), 0.22, 0.2), 0.1)
            d = smax(d, -cv.ellipse(V(0.6, 0.2), 0.14, 0.1), 0.06)            # the kidney notch
        else:
            d = smin(cv.ellipse(V(0.56, 0.42), 0.3, 0.24), cv.circle(V(0.36, 0.64), 0.1), 0.16)
        d = d + (vnoise(cv.X, cv.Y, 9, 21) - 0.5) * 0.02                       # a cut, uneven edge
        cv.add(d, ys, fat, 0.1)
        cv.add(d + 0.04, ys, m, 0.16)
        if mask == "chop":
            cv.add(cap(cv, V(0.3, 0.7), V(0.08, 0.9), 0.04), ys, "bone", 0.04)
            cv.add(cv.circle(V(0.08, 0.9), 0.05), ys, "bone", 0.05)
            cv.add(intersect(cv.circle(V(0.6, 0.4), 0.06), d + 0.07), ys, fat, 0.05)
        else:
            for p0, c0, p1 in ((V(0.24, 0.44), V(0.36, 0.36), V(0.5, 0.46)), (V(0.5, 0.62), V(0.62, 0.52), V(0.78, 0.6)), (V(0.3, 0.6), V(0.38, 0.68), V(0.48, 0.64))):
                cv.add(intersect(cv.poly(band(p0, c0, p1, 0.022, 0.012, 10)), d + 0.06), ys, fat, 0.012)
    elif mask == "drumstick":
        m = soft(base)
        cv.add(cap(cv, V(0.3, 0.7), V(0.12, 0.88), 0.045), ys, soft(ex.get("c", 0xF0E8E0)), 0.045)
        cv.add(cv.circle(V(0.1, 0.84), 0.05), ys, soft(ex.get("c", 0xF0E8E0)), 0.05)
        cv.add(cv.circle(V(0.15, 0.9), 0.05), ys, soft(ex.get("c", 0xF0E8E0)), 0.05)
        cv.add(union(cv.ellipse(V(0.58, 0.42), 0.3, 0.24), cap(cv, V(0.5, 0.5), V(0.3, 0.7), 0.1)), xs, m, 0.22)
    elif mask == "bread":
        d = cv.capsule(V(0.2, 0.6), V(0.8, 0.44), 0.2)[0]
        cv.add(d, xs, soft(base), 0.2)
        for k in range(3):
            cx, cy = 0.34 + k * 0.16, 0.56 - k * 0.04
            cv.add(intersect(cap(cv, V(cx - 0.05, cy - 0.12), V(cx + 0.03, cy + 0.06), 0.02), d + 0.03), xs, soft(lighter(base, 0.4)), 0.02)
    elif mask == "cookie":
        d = cv.circle(V(0.5, 0.52), 0.32)
        cv.add(d, ys, soft(base), 0.1)
        for c in (V(0.4, 0.4), V(0.62, 0.46), V(0.46, 0.64), V(0.66, 0.66), V(0.32, 0.56)):
            cv.add(intersect(cv.circle(c, 0.04), d + 0.04), ys, soft(0x4A2A14), 0.03)
    elif mask == "melon":
        rind = cv.poly([V(0.12, 0.34), V(0.88, 0.34), V(0.5, 0.9)])
        cv.add(rind, xs, soft(0x3A8A2A if "glister" not in name else 0xE8B830), 0.08)
        flesh = cv.poly([V(0.2, 0.34), V(0.8, 0.34), V(0.5, 0.8)])
        cv.add(flesh, xs, soft(base), 0.1, "chamfer")
        for c in (V(0.38, 0.44), V(0.6, 0.44), V(0.5, 0.58)):
            cv.add(cv.ellipse(c, 0.018, 0.03), xs, soft(0x1A1A1A), 0.02)
    elif mask in ("stew", "bowl"):
        bowl = intersect(cv.ellipse(V(0.5, 0.5), 0.4, 0.34), -cv.below(0.5))
        cv.add(bowl, xs, M("wood", 0x8A6435), 0.2)
        if mask == "stew":
            cv.add(cv.ellipse(V(0.5, 0.5), 0.36, 0.09), xs, soft(ex.get("d", base) if name != "beetroot_soup" else base), 0.05)
            for c in (V(0.38, 0.49), V(0.56, 0.47), V(0.64, 0.52)):
                cv.add(cv.ellipse(c, 0.05, 0.025), xs, soft(ex.get("c", lighter(base, 0.3))), 0.02)
        else:
            cv.add(cv.ellipse(V(0.5, 0.5), 0.34, 0.08), xs, M("wood", 0x5A3D1F), 0.04)
        cv.add(abs(cv.ellipse(V(0.5, 0.5), 0.38, 0.1)) - 0.015, xs, M("wood", 0xA07A48), 0.015)
    elif mask == "rotten":
        pts = [V(0.16, 0.44), V(0.36, 0.26), V(0.68, 0.24), V(0.86, 0.42), V(0.8, 0.68), V(0.52, 0.8), V(0.22, 0.7)]
        d = cv.poly(pts)
        cv.add(d, ys, soft(base), 0.15)
        for c in (V(0.4, 0.42), V(0.64, 0.56), V(0.42, 0.64)):
            cv.add(intersect(cv.circle(c, 0.06), d + 0.03), ys, soft(0x4A6A2A), 0.04)
    else:
        return family3(cv, name, mask, base, ex, ys, xs)
    return True


def family3(cv, name, mask, base, ex, ys, xs):
    soft = lambda h: M("soft", h)
    wood = lambda h: M("wood", h)
    zero = np.zeros_like(ys)
    if mask == "stick":
        handle(cv, V(0.2, 0.84), V(0.8, 0.16), 0.045)
        cv.add(cap(cv, V(0.48, 0.52), V(0.62, 0.54), 0.025), zero, "handle", 0.025)
    elif mask == "rod":
        d, t = cv.capsule(V(0.22, 0.82), V(0.78, 0.18), 0.055)
        cv.add(d, t, soft(base), 0.055)
        for k in range(4):
            c = V(0.22, 0.82) + (V(0.78, 0.18) - V(0.22, 0.82)) * (0.15 + k * 0.23)
            cv.add(cv.capsule(c + V(-0.07, -0.06), c + V(0.07, 0.06), 0.022)[0], t, soft(darker(base, 0.75)), 0.02)
    elif mask == "bone":
        m = "bone"
        cv.add(smin(smin(cap(cv, V(0.26, 0.74), V(0.74, 0.26), 0.06), smin(cv.circle(V(0.2, 0.73), 0.075), cv.circle(V(0.27, 0.8), 0.075), 0.03), 0.04),
                    smin(cv.circle(V(0.73, 0.2), 0.075), cv.circle(V(0.8, 0.27), 0.075), 0.03), 0.04), zero, m, 0.08)
    elif mask == "string":
        a_ = cv.poly(band(V(0.12, 0.82), V(0.28, 0.14), V(0.5, 0.5), 0.06, 0.06, 18))
        b_ = cv.poly(band(V(0.5, 0.5), V(0.72, 0.86), V(0.88, 0.18), 0.06, 0.06, 18))
        cv.add(union(a_, b_), xs, "string", 0.03)
    elif mask == "feather":
        vane = cv.poly(band(V(0.22, 0.82), V(0.3, 0.26), V(0.84, 0.12), 0.22, 0.02, 18))
        cv.add(vane, xs, "white", 0.1)
        for k in range(5):
            t = 0.2 + k * 0.14
            p0 = bez(V(0.22, 0.82), V(0.3, 0.26), V(0.84, 0.12), 20)[int(t * 19)]
            cv.add(intersect(cap(cv, p0, p0 + V(0.1, 0.06), 0.006), vane + 0.01), xs, soft(0xB8B8C4), 0.006)
        cv.add(cv.poly(band(V(0.14, 0.92), V(0.3, 0.4), V(0.82, 0.14), 0.026, 0.008, 18)), xs, "bone", 0.013)
    elif mask == "leather":
        pts = [V(0.2, 0.2), V(0.42, 0.28), V(0.6, 0.18), V(0.82, 0.26), V(0.74, 0.5), V(0.84, 0.78), V(0.56, 0.72), V(0.36, 0.84), V(0.18, 0.72), V(0.26, 0.48)]
        cv.add(cv.poly(pts), ys, M("leather", base), 0.06)
    elif mask == "paper":
        d = cv.poly([V(0.2, 0.12), V(0.8, 0.12), V(0.8, 0.88), V(0.2, 0.88)])
        cv.add(d, ys, "paper", 0.03)
        if name.endswith("banner_pattern"):
            emblem(cv, name, V(0.5, 0.5), 0.2, soft(ex.get("a", 0x5A5040)))
        else:
            for yy in (0.3, 0.42, 0.54, 0.66):
                cv.add(cap(cv, V(0.3, yy), V(0.7 if yy < 0.6 else 0.56, yy), 0.012), ys, soft(ex.get("a", 0x9A9488)), 0.01)
    elif mask == "book":
        cover = M("leather", base)
        cv.add(cv.poly([V(0.24, 0.16), V(0.84, 0.16), V(0.84, 0.84), V(0.24, 0.84)]), ys, "paper", 0.03)
        cv.add(cv.poly([V(0.16, 0.12), V(0.78, 0.12), V(0.78, 0.8), V(0.16, 0.8)]), ys, cover, 0.05)
        cv.add(cv.poly([V(0.14, 0.12), V(0.26, 0.12), V(0.26, 0.88), V(0.14, 0.88)]), ys, M("leather", darker(base, 0.7)), 0.05)
        acc = ex.get("c")
        if acc is not None:
            cv.add(cv.poly([V(0.38, 0.3), V(0.66, 0.3), V(0.66, 0.42), V(0.38, 0.42)]), ys, M("metal", acc) if name != "writable_book" else soft(acc), 0.02)
        if name == "writable_book":
            cv.add(cv.poly(band(V(0.92, 0.06), V(0.8, 0.3), V(0.62, 0.62), 0.1, 0.01, 10)), xs, "white", 0.04)
    elif mask == "compass":
        m = "golden" if name == "clock" else M("metal", base)
        cv.add(cv.circle(V(0.5, 0.53), 0.36), ys, m, 0.12)
        cv.add(cv.circle(V(0.5, 0.53), 0.27), ys, soft(0xE8E4D8) if name != "recovery_compass" else soft(0x2A3A3A), 0.06)
        cv.add(cv.circle(V(0.5, 0.15), 0.06), ys, m, 0.04)
        for k in range(4):
            a = k * math.pi / 2
            cv.add(cap(cv, V(0.5, 0.53) + V(math.cos(a), math.sin(a)) * 0.22, V(0.5, 0.53) + V(math.cos(a), math.sin(a)) * 0.25, 0.01), ys, soft(0x4A4A4A), 0.01)
    elif mask == "eye":
        if name == "ender_eye":
            cv.add(cv.circle(V(0.5, 0.52), 0.32), ys, M("gem", 0x2A9A6A), 0.32)
            cv.add(cv.ellipse(V(0.5, 0.52), 0.2, 0.12), ys, soft(0xD8F070), 0.1)
            cv.add(cv.ellipse(V(0.5, 0.52), 0.05, 0.12), ys, soft(0x101810), 0.04)
        else:
            d = cv.ellipse(V(0.5, 0.54), 0.32, 0.28)
            cv.add(d, ys, soft(base), 0.28)
            for c in (V(0.38, 0.46), V(0.6, 0.44), V(0.5, 0.64)):
                cv.add(cv.circle(c, 0.06), ys, soft(ex.get("d", 0x200808)), 0.05)
                cv.add(cv.circle(c + V(-0.02, -0.02), 0.018), ys, "white", 0.01)
    elif mask == "arrow":
        handle(cv, V(0.18, 0.82), V(0.74, 0.26), 0.022)
        cv.add(cv.poly([V(0.66, 0.2), V(0.92, 0.08), V(0.8, 0.34)]), cv.axis(V(0.7, 0.3), V(0.9, 0.1)), "flint", 0.05, "chamfer")
        for sgn in (-1, 1):
            o = V(0.707, 0.707) * 0.07 * sgn
            cv.add(cv.poly([V(0.14, 0.86), V(0.3, 0.7), V(0.36, 0.64) + o, V(0.2, 0.8) + o * 1.3]), xs, "white", 0.03)
    elif mask == "bow":
        cv.add(cv.poly(band(V(0.18, 0.1), V(0.94, 0.16), V(0.88, 0.84), 0.07, 0.07, 22)), xs, "handle", 0.035)
        cv.add(cap(cv, V(0.2, 0.12), V(0.86, 0.84), 0.017), zero, "string", 0.017)
        wraps(cv, V(0.66, 0.3), V(0.76, 0.4), 0.05, 2)
    elif mask == "crossbow":
        handle(cv, V(0.16, 0.86), V(0.7, 0.32), 0.05)
        cv.add(cv.poly(band(V(0.36, 0.1), V(0.68, 0.18), V(0.92, 0.64), 0.07, 0.07, 18)), xs, "iron", 0.035)
        cv.add(cap(cv, V(0.38, 0.12), V(0.56, 0.5), 0.015), zero, "string", 0.015)
        cv.add(cap(cv, V(0.9, 0.62), V(0.56, 0.5), 0.015), zero, "string", 0.015)
        cv.add(cv.circle(V(0.62, 0.38), 0.06), zero, "iron", 0.05)
        cv.add(cap(cv, V(0.34, 0.68), V(0.42, 0.74), 0.03), zero, "iron", 0.03)
    elif mask == "shield":
        d = cv.poly(band(V(0.5, 0.1), V(0.5, 0.1), V(0.5, 0.1), 0.0, 0.0, 3)) if False else None
        outline_ = smin(cv.poly([V(0.16, 0.12), V(0.84, 0.12), V(0.84, 0.5)] + bez(V(0.84, 0.5), V(0.82, 0.8), V(0.5, 0.94), 8) + bez(V(0.5, 0.94), V(0.18, 0.8), V(0.16, 0.5), 8)), cv.circle(V(0.5, 0.5), 0.0), 0.0) if False else \
            cv.poly([V(0.16, 0.12), V(0.84, 0.12), V(0.84, 0.5)] + bez(V(0.84, 0.5), V(0.82, 0.8), V(0.5, 0.94), 8)[1:] + bez(V(0.5, 0.94), V(0.18, 0.8), V(0.16, 0.5), 8)[1:-1])
        cv.add(outline_, ys, "iron", 0.04)
        cv.add(outline_ + 0.05, ys, M("wood", base), 0.12)
        for x in (0.38, 0.62):
            cv.add(intersect(cap(cv, V(x, 0.12), V(x, 0.94), 0.006), outline_ + 0.05), ys, M("wood", darker(base, 0.6)), 0.006)
        cv.add(cv.circle(V(0.5, 0.48), 0.09), ys, "iron", 0.08)
    elif mask == "trident":
        handle(cv, V(0.1, 0.92), V(0.66, 0.36), 0.03, M("metal", base))
        tm = M("metal", base)
        c = V(0.68, 0.34)
        up, rt = V(0.707, -0.707), V(0.707, 0.707)
        cv.add(cap(cv, c - rt * 0.14, c + rt * 0.14, 0.03), zero, tm, 0.03)
        for o, l in ((-0.14, 0.2), (0.0, 0.3), (0.14, 0.2)):
            b = c + rt * o
            tip = b + up * l
            cv.add(cap(cv, b, tip - up * 0.04, 0.024), zero, tm, 0.024)
            cv.add(cv.poly([tip + up * 0.06, tip - up * 0.02 + rt * 0.05, tip - up * 0.02 - rt * 0.05]), zero, tm, 0.03, "chamfer")
    elif mask == "fishing_rod":
        cv.add(cv.poly(band(V(0.12, 0.9), V(0.4, 0.4), V(0.86, 0.1), 0.06, 0.02, 18)), xs, "handle", 0.03)
        wraps(cv, V(0.13, 0.88), V(0.22, 0.75), 0.04, 2)
        bait = ex.get("c", 0xD03030)
        if name == "fishing_rod":
            cv.add(cap(cv, V(0.86, 0.1), V(0.86, 0.66), 0.012), zero, "string", 0.012)
            cv.add(cv.circle(V(0.86, 0.7), 0.045), zero, soft(bait), 0.04)
        else:
            cv.add(cap(cv, V(0.86, 0.1), V(0.82, 0.5), 0.012), zero, "string", 0.012)
            cv.add(cv.poly(band(V(0.82, 0.48), V(0.86, 0.66), V(0.8, 0.86), 0.12, 0.02, 10)), ys, soft(bait), 0.06)
    elif mask == "shears":
        piv = V(0.52, 0.48)
        for tip, side in ((V(0.9, 0.16), V(0.04, 0.05)), (V(0.84, 0.1), V(-0.05, -0.04))):
            dr = norm(tip - piv)
            nr = V(-dr[1], dr[0])
            bl = cv.poly([piv - dr * 0.06 + nr * 0.05, tip, piv - dr * 0.06 - nr * 0.04])
            cv.add(bl, cv.axis(piv, tip), "iron", 0.04, "chamfer")
        for c in (V(0.24, 0.58), V(0.42, 0.78)):
            cv.add(cap(cv, piv, c, 0.03), np.zeros_like(ys), "iron", 0.03)
            cv.add(abs(cv.circle(c, 0.1)) - 0.035, np.zeros_like(ys), soft(ex.get("d", 0x5A3D1F)), 0.035)
        cv.add(cv.circle(piv, 0.035), np.zeros_like(ys), "iron", 0.03)
    elif mask == "flint_steel":
        # A C-shaped steel striker with a grip, and a big knapped flint.
        st = intersect(abs(cv.ellipse(V(0.38, 0.4), 0.26, 0.2)) - 0.045, -(cv.poly([V(0.5, 0.4), V(0.9, 0.2), V(0.9, 0.6)])))
        cv.add(st, xs, "iron", 0.045)
        cv.add(cap(cv, V(0.18, 0.4), V(0.18, 0.4), 0.06), xs, "grip", 0.05)
        cv.add(cv.poly([V(0.46, 0.56), V(0.7, 0.46), V(0.9, 0.62), V(0.8, 0.9), V(0.52, 0.86)]), ys, "flint", 0.1, "chamfer")
        for c in (V(0.62, 0.42), V(0.68, 0.36), V(0.58, 0.34)):
            cv.add(cv.circle(c, 0.018), xs, M("soft", 0xFFD060), 0.015)
    elif mask == "minecart":
        body = cv.poly([V(0.12, 0.34), V(0.88, 0.34), V(0.8, 0.72), V(0.2, 0.72)])
        cont = ex.get("c", 0x4A4A50)
        if name != "minecart":
            cv.add(cv.poly([V(0.24, 0.12), V(0.76, 0.12), V(0.76, 0.4), V(0.24, 0.4)]), ys, M("wood" if "chest" in name else "soft", cont), 0.05)
        cv.add(body, xs, M("metal", base), 0.08)
        cv.add(cv.poly([V(0.16, 0.38), V(0.84, 0.38), V(0.82, 0.46), V(0.18, 0.46)]), xs, M("metal", darker(base, 0.6)), 0.02)
        for x in (0.3, 0.7):
            cv.add(cv.circle(V(x, 0.76), 0.1), ys, M("metal", 0x3A3A40), 0.08)
            cv.add(cv.circle(V(x, 0.76), 0.035), ys, "iron", 0.03)
    elif mask in ("boat", "chest_boat"):
        cv.add(cap(cv, V(0.7, 0.12), V(0.5, 0.6), 0.022), zero, "handle", 0.022)
        cv.add(cv.ellipse(V(0.72, 0.14), 0.05, 0.08), zero, "handle", 0.04)
        hull = cv.poly([V(0.04, 0.44), V(0.96, 0.44), V(0.82, 0.78), V(0.18, 0.78)])
        cv.add(hull, xs, wood(base), 0.08)
        for yy in (0.56, 0.66):
            cv.add(intersect(cap(cv, V(0.06, yy), V(0.94, yy), 0.008), hull), xs, wood(darker(base, 0.6)), 0.008)
        cv.add(cap(cv, V(0.06, 0.46), V(0.94, 0.46), 0.03), xs, wood(darker(base, 0.8)), 0.03)
        if mask == "chest_boat":
            cv.add(cv.poly([V(0.28, 0.14), V(0.66, 0.14), V(0.66, 0.46), V(0.28, 0.46)]), ys, wood(ex.get("c", 0x9A6A2A)), 0.05)
            cv.add(cap(cv, V(0.28, 0.25), V(0.66, 0.25), 0.012), ys, wood(0x5A3A1A), 0.012)
            cv.add(cv.poly([V(0.44, 0.22), V(0.5, 0.22), V(0.5, 0.32), V(0.44, 0.32)]), ys, "iron", 0.02)
    elif mask == "horse_armor":
        m = M("leather" if name.startswith("leather") or name == "wolf_armor" else ("gem" if "diamond" in name else "metal"), base)
        m = METAL_BY_NAME.get(name.split("_")[0], m)
        head = cv.poly([V(0.36, 0.1), V(0.6, 0.14), V(0.84, 0.54), V(0.8, 0.7), V(0.6, 0.64), V(0.42, 0.9), V(0.18, 0.86), V(0.2, 0.4)])
        cv.add(head, ys, m, 0.2)
        cv.add(cv.circle(V(0.48, 0.36), 0.05), ys, soft(0x101014), 0.04)
        cv.add(intersect(cap(cv, V(0.2, 0.62), V(0.6, 0.62), 0.03), head), xs, m, 0.03)
        cv.add(cv.poly([V(0.36, 0.1), V(0.44, 0.0), V(0.48, 0.14)]), ys, m, 0.03)
    elif mask == "bundle":
        m = M("leather", base)
        sack = smin(cv.ellipse(V(0.5, 0.62), 0.34, 0.28), cv.poly([V(0.36, 0.3), V(0.64, 0.3), V(0.6, 0.44), V(0.4, 0.44)]), 0.06)
        cv.add(sack, ys, m, 0.25)
        cv.add(cv.poly([V(0.34, 0.16), V(0.66, 0.16), V(0.6, 0.32), V(0.4, 0.32)]), ys, m, 0.05)
        cv.add(cap(cv, V(0.36, 0.33), V(0.64, 0.33), 0.025), xs, "string", 0.02)
    elif mask == "disc":
        cv.add(cv.circle(V(0.5, 0.5), 0.4), ys, soft(0x16161A), 0.06)
        for r in (0.3, 0.34, 0.24):
            cv.add(abs(cv.circle(V(0.5, 0.5), r)) - 0.004, ys, soft(0x34343C), 0.004)
        cv.add(cv.circle(V(0.5, 0.5), 0.19), ys, soft(ex.get("c", 0xC03030)), 0.05)
        cv.add(abs(cv.circle(V(0.5, 0.5), 0.12)) - 0.008, ys, soft(lighter(ex.get("c", 0xC03030), 0.45)), 0.008)
        cv.add(cv.circle(V(0.5, 0.5), 0.025), ys, soft(0x08080A), 0.02)
    elif mask == "sherd":
        d = cv.poly([V(0.16, 0.24), V(0.56, 0.14), V(0.86, 0.3), V(0.8, 0.74), V(0.4, 0.86), V(0.14, 0.66)])
        cv.add(d, ys, M("stone", base), 0.1, "chamfer")
        emblem(cv, name, V(0.5, 0.5), 0.17, M("stone", ex.get("c", 0x6A3A2A)))
    elif mask == "template":
        d = cv.poly([V(0.2, 0.12), V(0.8, 0.12), V(0.8, 0.88), V(0.2, 0.88)])
        cv.add(d, ys, M("stone", base), 0.06, "chamfer")
        emblem(cv, name, V(0.5, 0.5), 0.2, M("metal", ex.get("c", 0x6A8AAA)))
    elif mask == "key":
        km = M("metal", base)
        cv.add(abs(cv.circle(V(0.32, 0.32), 0.15)) - 0.045, zero, km, 0.045)
        cv.add(cap(cv, V(0.42, 0.42), V(0.82, 0.82), 0.045), zero, km, 0.045)
        cv.add(cap(cv, V(0.7, 0.7), V(0.6, 0.8), 0.04), zero, km, 0.04)
        cv.add(cap(cv, V(0.8, 0.8), V(0.7, 0.9), 0.04), zero, km, 0.04)
    elif mask == "star":
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            r = 0.42 if k % 2 == 0 else 0.18
            pts.append(V(0.5 + math.cos(a) * r, 0.54 + math.sin(a) * r))
        cv.add(cv.poly(pts), ys, M("gem", base), 0.2, "chamfer")
    elif mask == "totem":
        tm = "golden"
        cv.add(cv.poly([V(0.3, 0.42), V(0.7, 0.42), V(0.64, 0.92), V(0.36, 0.92)]), ys, tm, 0.1)
        cv.add(cv.poly([V(0.1, 0.44), V(0.3, 0.42), V(0.3, 0.6), V(0.14, 0.62)]), ys, tm, 0.05)
        cv.add(cv.poly([V(0.9, 0.44), V(0.7, 0.42), V(0.7, 0.6), V(0.86, 0.62)]), ys, tm, 0.05)
        cv.add(cv.ellipse(V(0.5, 0.26), 0.2, 0.18), ys, tm, 0.15)
        for x in (0.42, 0.58):
            cv.add(cv.circle(V(x, 0.26), 0.035), ys, M("gem", ex.get("c", 0x2A8A3A)), 0.03)
        cv.add(cv.poly([V(0.4, 0.5), V(0.6, 0.5), V(0.5, 0.64)]), ys, M("gem", ex.get("c", 0x2A8A3A)), 0.04, "chamfer")
    elif mask == "spyglass":
        a, b = V(0.16, 0.84), V(0.84, 0.16)
        d, t = cv.capsule(a, b, 0.05, 0.085)
        cv.add(d, t, M("metal", base), 0.08)
        for k, r in ((0.0, 0.07), (0.45, 0.085), (1.0, 0.1)):
            c = a + (b - a) * k
            cv.add(cap(cv, c - V(0.03, -0.03) * 0 - norm(b - a) * 0.03, c + norm(b - a) * 0.03, r), t, "golden", 0.06)
    elif mask == "mace":
        handle(cv, V(0.16, 0.88), V(0.6, 0.44), 0.035, "grip")
        wraps(cv, V(0.18, 0.86), V(0.36, 0.68), 0.035, 3)
        hd = cv.circle(V(0.68, 0.34), 0.18)
        for k in range(6):
            a = k * math.pi / 3
            c = V(0.68, 0.34) + V(math.cos(a), math.sin(a)) * 0.2
            hd = union(hd, cv.poly([c + V(math.cos(a), math.sin(a)) * 0.08, c + V(-math.sin(a), math.cos(a)) * 0.05, c - V(-math.sin(a), math.cos(a)) * 0.05]))
        cv.add(hd, ys, M("metal", base), 0.12, "chamfer")
    elif mask == "brush":
        handle(cv, V(0.14, 0.88), V(0.56, 0.46), 0.04, "handle")
        cv.add(cv.poly([V(0.5, 0.42), V(0.62, 0.3), V(0.92, 0.2), V(0.8, 0.5)]), cv.axis(V(0.56, 0.44), V(0.86, 0.3)), M("wood", base), 0.05)
        cv.add(cap(cv, V(0.5, 0.4), V(0.6, 0.5), 0.04), zero, "copper", 0.04)
    elif mask == "lead":
        cv.add(cv.poly(band(V(0.2, 0.2), V(0.9, 0.4), V(0.4, 0.86), 0.05, 0.05, 20)), xs, M("leather", base), 0.025)
        cv.add(abs(cv.circle(V(0.24, 0.22), 0.1)) - 0.03, zero, M("leather", base), 0.03)
    elif mask == "crystal":
        if name == "end_crystal":
            cv.add(cv.poly([V(0.5, 0.08), V(0.82, 0.46), V(0.5, 0.9), V(0.18, 0.46)]), ys, M("gem", base), 0.16, "chamfer")
            cv.add(abs(cv.ellipse(V(0.5, 0.48), 0.4, 0.14)) - 0.03, xs, M("metal", 0x8A8A9A), 0.03)
        else:
            for (a, b, w) in ((V(0.36, 0.86), V(0.5, 0.12), 0.16), (V(0.58, 0.86), V(0.78, 0.38), 0.12)):
                dr = norm(b - a); nr = V(-dr[1], dr[0]); ln = float(np.linalg.norm(b - a))
                cv.add(cv.poly([a + nr * w / 2, a + dr * ln * 0.7 + nr * w / 2, b, a + dr * ln * 0.7 - nr * w / 2, a - nr * w / 2]), cv.axis(a, b), M("gem", base), w / 2, "chamfer")
    elif mask == "tear":
        d = smin(cv.circle(V(0.5, 0.62), 0.24), cv.poly([V(0.5, 0.1), V(0.7, 0.5), V(0.3, 0.5)]), 0.08)
        cv.add(d, ys, M("gem", base), 0.24)
    elif mask == "membrane":
        pts = [V(0.12, 0.3), V(0.88, 0.2), V(0.78, 0.5), V(0.86, 0.8), V(0.56, 0.66), V(0.3, 0.84), V(0.3, 0.56)]
        cv.add(cv.poly(pts), ys, M("leather", base), 0.05)
        for a_, b_ in ((V(0.14, 0.31), V(0.56, 0.66)), (V(0.5, 0.26), V(0.56, 0.66)), (V(0.84, 0.22), V(0.56, 0.66))):
            cv.add(cap(cv, a_, b_, 0.012), ys, M("leather", darker(base, 0.7)), 0.012)
    elif mask == "kelp":
        for k in range(3):
            o = V(0.1 * k - 0.1, 0.04 * k)
            cv.add(cv.poly(band(V(0.3, 0.88) + o, V(0.62, 0.5) + o, V(0.44, 0.12) + o, 0.12, 0.05, 14)), xs, M("leather", darker(base, 1.0 - 0.12 * k)), 0.05)
    elif mask == "foot":
        d = smin(cv.ellipse(V(0.46, 0.62), 0.2, 0.26), cv.ellipse(V(0.64, 0.3), 0.12, 0.16), 0.12)
        cv.add(d, ys, M("leather", base), 0.2)
        for c in (V(0.56, 0.16), V(0.68, 0.16), V(0.76, 0.24)):
            cv.add(cv.ellipse(c, 0.035, 0.05), ys, soft(0x3A3030), 0.03)
        cv.add(cap(cv, V(0.36, 0.84), V(0.56, 0.84), 0.04), ys, soft(ex.get("c", 0xE8D8C0)), 0.04)
    elif mask == "rocket":
        d, t = cv.capsule(V(0.3, 0.74), V(0.66, 0.34), 0.1)
        cv.add(cap(cv, V(0.1, 0.94), V(0.3, 0.74), 0.018), np.zeros_like(ys), "handle", 0.018)
        cv.add(d, t, "paper", 0.1)
        for k in (0.3, 0.6):
            c = V(0.3, 0.74) + (V(0.66, 0.34) - V(0.3, 0.74)) * k
            cv.add(intersect(cap(cv, c - V(0.08, 0.08), c + V(0.08, 0.08), 0.035), d), t, soft(base), 0.03)
        cv.add(cv.poly([V(0.6, 0.26), V(0.84, 0.16), V(0.74, 0.4)]), t, soft(base), 0.05, "chamfer")
    elif mask in ("firework_star", "charge"):
        d = cv.circle(V(0.5, 0.52), 0.3)
        cv.add(d, ys, M("stone", base) if mask == "firework_star" else soft(0x3A2A1A), 0.3)
        if mask == "charge":
            for c in (V(0.4, 0.44), V(0.58, 0.5), V(0.46, 0.64)):
                cv.add(intersect(cv.circle(c, 0.07), d + 0.03), ys, soft(0xF8A030), 0.05)
        else:
            for c in (V(0.42, 0.42), V(0.6, 0.52), V(0.44, 0.62)):
                cv.add(intersect(cv.circle(c, 0.05), d + 0.03), ys, soft(ex.get("c", 0x9A9AA0)), 0.04)
    elif mask == "scute":
        pts = [V(0.5, 0.12), V(0.82, 0.3), V(0.78, 0.7), V(0.5, 0.88), V(0.22, 0.7), V(0.18, 0.3)]
        d = cv.poly(pts)
        cv.add(d, ys, M("leather", base), 0.14, "chamfer")
        cv.add(intersect(abs(cv.poly([V(0.5, 0.3), V(0.66, 0.4), V(0.64, 0.6), V(0.5, 0.7), V(0.36, 0.6), V(0.34, 0.4)])) - 0.012, d + 0.04), ys, M("leather", darker(base, 0.7)), 0.012)
    elif mask == "sac":
        d = smin(cv.ellipse(V(0.5, 0.6), 0.3, 0.26), cv.ellipse(V(0.5, 0.3), 0.1, 0.12), 0.1)
        cv.add(d, ys, soft(base), 0.25)
        cv.add(intersect(cv.circle(V(0.42, 0.56), 0.08), d), ys, soft(lighter(base, 0.25)), 0.06)
    elif mask == "shell":
        if name == "nautilus_shell":
            d = cv.circle(V(0.5, 0.54), 0.36)
            cv.add(d, ys, soft(0xE8D8C4), 0.3)
            for k in range(4):
                cv.add(intersect(abs(cv.circle(V(0.56 - 0.03 * k, 0.56), 0.08 + k * 0.08)) - 0.012, d + 0.02), ys, soft(0xA0583A), 0.012)
        else:
            d = intersect(cv.ellipse(V(0.5, 0.6), 0.4, 0.34), cv.below(0.66))
            cv.add(d, ys, M("leather", base), 0.2)
            for x in (0.3, 0.5, 0.7):
                cv.add(intersect(cap(cv, V(x, 0.3), V(x, 0.66), 0.012), d + 0.02), ys, M("leather", darker(base, 0.7)), 0.012)
    elif mask == "honeycomb":
        for c in (V(0.36, 0.38), V(0.64, 0.38), V(0.5, 0.62), V(0.22, 0.62), V(0.78, 0.62), V(0.36, 0.86) - V(0, 0.0), V(0.64, 0.86)):
            if c[1] > 0.8:
                continue
            hexp = [c + V(math.cos(a) * 0.14, math.sin(a) * 0.14) for a in np.arange(6) * math.pi / 3 + math.pi / 6]
            cv.add(cv.poly(hexp), ys, soft(base), 0.06, "chamfer")
            cv.add(cv.poly([c + V(math.cos(a) * 0.07, math.sin(a) * 0.07) for a in np.arange(6) * math.pi / 3 + math.pi / 6]), ys, soft(ex.get("c", 0xF8C850)), 0.03)
    elif mask == "horn":
        cv.add(cv.poly(band(V(0.84, 0.24), V(0.5, 0.92), V(0.14, 0.4), 0.2, 0.04, 18)), xs, soft(base), 0.08)
        for k in range(4):
            p0 = bez(V(0.84, 0.24), V(0.5, 0.92), V(0.14, 0.4), 18)[3 + k * 3]
            cv.add(cv.circle(p0, 0.02), xs, soft(darker(base, 0.75)), 0.015)
    elif mask == "name_tag":
        d = cv.poly([V(0.12, 0.36), V(0.68, 0.36), V(0.88, 0.5), V(0.68, 0.64), V(0.12, 0.64)])
        cv.add(d, xs, "paper", 0.04)
        cv.add(cv.circle(V(0.72, 0.5), 0.03), xs, soft(0x2A2A2A), 0.02)
        cv.add(cap(cv, V(0.74, 0.5), V(0.94, 0.2), 0.014), np.zeros_like(ys), "string", 0.014)
        for x in (0.2, 0.32, 0.44):
            cv.add(cap(cv, V(x, 0.5), V(x + 0.07, 0.5), 0.014), xs, soft(0x5A5048), 0.012)
    elif mask == "pufferfish":
        d = cv.circle(V(0.48, 0.54), 0.28)
        for k in range(10):
            a = k * math.pi / 5
            c = V(0.48, 0.54) + V(math.cos(a), math.sin(a)) * 0.28
            d = union(d, cv.poly([c + V(math.cos(a), math.sin(a)) * 0.08, c + V(-math.sin(a), math.cos(a)) * 0.04, c - V(-math.sin(a), math.cos(a)) * 0.04]))
        cv.add(d, ys, soft(base), 0.25)
        cv.add(cv.circle(V(0.34, 0.46), 0.04), ys, soft(0x18181C), 0.03)
    elif mask == "map":
        d = cv.poly([V(0.14, 0.14), V(0.86, 0.14), V(0.86, 0.86), V(0.14, 0.86)])
        cv.add(d, ys, soft(ex.get("c", 0xE8E0C0)), 0.04)
        if name == "filled_map":
            cv.add(intersect(cv.ellipse(V(0.44, 0.5), 0.2, 0.16), d + 0.08), ys, soft(ex.get("d", 0x6A9A5A)), 0.05)
            cv.add(intersect(cv.ellipse(V(0.66, 0.66), 0.12, 0.1), d + 0.08), ys, soft(0x5A8ACA), 0.03)
        cv.add(abs(d + 0.06) - 0.01, ys, soft(0xA08A60), 0.01)
    elif mask == "banner":
        cv.add(cap(cv, V(0.16, 0.12), V(0.84, 0.12), 0.03), xs, "handle", 0.03)
        cv.add(cv.poly([V(0.24, 0.14), V(0.76, 0.14), V(0.76, 0.86), V(0.5, 0.74), V(0.24, 0.86)]), ys, M("leather", base), 0.08)
    elif mask == "chestplate" and name == "elytra":
        for sg in (-1, 1):
            pts = [V(0.5 + 0.04 * sg, 0.16), V(0.5 + 0.38 * sg, 0.12), V(0.5 + 0.44 * sg, 0.3)] + \
                  bez(V(0.5 + 0.44 * sg, 0.3), V(0.5 + 0.36 * sg, 0.7), V(0.5 + 0.2 * sg, 0.9), 8)[1:] + [V(0.5 + 0.06 * sg, 0.6)]
            w = cv.poly(pts)
            cv.add(w, ys, M("leather", base), 0.1)
            for k in range(3):
                y0 = 0.3 + k * 0.16
                cv.add(intersect(cap(cv, V(0.5 + 0.08 * sg, y0 - 0.06), V(0.5 + 0.4 * sg, y0 + 0.04), 0.008), w + 0.03), ys, M("leather", darker(base, 0.7)), 0.008)
    elif mask == "armor_stand":
        wd = M("wood", base)
        cv.add(rect(cv, 0.2, 0.86, 0.8, 0.94), xs, M("stone", 0x9A9A9C), 0.03)
        cv.add(cap(cv, V(0.5, 0.18), V(0.5, 0.88), 0.03), ys, wd, 0.03)
        cv.add(cap(cv, V(0.24, 0.3), V(0.76, 0.3), 0.03), xs, wd, 0.03)
        cv.add(cap(cv, V(0.32, 0.56), V(0.68, 0.56), 0.028), xs, wd, 0.028)
        for x in (0.42, 0.58):
            cv.add(cap(cv, V(x, 0.56), V(x, 0.86), 0.022), ys, wd, 0.022)
        cv.add(cv.ellipse(V(0.5, 0.14), 0.08, 0.08), ys, wd, 0.06)
    elif mask == "saddle":
        lm = M("leather", base)
        seat = cv.poly(bez(V(0.12, 0.3), V(0.5, 0.62), V(0.86, 0.36), 12) + [V(0.88, 0.5), V(0.7, 0.62), V(0.3, 0.62), V(0.12, 0.46)])
        cv.add(seat, xs, lm, 0.12)
        cv.add(cv.poly([V(0.36, 0.56), V(0.64, 0.56), V(0.6, 0.84), V(0.4, 0.84)]), ys, M("leather", darker(base, 0.8)), 0.06)
        cv.add(cap(cv, V(0.5, 0.6), V(0.5, 0.84), 0.016), np.zeros_like(ys), M("leather", darker(base, 0.6)), 0.015)
        cv.add(abs(cv.ellipse(V(0.5, 0.88), 0.07, 0.05)) - 0.018, np.zeros_like(ys), "iron", 0.018)
    else:
        return False
    return True


def pair_canvas(key, n):
    """Overlay pairs: (canvas) for item_potion_bottle / splash / lingering + item_potion_liquid, item_spawn_egg +
    shell, item_tipped_arrow + head. The tinted part uses the material 'tint'."""
    cv = Canvas(n)
    ys, xs = ys_xs(cv)
    zero = np.zeros_like(ys)
    if key in ("potion", "splash", "lingering"):
        body = smin(cv.circle(V(0.5, 0.62), 0.28), cap(cv, V(0.5, 0.18), V(0.5, 0.45), 0.085 if key != "lingering" else 0.07), 0.06)
        cv.add(body, ys, "glass", 0.26)
        cv.add(intersect(cv.circle(V(0.5, 0.62), 0.235), -cv.below(0.5)), ys, "tint", 0.22)
        if key == "splash":
            cv.add(cap(cv, V(0.38, 0.3), V(0.62, 0.3), 0.03), ys, "glass", 0.03)
        cv.add(cap(cv, V(0.4, 0.2), V(0.6, 0.2), 0.032), ys, "glass", 0.03)
        cork = 0xA87A4A if key != "lingering" else 0xB080C8
        cv.add(cv.poly([V(0.42, 0.05), V(0.58, 0.05), V(0.57, 0.19), V(0.43, 0.19)]), ys, M("wood", cork), 0.04)
        cv.add(intersect(cv.poly(band(V(0.33, 0.74), V(0.3, 0.56), V(0.4, 0.44), 0.045, 0.02, 10)), body + 0.03), ys, "white", 0.02)
    elif key == "egg":
        d = cv.ellipse(V(0.5, 0.55), 0.29, 0.37)
        cv.add(d, ys, "tint", 0.32)
        for c, r in ((V(0.42, 0.38), 0.05), (V(0.62, 0.5), 0.06), (V(0.44, 0.66), 0.045), (V(0.64, 0.74), 0.04), (V(0.34, 0.54), 0.035)):
            cv.add(intersect(cv.circle(c, r), d + 0.03), ys, M("soft", 0x3A3436), 0.03)
    elif key == "arrow":
        handle(cv, V(0.18, 0.82), V(0.74, 0.26), 0.022)
        for sgn in (-1, 1):
            o = V(0.707, 0.707) * 0.07 * sgn
            cv.add(cv.poly([V(0.14, 0.86), V(0.3, 0.7), V(0.36, 0.64) + o, V(0.2, 0.8) + o * 1.3]), xs, "white", 0.03)
        cv.add(cv.poly([V(0.64, 0.18), V(0.94, 0.06), V(0.82, 0.36)]), cv.axis(V(0.7, 0.3), V(0.9, 0.1)), "tint", 0.06, "chamfer")
    return cv


def pair_sheet(out, n=128):
    tints = {"potion": [0x3F76E4, 0xE83A3A, 0x7ED957], "splash": [0xF8A030, 0x9A4AD8], "lingering": [0x4AD8E8],
             "egg": [0x2A8A3A, 0xE8B0A0, 0x6A4A2A], "arrow": [0x7ED957, 0xE83A3A]}
    cells = []
    for k, ts in tints.items():
        b, o = render(pair_canvas(k, n), split=True)
        for t in ts:
            tc = hexc(t)
            img = b.copy()
            a = o[..., 3:4]
            img[..., :3] = img[..., :3] * (1 - a) + o[..., :3] * tc * a
            img[..., 3] = np.maximum(img[..., 3], o[..., 3])
            cells.append(img)
    art_sheet(cells, n, 1, 6, out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--n", type=int, default=128)
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--names", default="")
    ap.add_argument("--bg", default="dark")
    ap.add_argument("--cols", type=int, default=7)
    a = ap.parse_args()
    names = a.names.split(",") if a.names else item_names()
    sheet(names, a.n, a.scale, a.bg, a.cols).save(a.out)


# MARK: Steelhold guns and ammo (mirror ItemHDGear.gun)

def rect(cv, x0, y0, x1, y1):
    return cv.poly([V(x0, y0), V(x1, y0), V(x1, y1), V(x0, y1)])


def gun(cv, key):
    ys, xs = ys_xs(cv)
    steel, dark, wood, poly_, brass = M("metal", 0x4A4E56), M("metal", 0x2A2C32), M("wood", 0x8A5A30), M("leather", 0x34363A), "golden"
    if key == "gun_rifle":
        cv.add(cv.poly([V(0.04, 0.46), V(0.3, 0.42), V(0.32, 0.56), V(0.08, 0.66)]), xs, wood, 0.05)          # stock
        cv.add(cv.poly(band(V(0.44, 0.56), V(0.48, 0.7), V(0.42, 0.82), 0.09, 0.08, 10)), ys, dark, 0.04)    # curved mag
        cv.add(rect(cv, 0.28, 0.4, 0.62, 0.56), xs, steel, 0.06, "chamfer")                                   # receiver
        cv.add(cv.poly([V(0.33, 0.55), V(0.39, 0.55), V(0.37, 0.7), V(0.3, 0.7)]), ys, wood, 0.03)           # grip
        cv.add(rect(cv, 0.6, 0.42, 0.82, 0.53), xs, wood, 0.04)                                               # handguard
        cv.add(cap(cv, V(0.8, 0.46), V(0.97, 0.46), 0.018), xs, dark, 0.018)                                  # barrel
        cv.add(rect(cv, 0.36, 0.34, 0.5, 0.4), xs, dark, 0.02)                                                # rear sight / rail
        cv.add(cv.poly([V(0.84, 0.44), V(0.86, 0.38), V(0.88, 0.44)]), xs, dark, 0.01)
    elif key == "gun_smg":
        cv.add(cap(cv, V(0.08, 0.5), V(0.26, 0.48), 0.018), xs, dark, 0.018)                                  # wire stock
        cv.add(cap(cv, V(0.08, 0.5), V(0.1, 0.62), 0.018), xs, dark, 0.018)
        cv.add(rect(cv, 0.42, 0.56, 0.52, 0.86), ys, dark, 0.04)                                              # long straight mag
        cv.add(rect(cv, 0.24, 0.38, 0.72, 0.56), xs, steel, 0.07, "chamfer")
        cv.add(cv.poly([V(0.28, 0.55), V(0.36, 0.55), V(0.33, 0.74), V(0.25, 0.74)]), ys, poly_, 0.03)
        cv.add(cap(cv, V(0.7, 0.45), V(0.86, 0.45), 0.03), xs, dark, 0.03)
        cv.add(rect(cv, 0.6, 0.56, 0.66, 0.66), ys, poly_, 0.02)
    elif key == "gun_shotgun":
        cv.add(cv.poly([V(0.03, 0.48), V(0.28, 0.44), V(0.3, 0.56), V(0.06, 0.68)]), xs, wood, 0.05)
        cv.add(rect(cv, 0.27, 0.42, 0.46, 0.56), xs, steel, 0.06, "chamfer")
        cv.add(cv.poly([V(0.3, 0.55), V(0.36, 0.55), V(0.34, 0.68), V(0.28, 0.68)]), ys, wood, 0.03)
        cv.add(cap(cv, V(0.44, 0.45), V(0.96, 0.45), 0.026), xs, dark, 0.026)                                 # barrel
        cv.add(cap(cv, V(0.44, 0.52), V(0.9, 0.52), 0.022), xs, steel, 0.022)                                 # tube
        cv.add(rect(cv, 0.56, 0.48, 0.74, 0.58), xs, wood, 0.04)                                              # pump
        for x in (0.6, 0.64, 0.68):
            cv.add(intersect(cap(cv, V(x, 0.48), V(x, 0.58), 0.006), rect(cv, 0.56, 0.48, 0.74, 0.58)), ys, M("wood", 0x5A3A1A), 0.006)
    elif key == "gun_sniper":
        cv.add(cv.poly([V(0.02, 0.5), V(0.26, 0.46), V(0.28, 0.58), V(0.04, 0.68)]), xs, wood, 0.05)
        cv.add(rect(cv, 0.24, 0.45, 0.52, 0.58), xs, steel, 0.06, "chamfer")
        cv.add(cv.poly([V(0.3, 0.57), V(0.36, 0.57), V(0.34, 0.7), V(0.28, 0.7)]), ys, wood, 0.03)
        cv.add(rect(cv, 0.5, 0.47, 0.7, 0.56), xs, wood, 0.04)
        cv.add(cap(cv, V(0.68, 0.5), V(0.98, 0.5), 0.015), xs, dark, 0.015)
        sc = cap(cv, V(0.3, 0.37), V(0.56, 0.37), 0.04)
        cv.add(sc, xs, dark, 0.04)                                                                             # scope
        cv.add(cv.circle(V(0.56, 0.37), 0.045), xs, dark, 0.045)
        cv.add(cv.ellipse(V(0.575, 0.37), 0.012, 0.03), xs, M("gem", 0x3A8AE0), 0.01)
        cv.add(rect(cv, 0.38, 0.4, 0.44, 0.46), xs, dark, 0.02)
        for sg in (-1, 1):
            cv.add(cap(cv, V(0.66, 0.56), V(0.66 + 0.06 * sg, 0.72), 0.012), ys, dark, 0.012)                 # bipod
    elif key == "gun_launcher":
        olive = M("leather", 0x5A6A3A)
        cv.add(cap(cv, V(0.06, 0.46), V(0.94, 0.46), 0.075), xs, olive, 0.075)                                # tube
        cv.add(rect(cv, 0.0, 0.38, 0.08, 0.54), xs, dark, 0.03)
        cv.add(rect(cv, 0.9, 0.37, 0.98, 0.55), xs, dark, 0.03)
        for x in (0.34, 0.56):
            cv.add(cv.poly([V(x, 0.52), V(x + 0.07, 0.52), V(x + 0.05, 0.7), V(x - 0.02, 0.7)]), ys, poly_, 0.03)
        cv.add(rect(cv, 0.44, 0.3, 0.58, 0.39), xs, dark, 0.02)
        cv.add(intersect(cap(cv, V(0.2, 0.46), V(0.8, 0.46), 0.08), rect(cv, 0.7, 0.3, 0.74, 0.6)), xs, M("soft", 0xC8A030), 0.02)
    elif key == "gun_arc":
        white, glow = M("soft", 0xD8DCE4), M("soft", 0x4AE8F0)
        cv.add(cv.poly([V(0.04, 0.5), V(0.24, 0.44), V(0.26, 0.58), V(0.06, 0.62)]), xs, white, 0.05)
        cv.add(cv.poly([V(0.22, 0.4), V(0.64, 0.38), V(0.7, 0.46), V(0.64, 0.58), V(0.22, 0.58)]), xs, white, 0.08, "chamfer")
        cv.add(cv.poly([V(0.3, 0.57), V(0.36, 0.57), V(0.34, 0.7), V(0.28, 0.7)]), ys, poly_, 0.03)
        cv.add(cap(cv, V(0.66, 0.48), V(0.96, 0.48), 0.02), xs, steel, 0.02)
        for x in (0.72, 0.8, 0.88):
            cv.add(abs(cv.ellipse(V(x, 0.48), 0.018, 0.05)) - 0.01, xs, "copper", 0.01)
        cv.add(rect(cv, 0.32, 0.44, 0.58, 0.5), xs, glow, 0.02)
        cv.add(cv.circle(V(0.96, 0.48), 0.03), xs, glow, 0.03)
    elif key == "gun_sidearm":
        cv.add(cv.poly([V(0.22, 0.34), V(0.82, 0.34), V(0.82, 0.48), V(0.22, 0.48)]), xs, steel, 0.05, "chamfer")   # slide
        cv.add(cv.poly([V(0.24, 0.47), V(0.46, 0.47), V(0.42, 0.84), V(0.24, 0.84), V(0.2, 0.6)]), ys, poly_, 0.06)  # grip
        cv.add(abs(cv.ellipse(V(0.52, 0.56), 0.07, 0.07)) - 0.014, ys, dark, 0.014)                            # trigger guard
        for x in (0.6, 0.66, 0.72):
            cv.add(cap(cv, V(x, 0.36), V(x, 0.46), 0.006), ys, dark, 0.006)
    elif key == "rifle_rounds":
        for k in range(3):
            x = 0.26 + k * 0.22
            cv.add(rect(cv, x - 0.07, 0.42, x + 0.07, 0.86), xs, brass, 0.07)
            cv.add(cv.poly(band(V(x, 0.43), V(x, 0.3), V(x, 0.16), 0.13, 0.02, 10)), xs, "copper", 0.06)
    elif key == "shotgun_shells":
        for k in range(2):
            x = 0.34 + k * 0.3
            cv.add(rect(cv, x - 0.11, 0.16, x + 0.11, 0.68), xs, M("soft", 0xC8282A), 0.11)
            cv.add(rect(cv, x - 0.12, 0.66, x + 0.12, 0.86), xs, brass, 0.06)
    elif key == "heavy_rounds":
        for k in range(2):
            x = 0.34 + k * 0.3
            cv.add(rect(cv, x - 0.09, 0.4, x + 0.09, 0.92), xs, brass, 0.09)
            cv.add(cv.poly(band(V(x, 0.41), V(x, 0.22), V(x, 0.06), 0.16, 0.02, 10)), xs, dark, 0.07)
    elif key == "rocket_ammo":
        a_, b_ = V(0.14, 0.86), V(0.86, 0.14)
        d, t = cv.capsule(a_ + (b_ - a_) * 0.15, a_ + (b_ - a_) * 0.62, 0.09)
        cv.add(d, t, M("leather", 0x5A6A3A), 0.09)
        cv.add(cv.poly(band(a_ + (b_ - a_) * 0.6, a_ + (b_ - a_) * 0.8, b_, 0.2, 0.02, 10)), t, dark, 0.08)
        for sg in (-1, 1):
            nrm = V(0.707, 0.707) * sg
            cv.add(cv.poly([a_ + (b_ - a_) * 0.12, a_ + (b_ - a_) * 0.3 + nrm * 0.08, a_ + (b_ - a_) * 0.05 + nrm * 0.16]), t, dark, 0.03)
    elif key == "arc_cell":
        cv.add(rect(cv, 0.26, 0.16, 0.74, 0.88), ys, M("metal", 0x6A707A), 0.08, "chamfer")
        cv.add(rect(cv, 0.4, 0.08, 0.6, 0.17), ys, "copper", 0.03)
        cv.add(rect(cv, 0.34, 0.28, 0.66, 0.78), ys, M("soft", 0x4AE8F0), 0.06)
        for y in (0.4, 0.53, 0.66):
            cv.add(cap(cv, V(0.36, y), V(0.64, y), 0.01), ys, M("soft", 0x1A6A7A), 0.01)
    return cv


GUN_POSE = {"gun_rifle": (0.42, 1.12), "gun_smg": (0.3, 1.15), "gun_shotgun": (0.45, 1.1), "gun_sniper": (0.45, 1.08),
            "gun_launcher": (0.45, 1.05), "gun_arc": (0.42, 1.1), "gun_sidearm": (0.15, 1.1)}
GUN_KEYS = ["gun_rifle", "gun_smg", "gun_shotgun", "gun_sniper", "gun_launcher", "gun_arc", "gun_sidearm",
            "rifle_rounds", "shotgun_shells", "heavy_rounds", "rocket_ammo", "arc_cell"]


def gun_sheet(out, n=128):
    imgs = [render(gun(Canvas(n, *GUN_POSE.get(k, (0.0, 1.0))), k)) for k in GUN_KEYS]
    art_sheet(imgs, n, 1, 6, out)
