#!/usr/bin/env python3
"""Blind visual critic on CI snapshots with Gemini vision (QA loop step 3, a second opinion next to a fresh
Claude subagent). It sees only the images and docs/qa/REFERENCE_SPEC.md: no commit messages, no notes.

    python3 tools/gemini_critic.py [--ref origin/ci-snaps-claude-blocksmith-playtest] [--shots a.png,b.png]
                                   [--model gemini-flash-latest] [--out docs/qa/critic_gemini.md]

Images are read from the ci-snaps branch with `git show`; per shot the critic scores the spec axes it can judge
(0-10, ranges), lists concrete defects with where in the image they are, and names the single biggest gap as a
testable instruction. Spot-check its claims on the PNG before acting (critics hallucinate). In cloud sessions the
egress proxy injects the API key; elsewhere GEMINI_API_KEY is used. Free-tier keys work (vision, not images).
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SHOTS = ["spawn.png", "village_street.png", "tour_777_aerial.png", "night.png", "cave_torches.png", "underwater.png",
                 "inventory.png", "creative.png", "gallery_stone.png", "forest_in.png", "tv_hud.png", "lush_caves.png"]


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
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(5 * 2 ** attempt); continue
            raise RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ref', default='origin/ci-snaps-claude-blocksmith-playtest')
    ap.add_argument('--shots')
    ap.add_argument('--model', default=os.environ.get('GEMINI_CRITIC_MODEL', 'gemini-flash-latest,gemini-flash-lite-latest,gemini-2.5-flash'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'docs/qa/critic_gemini.md'))
    a = ap.parse_args()
    spec = open(os.path.join(ROOT, 'docs/qa/REFERENCE_SPEC.md')).read()
    listing = subprocess.run(['git', 'ls-tree', '--name-only', a.ref], cwd=ROOT, capture_output=True, text=True).stdout.split()
    shots = a.shots.split(',') if a.shots else [s for s in DEFAULT_SHOTS if s in listing]
    head = subprocess.run(['git', 'log', '-1', '--format=%s', a.ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    key = os.environ.get('GEMINI_API_KEY')
    out = [f"# Gemini blind critic ({a.model})", "", f"Snapshots: {head}", ""]
    for shot in shots:
        png = subprocess.run(['git', 'show', f"{a.ref}:{shot}"], cwd=ROOT, capture_output=True).stdout
        if not png:
            out.append(f"## {shot}\n\n(missing)\n"); continue
        prompt = ("You are a strict art director reviewing one screenshot of a voxel sandbox game in development. "
                  "Judge it against this quality spec (score only axes you can judge from this image; 0-10, give a "
                  "range like 5-6):\n\n" + spec + "\n\nReply in Markdown with: a one-line description of the view; "
                  "a table of axis scores with one-line evidence each; a list of concrete defects (what, where in "
                  "the image as left/centre/right and top/middle/bottom, how bad); and finally 'Biggest gap:' as one "
                  "testable instruction. Do not praise. Do not guess about things not visible.")
        try:
            parts = [{"text": prompt}, {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(png).decode()}}]
            txt = None
            # --model takes a comma list: a model whose quota is spent (HTTP 429 after the retries) hands over to the
            # next (the free tier's per-model daily quota ran out after one shot in a session).
            models = a.model.split(',')
            for mi, m in enumerate(models):
                try:
                    txt = call(m, parts, key); break
                except RuntimeError as e:
                    if '429' not in str(e) or mi == len(models) - 1: raise
                    print(f"{shot}: {m} quota spent, trying {models[mi + 1]}", file=sys.stderr)
        except Exception as e:  # noqa: BLE001
            txt = f"(critic failed: {e})"
        out += [f"## {shot}", "", txt.strip(), ""]
        print(f"{shot}: {len(txt)} chars", file=sys.stderr)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, 'w') as f:
        f.write("\n".join(out) + "\n")
    print(a.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
