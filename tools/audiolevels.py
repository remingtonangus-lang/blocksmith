#!/usr/bin/env python3
"""Loudness, peak and clipping analysis of rendered WAVs + the wet-footstep check (STORE_QUALITY objective 5).

  Blocksmith --sounds build/sounds && Blocksmith --music build/sounds/music --seconds 30
  tools/audiolevels.py build/sounds [--out snaps/audio_levels.md]

Per file: sample peak (dBFS), clipped samples, integrated loudness (ITU-R BS.1770 K-weighting with the -70 / -10 LU
gates; short sounds under 400 ms use one block). Rules: SFX peak <= -1 dBFS, no clipped samples, music about -16
LUFS (+-2). Steps: each step_<material>.wav is compared with the mud and slime steps by its spectrum and decay; a dry
material closer to mud/slime than to stone/gravel/wood is flagged WET-SOUNDING.
"""
import glob, math, os, sys, wave, struct

def read(path):
    w = wave.open(path)
    n, ch, sw, fs = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
    raw = w.readframes(n)
    if sw != 2: return fs, []
    s = struct.unpack("<%dh" % (n * ch), raw)
    x = [sum(s[i:i + ch]) / ch / 32768 for i in range(0, len(s), ch)] if ch > 1 else [v / 32768 for v in s]
    return fs, x

def biquad(x, b0, b1, b2, a1, a2):
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y

def kweight(x, fs):
    # BS.1770 stage 1 (high shelf) and stage 2 (RLB high-pass), coefficients derived for any rate.
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / fs); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    x = biquad(x, (Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / fs); a0 = 1 + K / Q + K * K
    return biquad(x, 1, -2, 1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)

def lufs(x, fs):
    y = kweight(x, fs)
    blk, hop = int(0.4 * fs), int(0.1 * fs)
    ms = [sum(v * v for v in y[i:i + blk]) / blk for i in range(0, max(1, len(y) - blk + 1), hop)] if len(y) >= blk else [sum(v * v for v in y) / max(1, len(y))]
    L = lambda m: -0.691 + 10 * math.log10(m) if m > 0 else -99
    g = [m for m in ms if L(m) > -70]
    if not g: return -99
    rel = L(sum(g) / len(g)) - 10
    g = [m for m in g if L(m) > rel]
    return L(sum(g) / len(g))

def bandpass(x, fs, f0, Q=1.4):
    w0 = 2 * math.pi * f0 / fs; al = math.sin(w0) / (2 * Q); a0 = 1 + al
    return biquad(x, al / a0, 0, -al / a0, -2 * math.cos(w0) / a0, (1 - al) / a0)

def step_features(fs, x):
    bands = [150, 300, 600, 1200, 2400, 4800, 9000]
    e = [sum(v * v for v in bandpass(x, fs, f)) + 1e-12 for f in bands]
    tot = sum(e); spec = [math.log10(v / tot) for v in e]
    pk = max(abs(v) for v in x) or 1e-9
    last = max(i for i, v in enumerate(x) if abs(v) > pk * 0.03) if pk > 0 else 0
    return spec + [last / fs * 4]            # decay (s, weighted): wet squelches ring longer and lower

def main():
    d = sys.argv[1]; out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    rows, fails = [], 0
    files = sorted(glob.glob(os.path.join(d, "**", "*.wav"), recursive=True))
    for f in files:
        fs, x = read(f)
        if not x: continue
        name = os.path.relpath(f, d)[:-4]
        pk = max(abs(v) for v in x); pdb = 20 * math.log10(pk) if pk > 0 else -99
        clip = sum(1 for v in x if abs(v) >= 0.999)
        music = name.startswith("music")
        L = lufs(x, fs) if (music or len(x) < fs * 12) else float("nan")
        bad = []
        if clip: bad.append(f"{clip} clipped")
        if pdb > -1.0: bad.append("peak > -1 dBFS")
        if music and not (-18 <= L <= -14): bad.append("music off -16 LUFS")
        fails += bool(bad)
        rows.append((name, pdb, L, len(x) / fs, ", ".join(bad) or "ok"))
    md = ["| sound | peak dBFS | LUFS | length s | verdict |", "|---|---|---|---|---|"]
    md += [f"| {n} | {p:.1f} | {l:.1f} | {t:.2f} | {v} |" for n, p, l, t, v in rows]
    sfx = [r for r in rows if not r[0].startswith("music")]
    summary = [f"files {len(rows)}, failing {fails}; SFX peak > -1 dBFS: {sum(1 for r in sfx if r[1] > -1)}; clipped files: {sum(1 for r in rows if 'clipped' in r[4])}"]
    music = [r for r in rows if r[0].startswith("music")]
    if music: summary.append("music LUFS: " + ", ".join(f"{r[0]} {r[2]:.1f}" for r in music))
    # Wet-footstep check.
    steps = {os.path.basename(f)[5:-4]: f for f in files if os.path.basename(f).startswith("step_")}
    feats = {m: step_features(*read(f)) for m, f in steps.items()}
    dist = lambda a, b: math.sqrt(sum((p - q) ** 2 for p, q in zip(a, b)))
    wet = [feats[m] for m in ("mud", "slime") if m in feats]
    dryrefs = [m for m in ("stone", "gravel", "wood", "deepslate") if m in feats]; dry = dryrefs
    wetlist = []
    if wet and dry:
        summary.append("steps (distance to wet refs / dry refs; lower = closer):")
        for m in sorted(feats):
            if m in ("mud", "slime"): continue
            dw = min(dist(feats[m], w) for w in wet); dd = min(dist(feats[m], feats[r]) for r in dryrefs if r != m)
            flag = dw < dd
            if flag: wetlist.append(m)
            summary.append(f"  step_{m}: wet {dw:.2f} dry {dd:.2f}{'  WET-SOUNDING' if flag else ''}")
        summary.append("wet-sounding dry steps: " + (", ".join(wetlist) or "none"))
    text = "\n".join(summary)
    print(text)
    if out:
        open(out, "w").write("# Audio levels (tools/audiolevels.py)\n\n" + "\n".join("- " + s for s in summary) + "\n\n" + "\n".join(md) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
