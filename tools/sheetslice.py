#!/usr/bin/env python3
"""Slice Gemini texture sheets (NxN grids) into game textures.

Spec: docs/textures/sheets.json, one entry per sheet:
  {"sheet": "assets/gemini/sheets/s01_terrain.png", "grid": 4, "crop": 0.06,
   "tiles": [["grass_block_top:tint", "dirt", ...], ...], "stylise": 0.5, "maxsat": 0.5}
A tile may end in "#0.17" to crop more of that cell (e.g. round end grain) and/or "%30" to raise its
minimum luminance spread (min_contrast target, default the sheet's minstd or 13).
A tile is "name[:mode][@base]"; "-" skips the cell. mode is a tools/teximport.py mode (plain by default)
or 'single' (a face that is not meant to repeat, e.g. log end grain: resampled only).
"@base" marks an ore: the mineral pixels (far from the tile's median rock colour) are composited onto the
already-imported texture `base`, so every ore sits on exactly the same stone as the plain block.

  python3 tools/sheetslice.py [--only s02] [--out Resources/Textures]
Tiles go to build/texgen/tiles/<name>.png, finished textures to --out (128 px, via teximport).
"""
import argparse, json, os, subprocess, sys
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def cut(sheet, grid, crop):
    w, h = sheet.size
    tw, th = w / grid, h / grid
    for r in range(grid):
        for c in range(grid):
            x0, y0 = c * tw, r * th
            m = crop * tw
            yield r, c, sheet.crop((int(x0 + m), int(y0 + m), int(x0 + tw - m), int(y0 + th - m)))


def recrop(sheet, grid, r, c, crop):
    for rr, cc, t in cut(sheet, grid, crop):
        if (rr, cc) == (r, c):
            return t


def stylise(tile, amount):
    """Shared finishing so photo-like and painted sheets meet in one look: soften fine grain, mute colour."""
    if amount <= 0:
        return tile
    rgb = tile.convert('RGB')
    soft = rgb.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.SMOOTH_MORE)
    out = Image.blend(rgb, soft, amount)
    from PIL import ImageEnhance
    out = ImageEnhance.Color(out).enhance(1.0 - 0.25 * amount)
    if tile.mode == 'RGBA':
        out.putalpha(tile.getchannel('A'))
    return out


