#!/usr/bin/env python3
"""Spectrogram + waveform contact sheet for the synthesized sounds: python3 spectro.py WAV_DIR OUT.png [names...]"""
import sys, wave, numpy as np
from PIL import Image, ImageDraw

def load(p):
    w = wave.open(p)
    d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    return d, w.getframerate()

def spec(x, rate, w=520, h=150):
    n = 512
    hop = max(1, (len(x) - n) // w) if len(x) > n else 1
    cols = []
    for i in range(w):
        s = i * hop
        seg = x[s:s + n]
        if len(seg) < n: seg = np.pad(seg, (0, n - len(seg)))
        m = np.abs(np.fft.rfft(seg * np.hanning(n)))[: n // 2]
        cols.append(20 * np.log10(m + 1e-6))
    a = np.array(cols).T[::-1]
    # log-frequency rows
    idx = np.clip((np.geomspace(1, n // 2 - 1, h)).astype(int), 0, n // 2 - 1)[::-1]
    a = a[::-1][idx]
    a = np.clip((a + 80) / 80, 0, 1)
    return Image.fromarray((np.stack([a ** 0.7, a ** 1.5, a ** 3], -1) * 255).astype(np.uint8))

def main():
    d, out = sys.argv[1], sys.argv[2]
    names = sys.argv[3:]
    rows = []
    for nm in names:
        x, r = load(f"{d}/{nm}.wav")
        img = Image.new("RGB", (640, 230), (16, 18, 22))
        dr = ImageDraw.Draw(img)
        dr.text((8, 4), f"{nm}  {len(x)/r:.2f}s  peak {np.abs(x).max():.2f}", fill=(230, 230, 230))
        img.paste(spec(x, r), (110, 22))
        # waveform envelope
        env = np.abs(x)
        bins = np.array_split(env, 520)
        pts = [(110 + i, 225 - int(50 * b.max())) for i, b in enumerate(bins)]
        dr.line(pts, fill=(120, 200, 255))
        rows.append(img)
    sheet = Image.new("RGB", (640, 230 * len(rows)))
    for i, r in enumerate(rows): sheet.paste(r, (0, 230 * i))
    sheet.save(out)

main()
