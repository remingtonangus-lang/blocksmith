#!/usr/bin/env python3
"""Fetches CC0 / public-domain field recordings from Wikimedia Commons for sounds synthesis can't make convincing
(horse vocalisations, cattle, dogs, crowds, thunder, rooster) and processes them into game-ready one-shots and loops.
Runs in CI (.github/workflows/frontier-assets.yml); the cloud session can't reach Commons.

  python3 frontier/tools/audio/commons.py [--out DIR] [--dry-run]
  python3 frontier/tools/audio/commons.py --mirror-licenses DIR   # copy the per-file table into frontier/LICENSES.md

Licence rule (checked per file through the Commons API, imageinfo/extmetadata): only files whose licence is CC0 or
public domain are used ("LicenseShortName"/"License" = cc0, pd, Public domain, PD-*). Each kept file is listed with its
title, author, licence, source page and processing in LICENSES_AUDIO.json / LICENSES_AUDIO.md (shipped in audio.zip).
Pins: commons_pins.json may list exact titles per target (used first) and titles to exclude.
Processing: decode (ffmpeg) -> mono 44.1 kHz -> high-pass -> one-shots: split into events by energy, keep the
best-shaped ones; loops: trim, crossfade seam -> loudness per category -> OGG. Output ids rec_* (the game prefers
them over the synthesised fallbacks when present).
"""
from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402

import dsp  # noqa: E402

API = "https://commons.wikimedia.org/w/api.php"
UA = "FrontierGameAudioFetcher/1.0 (https://github.com/remingtonangus-lang/blocksmith; CI asset build) python-urllib"

# target id: (search queries, mode, category, max files, max events, (min_s, max_s) source duration)
TARGETS = {
    "rec_horse_whinny": (["horse whinny", "horse neigh", "horse neighing"], "oneshot", "horse", 4, 6, (0.5, 120)),
    "rec_horse_snort": (["horse snort", "horse snorting", "horse blowing"], "oneshot", "horse", 3, 6, (0.3, 120)),
    "rec_horse_breath": (["horse breathing", "horse breath"], "oneshot", "horse", 2, 5, (0.5, 120)),
    "rec_cattle_moo": (["cow moo", "cattle mooing", "cow mooing", "cows"], "oneshot", "creature", 4, 6, (0.5, 180)),
    "rec_dog_bark": (["dog barking", "dog bark"], "oneshot", "creature", 4, 8, (0.3, 120)),
    "rec_rooster": (["rooster crowing", "rooster"], "oneshot", "creature", 3, 4, (0.8, 120)),
    "rec_thunder": (["thunder", "thunderclap", "thunderstorm"], "oneshot", "weather", 4, 4, (2.0, 600)),
    "rec_thunder_far": (["distant thunder", "rolling thunder"], "oneshot", "weather", 3, 3, (2.0, 600)),
    "rec_crowd_indoor": (["crowd talking", "people talking restaurant", "murmur crowd", "pub ambience"], "loop",
                         "amb_loop", 2, 1, (20, 900)),
    "rec_crowd_outdoor": (["street crowd ambience", "market crowd", "crowd outdoor"], "loop", "amb_bed", 2, 1, (20, 900)),
    "rec_coyote": (["coyote howl", "coyotes howling", "coyote"], "oneshot", "creature", 3, 4, (1.0, 180)),
    "rec_steam_whistle": (["steam locomotive whistle", "steam whistle"], "oneshot", "foley", 2, 3, (1.0, 180)),
}
LOUD = {"horse": -18.0, "creature": -20.0, "weather": -16.0, "foley": -20.0, "amb_loop": -26.0, "amb_bed": -32.0}
BAD_WORDS = re.compile(r"\b(film|movie|trailer|game|soundtrack|song|music|remix|synth|synthesized|generated)\b", re.I)


def api(params: dict) -> dict:
    params = dict(params, format="json", formatversion="2")
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001
            print("  api retry", attempt, e)
            time.sleep(2 + attempt * 3)
    return {}


def licence_ok(meta: dict) -> tuple[bool, str]:
    short = html.unescape(re.sub("<[^>]+>", "", meta.get("LicenseShortName", {}).get("value", ""))).strip()
    lic = meta.get("License", {}).get("value", "").strip().lower()
    s = short.lower()
    ok = lic in ("cc0", "pd") or lic.startswith("pd-") or s.startswith("cc0") or "public domain" in s or s.startswith("pd")
    return ok, short or lic


