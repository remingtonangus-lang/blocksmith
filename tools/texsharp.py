#!/usr/bin/env python3
"""Texture sharpness at headset distance, measured on the Mac with the Quest's texture data and sampler maths.

  tools/texsharp.py [--tex stone,cobblestone,chest_front,oak_planks,grass_block_top] [--ppt 760] [--out DIR]

Why a model and not a capture: questcheck's render test runs on Linux CI only, and the headset adds lens and
compositor resampling no capture shows. So this renders, in numpy, what the Quest's fragment shaders sample:
  * the texture array the APK builds (tools/texpack.py tile size; TextureGen.mipChain mips: box or Lanczos-2),
  * the sampler (quest/src/vk/SceneRenderer.swift: mag nearest/linear, trilinear min, anisotropy N with the Vulkan
    LOD = log2(major / min(major/minor, N)) and N taps along the major axis),
  * the shader's sharp-bilinear magnification (quest/shaders/common.glsl texSharp),
into a Quest 3 eye buffer: --ppt pixels per unit tangent at the view centre (the runtime-recommended 1680 px over a
per-eye tangent span of about 2.2 gives ~760, i.e. a 1 m block at d metres covers 760/d px).
Scenes: a wall face-on at 1, 2 and 4 m (the blurry bedroom, 09:24 notes) and the ground seen standing (eye 1.62 m,
pitch -15: 4-12 m away, where mips and anisotropy decide). Metrics:
  walls   texel detail = Laplacian variance of the render averaged back onto the 128 px art grid / the art's own
          (1.00 = every texel's own value reaches the eye; < 1 = blurred), texel psnr = dB of those averages against
          the art, edge pop = 99.5th-percentile frame-to-frame change over a quarter-pixel head drift / the
          reference's (reference = the art 4x4 supersampled with bilinear reconstruction; > 1 = texel edges popping
          and crawling, nearest's stair-steps).
  ground  detail = screen Laplacian variance / the 16-spp reference's (> 1 = aliasing, < 1 = blur), psnr = dB
          against it, shimmer = mean frame-to-frame change over the drift / the reference's.
With --out, writes strips (reference, then each config left to right) per texture and scene.
  tools/texsharp.py --noise a.png,b.png   ground-noise numbers for grass tops (see noise()).
"""
import argparse
import math
import os

import numpy as np
from PIL import Image

LANCZOS2 = np.array([-0.0089, -0.0483, 0.1209, 0.4363, 0.4363, 0.1209, -0.0483, -0.0089])
LANCZOS2 /= LANCZOS2.sum()
ART = 128                          # uv unit: one texel of the 128 px art


