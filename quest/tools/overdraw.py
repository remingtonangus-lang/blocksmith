#!/usr/bin/env python3
"""Fragment counts for the headset's GPU side, off the headset (Nov 11, frame rate).

questcheck can't time the Quest's GPU, and quads drawn say little about what a pixel costs: in a forest most of the
GPU's time goes on shading fragments, several deep where leaves, plants and water lie over one another.

  quest/tools/overdraw.py shaders DIR [SPLIT]
      writes a counting copy of every fragment shader into DIR (DIR/<name>.frag.spv): each runs the real shader
      (so cut-out texels still discard) and then writes 1/255 into one channel: red for the terrain's and ships'
      solid passes, green for their cut-out passes (leaves, plants, vines), blue for everything else (water, sky,
      clouds, mobs, entities, particles, panels). SPLIT takes the rest apart instead: "sky,clouds/simple" counts
      the sky and clouds in red, simple.frag (particles, the far ring, horizon, landmarks) in green, the rest in blue.
  BS_OVERDRAW=1 BS_SPVDIR=DIR questcheck --view out.png ...
      renders with every colour pipeline additive and the target cleared to black, so each pixel holds how many
      fragments passed the depth test there, by pass (draw order as in play: solid near to far, then cut-out).
  quest/tools/overdraw.py stats out.png [heat.png]
      prints fragments per pixel by pass, how many pixels are 2, 3, 4+ deep, and writes a heat map.
"""
import os, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, '..', 'shaders')

SOLID = {'chunk_solid.frag', 'ship_solid.frag'}
CUT = {'chunk_cut.frag', 'ship_cut.frag'}
SKIP = {'swdepth.frag', 'swmotion.frag'}     # SpaceWarp's motion passes (off in the harness)


def shaders(out, split=None):
    # split (the "other" pass taken apart): red for these shaders, green for those, blue for the rest, e.g.
    # "sky,clouds,star/simple" (names without .frag); the terrain's own passes then count in no channel.
    groups = [set(g.split(',')) for g in split.split('/')] if split else None
    os.makedirs(out, exist_ok=True)
    common = open(os.path.join(src, 'common.glsl')).read()
    tmp = tempfile.mkdtemp()
    for name in sorted(os.listdir(src)):
        if not name.endswith('.frag') or name in SKIP:
            continue
        text = open(os.path.join(src, name)).read().replace('#include "common.glsl"', '#define BS_FRAG 1\n' + common)
        assert text.count('void main()') == 1, name
        inc = '1.0, 0.0, 0.0' if name in SOLID else '0.0, 1.0, 0.0' if name in CUT else '0.0, 0.0, 1.0'
        if groups:
            base = name[:-5]
            inc = ('1.0, 0.0, 0.0' if base in groups[0] else '0.0, 1.0, 0.0' if len(groups) > 1 and base in groups[1]
                   else '0.0, 0.0, 0.0' if name in SOLID or name in CUT else '0.0, 0.0, 1.0')
        text = text.replace('void main()', 'void main_counted()')
        text += '\nvoid main() { main_counted(); outColor = vec4(%s, 0.0) / 255.0; }\n' % inc
        path = os.path.join(tmp, name)
        open(path, 'w').write(text)
        spv = os.path.join(out, name + '.spv')
        r = subprocess.run(['glslangValidator', '-V', '--target-env', 'vulkan1.1', '-S', 'frag', path, '-o', spv],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f'overdraw.py: {name} failed:\n{r.stdout}{r.stderr}')
    print(f'counting shaders in {out}')


def stats(png, heat=None):
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(png).convert('RGB')).astype(np.int64)
    n = a.shape[0] * a.shape[1]
    tot = a.sum(axis=2)
    names = ['solid', 'cut-out', 'other']
    parts = ', '.join(f'{names[i]} {a[..., i].sum() / n:.2f}' for i in range(3))
    print(f'{os.path.basename(png)}: {a.shape[1]}x{a.shape[0]}, fragments a pixel {tot.sum() / n:.2f} ({parts})')
    deep = ', '.join(f'{k}+ {100 * (tot >= k).sum() / n:.1f}%' for k in (2, 3, 4, 6, 8))
    print(f'  pixels shaded at least: {deep}; most {tot.max()}')
    cut = a[..., 1]
    print(f'  cut-out alone: {100 * (cut >= 2).sum() / n:.1f}% of pixels 2+ deep, {100 * (cut >= 3).sum() / n:.1f}% 3+')
    if heat:
        lut = np.array([[0, 0, 0], [40, 40, 140], [40, 160, 60], [230, 220, 40], [240, 130, 30], [220, 30, 30], [255, 255, 255]])
        img = lut[np.clip(tot, 0, 6)].astype(np.uint8)
        Image.fromarray(img).save(heat)
        print(f'  heat map {heat}: black 0, blue 1, green 2, yellow 3, orange 4, red 5, white 6+')


if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == 'shaders':
        shaders(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif len(sys.argv) >= 3 and sys.argv[1] == 'stats':
        for p in sys.argv[2:3]:
            stats(p, sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        sys.exit(__doc__)
