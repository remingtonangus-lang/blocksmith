#!/usr/bin/env python3
"""Texture import pipeline: a large source image (generated or CC0 photo) -> a 128 px tileable block texture.

    python3 tools/teximport.py SRC.png NAME [--out Resources/Textures] [--size 128] [--mode plain|tint|overlay|cutout]
                               [--flatten 0.85] [--mean '#7c7c80'] [--report docs/textures/import_report.md]

Steps (each logged in the report):
  1. square crop (centre);
  2. internal-repeat check: a source that already tiles 2x2 inside itself (seen from Gemini) is cut to one quadrant;
  3. large-scale luminance flattening: the luminance blurred at 1/6 of the tile (wrapping) is divided out with
     strength --flatten, so big light/dark patches don't repeat as a visible grid across blocks;
  4. optional colour lock: --mean shifts the average colour to a palette target (style consistency with the
     procedural set);
  5. wrap-aware area downsample to --size (the source is tiled 3x3, resampled, and the middle cut out, so the
     filter sees across the seams);
  6. seam check: the jump across the wrap edges against the typical jump between neighbouring texels; above 1.6x the
     edges are cross-faded with a half-offset copy and re-checked;
  7. mode: tint = greyscale for biome tinting (grass top, leaves), mean grey 0.72 like the procedural set;
     overlay = grass side, green texels become grey with alpha 0.9 (the tinted overlay) and the rest stays;
     cutout = a magenta (#ff00ff) background becomes transparent (leaves, plants).
The result goes to OUT/NAME.png; build.sh bundles Resources/Textures into the app, and a file there replaces the
procedural material for that texture (Sources/TextureImport.swift). Trials go to another --out and are compared in
the game with `--texdir DIR`. Mips and the texture array are built by the game as for every layer.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image


def load(path):
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im).astype(np.float32) / 255
    h, w = a.shape[:2]
    s = min(h, w)
    y0, x0 = (h - s) // 2, (w - s) // 2
    return a[y0:y0 + s, x0:x0 + s]


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def mad(a, b):
    return float(np.mean(np.abs(a - b)))


def repeat_check(img):
    """Self-difference at half shifts against a quarter shift (the image's normal self-difference): a true 2x2
    internal repeat is tiny at both the x and the y half shift; a diagonal-only repeat (seen in a CC0 preview) is
    tiny at the diagonal shift only and has no tileable quadrant. Returns (2x2 ratio, diagonal ratio)."""
    L = lum(img[..., :3])
    s = L.shape[0]
    base = mad(L, np.roll(np.roll(L, s // 4 + 3, 0), s // 3 + 5, 1)) + 1e-6
    hx = mad(L, np.roll(L, s // 2, 1))
    hy = mad(L, np.roll(L, s // 2, 0))
    hd = mad(L, np.roll(np.roll(L, s // 2, 0), s // 2, 1))
    return max(hx, hy) / base, hd / base


def blur_wrap(f, sigma):
    """Gaussian blur with wrap-around, via FFT."""
    n = f.shape[0]
    k = np.fft.fftfreq(n)
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (k[:, None] ** 2 + k[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(f) * g))


def flatten(img, strength):
    if strength <= 0:
        return img
    rgb = img[..., :3]
    L = lum(rgb)
    B = blur_wrap(L, L.shape[0] / 6)
    gain = (L.mean() / np.maximum(B, 1e-3)) ** strength
    out = img.copy()
    out[..., :3] = np.clip(rgb * gain[..., None], 0, 1)
    return out


def resize_wrap(img, size):
    s = img.shape[0]
    t = np.tile(img, (3, 3, 1))
    im = Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), 'RGBA')
    im = im.resize((size * 3, size * 3), Image.LANCZOS, reducing_gap=3.0)
    a = np.asarray(im).astype(np.float32) / 255
    return a[size:size * 2, size:size * 2]


def seam_ratio(img):
    """Jump across the wrap edges / typical jump between neighbouring columns and rows."""
    L = lum(img[..., :3])
    inner = (np.mean(np.abs(np.diff(L, axis=1))) + np.mean(np.abs(np.diff(L, axis=0)))) / 2 + 1e-6
    edge = (np.mean(np.abs(L[:, 0] - L[:, -1])) + np.mean(np.abs(L[0, :] - L[-1, :]))) / 2
    return float(edge / inner)


def fix_seams(img):
    """Cross-fade with a half-offset copy near the edges (the offset copy is seamless at the original edges)."""
    n = img.shape[0]
    off = np.roll(np.roll(img, n // 2, 0), n // 2, 1)
    d = np.minimum(np.arange(n), n - 1 - np.arange(n)) / (n * 0.18)
    w1 = np.clip(d, 0, 1)
    w = np.minimum(w1[:, None], w1[None, :])[..., None]
    return img * w + off * (1 - w)


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def process(src, name, out, size=128, mode='plain', strength=0.85, mean=None, quiet=False):
    notes = []
    img = load(src)
    notes.append(f'source {img.shape[0]} px')
    r, rd = repeat_check(img)
    if r < 0.35:
        img = img[:img.shape[0] // 2, :img.shape[0] // 2]
        notes.append(f'internal 2x2 repeat (self-difference at half shift {r:.2f} of normal): cropped one quadrant')
    elif rd < 0.35:
        notes.append(f'diagonal internal repeat ({rd:.2f}): kept whole (no quadrant tiles); prefer another source')
    if mode == 'cutout':
        key = (img[..., 0] > 0.75) & (img[..., 2] > 0.75) & (img[..., 1] < 0.35)
        img[..., 3] = np.where(key, 0, img[..., 3])
        img[..., :3] = np.where(key[..., None], 0, img[..., :3])
    img = flatten(img, strength)
    if strength > 0:
        notes.append(f'large-scale luminance flattened (strength {strength})')
    if mean is not None:
        m = img[..., :3][img[..., 3] > 0.5].mean(0)
        img[..., :3] = np.clip(img[..., :3] * (hexrgb(mean) / np.maximum(m, 1e-3)), 0, 1)
        notes.append(f'colour locked to mean {mean}')
    img = resize_wrap(img, size)
    if mode == 'cutout':
        img[..., 3] = (img[..., 3] > 0.5).astype(np.float32)
    sr = seam_ratio(img)
    notes.append(f'seam ratio {sr:.2f}')
    if sr > 1.6:
        img = fix_seams(img)
        sr2 = seam_ratio(img)
        notes.append(f'seams cross-faded: ratio {sr2:.2f}')
        sr = sr2
    if mode == 'tint' or mode == 'cutout_tint':
        L = lum(img[..., :3])
        L = L * (0.72 / max(L[img[..., 3] > 0.5].mean(), 1e-3))
        img[..., :3] = np.clip(L, 0, 1)[..., None]
        notes.append('greyscale for biome tint (mean 0.72)')
    if mode == 'overlay':
        rgb = img[..., :3]
        green = (rgb[..., 1] > rgb[..., 0] * 1.08) & (rgb[..., 1] > rgb[..., 2] * 1.08)
        L = lum(rgb)
        g = np.clip(L * (0.72 / max(L[green].mean() if green.any() else 0.72, 1e-3)), 0, 1)
        img[..., :3] = np.where(green[..., None], g[..., None], rgb)
        img[..., 3] = np.where(green, 0.9, 1.0)
        notes.append(f'grass overlay: {green.mean() * 100:.0f}% of texels tinted (alpha 0.9)')
    os.makedirs(out, exist_ok=True)
    dst = os.path.join(out, name + '.png')
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(dst)
    if not quiet:
        print(f'{name}: ' + '; '.join(notes) + f' -> {dst}')
    return dst, notes, sr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('name')
    ap.add_argument('--out', default='Resources/Textures')
    ap.add_argument('--size', type=int, default=128)
    ap.add_argument('--mode', default='plain', choices=['plain', 'tint', 'overlay', 'cutout', 'cutout_tint'])
    ap.add_argument('--flatten', type=float, default=0.85)
    ap.add_argument('--mean')
    ap.add_argument('--report')
    a = ap.parse_args()
    dst, notes, sr = process(a.src, a.name, a.out, a.size, a.mode, a.flatten, a.mean)
    if a.report:
        with open(a.report, 'a') as f:
            f.write(f'- **{a.name}** from `{os.path.basename(a.src)}`: ' + '; '.join(notes) + '\n')
    sys.exit(0 if sr <= 1.6 else 1)


if __name__ == '__main__':
    main()
