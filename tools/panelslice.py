#!/usr/bin/env python3
"""Slice Gemini sheets of tall or keyed panels (doors, trapdoors, two-block plants) into block layers.

Spec: docs/textures/panels.json, one entry per sheet:
  {"sheet": "assets/gemini/sheets/g01_doors.jpg", "cols": 4, "rows": 2, "inset": 0.01, "mode": "door",
   "tiles": [["oak_door", ...], ...]}
Modes (openings and backgrounds painted flat magenta are keyed out with tools/iconslice.py's key):
  door    a 1x2 cell -> <name>_top and <name>_bottom (128 px each, hard alpha: the windows)
  square  a square cell -> <name> (128 px, hard alpha: trapdoor slots, glass, rails); "name:tint" greyscale for
          the biome tint (vines, lily pads)
  plant   a 1x2 cell, the plant standing on the bottom edge -> <name>_top / <name>_bottom (64 px, cutout);
          "name:tint" makes it greyscale for the biome tint, "name:1" saves the whole plant in one square layer,
          "name:top" only the top half (hanging vines).
"-" skips a cell.
  python3 tools/panelslice.py [--only g01] [--out Resources/Textures]
"""
import argparse, json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from iconslice import key_cell, as_block_cutout   # noqa: E402


def premul_resize(img, size):
    """Resize straight-alpha RGBA without dark fringes (premultiply, resize, unpremultiply)."""
    r, g, b, a = img.split()
    pm = Image.merge('RGBA', [Image.composite(c, Image.new('L', img.size), a) for c in (r, g, b)] + [a])
    pm = pm.resize(size, Image.LANCZOS)
    data = []
    for (cr, cg, cb, ca) in pm.getdata():
        if ca == 0:
            data.append((0, 0, 0, 0))
        else:
            f = 255.0 / ca
            data.append((min(255, int(cr * f)), min(255, int(cg * f)), min(255, int(cb * f)), ca))
    pm.putdata(data)
    return pm


def hard(img):
    a = img.getchannel('A').point(lambda v: 255 if v >= 128 else 0)
    img.putalpha(a)
    return img


def plant_canvas(keyed, w, h, fill=0.96):
    """The plant cropped to its bounding box, scaled to fit w x h, standing on the bottom edge."""
    bbox = keyed.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    if not bbox:
        return None
    p = keyed.crop(bbox)
    s = min(fill * w / p.size[0], fill * h / p.size[1])
    p = premul_resize(p, (max(1, round(p.size[0] * s)), max(1, round(p.size[1] * s))))
    c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    c.paste(p, ((w - p.size[0]) // 2, h - p.size[1]))
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', default=os.path.join(ROOT, 'docs/textures/panels.json'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'Resources/Textures'))
    ap.add_argument('--only')
    a = ap.parse_args()
    for s in json.load(open(a.spec)):
        if a.only and a.only not in s['sheet']:
            continue
        sheet = Image.open(os.path.join(ROOT, s['sheet'])).convert('RGB')
        W, H = sheet.size
        cols, rows, mode = s['cols'], s['rows'], s['mode']
        inset = s.get('inset', 0.01)
        bg = (255, 0, 255)
        for r, names in enumerate(s['tiles']):
            for c, spec in enumerate(names):
                if spec == '-':
                    continue
                name, _, opt = spec.partition(':')
                cw, ch = W / cols, H / rows
                x0, y0 = c * cw, r * ch
                box = (int(x0 + cw * inset), int(y0 + ch * inset), int(x0 + cw * (1 - inset)), int(y0 + ch * (1 - inset)))
                cell = key_cell(sheet.crop(box), bg)
                if mode == 'door':
                    full = hard(premul_resize(cell, (128, 256)))
                    full.crop((0, 0, 128, 128)).save(os.path.join(a.out, name + '_top.png'))
                    full.crop((0, 128, 128, 256)).save(os.path.join(a.out, name + '_bottom.png'))
                elif mode == 'square':
                    sq = hard(premul_resize(cell, (128, 128)))
                    (as_block_cutout(sq, True) if opt == 'tint' else sq).save(os.path.join(a.out, name + '.png'))
                elif mode == 'plant':
                    tint = opt == 'tint'
                    if opt == '1':
                        p = plant_canvas(cell, 64, 64, 0.9)
                        as_block_cutout(p, False).save(os.path.join(a.out, name + '.png'))
                    else:
                        p = plant_canvas(cell, 64, 128, 1.0 if opt == 'top' else 0.96)
                        p = as_block_cutout(p, tint)
                        p.crop((0, 0, 64, 64)).save(os.path.join(a.out, (name if opt == 'top' else name + '_top') + '.png'))
                        if opt != 'top':
                            p.crop((0, 64, 64, 128)).save(os.path.join(a.out, name + '_bottom.png'))
                print(name, 'ok')


if __name__ == '__main__':
    main()
