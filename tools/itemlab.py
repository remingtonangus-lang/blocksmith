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
    ("stone", "stone", 0x8C8C8E, 0x4C4C50, 0xC4C4C6), ("iron", "metal", 0xC9CED6, 0x5E646E, 0xFFFFFF),
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
    def __init__(self, n):
        self.n = n
        c = (np.arange(n, dtype=np.float32) + 0.5) / n
        self.X, self.Y = np.meshgrid(c, c)
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
        cx = X * 17
        cy = Y * 17 + 0.5 * np.mod(np.floor(X * 17), 2)
        rx = cx - np.floor(cx) - 0.5
        ry = cy - np.floor(cy) - 0.5
        rr = np.sqrt(rx * rx + ry * ry)
        ring = np.clip(1 - np.abs(rr - 0.3) / 0.13, 0, 1)
        e = env(view_r[..., 1])[..., None]
        metal = dark + (light - dark) * e
        col = col * 0.45 + metal * 0.55
        col = col * (0.5 + 0.65 * ring)[..., None] + (light - col) * (ring * (ry < -0.1) * 0.35)[..., None]
        col = col * (0.55 + 0.55 * np.clip(lam, 0, 1.2))
    return np.clip(col, 0, 1)


def shift(a, dx, dy, fill):
    out = np.full_like(a, fill)
    n = a.shape[0]
    out[dy:, dx:] = a[: n - dy, : n - dx]
    return out


def render(cv, bevel=0.03):
    n = cv.n
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
    return np.concatenate([rgb, a[..., None]], -1)


# MARK: designs (mirror ItemHD.tool / armor / common)

