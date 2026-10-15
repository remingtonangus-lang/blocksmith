#!/usr/bin/env python3
"""Blind visual critic for Alabaster's CI shots with Gemini vision (bug hunting by eye, a second opinion).
It sees only each image and game/tools/critic_spec.md: no code, commit messages or notes.

    python3 game/tools/critic.py [--ref origin/capital-shots] [--shots a,b] [--out FILE]

Shots are read from the capital-shots branch (shots/NAME.png) with `git show`. Per shot: axis scores, concrete
defects with where they are in the image, and the single biggest gap as a testable instruction. Spot-check
every claim on the PNG before acting on it (critics hallucinate). In cloud sessions the egress proxy injects
the API key; elsewhere GEMINI_API_KEY is used.
"""
import argparse
import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = ["capital_noon", "capital_dusk", "capital_night", "overview", "mountains", "forest_floor", "battle_ground",
           "troops_lineup", "vehicles_spawn", "frigate_deck", "coast", "road_bridge", "fort_lumen", "radar_night",
           "snow_peaks", "weapon_view"]
MODELS = "gemini-flash-latest,gemini-flash-lite-latest"   # first that answers (free-tier daily quotas run out)


def call(model, parts, key):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = json.dumps({"contents": [{"parts": parts}], "generationConfig": {"temperature": 0.2}}).encode()
    headers = {"Content-Type": "application/json"}
    if key:
        headers["x-goog-api-key"] = key
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=240) as r:
                js = json.loads(r.read())
            return "".join(p.get("text", "") for p in js["candidates"][0]["content"]["parts"])
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")
            if e.code == 429 and "PerDay" in msg:
                raise RuntimeError("daily quota used up")          # retrying cannot help today
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(5 * 2 ** attempt)
                continue
            raise RuntimeError(f"HTTP {e.code}: {msg[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="origin/capital-shots")
    ap.add_argument("--shots")
    ap.add_argument("--models", default=os.environ.get("CRITIC_MODELS", MODELS))
    ap.add_argument("--out", default=os.path.join(ROOT, "docs/status/capital-critic.md"))
    a = ap.parse_args()
    spec = open(os.path.join(HERE, "critic_spec.md")).read()
    shots = a.shots.split(",") if a.shots else DEFAULT
    head = subprocess.run(["git", "log", "-1", "--format=%s", a.ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    key = os.environ.get("GEMINI_API_KEY")
    out = ["# Alabaster blind critic (Gemini)", "", f"Shots: {head}", ""]
    for shot in shots:
        png = subprocess.run(["git", "show", f"{a.ref}:shots/{shot}.png"], cwd=ROOT, capture_output=True).stdout
        if not png:
            out += [f"## {shot}", "", "(missing)", ""]
            continue
        prompt = (spec + "\n\nYou are a strict art director reviewing one screenshot of this game (rendered with a "
                  "software rasterizer at 1280x720; ignore softness from that). Reply in Markdown: a line of axis "
                  "scores, then up to 6 concrete defects, each with where it is in the image (e.g. 'upper left'), "
                  "then 'Biggest gap:' as one testable instruction. Do not praise. Shot name: " + shot)
        parts = [{"text": prompt}, {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(png).decode()}}]
        text = None
        for m in a.models.split(","):
            try:
                text = call(m, parts, key)
                break
            except Exception as e:
                text = f"(error from {m}: {e})"
        out += [f"## {shot}", "", text.strip(), ""]
        print(f"critic: {shot} done", flush=True)
    open(a.out, "w").write("\n".join(out) + "\n")
    print(f"critic: wrote {a.out}")


if __name__ == "__main__":
    main()
