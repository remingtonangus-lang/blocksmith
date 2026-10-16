#!/usr/bin/env python3
"""Texture lab (prototype, numpy + Pillow): compares ways to reach 128x128 block textures before the Swift port.
  current: the game's 16x16 tile (from a CI atlas dump), nearest-upscaled
  hd:      edge-preserving 8x upscale of our own art + fractal micro-detail + top-left relief lighting
  cc0:     a CC0 photo material resized to 128 and colour-matched to our tile's palette, lightly posterised
Usage: texlab.py ATLAS_PNG ASSET_DIR OUT_PNG"""
import sys, numpy as np
from PIL import Image, ImageDraw

atlas, assets, out = sys.argv[1], sys.argv[2], sys.argv[3]
A = np.asarray(Image.open(atlas).convert('RGBA')).astype(np.float32) / 255

def tile(c, r=0):
    x0, y0 = c * 50 + 2, r * 50 + 2
    return A[y0 + 1:y0 + 48:3, x0 + 1:x0 + 48:3][:16, :16]

def hash2(x, y, s):
    h = (x * 374761393 + y * 668265263 + s * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

def vnoise(n, cell, s):
    """Tileable value noise n x n with the given cell size."""
    g = n // cell
    grid = np.array([[hash2(i % g, j % g, s) for i in range(g + 1)] for j in range(g + 1)])
    grid[g, :] = grid[0, :]; grid[:, g] = grid[:, 0]
    y, x = np.mgrid[0:n, 0:n] / cell
    x0, y0 = x.astype(int), y.astype(int)
    tx, ty = x - x0, y - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = grid[y0, x0] + (grid[y0, x0 + 1] - grid[y0, x0]) * tx
    b = grid[y0 + 1, x0] + (grid[y0 + 1, x0 + 1] - grid[y0 + 1, x0]) * tx
    return a + (b - a) * ty

def hd(t16, detail=0.10, relief=0.9, s=1):
    n = 128; k = 8
    src = t16[..., :3]
    # Edge-preserving upsample: bilinear from the 4 nearest source texels, each weighted by colour similarity
    # to the texel the output pixel falls in (hard edges between different colours, soft gradients inside).
    yy, xx = np.mgrid[0:n, 0:n]
    fx, fy = (xx + 0.5) / k - 0.5, (yy + 0.5) / k - 0.5
    x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - x0, fy - y0
    own = src[(yy // k) % 16, (xx // k) % 16]
    acc = np.zeros((n, n, 3)); wsum = np.zeros((n, n, 1))
    for dy, dx, w in [(0, 0, (1 - tx) * (1 - ty)), (0, 1, tx * (1 - ty)), (1, 0, (1 - tx) * ty), (1, 1, tx * ty)]:
        c = src[(y0 + dy) % 16, (x0 + dx) % 16]
        sim = np.exp(-np.sum((c - own) ** 2, axis=2) / 0.004)[..., None]
        ww = w[..., None] * sim
        acc += c * ww; wsum += ww
    img = acc / np.maximum(wsum, 1e-6)
    # Micro-detail: fractal noise around 1 (luminance-preserving multiply).
    fn = 0.5 * vnoise(n, 32, s) + 0.3 * vnoise(n, 8, s + 1) + 0.2 * vnoise(n, 2, s + 2)
    img = img * (1 + (fn[..., None] - 0.5) * 2 * detail)
    # Relief: height from luminance, lit from the top-left.
    h = img.mean(axis=2) + (fn - 0.5) * 0.15
    sh = (h - np.roll(np.roll(h, 1, 0), 1, 1)) * relief
    img = img * (1 + sh[..., None])
    return np.clip(img, 0, 1)

def cc0(path, t16, levels=20):
    im = Image.open(path).convert('RGB').resize((128, 128), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255
    ref = t16[..., :3].reshape(-1, 3)
    # Colour transfer: match per-channel mean / std to our tile.
    a = (a - a.mean((0, 1))) / (a.std((0, 1)) + 1e-4) * ref.std(0) * 1.15 + ref.mean(0)
    a = np.round(np.clip(a, 0, 1) * levels) / levels
    return np.clip(a, 0, 1)

def big(a, size=256):
    return Image.fromarray((np.clip(a[..., :3], 0, 1) * 255).astype(np.uint8)).resize((size, size), Image.NEAREST)

rows = [('grass_block_top', 3, 'ambientcg_Grass001.jpg', 'pollinations_grass.jpg'), ('stone', 1, 'ambientcg_Rock064.jpg', None),
        ('dirt', 4, 'ambientcg_Ground111.jpg', None), ('oak_log', 10, 'polyhaven_bark_bark_brown_02.jpg', None),
        ('oak_planks', 6, 'ambientcg_WoodFloor043.jpg', None), ('cobblestone', 5, 'polyhaven_rock_aerial_rocks_02.jpg', None)]
cols = ['current 16 px', 'HD upscale (ours)', 'CC0 stylised', 'Pollinations']
W = 4 * 266 + 10; H = len(rows) * 290 + 40
sheet = Image.new('RGB', (W, H), (24, 24, 28)); d = ImageDraw.Draw(sheet)
for i, c in enumerate(cols): d.text((10 + i * 266, 10), c, fill=(230, 230, 230))
for r, (name, c, photo, poll) in enumerate(rows):
    t = tile(c)
    y = 30 + r * 290
    d.text((10, y), name, fill=(200, 200, 120))
    sheet.paste(big(t), (10, y + 16))
    sheet.paste(big(hd(t, s=c + 1)), (276, y + 16))
    sheet.paste(big(cc0(f'{assets}/{photo}', t)), (542, y + 16))
    if poll:
        p = np.asarray(Image.open(f'{assets}/{poll}').convert('RGB').resize((128, 128), Image.LANCZOS)).astype(np.float32) / 255
        sheet.paste(big(p), (808, y + 16))
sheet.save(out)
print('wrote', out)