def cap_saturation(path, cap):
    """Natural muted palette: scale chroma so the tile's mean colour has HLS saturation <= cap."""
    import colorsys
    import numpy as np
    im = np.asarray(Image.open(path).convert('RGBA'), dtype=np.float32) / 255
    m = im[..., :3][im[..., 3] > 0.5].mean(0)
    _, _, sat = colorsys.rgb_to_hls(*m)
    if sat <= cap:
        return
    L = (im[..., :3] * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    lo, hi = 0.0, 1.0   # bisect the chroma gain that brings the mean to the cap
    for _ in range(20):
        k = (lo + hi) / 2
        mm = np.clip(L + (im[..., :3] - L) * k, 0, 1)[im[..., 3] > 0.5].mean(0)
        if colorsys.rgb_to_hls(*mm)[2] > cap:
            hi = k
        else:
            lo = k
    im[..., :3] = np.clip(L + (im[..., :3] - L) * lo, 0, 1)
    Image.fromarray((im * 255 + 0.5).astype(np.uint8)).save(path)


def min_contrast(path, target):
    """Subtle surface detail must survive the 64 px mip: lift the luminance spread to `target` (gain <= 2.5)."""
    im = Image.open(path).convert('RGBA')
    from PIL import ImageStat
    st = ImageStat.Stat(im.convert('L'))
    sd, mean = st.stddev[0], st.mean[0]
    if sd >= target or sd < 0.5:
        return
    k = min(2.5, target / sd)
    px = [tuple(max(0, min(255, int(mean + (c - mean) * k))) for c in p[:3]) + (p[3],) for p in im.getdata()]
    im.putdata(px)
    im.save(path)


def despill(path):
    """Magenta-key cutouts: drop the magenta fringe (spill = min(r, b) - g) and erode alpha by one texel."""
    im = Image.open(path).convert('RGBA')
    a = im.getchannel('A').filter(ImageFilter.MinFilter(3))
    px = []
    for r, g, b, _ in im.getdata():
        sp = max(0, min(r, b) - g)
        px.append((max(0, r - sp), g, max(0, b - sp)))
    rgb = Image.new('RGB', im.size); rgb.putdata(px)
    rgb.putalpha(a)
    rgb.save(path)


def ore_composite(tile, base_path, size, lo=38.0, hi=80.0):
    """Mineral pixels of `tile` over the finished base texture."""
    tile = tile.convert('RGB').resize((size, size), Image.LANCZOS)
    base = Image.open(base_path).convert('RGB').resize((size, size), Image.LANCZOS)
    px = list(tile.getdata())
    # median rock colour per channel
    med = [sorted(p[i] for p in px)[len(px) // 2] for i in range(3)]
    # colour counts double: soft verdigris / rust stains differ from the rock in hue more than in brightness
    def dist_of(p):
        d = [p[i] - med[i] for i in range(3)]
        m = sum(d) / 3
        return (m * m * 3 + 2 * sum((x - m) ** 2 for x in d)) ** 0.5
    dist = [dist_of(p) for p in px]
    mask = Image.new('L', (size, size))
    mask.putdata([int(255 * min(1.0, max(0.0, (d - lo) / (hi - lo)))) for d in dist])
    mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return Image.composite(tile, base, mask)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', default=os.path.join(ROOT, 'docs/textures/sheets.json'))
    ap.add_argument('--only')
    ap.add_argument('--out', default=os.path.join(ROOT, 'Resources/Textures'))
    ap.add_argument('--size', type=int, default=128)
    a = ap.parse_args()
    spec = json.load(open(a.spec))
    tiles_dir = os.path.join(ROOT, 'build/texgen/tiles')
    os.makedirs(tiles_dir, exist_ok=True)
    os.makedirs(a.out, exist_ok=True)
    ores = []
    for s in spec:
        if a.only and not any(k in s['sheet'] for k in a.only.split(',')):
            continue
        sheet = Image.open(os.path.join(ROOT, s['sheet'])).convert('RGBA')
        for r, c, tile in cut(sheet, s['grid'], s.get('crop', 0.06)):
            entry = s['tiles'][r][c]
            if entry == '-':
                continue
            base = None
            crop = None
            minstd = s.get('minstd', 13.0)
            if '%' in entry:
                entry, minstd = entry.split('%')
                minstd = float(minstd)
            if '#' in entry:
                entry, crop = entry.split('#')
                tile = recrop(sheet, s['grid'], r, c, float(crop))
            if '@' in entry:
                entry, base = entry.split('@')
            name, _, mode = entry.partition(':')
            mode = mode or 'plain'
            src = os.path.join(tiles_dir, name + '.png')
            if base:
                ores.append((tile, name, base, mode, s.get('ore', [38.0, 80.0])))
                continue
            tile = stylise(tile, s.get('stylise', 0.0))
            tile.save(src)
            if mode == 'single':  # one face per block (log end grain): no seam blending, just resample
                tile.convert('RGBA').resize((a.size, a.size), Image.LANCZOS).save(os.path.join(a.out, name + '.png'))
                if s.get('maxsat', 0.55) < 1:
                    cap_saturation(os.path.join(a.out, name + '.png'), s.get('maxsat', 0.55))
                print(name, mode, 'ok')
                continue
            cmd = [sys.executable, os.path.join(ROOT, 'tools/teximport.py'), src, name, '--out', a.out,
                   '--size', str(a.size), '--mode', mode] + s.get('args', ['--flatten', '0.35'])
            res = subprocess.run(cmd, capture_output=True, text=True)
            if mode.startswith('cutout'):
                despill(os.path.join(a.out, name + '.png'))
            else:
                min_contrast(os.path.join(a.out, name + '.png'), minstd)
            if s.get('maxsat', 0.55) < 1 and os.path.exists(os.path.join(a.out, name + '.png')):
                cap_saturation(os.path.join(a.out, name + '.png'), s.get('maxsat', 0.55))
            print(name, mode, 'ok' if res.returncode == 0 else ('seam-warn' if os.path.exists(os.path.join(a.out, name + '.png')) else 'FAIL ' + res.stderr[-300:]))
    for tile, name, base, mode, (lo, hi) in ores:
        bp = os.path.join(a.out, base + '.png')
        if not os.path.exists(bp):
            print(name, 'FAIL base missing', base)
            continue
        ore_composite(tile, bp, a.size, lo, hi).save(os.path.join(a.out, name + '.png'))
        print(name, 'ore on', base)


if __name__ == '__main__':
    main()
