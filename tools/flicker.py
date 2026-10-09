#!/usr/bin/env python3
"""Frame-diff flicker check (docs/STORE_QUALITY.md objective 4, defects).

Compares two renders of the same view, the second nudged by a tiny camera move (tools/golden.sh does 0.02 degrees).
Real motion only shifts edges by a fraction of a pixel, so a changed pixel should sit next to an edge in frame A.
A pixel that changes a lot while its whole 3x3 neighbourhood in frame A is flat is flicker: z-fighting, unstable
shading, sparkling seams or random per-frame effects.
  tools/flicker.py a.png b.png [--name N] [--out mask.png]
Prints one line: name, flicker pixels per million, verdict (ok < 50 ppm, warn < 500, FLICKER above).
"""
import sys
from PIL import Image

def lum(im):
    return im.convert("L")

def main():
    args = sys.argv[1:]
    name = args[args.index("--name") + 1] if "--name" in args else args[0]
    out = args[args.index("--out") + 1] if "--out" in args else None
    a, b = lum(Image.open(args[0])), lum(Image.open(args[1]))
    w, h = a.size
    if b.size != a.size:
        print(f"{name}: size mismatch {a.size} vs {b.size}"); return 2
    pa, pb = a.load(), b.load()
    bad, mask = 0, (Image.new("L", a.size, 0) if out else None)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            v = pa[x, y]
            if abs(v - pb[x, y]) < 48:
                continue
            lo = hi = v
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    n = pa[x + dx, y + dy]
                    lo, hi = min(lo, n), max(hi, n)
            if hi - lo < 12:                 # flat in A, yet it jumped in B
                bad += 1
                if mask: mask.putpixel((x, y), 255)
    ppm = bad * 1e6 / (w * h)
    verdict = "ok" if ppm < 50 else "warn" if ppm < 500 else "FLICKER"
    print(f"{name}: {bad} flicker px ({ppm:.0f} ppm) {verdict}")
    if mask: mask.save(out)
    return 0

if __name__ == "__main__":
    sys.exit(main())
