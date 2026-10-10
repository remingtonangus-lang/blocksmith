#!/usr/bin/env python3
"""Packs Resources/Textures/*.png into Resources/texpack.bin for the Quest build (Android has no ImageIO).

  tools/texpack.py [--src Resources/Textures] [--out Resources/texpack.bin] [--size 128]

Format (little endian):  "BSTP", u32 version (2), u32 tile size, u32 count, u32 body length, then the body as one
zlib stream (RFC 1950; 57 MB of 128 px tiles pack to about 13 MB). The body is the version 1 entry list: per entry
(sorted by name) u16 name length, UTF-8 name (file name without .png = the Tex layer name), tile*tile*4 RGBA8 bytes,
rows top to bottom, straight (not premultiplied) alpha. Version 1 files (the body stored, no length field) still load.
128 px is the art's own resolution: the 64 px pack of Oct 10 halved the detail on the headset ("everything's blurry",
docs/status/texture-sharpness.md). Each PNG is box-filtered to the tile size with premultiplied weighting
(no dark fringes); a PNG whose alpha is all 0 or 255 (a cutout: leaves, torches, item sprites) is thresholded at 0.5
again afterwards so cutouts stay crisp. The output is deterministic. A missing or empty source folder gives a valid
0-entry pack. The Mac build keeps reading the PNGs (Sources/TextureImport.swift); quest/src/common/QuestTextureImport.swift
reads this pack.
"""
import argparse
import os
import struct
import sys
import zlib

from PIL import Image

MAGIC = b"BSTP"
VERSION = 2


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
    ap.add_argument("--size", type=int, default=128)
    a = ap.parse_args()
    n = a.size
    if n not in (16, 32, 64, 128):
        sys.exit("texpack: --size must be 16, 32, 64 or 128")
    names = []
    if os.path.isdir(a.src):
        names = sorted(f[:-4] for f in os.listdir(a.src) if f.lower().endswith(".png") and not f.startswith("."))
    body = bytearray()
    for name in names:
        b = name.encode("utf-8")
        body += struct.pack("<H", len(b)) + b + tile(os.path.join(a.src, name + ".png"), n)
    out = MAGIC + struct.pack("<IIII", VERSION, n, len(names), len(body)) + zlib.compress(bytes(body), 9)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, a.out)
    print(f"texpack: {len(names)} textures at {n} px -> {a.out} ({len(out) / 1024:.0f} KB, {len(body) / 1024:.0f} KB unpacked)")


if __name__ == "__main__":
    main()
