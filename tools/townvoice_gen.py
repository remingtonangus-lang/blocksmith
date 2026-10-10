#!/usr/bin/env python3
"""Townsfolk voice takes -> Resources/voices.bin (Sources/TownVoice.swift explains the format and playback).

  tools/townvoice_gen.py            fetch missing takes, pack, write build/voicewav/*.wav and assets/voices/manifest.tsv
  tools/townvoice_gen.py --pack     pack from the cache only (no network)

Reads the line table in Sources/TownVoice.swift (voices, groups, script). Each (voice, text) is spoken by an
ElevenLabs model through OpenRouter's OpenAI-compatible speech endpoint (key in ~/.config/openrouter/api-key),
24 kHz mono PCM, cached in build/voicecache/<key>.pcm so a re-run only fetches new or changed lines. Processing:
trim silence (20 ms head, 80 ms tail kept), the voice's rate change (the child), low-pass + resample to 16 kHz,
loudness matched on the speech part (RMS -20 dBFS) with the peak capped at -2.5 dBFS (ADPCM overshoots a little), then 4-bit IMA-ADPCM. The
decoded result is checked (peak <= -1 dBFS) and written as WAV for tools/audiolevels.py.
"""
import concurrent.futures as cf, datetime, json, os, re, struct, sys, urllib.request, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources", "TownVoice.swift")
CACHE = os.path.join(ROOT, "build", "voicecache")
WAVS = os.path.join(ROOT, "build", "voicewav")
OUT = os.path.join(ROOT, "Resources", "voices.bin")
MANIFEST = os.path.join(ROOT, "assets", "voices", "manifest.tsv")
MODEL = "elevenlabs/eleven-v4-turbo"
RATE_IN, RATE_OUT = 24000, 16000

def parse():
    s = open(SRC).read()
    voices = {k: (v, float(r)) for k, v, r in re.findall(r'"(\w+)": \("(\w+)", ([\d.]+)\)', s.split("static let groups")[0])}
    gpart = s.split("static let groups")[1].split("static let script")[0]
    groups = {g: re.findall(r'"(\w+)"', vs) for g, vs in re.findall(r'"(\w+)": \[([^\]]*)\]', gpart)}
    spart = s.split("static let script")[1].split("struct Take")[0]
    takes = []
    for g, c, body in re.findall(r'\("(\w+)", "(\w+)", \[(.*?)\]\)', spart, re.S):
        for t in re.findall(r'"((?:[^"\\]|\\.)*)"', body):
            for v in groups[g]:
                takes.append((v, c, t))
    return voices, takes

def fnv(voice, text):
    h = 0xcbf29ce484222325
    for b in f"{voice}|{text}".encode():
        h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h