def strip(v: str) -> str:
    return html.unescape(re.sub("<[^>]+>", "", v or "")).strip()


def search(query: str, limit: int = 40) -> list[str]:
    d = api({"action": "query", "list": "search", "srnamespace": 6, "srlimit": limit,
             "srsearch": f"{query} filemime:audio"})
    return [h["title"] for h in d.get("query", {}).get("search", [])]


def info(titles: list[str]) -> list[dict]:
    out = []
    for i in range(0, len(titles), 20):
        d = api({"action": "query", "prop": "imageinfo", "titles": "|".join(titles[i:i + 20]),
                 "iiprop": "url|extmetadata|size|mime|metadata"})
        for p in d.get("query", {}).get("pages", []):
            ii = (p.get("imageinfo") or [{}])[0]
            if not ii:
                continue
            md = {m["name"]: m["value"] for m in (ii.get("metadata") or []) if isinstance(m, dict) and "name" in m}
            length = md.get("length") or md.get("playtime_seconds")
            out.append({"title": p["title"], "url": ii.get("url"), "page": ii.get("descriptionurl"), "mime": ii.get("mime"),
                        "size": ii.get("size", 0), "meta": ii.get("extmetadata", {}),
                        "length": float(length) if length else None})
    return out


def decode(url: str, tmp: Path) -> np.ndarray | None:
    src = tmp / ("src" + Path(urllib.parse.urlparse(url).path).suffix)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        src.write_bytes(r.read())
    wav = tmp / "dec.wav"
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-ac", "1", "-ar", str(dsp.SR), str(wav)])
    if r.returncode != 0 or not wav.exists():
        return None
    return dsp.read(wav)


def events(x: np.ndarray, max_n: int, min_s=0.25, max_s=4.0) -> list[np.ndarray]:
    """Split a recording into separate calls/hits by energy; return the loudest well-isolated ones."""
    fr = dsp.n_of(0.02)
    n = len(x) // fr
    if n < 5:
        return []
    rms = np.sqrt(np.mean(x[:n * fr].reshape(n, fr) ** 2, axis=1))
    floor = np.percentile(rms, 20)
    th = floor + (rms.max() - floor) * 0.15
    on = rms > th
    segs, i = [], 0
    while i < n:
        if on[i]:
            j = i
            while j < n and (on[j] or (j + 5 < n and on[j:j + 5].any())):
                j += 1
            segs.append((i, j))
            i = j
        else:
            i += 1
    out = []
    for a, b in segs:
        d = (b - a) * 0.02
        if d < min_s or d > max_s:
            continue
        s = max(0, (a - 4) * fr)
        e = min(len(x), (b + 8) * fr)
        out.append((float(rms[a:b].max()), x[s:e]))
    out.sort(key=lambda t: -t[0])
    return [dsp.fade(y, 0.01, 0.08) for _, y in out[:max_n]]


