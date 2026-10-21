#!/usr/bin/env python3
"""P390: the recorded sound effects (Resources/Sounds/real/*.wav) compressed for the Quest APK.

  tools/sfxpack.py OUT_DIR [--src Resources/Sounds/real] [--q 5]     encode (cached: a file is redone when its WAV is newer)
  tools/sfxpack.py OUT_DIR --check [--n 10]                          decode each back (ffmpeg) against its WAV

The WAVs stay the source (the Mac build and the host checks read them); the APK carries OUT_DIR instead, 118 MB of WAV
as about a sixth of that. The Quest decodes each file once when its sound first loads (RealSounds, through the same
AMediaExtractor + AMediaCodec path as the soundtrack) to the same samples in memory as the WAV gave.

OUT_DIR/sfx-index.txt, one line per file: "<name>.<ogg|m4a> <frames> <pad> <priming>": the WAV's length, the samples added at
each end before encoding, and the encoder's leading delay. A decoder that hands back the encoder's delay (the extractor
didn't trim it) gives at least frames + 2 pad + priming samples; one that trimmed it, fewer; RealSounds drops the delay
and the pads and keeps `frames`. Loops (names ending in Loop, rain, rainRoof, ashSiren) are padded with their own
other end (the last `pad` samples before, the first after), so the codec sees the seam mid-stream and the loop still
joins without a click; one-shots get no pad.

Encoder: Ogg Vorbis (ffmpeg's libvorbis, quality 5, no leading delay) where ffmpeg is installed: on these clips it kept
RMS and peaks within a few hundredths of a dB where ffmpeg's own AAC moved some by 2 dB (RMS) and 5 dB (peaks) at 96
and 128 kbps. Without ffmpeg, macOS afconvert's AAC at 160 kbps (.m4a, priming 2112). With neither, nothing is
written and build-apk.sh ships the WAVs as before. Both decode on the Quest through AMediaExtractor + AMediaCodec.
"""
import argparse
import array
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

LOOPS = {"rain", "rainRoof", "ashSiren"}
PAD = 2048


def is_loop(name):
    base = name
    if len(base) > 2 and base[-2] == "_" and base[-1] in "12345":
        base = base[:-2]
    return base.endswith("Loop") or base in LOOPS


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError(f"{path}: {sw * 8}-bit (only 16-bit is packed; it ships as WAV)")
    a = array.array("h", raw)
    if sys.byteorder != "little":
        a.byteswap()
    if ch > 1:
        a = array.array("h", [int(sum(a[i:i + ch]) / ch) for i in range(0, len(a), ch)])
    return a, rate


def write_wav(path, a, rate):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        b = array.array("h", a)
        if sys.byteorder != "little":
            b.byteswap()
        w.writeframes(b.tobytes())


def encoder():
    """(tool, file extension, leading delay in samples)"""
    if shutil.which("ffmpeg"):
        return "ffmpeg", "ogg", 0
    if shutil.which("afconvert"):
        return "afconvert", "m4a", 2112
    return None, "", 0


def encode(tool, src, dst, q):
    if tool == "ffmpeg":
        cmd = ["ffmpeg", "-v", "error", "-y", "-i", src, "-c:a", "libvorbis", "-q:a", str(q), dst]
    else:
        cmd = ["afconvert", "-f", "m4af", "-d", "aac", "-b", "160000", src, dst]
    subprocess.run(cmd, check=True)