def fetch(voice_name, text, path):
    key = open(os.path.expanduser("~/.config/openrouter/api-key")).read().strip()
    body = json.dumps({"model": MODEL, "input": text, "voice": voice_name, "response_format": "pcm"}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/audio/speech", data=body, method="POST",
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    err = "short reply"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if len(data) > 2000:
                open(path, "wb").write(data)
                return True
        except Exception as e:
            err = e
    print("FAILED", voice_name, text, err, file=sys.stderr)
    return False

def lowpass_resample(x, rin, rout):
    cut = 0.45 * min(rin, rout) / rin               # cycles per input sample
    n = 63
    t = np.arange(n) - (n - 1) / 2
    h = 2 * cut * np.sinc(2 * cut * t) * np.hanning(n)
    h /= h.sum()
    y = np.convolve(x, h, mode="same")
    m = int(len(y) * rout / rin)
    pos = np.arange(m) * (rin / rout)
    return np.interp(pos, np.arange(len(y)), y)

def process(pcm, rate_mult):
    x = np.frombuffer(pcm, dtype="<i2").astype(np.float64) / 32768
    env = np.convolve(np.abs(x), np.ones(240) / 240, mode="same")
    on = np.where(env > 10 ** (-48 / 20))[0]
    if len(on) == 0: return None
    a = max(0, on[0] - int(0.02 * RATE_IN)); b = min(len(x), on[-1] + int(0.08 * RATE_IN))
    x = x[a:b]
    y = lowpass_resample(x, RATE_IN * rate_mult, RATE_OUT)
    speech = y[np.convolve(np.abs(y), np.ones(160) / 160, mode="same") > 10 ** (-40 / 20)]
    rms = np.sqrt(np.mean(speech ** 2)) if len(speech) else 1e-3
    gain = min(10 ** (-20 / 20) / rms, 10 ** (-2.5 / 20) / max(1e-6, np.max(np.abs(y))))
    y = y * gain
    f = min(len(y) // 4, int(0.004 * RATE_OUT))
    ramp = np.linspace(0, 1, f)
    y[:f] *= ramp; y[-f:] *= ramp[::-1]
    return np.clip(np.round(y * 32767), -32768, 32767).astype(np.int32)

STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
        143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
        1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
        11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
IDX = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

def adpcm(s):
    """Encode int samples; returns (bytes, decoded samples) using the exact decoder of TownVoice.decode."""
    pred, idx = int(s[0]), 0
    out = bytearray(struct.pack("<hBB", pred, idx, 0))
    dec = [pred]
    codes = []
    for v in s[1:]:
        step = STEP[idx]
        d = int(v) - pred
        code = 8 if d < 0 else 0
        d = abs(d)
        diff = step >> 3
        if d >= step: code |= 4; d -= step; diff += step
        if d >= step >> 1: code |= 2; d -= step >> 1; diff += step >> 1
        if d >= step >> 2: code |= 1; diff += step >> 2
        pred = max(-32768, min(32767, pred - diff if code & 8 else pred + diff))
        idx = max(0, min(88, idx + IDX[code]))
        codes.append(code); dec.append(pred)
    if len(codes) % 2: codes.append(0)
    for i in range(0, len(codes), 2): out.append(codes[i] | (codes[i + 1] << 4))
    return bytes(out), np.array(dec)

def main():
    pack_only = "--pack" in sys.argv
    voices, takes = parse()
    os.makedirs(CACHE, exist_ok=True); os.makedirs(WAVS, exist_ok=True); os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    uniq = {}
    for v, c, t in takes: uniq[(v, t)] = c
    chars = sum(len(t) for (v, t) in uniq)
    print(f"{len(uniq)} takes, {chars} characters, {len(voices)} voices")
    todo = [(v, t) for (v, t) in uniq if not os.path.exists(os.path.join(CACHE, "%016x.pcm" % fnv(v, t)))]
    if todo and not pack_only:
        print(f"fetching {len(todo)} takes ({sum(len(t) for _, t in todo)} characters) with {MODEL}")
        with cf.ThreadPoolExecutor(6) as ex:
            list(ex.map(lambda vt: fetch(voices[vt[0]][0], vt[1], os.path.join(CACHE, "%016x.pcm" % fnv(*vt))), todo))
    entries, blobs, rows, worst = [], [], [], -99.0
    for (v, t), c in uniq.items():
        k = fnv(v, t)
        p = os.path.join(CACHE, "%016x.pcm" % k)
        if not os.path.exists(p): continue
        s = process(open(p, "rb").read(), voices[v][1])
        if s is None or len(s) < 800: print("skip (silent)", v, t); continue
        blob, dec = adpcm(s)
        peak = 20 * np.log10(max(1, np.max(np.abs(dec))) / 32768)
        worst = max(worst, peak)
        entries.append((k, RATE_OUT, len(dec), len(blob))); blobs.append(blob)
        w = wave.open(os.path.join(WAVS, f"voice_{v}_{k:016x}.wav"), "wb")
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE_OUT)
        w.writeframes(np.clip(dec, -32768, 32767).astype("<i2").tobytes()); w.close()
        mt = os.path.getmtime(p)
        rows.append(f"{k:016x}\t{v}\t{voices[v][0]}\t{MODEL}\t{datetime.date.fromtimestamp(mt).isoformat()}\t{len(dec) / RATE_OUT:.2f}\t{c}\t{t}")
    off = 8 + 24 * len(entries)
    head = bytearray(b"BSV1" + struct.pack("<I", len(entries)))
    for (k, r, n, b) in entries:
        head += struct.pack("<QIIII", k, r, n, off, b); off += b
    open(OUT, "wb").write(bytes(head) + b"".join(blobs))
    open(MANIFEST, "w").write("key\tvoice\tspeaker\tmodel\tdate\tseconds\tcontext\ttext\n" + "\n".join(sorted(rows, key=lambda r: r.split("\t")[1])) + "\n")
    secs = sum(e[2] for e in entries) / RATE_OUT
    print(f"packed {len(entries)}/{len(uniq)} takes, {secs:.0f} s of speech, {os.path.getsize(OUT) / 1e6:.2f} MB -> {OUT}; worst decoded peak {worst:.2f} dBFS")
    if worst > -1.0: sys.exit("peak above -1 dBFS")

if __name__ == "__main__":
    main()
