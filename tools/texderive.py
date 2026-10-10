#!/usr/bin/env python3
"""Derive texture families from the imported art set (run after tools/sheetslice.py).

The Gemini sheets cover one member of each family; this carries that look to the rest so a family never mixes the
new art with procedural layers:
  * "name@r" (sideways logs, pillars): the imported base turned a quarter, rot(x, y) = base(y, 15 - x) like
    WoodBlocks.rotatedPainters.
  * colour families (wool, concrete, terracotta, concrete powder, stripped log ends): the imported base's surface
    detail (luminance relative to its mean) times the procedural layer's own mean colour, muted a little toward grey
    so dyed blocks sit with the natural palette. Procedural means come from `Blocksmith --procedural --hdatlas`.
A layer that already has its own imported PNG is never overwritten.

  python3 tools/texderive.py [--bin build/Blocksmith.app/Contents/MacOS/Blocksmith] [--out Resources/Textures]
"""
import argparse, os, re, subprocess, tempfile
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLOURS = ('white orange magenta light_blue yellow lime pink gray light_gray cyan purple blue brown green red '
           'black').split()
MUTE = 0.7    # keep 70% of the procedural colour saturation: dyes sit with the natural palette
TONED = [('farmland', 'farmland_moist', 1.45), ('furnace_side', 'furnace_body', 1.0), ('furnace_plate', 'furnace_body', 0.92),
         ('furnace_top', 'furnace_body', 0.92), ('cactus_bottom', 'cactus_top', 0.85)]
UNLIT = [('furnace_front', 'furnace_front_on')]   # the lit face with its fire painted out   # keep 85% of the procedural colour's saturation


def families(names, have):
    """(target, base) pairs: target gets base's detail in target's procedural colour."""
    out = []
    for c in COLOURS:
        for fam, base in (('wool', 'white_wool'), ('concrete', 'white_concrete'), ('terracotta', 'terracotta'),
                          ('concrete_powder', 'sand')):
            out.append((f'{c}_{fam}', base))
    for n in names:
        m = re.match(r'stripped_(\w+)_log_top$', n)
        if m:
            out.append((n, f'{m.group(1)}_log_top'))
    return [(t, b) for t, b in out if t in names and t not in have and b in have]


def procedural_means(binary, names):
    """Mean straight-alpha colour of each named procedural layer (16 px is enough for a mean)."""
    means = {}
    with tempfile.TemporaryDirectory() as d:
        png = os.path.join(d, 'a.png')
        env = dict(os.environ, BLOCKSMITH_TEXRES='16')
        r = subprocess.run([binary, '--procedural', '--hdatlas', png, '--names', ','.join(names)],
                           capture_output=True, text=True, env=env, cwd=ROOT)
        im = np.asarray(Image.open(png).convert('RGB'), dtype=np.float32) / 255
        n, gap = 16, 4
        for line in r.stdout.splitlines():
            m = re.match(r'hdatlas r(\d+) c(\d+) (\S+)', line)
            if m:
                rr, cc, name = int(m.group(1)), int(m.group(2)), m.group(3)
                ox, oy = gap + cc * (n + gap), gap + rr * (n + gap)
                means[name] = im[oy:oy + n, ox:ox + n].reshape(-1, 3).mean(0)
    return means


def lum(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def recolour(base_path, mean):
    b = np.asarray(Image.open(base_path).convert('RGBA'), dtype=np.float32) / 255
    L = lum(b[..., :3])
    rel = L / max(L.mean(), 1e-3)
    grey = lum(mean)
    tgt = grey + (mean - grey) * MUTE
    rgb = np.clip(rel[..., None] * tgt, 0, 1)
    out = np.concatenate([rgb, b[..., 3:4]], -1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bin', default=os.path.join(ROOT, 'build/Blocksmith.app/Contents/MacOS/Blocksmith'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'Resources/Textures'))
    a = ap.parse_args()
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        subprocess.run([a.bin, '--texnames', f.name], check=True, cwd=ROOT)
        names = set(open(f.name).read().split())
    derived = set()
    have = {p[:-4] for p in os.listdir(a.out) if p.endswith('.png')}
    # Previously derived files are regenerated (their bases may have changed); hand-imported ones are kept.
    log = os.path.join(a.out, '.derived')
    if os.path.exists(log):
        have -= set(open(log).read().split())
    count = 0
    for n in sorted(names):
        if n.endswith('@r') and n not in have and n[:-2] in have:
            Image.open(os.path.join(a.out, n[:-2] + '.png')).rotate(-90).save(os.path.join(a.out, n + '.png'))
            derived.add(n)
    pairs = families(names, have)
    means = procedural_means(a.bin, [t for t, _ in pairs])
    for t, _ in pairs:   # stripped log ends take the imported stripped side's colour, so end and side match
        side = t[:-4]
        if t.endswith('_log_top') and side in have:
            px = np.asarray(Image.open(os.path.join(a.out, side + '.png')).convert('RGB'), dtype=np.float32) / 255
            means[t] = px.reshape(-1, 3).mean(0)
    for t, b in pairs:
        if t in means:
            recolour(os.path.join(a.out, b + '.png'), means[t]).save(os.path.join(a.out, t + '.png'))
            derived.add(t)
    for t, b, k in TONED:   # same material, lighter or darker (dry farmland from the moist one)
        if t in names and t not in have and b in have:
            im = np.asarray(Image.open(os.path.join(a.out, b + '.png')).convert('RGBA'), dtype=np.float32) / 255
            im[..., :3] = np.clip(im[..., :3] * k, 0, 1)
            Image.fromarray((im * 255 + 0.5).astype(np.uint8)).save(os.path.join(a.out, t + '.png'))
            derived.add(t)
    for t, b in UNLIT:
        if t in names and t not in have and b in have:
            im = np.asarray(Image.open(os.path.join(a.out, b + '.png')).convert('RGBA'), dtype=np.float32) / 255
            r, g, bl = im[..., 0], im[..., 1], im[..., 2]
            fire = np.clip((r - bl - 0.25) * 3, 0, 1) * np.clip((r - 0.45) * 3, 0, 1)   # warm, bright texels
            dark = np.array([0.07, 0.06, 0.06])
            im[..., :3] = im[..., :3] * (1 - fire[..., None]) + dark * fire[..., None]
            Image.fromarray((im * 255 + 0.5).astype(np.uint8)).save(os.path.join(a.out, t + '.png'))
            derived.add(t)
    open(log, "w").write('\n'.join(sorted(derived)) + '\n')
    print(f'texderive: {len(derived)} layers derived ({sum(1 for d in derived if d.endswith("@r"))} rotated)')


if __name__ == '__main__':
    main()
