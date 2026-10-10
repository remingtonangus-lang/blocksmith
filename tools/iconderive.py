#!/usr/bin/env python3
"""Derive item-icon families from one Gemini-painted member (run after tools/iconslice.py).

Like tools/texderive.py for blocks: a family member without its own PNG gets the base icon's shading (luminance
relative to its mean, alpha kept) times the member's own procedural colour (alpha-weighted mean of its 16 px sprite,
muted toward grey so it sits with the natural palette). "copy" families take the base unchanged (suspicious stews
look like mushroom stew). An icon that already has its own PNG is never overwritten.

  python3 tools/iconderive.py [--bin build/Blocksmith.app/Contents/MacOS/Blocksmith] [--out Resources/Textures]
"""
import argparse, os, re, subprocess, tempfile
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLOURS = ('white orange magenta light_blue yellow lime pink gray light_gray cyan purple blue brown green red '
           'black').split()
WOODS = 'oak spruce birch jungle acacia dark_oak mangrove cherry pale_oak'.split()
MUTE = 0.75
# (regex over item layer names, base layer, mode)
FAMILIES = [
    (r'item_\w+_dye$', 'item_white_dye', 'tint'),
    (r'item_\w+_bundle$', 'item_bundle', 'tint'),
    (r'item_(%s)_boat$' % '|'.join(WOODS), 'item_oak_boat', 'ratio'),
    (r'item_(%s)_chest_boat$' % '|'.join(WOODS), 'item_oak_chest_boat', 'ratio'),
    (r'item_suspicious_stew_\w+$', 'item_mushroom_stew', 'copy'),
    (r'item_\w+_spear$', 'item_iron_spear', 'ratio'),
    (r'item_\w+_horse_armor$', 'item_iron_horse_armor', 'tint'),
    (r'item_music_disc_\w+$', 'item_music_disc_13', 'tint'),
    (r'item_\w+_smithing_template$', 'item_netherite_upgrade_smithing_template', 'tint'),
    (r'item_\w+_banner_pattern$', 'item_flower_banner_pattern', 'tint'),
    (r'item_(%s)_banner$' % '|'.join(COLOURS), 'item_white_banner', 'tint'),
    (r'item_\w+_pottery_sherd$', 'item_angler_pottery_sherd', 'copy'),
]


# 'ratio' families: base x (material / base material) mean colour of imported block textures; spears only on the head
MATERIAL = {'wooden': 'oak_planks', 'stone': 'cobblestone', 'iron': 'iron_block', 'golden': 'gold_block',
            'diamond': 'diamond_block', 'netherite': 'netherite_block', 'copper': 'copper_block'}


def material_of(name):
    m = re.match(r'item_(\w+?)_(chest_)?boat$', name)
    if m:
        w = {'pale_oak': 'birch'}.get(m.group(1), m.group(1))   # no imported pale oak planks yet
        return w + '_planks', 'oak_planks', False
    m = re.match(r'item_(\w+)_spear$', name)
    if m and m.group(1) in MATERIAL:
        return MATERIAL[m.group(1)], 'iron_block', True
    return None


def mean_png(path):
    a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32) / 255
    return a.reshape(-1, 3).mean(0)


def ratio(base, target, ref, head_only):
    a = np.asarray(base.convert('RGBA'), dtype=np.float32) / 255
    k = np.clip(target / np.maximum(ref, 1e-3), 0.2, 4.0)
    rgb = np.clip(a[..., :3] * k, 0, 1)
    if head_only:                         # the spearhead sits in the top-right corner (icon points up-right)
        h, w = a.shape[:2]
        y, x = np.mgrid[0:h, 0:w]
        m = ((x + (h - 1 - y)) > 1.38 * w).astype(np.float32)[..., None]
        rgb = rgb * m + a[..., :3] * (1 - m)
    return Image.fromarray((np.concatenate([rgb, a[..., 3:]], -1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def layer_names(binary):
    r = subprocess.run([binary, '--procedural', '--hdatlas', '/dev/null', '--names', 'item_*'], capture_output=True,
                       text=True, cwd=ROOT)
    return [m.group(3) for m in (re.match(r'hdatlas r(\d+) c(\d+) (\S+)', l) for l in r.stdout.splitlines()) if m]


def procedural_means(binary, names):
    """Alpha-weighted mean colour of each named procedural layer at 16 px."""
    means = {}
    with tempfile.TemporaryDirectory() as d:
        png = os.path.join(d, 'a.png')
        env = dict(os.environ, BLOCKSMITH_TEXRES='16')
        r = subprocess.run([binary, '--procedural', '--hdatlas', png, '--names', ','.join(names)],
                           capture_output=True, text=True, env=env, cwd=ROOT)
        im = np.asarray(Image.open(png).convert('RGBA'), dtype=np.float32) / 255
        n, gap = 16, 4
        for line in r.stdout.splitlines():
            m = re.match(r'hdatlas r(\d+) c(\d+) (\S+)', line)
            if m:
                rr, cc, name = int(m.group(1)), int(m.group(2)), m.group(3)
                ox, oy = gap + cc * (n + gap), gap + rr * (n + gap)
                c = im[oy:oy + n, ox:ox + n].reshape(-1, 4)
                w = c[:, 3:4]
                means[name] = (c[:, :3] * w).sum(0) / max(1e-4, w.sum())
    return means


def tint(base, colour):
    a = np.asarray(base.convert('RGBA'), dtype=np.float32) / 255
    rgb, al = a[..., :3], a[..., 3:4]
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    mean = (lum * al[..., 0]).sum() / max(1e-4, al.sum())
    detail = (lum / max(1e-3, mean))[..., None]
    grey = colour @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    c = grey + (colour - grey) * MUTE
    out = np.clip(detail * c, 0, 1)
    return Image.fromarray((np.concatenate([out, al], -1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bin', default=os.path.join(ROOT, 'build/Blocksmith.app/Contents/MacOS/Blocksmith'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'Resources/Textures'))
    ap.add_argument('--names', help='comma-separated item layer names (default: ask the binary)')
    a = ap.parse_args()
    have = {f[:-4] for f in os.listdir(a.out) if f.endswith('.png')}
    names = a.names.split(',') if a.names else layer_names(a.bin)
    jobs = []
    for n in names:
        if n in have:
            continue
        for pat, base, mode in FAMILIES:
            if re.match(pat, n) and base in have:
                jobs.append((n, base, mode))
                break
    means = procedural_means(a.bin, [n for n, _, m in jobs if m == 'tint'])
    for n, base, mode in jobs:
        img = Image.open(os.path.join(a.out, base + '.png'))
        if mode == 'ratio':
            mat = material_of(n)
            tp = mat and os.path.join(a.out, mat[0] + '.png')
            if not mat or not os.path.exists(tp):
                print('no material for', n); continue
            img = ratio(img, mean_png(tp), mean_png(os.path.join(a.out, mat[1] + '.png')), mat[2])
        elif mode == 'tint':
            if n not in means:
                print('no procedural colour for', n); continue
            img = tint(img, means[n])
        img.save(os.path.join(a.out, n + '.png'))
        print(n, '<-', base, mode)


if __name__ == '__main__':
    main()