def pack(out, src, q):
    tool, ext, priming = encoder()
    if tool is None:
        print("sfxpack: no ffmpeg or afconvert: the WAVs ship as they are")
        return 1
    os.makedirs(out, exist_ok=True)
    lines, done, kept = [], 0, 0
    tmp = tempfile.mkdtemp()
    try:
        for f in sorted(os.listdir(src)):
            if not f.lower().endswith(".wav") or f.startswith("."):
                continue
            name = f[:-4]
            wpath, mpath = os.path.join(src, f), os.path.join(out, name + "." + ext)
            a, rate = read_wav(wpath)
            pad = PAD if is_loop(name) and len(a) > 2 * PAD else 0
            if not (os.path.exists(mpath) and os.path.getmtime(mpath) >= os.path.getmtime(wpath)):
                ipath = wpath
                if pad or rate != 44100:
                    ipath = os.path.join(tmp, name + ".wav")
                    write_wav(ipath, a[-pad:] + a + a[:pad] if pad else a, rate)
                encode(tool, ipath, mpath, q)
                done += 1
            else:
                kept += 1
            lines.append(f"{name}.{ext} {len(a)} {pad} {priming}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    with open(os.path.join(out, "sfx-index.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    size = sum(os.path.getsize(os.path.join(out, x)) for x in os.listdir(out))
    print(f"sfxpack: {len(lines)} sounds ({done} encoded, {kept} unchanged) as .{ext} with {tool}: {size / 1e6:.1f} MB")
    return 0


def decode(path):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", "44100", "-"], check=True, capture_output=True)
    a = array.array("h")
    a.frombytes(r.stdout)
    if sys.byteorder != "little":
        a.byteswap()
    return a


def trim(d, frames, pad, priming):
    # (as RealSounds.trimDecoded)
    start = priming if len(d) >= frames + 2 * pad + priming else 0
    return d[start + pad:start + pad + frames]


def db(x):
    return 20 * math.log10(max(x, 1e-9))


def check(out, src, n):
    idx = {}
    for ln in open(os.path.join(out, "sfx-index.txt")):
        p = ln.split()
        if len(p) == 4:
            idx[p[0].rsplit(".", 1)[0]] = (p[0], int(p[1]), int(p[2]), int(p[3]))
    rows = []
    for name, (file, frames, pad, priming) in sorted(idx.items()):
        a, _ = read_wav(os.path.join(src, name + ".wav"))
        d = trim(decode(os.path.join(out, file)), frames, pad, priming)
        if len(d) < frames:
            d = d + array.array("h", [0] * (frames - len(d)))
        s = sum(v * v for v in a) / max(1, frames)
        e = sum((x - y) * (x - y) for x, y in zip(a, d)) / max(1, frames)
        t = sum(v * v for v in d) / max(1, frames)
        pa, pd = max((abs(v) for v in a), default=0), max((abs(v) for v in d), default=0)
        seam = abs(d[-1] - d[0]) - abs(a[-1] - a[0]) if pad else 0
        rows.append((name, db(math.sqrt(s) / 32768), db(math.sqrt(t)) - db(math.sqrt(s)), db(pd) - db(pa),
                     db(math.sqrt(s)) - db(math.sqrt(e)), pad > 0, seam / 32768))
    rows.sort(key=lambda r: r[1])
    pick = rows[-n:][::-1] + rows[:n]
    print(f"sfxcheck: {len(rows)} sounds; the {n} loudest and {n} quietest by RMS (dBFS): RMS and peak change after encoding, error under the signal")
    for r in pick:
        print(f"  {r[0]:<34} RMS {r[1]:7.1f}  RMS change {r[2]:+.2f} dB  peak change {r[3]:+.2f} dB  error {r[4]:5.1f} dB under" + (f"  (loop; seam step {r[6]:+.4f})" if r[5] else ""))
    worst = max(rows, key=lambda r: abs(r[2]))
    wp = max(rows, key=lambda r: abs(r[3]))
    ws = min(rows, key=lambda r: r[4])
    print(f"  all: largest RMS change {worst[2]:+.2f} dB ({worst[0]}), largest peak change {wp[3]:+.2f} dB ({wp[0]}), least error margin {ws[4]:.1f} dB ({ws[0]})")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--src", default="Resources/Sounds/real")
    ap.add_argument("--q", type=float, default=5)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--n", type=int, default=10)
    a = ap.parse_args()
    return check(a.out, a.src, a.n) if a.check else pack(a.out, a.src, a.q)


if __name__ == "__main__":
    sys.exit(main())
