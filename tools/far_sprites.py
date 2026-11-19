#!/usr/bin/env python3
"""Photographs every far-card tree with the game's own renderer (ledger 362) and packs the pictures.

  tools/far_sprites.py [--bin build/quest-inc-o/questcheck] [--only spruce,oak] [--work DIR]

For each kind, variant and (where the kind has them) the snowy twin, a scene script grows the tree alone in the air
(questcheck --scene: `tree`), and shoots it from 4 sides nearly level (8 degrees above, as a wood on the
next hill is seen) and 4 sides from 40 degrees above, at noon, without
sky, far ring or landmarks, so everything that is not the tree is the flat clear colour. That colour is keyed out, the
left eye is box-filtered to 128 px (premultiplied), and the tiles go to Resources/FarSprites/far_<kind>_<variant>[_s]_<n>.png
(n 0-3 level, 4-7 from above); tools/texpack.py packs them into Resources/farpack.bin. Run from the repo. Rerun
whenever a tree's design or the leaf art changes. The kinds are FarSprites.kinds (Sources/FarSprites.swift).
"""
import argparse, math, os, re, subprocess, sys
from PIL import Image

KINDS = [("oak", 1), ("small_oak", 0), ("fancy_oak", 0), ("ancient_oak", 0), ("swamp_oak", 0), ("birch", 1), ("tall_birch", 0),
         ("spruce", 1), ("pine", 1), ("mega_spruce", 1), ("mega_pine", 1), ("jungle", 0), ("mega_jungle", 0), ("acacia", 0),
         ("dark_oak", 0), ("mangrove", 0), ("cherry", 0), ("pale_oak", 0), ("saltpalm", 0)]
VARIANTS, DIST, Y, PX, UP, LEVEL = 2, 48.0, 250, 512, 40.0, 8.0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="build/quest-inc-o/questcheck")
    ap.add_argument("--only", default="")
    ap.add_argument("--work", default="/tmp/far_sprites")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    os.makedirs(a.work, exist_ok=True)
    os.makedirs("Resources/FarSprites", exist_ok=True)
    jobs = [(k, v, s) for k, snow in KINDS if not only or k in only for v in range(VARIANTS) for s in range(snow + 1)]
    # Pass 1: the frames (the `tree` line prints its kind's frame side).
    env = dict(os.environ, QUEST_SKIP="sky,far,landmarks,mobs,entities", BS_FOGSNAP="1", BS_NOFOG="1", BLOCKSMITH_TEXRES="128")
    for n, (k, v, s) in enumerate(jobs):
        cx = 400 * (n + 1) + 8
        name = f"far_{k}_{v}{'_s' if s else ''}"
        probe = os.path.join(a.work, name + ".probe.scene")
        open(probe, "w").write(f"tree {k} {cx} {Y} 8 {v}\n")
        out = subprocess.run([a.bin, "--scene", probe, "--headset", "--out", a.work], env=env, capture_output=True, text=True).stdout
        m = re.search(r"frame ([0-9.]+)", out)
        if not m: sys.exit(f"{name}: no frame in\n{out[-600:]}")
        side = float(m.group(1))
        fov = 2 * math.degrees(math.atan(side / 2 / DIST))
        cy = Y + side / 2
        lines = [f"at {cx} {cy:.2f} {DIST + 8}", "fly on", "time 0.25", "load 5", "tick 0.5", f"tree {k} {cx} {Y} 8 {v}{' snow' if s else ''}", "tick 0.6"][:-1]
        for i in range(8):
            ang = i % 4 * 90.0 + 20.0
            up = UP if i >= 4 else LEVEL
            h = DIST * math.cos(math.radians(up))
            x = cx + h * math.sin(math.radians(ang)); z = 8 + h * math.cos(math.radians(ang)); y = cy + DIST * math.sin(math.radians(up))
            lines += [f"at {x:.3f} {y:.3f} {z:.3f}", f"look {-ang:.2f} {-up:.2f}", f"shot {name}_{i}.png {PX} {PX} {fov:.3f}"]
        sc = os.path.join(a.work, name + ".scene")
        open(sc, "w").write("\n".join(lines) + "\n")
        r = subprocess.run([a.bin, "--scene", sc, "--headset", "--out", a.work], env=env, capture_output=True, text=True)
        if "all checks passed" not in r.stdout: sys.exit(f"{name}: scene failed\n{r.stdout[-800:]}")
        for i in range(8):
            im = Image.open(os.path.join(a.work, f"{name}_{i}.png")).convert("RGB")
            im = im.crop((0, 0, im.width // 2, im.height))
            key = im.getpixel((0, 0))
            px = im.load()
            rgba = Image.new("RGBA", im.size)
            q = rgba.load()
            for yy in range(im.height):
                for xx in range(im.width):
                    c = px[xx, yy]
                    q[xx, yy] = (0, 0, 0, 0) if max(abs(c[0] - key[0]), abs(c[1] - key[1]), abs(c[2] - key[2])) <= 2 else c + (255,)
            pm = rgba.convert("RGBa").resize((128, 128), Image.BOX).convert("RGBA")
            pm.save(f"Resources/FarSprites/{name}_{i}.png")
        print(f"{name}: frame {side:.1f} blocks, fov {fov:.1f}", flush=True)
    subprocess.check_call([sys.executable, "tools/texpack.py", "--src", "Resources/FarSprites", "--out", "Resources/farpack.bin", "--size", "128"])

if __name__ == "__main__":
    main()