def handle(cv, a, b, r=0.04, m="handle"):
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
        bd = cv.poly(blade)
        cv.add(bd, t, head, 0.09, "chamfer")
        # Crossguard: a bar with flared ends and a centre boss.
        gd, gt = cv.capsule(g0 - nr * 0.15, g0 + nr * 0.15, 0.03)
        gd = union(gd, union(cv.circle(g0 - nr * 0.15, 0.042), cv.circle(g0 + nr * 0.15, 0.042)))
        cv.add(gd, gt, accent, 0.04)
        cv.add(cv.circle(g0, 0.04), gt, accent, 0.04)
    elif kind == "pickaxe":
        top = V(0.66, 0.34)
        handle(cv, V(0.12, 0.9), top + up * 0.02, 0.038)
        ctrl1, ctrl2 = top - rt * 0.2 + up * 0.1, top + rt * 0.2 + up * 0.1
        e1, e2 = top - rt * 0.42 - up * 0.06, top + rt * 0.42 - up * 0.06
        d = union(cv.poly(band(top + up * 0.02, ctrl1, e1, 0.13, 0.02, 16)), cv.poly(band(top + up * 0.02, ctrl2, e2, 0.13, 0.02, 16)))
        t = cv.axis(e1, e2)
        cv.add(d, t, head, 0.06, "chamfer")
        cd, ct = cv.capsule(top - rt * 0.05 + up * 0.02, top + rt * 0.05 + up * 0.02, 0.06)
        cv.add(cd, ct, accent if head != "wood" else "handle", 0.06)
    elif kind == "axe":
        top = V(0.62, 0.3)
        handle(cv, V(0.16, 0.9), top + up * 0.06, 0.04)
        edge = bez(V(0.70, 0.02), V(1.0, 0.16), V(0.84, 0.56), 12)
        pts = [V(0.52, 0.24), V(0.6, 0.16)] + edge + [V(0.7, 0.44), V(0.6, 0.38)]
        d = cv.poly(pts)
        t = cv.axis(V(0.55, 0.3), V(0.95, 0.3))
        cv.add(d, t, head, 0.05, "chamfer")
        inner = bez(V(0.73, 0.08), V(0.93, 0.19), V(0.81, 0.48), 12)
        strip = cv.poly(edge + inner[::-1])
        cv.add(intersect(strip, d + 0.004), t, edge_m, 0.03, "chamfer")
        # Butt (poll) behind the handle and the eye ring.
        cv.add(cv.poly([V(0.44, 0.22), V(0.52, 0.14), V(0.6, 0.22), V(0.52, 0.3)]), t, head, 0.04)
        cv.add(cv.circle(V(0.565, 0.255), 0.05), t, accent if head != "wood" else "handle", 0.05)
    elif kind == "shovel":
        handle(cv, V(0.13, 0.9), V(0.62, 0.42), 0.036)
        cv.add(*cv.capsule(V(0.07, 0.86), V(0.19, 0.97), 0.032), "handle", 0.03)
        c = V(0.73, 0.28)
        pts = [c - up * 0.13 + rt * 0.1]
        pts += bez(c + up * 0.0 + rt * 0.13, c + up * 0.17 + rt * 0.12, c + up * 0.24, 7)[0:]
        pts += bez(c + up * 0.24, c + up * 0.17 - rt * 0.12, c - rt * 0.13, 7)
        pts.append(c - up * 0.13 - rt * 0.1)
        bd = cv.poly(pts)
        cv.add(bd, cv.axis(V(0.6, 0.4), V(0.9, 0.1)), head, 0.08)
        cv.add(intersect(cv.capsule(c - up * 0.12, c + up * 0.14, 0.012)[0], bd + 0.02), cv.axis(V(0.6, 0.4), V(0.9, 0.1)), head, 0.012)
        cd, ct = cv.capsule(c - up * 0.17, c - up * 0.1, 0.045)
        cv.add(cd, ct, accent if head != "wood" else "handle", 0.045)
    elif kind == "hoe":
        top = V(0.68, 0.26)
        handle(cv, V(0.14, 0.9), top, 0.036)
        bd, bt = cv.capsule(top + V(0.02, -0.01), V(0.42, 0.14), 0.04)
        cv.add(bd, bt, head, 0.04)
        blade = cv.poly([V(0.3, 0.08), V(0.47, 0.1), V(0.45, 0.24), V(0.32, 0.47), V(0.2, 0.42), V(0.28, 0.22)])
        cv.add(blade, cv.axis(V(0.38, 0.08), V(0.26, 0.45)), head, 0.06, "chamfer")
        cv.add(intersect(cv.capsule(V(0.2, 0.42), V(0.32, 0.47), 0.03)[0], blade + 0.004), bt, edge_m, 0.02, "chamfer")
        cv.add(cv.circle(top, 0.05), bt, accent if head != "wood" else "handle", 0.05)
    else:
        b0 = V(0.68, 0.32)
        handle(cv, V(0.07, 0.95), b0, 0.03)
        tip = V(0.95, 0.05)
        sides1 = bez(b0, b0 + up * 0.12 + rt * 0.16, tip, 10)
        sides2 = bez(tip, b0 + up * 0.12 - rt * 0.16, b0, 10)
        cv.add(cv.poly(sides1 + sides2[1:-1]), cv.axis(b0, tip), head, 0.07, "chamfer")
        wraps(cv, b0 - up * 0.12, b0 + up * 0.0, 0.034, 3)


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
        else:
            cv.add(intersect(cv.capsule(V(0.2, 0.4), V(0.8, 0.4), 0.006)[0], d + 0.03), xs, "grip", 0.006)
    elif kind == "chestplate":
        torso = cv.poly([V(0.26, 0.2), V(0.4, 0.16), V(0.5, 0.28), V(0.6, 0.16), V(0.74, 0.2), V(0.76, 0.86), V(0.5, 0.92), V(0.24, 0.86)])
        cv.add(torso, ys, m, 0.3)
        cv.add(cv.poly(band(V(0.1, 0.44), V(0.11, 0.16), V(0.36, 0.16), 0.14, 0.11, 10)), xs, m, 0.07)
        cv.add(cv.poly(band(V(0.9, 0.44), V(0.89, 0.16), V(0.64, 0.16), 0.14, 0.11, 10)), xs, m, 0.07)
        cv.add(intersect(cv.poly(band(V(0.36, 0.17), V(0.5, 0.4), V(0.64, 0.17), 0.04, 0.04, 12)), torso + 0.0), xs, trim, 0.03)
        if not soft:
            cv.add(intersect(cv.capsule(V(0.5, 0.36), V(0.5, 0.86), 0.012)[0], torso + 0.03), ys, m, 0.012)
        for yy in (0.62, 0.76):
            cv.add(intersect(cv.capsule(V(0.24, yy), V(0.76, yy), 0.016)[0], torso), xs, trim if not soft else "grip", 0.016)
    elif kind == "leggings":
        d = cv.poly([V(0.22, 0.14), V(0.78, 0.14), V(0.82, 0.9), V(0.6, 0.9), V(0.5, 0.42), V(0.4, 0.9), V(0.18, 0.9)])
        cv.add(d, ys, m, 0.2)
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
