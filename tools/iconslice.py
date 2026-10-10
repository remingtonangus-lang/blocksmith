#!/usr/bin/env python3
"""Slice Gemini item-icon sheets (NxN grid, items on flat magenta) into item_<name>.png sprites.

Spec: docs/textures/icons.json, one entry per sheet:
  {"sheet": "assets/gemini/icons/i01_tools.jpg", "grid": 4, "tiles": [["wooden_pickaxe", ...], ...]}
"-" skips a cell. Output: Resources/Textures/item_<name>.png at --size (default 64), straight alpha.
The magenta key is tolerant (JPEG sheets): distance to the sampled background colour, soft edge, de-spilled.
"""
import argparse, json, os
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def key_cell(cell, bg):
    cell = cell.convert('RGB')
    w, h = cell.size
    px = cell.load()
    a = Image.new('L', (w, h))
    ap = a.load()
    out = Image.new('RGBA', (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # magenta-ness: red and blue high, green low
            m = min(r, b) - g
            mb = min(bg[0], bg[2]) - bg[1]
            t = m / max(1, mb)                 # 1 = background, 0 = item
            al = max(0.0, min(1.0, (0.85 - t) / 0.35))
            ap[x, y] = int(al * 255)
            if al > 0 and m > 0:              # de-spill the magenta fringe
                k = min(m, int(m * (1 - al) + m * 0.5))
                r, b = r - k, b - k
            op[x, y] = (max(0, r), g, max(0, b), 0)
    a = a.filter(ImageFilter.MinFilter(3))     # eat the JPEG halo by one pixel
    out.putalpha(a)
    return out


def fit(img, size, fill=0.9, bottom=False):
    bbox = img.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    if not bbox:
        return None
    img = img.crop(bbox)
    w, h = img.size
    s = fill * size / max(w, h)
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    # premultiply for the resize so edges don't pick up dark fringes
    r, g, b, a = img.split()
    pm = Image.merge('RGBA', [Image.composite(c, Image.new('L', img.size), a) for c in (r, g, b)] + [a])
    pm = pm.resize((nw, nh), Image.LANCZOS)
    data = []
    for (cr, cg, cb, ca) in pm.getdata():
        if ca == 0:
            data.append((0, 0, 0, 0))
        else:
            f = 255.0 / ca
            data.append((min(255, int(cr * f)), min(255, int(cg * f)), min(255, int(cb * f)), ca))
    pm.putdata(data)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.paste(pm, ((size - nw) // 2, size - nh if bottom else (size - nh) // 2))
    return canvas


def as_block_cutout(icon, tint):
    """Plant sheets ("plants": true): hard 0/255 alpha like the procedural cutouts; "=name:...:tint" cells become
    greyscale at mean 0.72 so the biome tint colours them (grass, ferns), like teximport's cutout_tint."""
    px = icon.load()
    w, h = icon.size
    lum = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= 128 else 0)
            if a >= 128:
                lum.append(0.299 * r + 0.587 * g + 0.114 * b)
    if tint and lum:
        k = 0.72 * 255 / max(sum(lum) / len(lum), 1)
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a:
                    v = min(255, int((0.299 * r + 0.587 * g + 0.114 * b) * k))
                    px[x, y] = (v, v, v, 255)
    return icon


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', default=os.path.join(ROOT, 'docs/textures/icons.json'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'Resources/Textures'))
    ap.add_argument('--size', type=int, default=64)
    ap.add_argument('--only', help='only this sheet (substring)')
    a = ap.parse_args()
    for s in json.load(open(a.spec)):
        if a.only and a.only not in s['sheet']:
            continue
        sheet = Image.open(os.path.join(ROOT, s['sheet'])).convert('RGB')
        g = s['grid']
        W, H = sheet.size
        bg = sheet.getpixel((3, 3))
        inset = s.get('inset', 0.02)
        for row, names in enumerate(s['tiles']):
            for col, name in enumerate(names):
                if name == '-':
                    continue
                name, _, f = name.partition(':')     # "iron_nugget:0.55": smaller than the cell fill
                f, _, mode = f.partition(':')         # "=fern:0.9:tint": plant cell, greyscale for the biome tint
                x0, y0 = W * col / g, H * row / g
                cw, ch = W / g, H / g
                box = (int(x0 + cw * inset), int(y0 + ch * inset), int(x0 + cw * (1 - inset)), int(y0 + ch * (1 - inset)))
                plants = s.get('plants', False)       # cross/cutout block sprites: standing on the block's bottom
                icon = fit(key_cell(sheet.crop(box), bg), a.size, float(f) if f else s.get('fill', 0.9), bottom=plants)
                if icon is None:
                    print(name, 'EMPTY')
                    continue
                if plants:
                    icon = as_block_cutout(icon, mode == 'tint')
                # "=heart": a raw layer name (HUD icons), otherwise item_<name>
                fn = name[1:] if name.startswith('=') else 'item_' + name
                icon.save(os.path.join(a.out, fn + '.png'))
                print(name, 'ok')
    hud_halves(a.out)


def empty_of(full):
    """A dark, hollow container in the full icon's silhouette (heart/food/armour 'empty' slots)."""
    al = full.getchannel('A')
    inner = al.filter(ImageFilter.MinFilter(5))
    base = Image.new('RGBA', full.size, (28, 24, 22, 0))
    base.putalpha(Image.eval(al, lambda v: int(v * 0.55)))
    edge = Image.new('RGBA', full.size, (12, 10, 9, 0))
    edge.putalpha(Image.composite(Image.new('L', full.size, 0), al, inner))
    base.alpha_composite(edge)
    return base


def hud_halves(out):
    """<x>_half = left half of <x> over the empty slot; <x>_empty derived when a full HUD icon was cut."""
    groups = [('heart', 'heart_empty', ['heart', 'heart_gold', 'heart_poison', 'heart_wither']),
              ('food', 'food_empty', ['food']), ('armor', 'armor_empty', ['armor'])]
    for shape, empty_name, fulls in groups:
        sp = os.path.join(out, shape + '.png')
        if not os.path.exists(sp):
            continue
        empty = empty_of(Image.open(sp).convert('RGBA'))
        empty.save(os.path.join(out, empty_name + '.png'))
        for f in fulls:
            fp = os.path.join(out, f + '.png')
            if not os.path.exists(fp):
                continue
            full = Image.open(fp).convert('RGBA')
            half = empty.copy()
            w, h = full.size
            half.paste(full.crop((0, 0, w // 2, h)), (0, 0))
            half.save(os.path.join(out, f + '_half.png'))


if __name__ == '__main__':
    main()
