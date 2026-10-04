#!/usr/bin/env python3
"""Packs fetched CC0 materials (assets/ext/) into the layouts the game's shaders read:

  assets/ext/packed/terrain_ah.png  vertical strip of N layers: RGB albedo, A height     (Texture2DArray)
  assets/ext/packed/terrain_nr.png  vertical strip of N layers: RG normal (GL), B roughness, A ambient occlusion
  assets/ext/packed/<group>_<name>_ah.png / _nr.png  same layout for single building/cloth materials (Texture2D)

and writes Godot .import files next to them (VRAM compressed, mipmaps) so `godot --import` builds GPU textures.
Missing materials become flat procedural stand-ins so the game always runs.
"""
import os, sys, json
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EXT = os.path.join(ROOT, "assets", "ext")
OUT = os.path.join(EXT, "packed")
SIZE = 1024

# Order is shared with shaders/terrain.gdshader (LAYER_* constants) and src/world/terrain.gd.
TERRAIN_LAYERS = ["grass_lush", "grass_dry", "grass_sparse", "dirt", "road", "mud", "forest_floor", "desert",
                  "red_sand", "rock", "red_rock", "snow", "pebbles"]
FALLBACK = {"grass_lush": (78, 92, 44), "grass_dry": (150, 132, 84), "grass_sparse": (120, 110, 70),
            "dirt": (110, 86, 62), "road": (140, 118, 92), "mud": (70, 56, 44), "forest_floor": (84, 66, 46),
            "desert": (176, 146, 110), "red_sand": (170, 102, 66), "rock": (118, 112, 104), "red_rock": (150, 84, 56),
            "snow": (236, 238, 242), "pebbles": (128, 120, 110)}


def load(path, mode, size, default):
    if os.path.exists(path):
        im = Image.open(path)
        if mode == "L" and im.mode not in ("L", "I", "I;16"):
            im = im.convert("L")
        im = im.convert(mode).resize((size, size), Image.LANCZOS)
        return np.asarray(im).astype(np.float32)
    shape = (size, size) if mode == "L" else (size, size, len(mode))
    return np.full(shape, default, np.float32)


def material(folder, size, fallback_rgb=(128, 128, 128)):
    d = os.path.join(EXT, folder)
    alb = load(os.path.join(d, "albedo.png"), "RGB", size, 0)
    if not os.path.exists(os.path.join(d, "albedo.png")):
        rng = np.random.default_rng(abs(hash(folder)) % 2**32)
        n = rng.random((size // 32, size // 32)).astype(np.float32)
        n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)) / 255.0
        alb = np.array(fallback_rgb, np.float32)[None, None, :] * (0.8 + 0.4 * n[..., None])
    hgt = load(os.path.join(d, "height.png"), "L", size, 128)
    nrm = load(os.path.join(d, "normal.png"), "RGB", size, 128)
    if not os.path.exists(os.path.join(d, "normal.png")):
        nrm[..., 2] = 255
    rough = load(os.path.join(d, "roughness.png"), "L", size, 220)
    ao = load(os.path.join(d, "ao.png"), "L", size, 255)
    arm = os.path.join(d, "arm.png")
    if os.path.exists(arm) and not os.path.exists(os.path.join(d, "roughness.png")):
        a = load(arm, "RGB", size, 255)
        ao, rough = a[..., 0], a[..., 1]
    # normalise height to full range per material (layers blend by relative height)
    lo, hi = np.percentile(hgt, 1), np.percentile(hgt, 99)
    hgt = np.clip((hgt - lo) / max(1.0, hi - lo) * 255, 0, 255)
    ah = np.dstack([alb, hgt]).astype(np.uint8)
    nr = np.dstack([nrm[..., 0], nrm[..., 1], rough, ao]).astype(np.uint8)
    return ah, nr, os.path.exists(os.path.join(d, "albedo.png"))


IMPORT_ARRAY = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[params]

compress/mode=2
compress/high_quality={hq}
mipmaps/generate=true
slices/horizontal=1
slices/vertical={n}
"""

IMPORT_2D = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality={hq}
mipmaps/generate=true
detect_3d/compress_to=0
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    # raw source folders are only read by this script; keep Godot from importing them
    for d in ("terrain", "build", "cloth"):
        if os.path.isdir(os.path.join(EXT, d)):
            open(os.path.join(EXT, d, ".gdignore"), "w").close()
    report = {}
    ahs, nrs = [], []
    for name in TERRAIN_LAYERS:
        ah, nr, real = material("terrain/" + name, SIZE, FALLBACK.get(name, (128, 128, 128)))
        ahs.append(ah); nrs.append(nr)
        report[name] = "cc0" if real else "fallback"
    Image.fromarray(np.concatenate(ahs, 0)).save(os.path.join(OUT, "terrain_ah.png"))
    Image.fromarray(np.concatenate(nrs, 0)).save(os.path.join(OUT, "terrain_nr.png"))
    for f in ("terrain_ah.png", "terrain_nr.png"):
        open(os.path.join(OUT, f + ".import"), "w").write(IMPORT_ARRAY.format(n=len(TERRAIN_LAYERS), hq="true"))
    # single materials
    for group in ("build", "cloth", "nature"):
        gd = os.path.join(EXT, group)
        if not os.path.isdir(gd):
            continue
        for name in sorted(os.listdir(gd)):
            if not os.path.exists(os.path.join(gd, name, "albedo.png")):
                continue
            ah, nr, real = material(group + "/" + name, 1024)
            for suf, img in (("ah", ah), ("nr", nr)):
                fn = f"{group}_{name}_{suf}.png"
                Image.fromarray(img).save(os.path.join(OUT, fn))
                open(os.path.join(OUT, fn + ".import"), "w").write(IMPORT_2D.format(hq="true"))
            report[group + "/" + name] = "cc0"
    json.dump(dict(terrain_layers=TERRAIN_LAYERS, materials=report), open(os.path.join(OUT, "packed.json"), "w"), indent=1)
    print("packed:", json.dumps(report))


if __name__ == "__main__":
    main()
