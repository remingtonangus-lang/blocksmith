#!/usr/bin/env python3
"""Voiced dialogue for Frontier: renders every line in frontier/design/dialogue/*.json with Kokoro-82M (Apache-2.0,
hexgrad; ONNX export + voice styles from the kokoro-onnx project, MIT) and merges them into the audio manifest.

  python3 frontier/tools/audio/voices.py --model DIR [--out DIR] [--only REGEX]
  (DIR holds kokoro-v1.0.onnx + voices-v1.0.bin, from
   https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0)

Casting lives in design/dialogue/voices.json (voice blends, tempo, pitch, EQ per speaker). Emotions are approximated
(tempo, pitch, level, drive) since the model has no emotion control. Lip sync: if the model export reports phoneme
durations (create_timed), those timings are used; otherwise phonemes are aligned to the rendered audio (clauses to
speech segments split at the longest pauses, phonemes inside a segment spread by typical duration weights). Output:
voice/<id>.ogg (24 kHz mono) + manifest "voice": {id: {file, duration, speaker, text, kind, emotion, visemes}}.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

DIALOGUE = HERE.parent.parent / "design" / "dialogue"
VSR = 24000

EMOTION = {  # tempo, pitch, level dB, drive, loudness target
    "calm": (1.0, 1.0, 0.0, 0.0, -19.0), "dry": (0.97, 1.0, 0.0, 0.0, -19.0), "angry": (1.03, 1.0, 1.5, 0.2, -17.0),
    "sad": (0.9, 0.98, -1.0, 0.0, -20.0), "tired": (0.92, 0.99, -1.0, 0.0, -20.0), "whisper": (0.95, 1.0, -6.0, 0.0, -25.0),
    "shout": (1.05, 1.04, 3.0, 0.3, -15.0), "scared": (1.1, 1.05, 1.0, 0.1, -17.0),
}

VISEME = {}
for chars, v in (("pbm", "PP"), ("fv", "FF"), ("θð", "TH"), ("td", "DD"), ("kgɡŋ", "kk"), ("ʃʒʧʤ", "CH"), ("sz", "SS"),
                 ("nl", "nn"), ("ɹrɚɝ", "RR"), ("ɑæaʌ", "aa"), ("əɐ", "aa"), ("ɛe", "E"), ("ɪijᵻ", "ih"), ("ɔo", "oh"),
                 ("uʊw", "ou"), ("h", "ih")):
    for c in chars:
        VISEME[c] = v
WEIGHT = {"PP": 0.6, "FF": 0.8, "TH": 0.8, "DD": 0.55, "kk": 0.6, "CH": 0.85, "SS": 0.85, "nn": 0.65, "RR": 0.7,
          "aa": 1.1, "E": 1.0, "ih": 0.9, "oh": 1.15, "ou": 1.0}
VOWELS = {"aa", "E", "ih", "oh", "ou"}


def load_tables(only: str | None):
    voices = json.loads((DIALOGUE / "voices.json").read_text())
    lines = []
    for f in sorted(DIALOGUE.glob("*.json")):
        if f.name == "voices.json":
            continue
        d = json.loads(f.read_text())
        for ln in d.get("lines", []):
            lines.append(dict(ln, source=f.name))
        for b in d.get("barks", []):
            for sp in b["speakers"]:
                lines.append({"id": f"{b['id']}__{sp}", "speaker": sp, "line": b["line"], "emotion": b.get("emotion", "calm"),
                              "kind": b["kind"], "source": f.name})
    if only:
        lines = [ln for ln in lines if re.search(only, ln["id"])]
    for ln in lines:
        if ln["speaker"] not in voices:
            raise SystemExit(f"speaker {ln['speaker']} of {ln['id']} missing from voices.json")
    return voices, lines


def phoneme_units(ph: str):
    """IPA string -> list of (viseme, weight) with clause breaks as ('|', 0)."""
    out = []
    for ch in ph:
        if ch in ".,!?;:—…":
            out.append(("|", 0.0))
        elif ch == " ":
            out.append(("_", 0.15))
        elif ch == "ː" and out:
            v, w = out[-1]
            out[-1] = (v, w * 1.5)
        elif ch in VISEME:
            v = VISEME[ch]
            if out and out[-1][0] == v and v in VOWELS:     # diphthong halves on the same shape
                out[-1] = (v, out[-1][1] + 0.5)
            else:
                out.append((v, WEIGHT[v]))
    return out


def speech_segments(a: np.ndarray, sr: int):
    fr = int(sr * 0.01)
    n = len(a) // fr
    if n == 0:
        return [(0.0, len(a) / sr)], []
    rms = np.sqrt(np.mean(a[:n * fr].reshape(n, fr) ** 2, axis=1))
    th = max(rms.max() * 0.06, 1e-4)
    on = rms > th
    k = np.ones(5) / 5
    on = np.convolve(on.astype(float), k, "same") > 0.3
    segs, gaps = [], []
    i = 0
    while i < n:
        if on[i]:
            j = i
            while j < n and on[j]:
                j += 1
            segs.append((i * 0.01, j * 0.01))
            i = j
        else:
            i += 1
    for s0, s1 in zip(segs, segs[1:]):
        gaps.append((s0[1], s1[0]))
    return segs, gaps


def align_visemes(ph: str, a: np.ndarray, sr: int):
    units = phoneme_units(ph)
    clauses, cur = [], []
    for u in units:
        if u[0] == "|":
            if cur:
                clauses.append(cur)
            cur = []
        else:
            cur.append(u)
    if cur:
        clauses.append(cur)
    segs, gaps = speech_segments(a, sr)
    if not segs:
        return []
    start, end = segs[0][0], segs[-1][1]
    # split points: the (clauses-1) longest pauses, in time order
    k = len(clauses) - 1
    long_gaps = sorted(sorted(gaps, key=lambda g: g[0] - g[1])[:max(0, k)])
    spans, s = [], start
    for g in long_gaps:
        spans.append((s, g[0]))
        s = g[1]
    spans.append((s, end))
    while len(spans) < len(clauses):          # fewer pauses than clauses: share the last span
        a0, a1 = spans[-1]
        spans[-1] = (a0, (a0 + a1) / 2)
        spans.append(((a0 + a1) / 2, a1))
    if len(spans) > len(clauses):
        spans = spans[:len(clauses) - 1] + [(spans[len(clauses) - 1][0], spans[-1][1])]
    ev = []
    for cl, (t0, t1) in zip(clauses, spans):
        tot = sum(w for _, w in cl) or 1.0
        t = t0
        for v, w in cl:
            if v != "_":
                ev.append([round(t, 3), v, 1.0 if v in VOWELS else 0.7])
            t += (t1 - t0) * w / tot
        ev.append([round(t1, 3), "sil", 0.0])
    return ev


def post(a: np.ndarray, sr: int, eq: dict, level_db: float, drive: float, target: float) -> np.ndarray:
    import dsp
    old = dsp.SR
    dsp.SR = sr          # the filters read the module sample rate
    try:
        y = dsp.hp(a.astype(np.float64), 75, 2)
        if eq.get("low_shelf_db"):
            y = dsp.shelf(y, 220, eq["low_shelf_db"], high=False)
        if eq.get("presence_db"):
            y = dsp.peak_eq(y, 3200, eq["presence_db"], 1.0)
        d = drive + eq.get("drive", 0.0)
        if d > 0:
            y = dsp.saturate(y * (1 + 3 * d), 1 + 2 * d)
        y = dsp.compress(y, -24, 2.5, 0.005, 0.12)
        y = dsp.normalize(y, target + level_db * 0.3, -1.0)
        y = dsp.fade(y, 0.005, 0.03)
    finally:
        dsp.SR = old
    return y


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", default=str(HERE.parent.parent / "assets" / "ext" / "audio"))
    ap.add_argument("--only", default=None)
    args = ap.parse_args()
    import soundfile as sf
    from kokoro_onnx import Kokoro
    import dsp
    md = Path(args.model)
    onnx = next(iter(sorted(md.glob("*.onnx"))))
    k = Kokoro(str(onnx), str(md / "voices-v1.0.bin"))
    voices, lines = load_tables(args.only)
    out = Path(args.out)
    (out / "voice").mkdir(parents=True, exist_ok=True)
    man_path = out / "manifest.json"
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {"version": 1, "sounds": {}, "music": {}}
    vt = manifest.setdefault("voice", {})
    styles = {}
    for ln in lines:
        vc = voices[ln["speaker"]]
        if ln["speaker"] not in styles:
            st = None
            for name, w in vc["blend"].items():
                s = np.asarray(k.get_voice_style(name), dtype=np.float32) * float(w)
                st = s if st is None else st + s
            styles[ln["speaker"]] = st
        tempo, pitch_e, lvl, drive, target = EMOTION.get(ln.get("emotion", "calm"), EMOTION["calm"])
        pitch = float(vc.get("pitch", 1.0)) * pitch_e
        speed = float(vc.get("speed", 1.0)) * tempo
        text = ln["line"]
        timings = []
        if hasattr(k, "create_timed"):
            a, sr, timings = k.create_timed(text, styles[ln["speaker"]], speed=speed / pitch, lang="en-us")
        else:
            a, sr = k.create(text, styles[ln["speaker"]], speed=speed / pitch, lang="en-us")
        a = np.asarray(a, dtype=np.float64)
        if abs(pitch - 1.0) > 0.005:
            a = dsp.pitch_resample(a, pitch)
        a = np.concatenate([np.zeros(int(sr * 0.05)), a, np.zeros(int(sr * 0.12))])
        y = post(a, sr, vc.get("eq", {}), lvl, drive, target)
        path = out / "voice" / f"{ln['id']}.ogg"
        sf.write(str(path), y.astype(np.float32), sr, format="OGG", subtype="VORBIS")
        ph = k.tokenizer.phonemize(text, "en-us")
        if timings:
            vis = []
            for tm in timings:
                v = VISEME.get(str(getattr(tm, "phoneme", "")))
                if v:
                    vis.append([round(float(tm.start) / pitch + 0.05, 3), v, 1.0 if v in VOWELS else 0.7])
        else:
            vis = align_visemes(ph, y, sr)
        vt[ln["id"]] = {"file": f"voice/{ln['id']}.ogg", "duration": round(len(y) / sr, 3), "speaker": ln["speaker"],
                        "text": text, "kind": ln.get("kind", ""), "emotion": ln.get("emotion", "calm"),
                        "phonemes": ph, "visemes": vis, "gain_db": 0.0, "viseme_source": "model" if timings else "aligned"}
        print(f"  voice {ln['id']:36s} {ln['speaker']:11s} {len(y) / sr:5.2f}s  {len(vis)} visemes", flush=True)
    man_path.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    print(f"voices: {len(lines)} lines -> {out / 'voice'}")


if __name__ == "__main__":
    main()