def load(name, n):
    """The layer as the Quest gets it: texpack.py box-reduces the PNG to the tile size (opaque layers here)."""
    im = Image.open(os.path.join("Resources/Textures", name + ".png")).convert("RGB")
    if im.size[0] > n:
        im = im.reduce(im.size[0] // n)
    elif im.size[0] < n:
        im = im.resize((n, n), Image.NEAREST)
    a = np.asarray(im).astype(np.float64) / 255
    if name == "grass_block_top":
        a = a * np.array([0.47, 0.70, 0.30]) / 0.72            # plains-like biome tint on the greyscale art
    return a


def mips(base, kind):
    levels = [base]
    while levels[-1].shape[0] > 1:
        p = levels[-1]
        if kind == "box" or p.shape[0] < 8:
            q = (p[0::2, 0::2] + p[1::2, 0::2] + p[0::2, 1::2] + p[1::2, 1::2]) / 4
        else:                                                    # separable Lanczos-2, wrapping (tiles repeat)
            t = sum(w * np.roll(p, 3 - k, axis=1) for k, w in enumerate(LANCZOS2))[:, 0::2]
            q = np.clip(sum(w * np.roll(t, 3 - k, axis=0) for k, w in enumerate(LANCZOS2))[0::2], 0, 1)
        levels.append(q)
    return levels


def bilinear(L, n0, u, v):
    """u, v in level-0 texels of an n0-px layer; L is any of its levels."""
    s = L.shape[0]
    x, y = u * s / n0 - 0.5, v * s / n0 - 0.5
    x0, y0 = np.floor(x), np.floor(y)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    x0, y0 = x0.astype(int) % s, y0.astype(int) % s
    x1, y1 = (x0 + 1) % s, (y0 + 1) % s
    return L[y0, x0] * (1 - fx) * (1 - fy) + L[y0, x1] * fx * (1 - fy) + L[y1, x0] * (1 - fx) * fy + L[y1, x1] * fx * fy


def nearest(L, n0, u, v):
    s = L.shape[0]
    return L[np.floor(v * s / n0).astype(int) % s, np.floor(u * s / n0).astype(int) % s]


def sharp_axis(t, fw):
    """common.glsl texSharp, one axis: flat texel interiors, the edge blended over about one screen pixel;
    exactly t once a texel is a pixel or smaller (fw >= 1)."""
    seam = np.floor(t + 0.5)
    d = np.clip(fw, 1e-6, 1.0)
    return seam + np.clip((t - seam) / d, -0.5, 0.5)


def sample(cfg, u, v, dux, dvx, duy, dvy):
    """One texture() call. u, v and derivatives in art texels; converted to this layer's texels."""
    levels, n0 = cfg["levels"], cfg["n"]
    s = n0 / ART
    u, v, dux, dvx, duy, dvy = u * s, v * s, dux * s, dvx * s, duy * s, dvy * s
    if cfg["sharp"]:
        u, v = sharp_axis(u, np.abs(dux) + np.abs(duy)), sharp_axis(v, np.abs(dvx) + np.abs(dvy))
    lx, ly = np.hypot(dux, dvx), np.hypot(duy, dvy)
    major, minor = np.maximum(lx, ly), np.maximum(np.minimum(lx, ly), 1e-9)
    ratio = np.minimum(major / minor, cfg["aniso"]) if cfg["aniso"] > 1 else np.ones_like(major)
    lod = np.log2(np.maximum(major / ratio, 1e-9))
    ax = np.where((lx >= ly)[..., None], np.stack([dux, dvx], -1), np.stack([duy, dvy], -1))
    out = np.zeros(u.shape + (3,))
    magm = lod <= 0
    if magm.any():
        f = nearest if cfg["mag"] == "nearest" else bilinear
        out[magm] = f(levels[0], n0, u[magm], v[magm])
    mm = ~magm
    if mm.any():
        uu, vv, rr, aa = u[mm], v[mm], ratio[mm], ax[mm]
        ll = np.minimum(lod[mm], len(levels) - 1)
        taps = np.ceil(rr - 1e-6).astype(int)
        l0 = np.floor(ll).astype(int)
        fl = (ll - l0)[..., None]
        acc = np.zeros(uu.shape + (3,))
        for k in range(int(taps.max())):
            use = k < taps
            t = np.where(use, (k + 0.5) / taps - 0.5, 0.0)
            su, sv = uu + aa[:, 0] * t, vv + aa[:, 1] * t
            c = np.zeros(uu.shape + (3,))
            for lev in np.unique(l0):
                m = l0 == lev
                lo = bilinear(levels[lev], n0, su[m], sv[m])
                hi = bilinear(levels[min(lev + 1, len(levels) - 1)], n0, su[m], sv[m])
                c[m] = lo * (1 - fl[m]) + hi * fl[m]
            acc += np.where(use[..., None], c, 0)
        out[mm] = acc / taps[..., None]
    return out


def uv_at(kind, d, w, ppt, ox, oy):
    """Art-texel uv of every pixel centre (offset by ox, oy pixels)."""
    ys, xs = np.mgrid[0:w, 0:w].astype(np.float64)
    tx, ty = (xs - w / 2 + ox) / ppt, (ys - w / 2 + oy) / ppt
    if kind == "wall":
        return tx * d * ART + 0.37 * ART, ty * d * ART + 0.21 * ART
    p = math.radians(-15)                                        # far ground: eye 1.62 m, pitch -15 (4-12 m away)
    dy = -ty * math.cos(p) + math.sin(p)
    dz = -(ty * math.sin(p) + math.cos(p))
    t = 1.62 / np.maximum(-dy, 1e-6)
    return tx * t * ART, dz * t * ART


def render(cfg, kind, d, w, ppt, ox=0.0):
    u, v = uv_at(kind, d, w, ppt, ox, 0)
    u1, v1 = uv_at(kind, d, w, ppt, ox + 1, 0)
    u2, v2 = uv_at(kind, d, w, ppt, ox, 1)
    return sample(cfg, u, v, u1 - u, v1 - v, u2 - u, v2 - v)


def reference(art, kind, d, w, ppt, ox=0.0):
    acc = np.zeros((w, w, 3))
    for j in range(4):
        for i in range(4):
            u, v = uv_at(kind, d, w, ppt, ox + (i + 0.5) / 4 - 0.5, (j + 0.5) / 4 - 0.5)
            acc += bilinear(art, ART, u, v)
    return acc / 16


def lapvar(g):
    """Laplacian variance of a luminance image (wrapping)."""
    return (-4 * g + np.roll(g, 1, 0) + np.roll(g, -1, 0) + np.roll(g, 1, 1) + np.roll(g, -1, 1)).var()


def lum(img):
    return img @ np.array([0.299, 0.587, 0.114])


def texel_means(img, u, v):
    """Mean of the screen pixels inside each art texel (wall scenes cover the whole 128 x 128 tile)."""
    idx = (np.floor(v).astype(int) % ART) * ART + np.floor(u).astype(int) % ART
    g = lum(img).ravel()
    cnt = np.bincount(idx.ravel(), minlength=ART * ART)
    return (np.bincount(idx.ravel(), g, minlength=ART * ART) / np.maximum(cnt, 1)).reshape(ART, ART)


def psnr(a, b):
    return 10 * math.log10(1 / max(((a - b) ** 2).mean(), 1e-12))


def pop(frames):
    """99.5th percentile of the frame-to-frame change over the head drift (texel edges popping)."""
    return np.percentile(np.concatenate([np.abs(lum(x) - lum(y)).ravel() for x, y in zip(frames[:-1], frames[1:])]), 99.5)


CONFIGS = [
    ("0.95: 64 px, nearest, box mips, aniso 4", dict(n=64, mag="nearest", mips="box", aniso=4, sharp=False)),
    ("128 px, nearest, box mips, aniso 4", dict(n=128, mag="nearest", mips="box", aniso=4, sharp=False)),
    ("128 px, linear, Lanczos mips, aniso 8", dict(n=128, mag="linear", mips="lanczos", aniso=8, sharp=False)),
    ("new: 128 px, sharp-bilinear, Lanczos mips, aniso 8", dict(n=128, mag="linear", mips="lanczos", aniso=8, sharp=True)),
]


def noise(paths):
    """Ground noise of a top texture (scorecard "grass calm"): close detail = std of the luminance high-pass at 128 px
    (texel minus its 3x3 mean) over the mean, what reads at 1-2 m; far pattern = std of the 16 px Lanczos mip over the
    mean, the blotches that repeat block after block at 8+ m (lower = calmer, no visible tiling grid)."""
    for p in paths:
        im = Image.open(p).convert("RGB")
        if im.size[0] != ART:
            im = im.resize((ART, ART), Image.LANCZOS)
        g = lum(np.asarray(im).astype(np.float64) / 255)
        blur = sum(np.roll(np.roll(g, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9
        far = lum(mips(np.asarray(im).astype(np.float64) / 255, "lanczos")[3])
        print(f"{p}: close detail {(g - blur).std() / g.mean():.3f}  far pattern {far.std() / far.mean():.3f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", default="stone,cobblestone,chest_front,oak_planks,grass_block_top")
    ap.add_argument("--ppt", type=float, default=760)
    ap.add_argument("--out")
    ap.add_argument("--noise", help="comma-separated top-texture PNGs: print ground-noise numbers and stop")
    a = ap.parse_args()
    if a.noise:
        noise(a.noise.split(","))
        return
    if a.out:
        os.makedirs(a.out, exist_ok=True)
    print("walls (texel detail = Laplacian variance of the per-texel means / the art's; texel psnr dB; edge pop vs reference)")
    print("far ground (detail = screen Laplacian variance / reference; psnr dB vs 16-spp reference; shimmer = mean change / reference)")
    for i, (c, _) in enumerate(CONFIGS):
        print(f"  [{i}] {c}")
    totals = {}
    for name in a.tex.split(","):
        art = load(name, ART)
        art_lv = lapvar(lum(art))
        for _, c in CONFIGS:
            c["levels"] = mips(load(name, c["n"]), c["mips"])
        for kind, d in [("wall", 1.0), ("wall", 2.0), ("wall", 4.0), ("ground", 0)]:
            w = int(a.ppt / d) + 4 if kind == "wall" else 192
            refs = [reference(art, kind, d, w, a.ppt, ox=k * 0.25) for k in range(4)]
            u, v = uv_at(kind, d, w, a.ppt, 0, 0)
            row, imgs = [], []
            for i, (cname, c) in enumerate(CONFIGS):
                frames = [render(c, kind, d, w, a.ppt, ox=k * 0.25) for k in range(4)]
                if kind == "wall":
                    tm = texel_means(frames[0], u, v)
                    m = (lapvar(tm) / art_lv, psnr(tm, lum(art)), pop(frames) / max(pop(refs), 1e-6))
                else:
                    mot = np.mean([np.abs(x - y).mean() for x, y in zip(frames[:-1], frames[1:])])
                    ref_mot = np.mean([np.abs(x - y).mean() for x, y in zip(refs[:-1], refs[1:])])
                    m = (lapvar(lum(frames[0])) / lapvar(lum(refs[0])), psnr(frames[0], refs[0]), mot / max(ref_mot, 1e-9))
                totals.setdefault((kind, i), []).append(m)
                row.append(f"[{i}] {m[0]:4.2f} {m[1]:4.1f} {m[2]:4.2f}")
                imgs.append(frames[0])
            label = "ground" if kind == "ground" else f"wall{d:g}m"
            print(f"{name:16} {label:8} " + "  ".join(row))
            if a.out:
                crop = min(w, 192)
                strip = np.concatenate([refs[0][:crop, :crop]] + [im[:crop, :crop] for im in imgs], axis=1)
                Image.fromarray((np.clip(strip, 0, 1) * 255).astype(np.uint8)).save(os.path.join(a.out, f"texsharp-{name}-{label}.png"))
    for kind in ("wall", "ground"):
        for i, (c, _) in enumerate(CONFIGS):
            t = np.array(totals[(kind, i)])
            names = ("texel detail", "texel psnr", "edge pop") if kind == "wall" else ("detail", "psnr", "shimmer")
            print(f"mean {kind:6} [{i}] {names[0]} {t[:, 0].mean():.2f}  {names[1]} {t[:, 1].mean():.1f}  {names[2]} {t[:, 2].mean():.2f}")


if __name__ == "__main__":
    main()
