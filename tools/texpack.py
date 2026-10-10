#!/usr/bin/env python3
"""Packs Resources/Textures/*.png into Resources/texpack.bin for the Quest build (Android has no ImageIO).

  tools/texpack.py [--src Resources/Textures] [--out Resources/texpack.bin] [--size 64]

Format (little endian):  "BSTP", u32 version (1), u32 tile size, u32 count, then per entry (sorted by name):
u16 name length, UTF-8 name (file name without .png = the Tex layer name), tile*tile*4 RGBA8 bytes, rows top to
bottom, straight (not premultiplied) alpha. Each PNG is box-filtered to the tile size with premultiplied weighting
(no dark fringes); a PNG whose alpha is all 0 or 255 (a cutout: leaves, torches, item sprites) is thresholded at 0.5
again afterwards so cutouts stay crisp. The output is deterministic. A missing or empty source folder gives a valid
0-entry pack. The Mac build keeps reading the PNGs (Sources/TextureImport.swift); quest/src/common/QuestTextureImport.swift
reads this pack.
"""
import argparse
import os
import struct
import sys

from PIL import Image

MAGIC = b"BSTP"
VERSION = 1


def tile(path, n):
    im = Image.open(path)
    im.load()
    im = im.convert("RGBA")
    binary = set(im.getchannel("A").getdata()) <= {0, 255}
    if im.size != (n, n):
        pm = im.convert("RGBa")
        w, h = pm.size
        if w % n == 0 and h % n == 0:
            pm = pm.reduce((w // n, h // n))          # exact box filter
        else:
            pm = pm.resize((n, n), Image.BOX)
        im = pm.convert("RGBA")
    if binary:
        a = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        im.putalpha(a)
    # Fully transparent texels carry no colour (stable bytes whatever the editor left there).
    px = bytearray(im.tobytes())
    for i in range(0, len(px), 4):
        if px[i + 3] == 0:
            px[i] = px[i + 1] = px[i + 2] = 0
    return bytes(px)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default="Resources/Textures")
    ap.add_argument("--out", default="Resources/texpack.bin")
    ap.add_argument("--size", type=int, default=64)
    a = ap.parse_args()
    n = a.size
    if n not in (16, 32, 64, 128):
        sys.exit("texpack: --size must be 16, 32, 64 or 128")
    names = []
    if os.path.isdir(a.src):
        names = sorted(f[:-4] for f in os.listdir(a.src) if f.lower().endswith(".png") and not f.startswith("."))
    out = bytearray(MAGIC + struct.pack("<III", VERSION, n, len(names)))
    for name in names:
        b = name.encode("utf-8")
        out += struct.pack("<H", len(b)) + b + tile(os.path.join(a.src, name + ".png"), n)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, a.out)
    print(f"texpack: {len(names)} textures at {n} px -> {a.out} ({len(out) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
