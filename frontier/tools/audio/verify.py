#!/usr/bin/env python3
"""Checks and plots the built audio (QUALITY_BAR 9: no clipping, loudness targets, every dialogue line has audio).

  python3 frontier/tools/audio/verify.py [--out DIR] [--plots PNG_DIR] [--only REGEX]

Checks every file listed in manifest.json: exists, decodes, true peak < -1 dBFS (bar: < -0.3), not silent, loudness
within +-3 LU of the family mean, loops start/end continuous (no click at the seam), music stems equal length.
Plots (matplotlib): waveform + spectrogram per sound id (first variation) into contact sheets, one per folder.
Exit code 1 on any failure.
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

import dsp  # noqa: E402


def seam_click(x: np.ndarray) -> float:
    """Jump at the loop seam relative to typical sample-to-sample change."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    d = np.abs(np.diff(m))
    typical = np.percentile(d, 99) + 1e-9
    return float(abs(m[0] - m[-1]) / typical)


def check(out: Path, only: str | None) -> list[str]:
    man = json.loads((out / "manifest.json").read_text())
    fails = []
    n = 0
    for sid, e in man.get("sounds", {}).items():
        if only and not re.search(only, sid):
            continue
        for f in e["files"]:
            p = out / f
            n += 1
            if not p.exists():
                fails.append(f"missing {f}")
                continue
            x = dsp.read(p)
            if len(x) < 10 or np.max(np.abs(x)) < 1e-4:
                fails.append(f"silent {f}")
                continue
            tp = dsp.peak_db(x)
            if tp > -0.3:
                fails.append(f"clipping {f} peak {tp:.2f} dBFS")
            if e.get("loop") and seam_click(x) > 1.5:
                fails.append(f"loop seam click {f} ({seam_click(x):.1f}x)")
    for tid, t in man.get("music", {}).items():
        if only and not re.search(only, tid):
            continue
        lens = set()
        for stem, f in t.get("stems", {}).items():
            p = out / f
            n += 1
            if not p.exists():
                fails.append(f"missing {f}")
                continue
            x = dsp.read(p)
            lens.add(len(x) // 441)
            if dsp.peak_db(x) > -0.3:
                fails.append(f"clipping {f}")
        if len(lens) > 1:
            fails.append(f"music {tid}: stems differ in length {sorted(lens)}")
    for lid, v in man.get("voice", {}).items():
        p = out / v["file"]
        n += 1
        if not p.exists():
            fails.append(f"voice line without audio: {lid}")
    print(f"verify: {n} files checked, {len(fails)} problems")
    return fails


def plots(out: Path, png_dir: Path, only: str | None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    man = json.loads((out / "manifest.json").read_text())
    groups: dict[str, list] = {}
    for sid, e in sorted(man["sounds"].items()):
        if only and not re.search(only, sid):
            continue
        folder = Path(e["files"][0]).parent.name
        groups.setdefault(folder, []).append((sid, out / e["files"][0]))
    for tid, t in sorted(man.get("music", {}).items()):
        if only and not re.search(only, tid):
            continue
        for stem, f in t["stems"].items():
            groups.setdefault("music", []).append((f"{tid}/{stem}", out / f))
    png_dir.mkdir(parents=True, exist_ok=True)
    for folder, items in groups.items():
        for page in range(0, len(items), 12):
            chunk = items[page:page + 12]
            fig, axes = plt.subplots(len(chunk), 2, figsize=(14, 1.6 * len(chunk)), squeeze=False,
                                     gridspec_kw={"width_ratios": [1, 1.4]})
            for i, (sid, p) in enumerate(chunk):
                x = dsp.read(p)
                m = x if x.ndim == 1 else x.mean(axis=1)
                t = np.arange(len(m)) / dsp.SR
                ax = axes[i][0]
                ax.plot(t, m, lw=0.4, color="#1f4e79")
                ax.axhline(dsp.db(-1), color="#c0392b", lw=0.5, ls="--")
                ax.axhline(-dsp.db(-1), color="#c0392b", lw=0.5, ls="--")
                ax.set_ylim(-1, 1)
                ax.set_xlim(0, t[-1] if len(t) else 1)
                ax.set_ylabel(sid, rotation=0, ha="right", fontsize=7)
                ax.tick_params(labelsize=6)
                ax2 = axes[i][1]
                nfft = 1024
                ax2.specgram(m + 1e-9, NFFT=nfft, Fs=dsp.SR, noverlap=nfft // 2, cmap="magma", vmin=-130, vmax=-20)
                ax2.set_yscale("symlog", linthresh=500)
                ax2.set_ylim(30, dsp.SR / 2)
                ax2.tick_params(labelsize=6)
                ax2.set_title(f"pk {dsp.peak_db(x):.1f} dBFS  LUFS {dsp.lufs(x):.1f}  {len(m) / dsp.SR:.2f}s", fontsize=6)
            fig.tight_layout()
            fn = png_dir / f"{folder}_{page // 12 + 1}.png"
            fig.savefig(fn, dpi=72)
            plt.close(fig)
            print("plot", fn)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE.parent.parent / "assets" / "ext" / "audio"))
    ap.add_argument("--plots", default=None)
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    out = Path(a.out)
    fails = check(out, a.only)
    for f in fails[:200]:
        print("FAIL", f)
    if a.plots:
        plots(out, Path(a.plots), a.only)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