def load_pins() -> dict:
    p = HERE / "commons_pins.json"
    return json.loads(p.read_text()) if p.exists() else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE.parent.parent / "assets" / "ext" / "audio"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--mirror-licenses", default=None, help="audio dir with LICENSES_AUDIO.md -> update LICENSES.md")
    a = ap.parse_args()
    if a.mirror_licenses:
        return mirror(Path(a.mirror_licenses))
    out = Path(a.out)
    man_path = out / "manifest.json"
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {"version": 1, "sounds": {}}
    pins = load_pins()
    exclude = set(pins.get("exclude", []))
    used_titles = set()
    licences = []
    tmp = Path(tempfile.mkdtemp(prefix="frontier_commons_"))
    for tid, (queries, mode, cat, max_files, max_events, (dmin, dmax)) in TARGETS.items():
        titles = list(pins.get(tid, []))
        for q in queries:
            titles += search(q)
        seen, cands = set(), []
        for t in titles:
            if t not in seen and t not in exclude and t not in used_titles:
                seen.add(t)
                cands.append(t)
        files, pieces = [], []
        for inf in info(cands):
            if len(files) >= max_files:
                break
            ok, lic = licence_ok(inf["meta"])
            desc = strip(inf["meta"].get("ImageDescription", {}).get("value", ""))
            if not ok:
                continue
            if BAD_WORDS.search(inf["title"] + " " + desc[:300]):
                continue
            if inf["length"] is not None and not (dmin <= inf["length"] <= dmax):
                continue
            if inf["size"] > 60_000_000:
                continue
            author = strip(inf["meta"].get("Artist", {}).get("value", "")) or "unknown (see source page)"
            print(f"  {tid}: {inf['title']}  [{lic}]  {author[:40]}")
            if a.dry_run:
                files.append(inf)
                continue
            try:
                x = decode(inf["url"], tmp)
            except Exception as e:  # noqa: BLE001
                print("   download failed", e)
                continue
            if x is None or len(x) < dsp.SR * 0.3:
                continue
            x = dsp.hp(x - np.mean(x), 60, 2)
            if mode == "oneshot":
                evs = events(x, max_events, 0.25, 8.0 if cat == "weather" else 4.0)
                if not evs:
                    continue
                pieces += [(e, inf) for e in evs]
            else:
                seg = x[: dsp.n_of(min(len(x) / dsp.SR, 90.0))]
                if len(seg) < dsp.n_of(12):
                    continue
                pieces.append((dsp.make_loop(seg, 1.5), inf))
            files.append(inf)
            used_titles.add(inf["title"])
            licences.append({"target": tid, "title": inf["title"], "author": author, "licence": lic,
                             "source": inf["page"], "file_url": inf["url"],
                             "processing": "decoded, mono 44.1 kHz, high-passed, " +
                                           ("split into events, " if mode == "oneshot" else "trimmed and loop-crossfaded, ") +
                                           "loudness-normalised, Ogg Vorbis"})
        if a.dry_run or not pieces:
            print(f"{tid}: {len(files)} files, {len(pieces)} pieces")
            continue
        rels = []
        target = LOUD[cat]
        for i, (y, inf) in enumerate(pieces[: max(max_events, max_files) * 2]):
            y = dsp.normalize(y, target, -1.0)
            p = dsp.write(out / "sfx" / "rec" / f"{tid}_{i + 1}", y, "ogg", 0.3)
            rels.append(str(p.relative_to(out)))
        bus = "Ambience" if cat in ("amb_loop", "amb_bed", "creature", "weather") else "SFX"
        manifest["sounds"][tid] = {"category": cat, "bus": bus, "files": rels, "loop": mode == "loop", "gain_db": 0.0,
                                   "pitch_var": 0.04 if mode == "oneshot" else 0.0, "vol_var_db": 1.5,
                                   "max_dist": 400.0 if cat in ("creature", "horse") else 60.0,
                                   "unit_size": 8.0 if cat == "creature" else 3.0, "stereo": False,
                                   "source": "recording"}
        print(f"{tid}: {len(files)} files -> {len(rels)} clips")
    if not a.dry_run:
        man_path.write_text(json.dumps(manifest, indent=1, sort_keys=True))
        (out / "LICENSES_AUDIO.json").write_text(json.dumps(licences, indent=1))
        md = ["| Target | Commons file | Author | Licence | Source |", "|---|---|---|---|---|"]
        for L in licences:
            md.append(f"| {L['target']} | {L['title'].replace('|', '/')} | {L['author'][:80].replace('|', '/')} | "
                      f"{L['licence']} | {L['source']} |")
        (out / "LICENSES_AUDIO.md").write_text("\n".join(md) + "\n")
        print(f"commons: {len(licences)} recordings, licences -> LICENSES_AUDIO.md")


def mirror(audio_dir: Path):
    lic = HERE.parent.parent / "LICENSES.md"
    table = (audio_dir / "LICENSES_AUDIO.md").read_text()
    s = lic.read_text()
    a, b = "<!-- audio-recordings:begin -->", "<!-- audio-recordings:end -->"
    if a in s and b in s:
        s = s[:s.index(a) + len(a)] + "\n" + table + s[s.index(b):]
        lic.write_text(s)
        print("LICENSES.md updated")
    else:
        print("markers missing in LICENSES.md")


if __name__ == "__main__":
    main()
