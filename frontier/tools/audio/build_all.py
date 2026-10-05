#!/usr/bin/env python3
"""Builds Frontier's synthesized audio: every registered SFX/ambience (sfx_*.py), the score (music.py) and merges the
CI-only parts (voices from voices.py, recordings from commons.py) into one manifest.

  python3 frontier/tools/audio/build_all.py [--out DIR] [--only REGEX] [--jobs N] [--no-music] [--report]

Output (default frontier/assets/ext/audio/):
  sfx/<folder>/<id>_<n>.ogg|wav   one file per variation
  music/<track>/<stem>.ogg        stems of each adaptive music track (all the same length, loop-ready)
  manifest.json                   {"sounds": {id: {...}}, "music": {...}, "voice": {...}} read by audio_director.gd
  report.json                     loudness/peak/duration per file (verify.py turns it into plots + checks)
Deterministic: same code -> identical files.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import dsp  # noqa: E402
from registry import CATEGORIES, SOUNDS  # noqa: E402

GEN_MODULES = ["sfx_guns", "sfx_foley", "sfx_ambience", "sfx_creatures", "sfx_ui"]
DEFAULT_OUT = HERE.parent.parent / "assets" / "ext" / "audio"


def load_modules():
    for m in GEN_MODULES:
        if (HERE / f"{m}.py").exists():
            __import__(m)


def momentary_max(x: np.ndarray) -> float:
    """Max 400 ms momentary loudness (LUFS scale), hop 50 ms."""
    if x.ndim == 1:
        x = x[:, None]
    y = dsp._k_weight(dsp.pad_to(x, max(len(x), dsp.n_of(0.4))))
    blk, hop = dsp.n_of(0.4), dsp.n_of(0.05)
    best = -70.0
    c = np.cumsum(np.concatenate([np.zeros((1, y.shape[1])), y ** 2]), axis=0)
    for s in range(0, len(y) - blk + 1, hop):
        z = np.sum((c[s + blk] - c[s]) / blk)
        best = max(best, -0.691 + 10 * np.log10(z + 1e-12))
    return float(best)


def render_one(sid: str, out_dir: str) -> dict:
    load_modules()
    sd = SOUNDS[sid]
    bus, target, measure, ceiling = CATEGORIES[sd.category]
    if sd.target is not None:
        target = sd.target
    files, stats = [], []
    raw = []
    for v in range(sd.variations):
        rng = dsp.rng_for(sid, v)
        x = np.asarray(sd.fn(rng, v), dtype=np.float64)
        if sd.stereo and x.ndim == 1:
            x = dsp.to_stereo(x)
        if not sd.stereo and x.ndim == 2:
            x = x.mean(axis=1)
        raw.append(x)
    # one gain for the whole family (keeps natural variation between takes), aligned on the mean loudness
    louds = [momentary_max(x) if measure == "max" else dsp.lufs(x) for x in raw]
    g = dsp.db(target - float(np.mean(louds)))
    fmt = sd.fmt
    if fmt == "auto":
        # Ogg Vorbis costs ~0.7 ms of decoder setup per play in Godot; short one-shots ship as WAV (imported as QOA)
        fmt = "wav" if (not sd.loop and max(len(x) for x in raw) / dsp.SR <= 3.2) else "ogg"
    for v, x in enumerate(raw):
        y = x * g
        tp = dsp.true_peak_db(y)
        if tp > ceiling:
            y = dsp.limit(y, ceiling - 0.6)
            tp2 = dsp.true_peak_db(y)
            if tp2 > ceiling:
                y *= dsp.db(ceiling - 0.2 - tp2)
        name = f"{sid}_{v + 1}" if sd.variations > 1 else sid
        stale = Path(out_dir) / "sfx" / sd.folder / (name + (".ogg" if fmt == "wav" else ".wav"))
        if stale.exists():
            stale.unlink()
        path = dsp.write(Path(out_dir) / "sfx" / sd.folder / name, y, fmt)
        files.append(str(path.relative_to(out_dir)))
        stats.append({"file": files[-1], "dur": round(len(y) / dsp.SR, 3), "peak_db": round(dsp.peak_db(y), 2),
                      "true_peak_db": round(dsp.true_peak_db(y), 2), "lufs": round(dsp.lufs(y), 2),
                      "mmax": round(momentary_max(y), 2), "rms_db": round(dsp.to_db(float(np.sqrt(np.mean(y ** 2)))), 2)})
    entry = {"category": sd.category, "bus": bus, "files": files, "loop": sd.loop, "gain_db": sd.gain_db,
             "pitch_var": sd.pitch_var, "vol_var_db": sd.vol_var_db, "max_dist": sd.max_dist, "unit_size": sd.unit_size,
             "stereo": sd.stereo}
    if sd.tags:
        entry["tags"] = sd.tags
    return {"id": sid, "entry": entry, "stats": stats}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--only", default=None, help="regex of sound ids to (re)build; others keep their manifest entries")
    ap.add_argument("--jobs", type=int, default=max(1, min(3, (os.cpu_count() or 2) - 1)))
    ap.add_argument("--no-music", action="store_true")
    ap.add_argument("--music-only", action="store_true")
    ap.add_argument("--music", default=None, help="regex of music track ids to (re)build")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    load_modules()
    if args.list:
        for sid, sd in SOUNDS.items():
            print(f"{sid:32s} {sd.category:10s} x{sd.variations} {'loop' if sd.loop else ''}")
        return
    man_path = out / "manifest.json"
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {}
    manifest.setdefault("version", 1)
    manifest.setdefault("sounds", {})
    manifest.setdefault("music", {})
    manifest.setdefault("voice", {})
    report_path = out / "report.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    t0 = time.time()
    if not args.music_only:
        ids = [s for s in SOUNDS if not args.only or re.search(args.only, s)]
        if not args.only:  # full rebuild: drop stale ids
            manifest["sounds"] = {k: v for k, v in manifest["sounds"].items() if v.get("source") in ("recording", "music")}
        with ProcessPoolExecutor(max_workers=args.jobs) as ex:
            for res in ex.map(render_one, ids, [str(out)] * len(ids)):
                manifest["sounds"][res["id"]] = res["entry"]
                report[res["id"]] = res["stats"]
                worst = max(s["true_peak_db"] for s in res["stats"])
                print(f"  {res['id']:32s} x{len(res['stats'])}  mmax {res['stats'][0]['mmax']:6.1f}  tp {worst:5.1f}"
                      f"  {res['stats'][0]['dur']:.2f}s", flush=True)
        print(f"sfx: {len(ids)} sounds in {time.time() - t0:.1f} s")
    if not args.no_music and (not args.only or args.music_only):
        import music
        manifest["music"] = music.build(out, report, manifest, args.music)
    man_path.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    report_path.write_text(json.dumps(report, indent=1, sort_keys=True))
    print(f"manifest: {len(manifest['sounds'])} sounds, {len(manifest['music'])} music tracks -> {man_path}")


if __name__ == "__main__":
    main()
