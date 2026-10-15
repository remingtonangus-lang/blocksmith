#!/usr/bin/env python3
"""Blind item-art critic (Gemini vision): shows two or more images of item art under neutral labels (A, B, ...)
in a random order and asks for a 0-10 rating per image against the item art brief, the concrete defects, and which is
better. The critic never learns which image is new. Used for the item art upgrade's critic rounds
(docs/qa/items/critic.md); spot-check what it claims on the images before acting.

    python3 tools/item_critic.py IMG [IMG...] [--context TEXT] [--seed N] [--out FILE]
"""
import argparse
import base64
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request

BRIEF = """You are a strict art director reviewing ITEM ART for a blocky voxel survival game played on a TV from a sofa
(icons appear about 60-70 px tall on a 1080p screen; the hotbar is the most seen UI). The terrain and block textures are
fine and out of scope. A good item set has: clean silhouettes readable at TV distance; consistent lighting (light from
the upper left) and a palette that sits with chunky voxel block textures; clearly distinct material tiers (wood, stone,
iron, gold, diamond, a dark violet top tier, copper); volume and material cues (metal reads as metal, food as food);
no muddy, noisy or mushy pixels; a consistent style across every item; originality (not copies of another game's art).
"""

ASK = """Rate each labelled image 0-10 against the brief (10 = shippable, polished commercial quality; 7 = clearly
good; 5 = mediocre; 3 = poor). For each image: score, the 3-6 most important concrete defects (say where: row/column or
which item), and what works. Then say which image is better overall and by how much, and the single most valuable change
for the better one. Be specific and terse. Answer in Markdown."""


def call(model, parts, key):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = json.dumps({"contents": [{"parts": parts}], "generationConfig": {"temperature": 0.2}}).encode()
    headers = {"Content-Type": "application/json"}
    if key:
        headers["x-goog-api-key"] = key
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=300) as r:
                js = json.loads(r.read())
            return "".join(p.get("text", "") for p in js["candidates"][0]["content"]["parts"])
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(5 * 2 ** attempt)
                continue
            raise RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--context", default="")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--model", default="gemini-flash-latest,gemini-3.8-flash,gemini-flash-lite-latest")
    ap.add_argument("--out")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    imgs = list(a.images)
    rng.shuffle(imgs)
    labels = [chr(65 + i) for i in range(len(imgs))]
    parts = [{"text": BRIEF + ("\n" + a.context if a.context else "")}]
    for lab, path in zip(labels, imgs):
        parts.append({"text": f"Image {lab}:"})
        parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(open(path, "rb").read()).decode()}})
    parts.append({"text": ASK})
    key = os.environ.get("GEMINI_API_KEY")
    text, err = None, None
    for model in a.model.split(","):
        try:
            text = call(model, parts, key)
            break
        except Exception as e:  # try the next model
            err = e
    if text is None:
        sys.exit(f"critic failed: {err}")
    key_line = ", ".join(f"{lab} = {os.path.basename(p)}" for lab, p in zip(labels, imgs))
    out = f"{text}\n\n<!-- labels (hidden from the critic): {key_line} -->\n"
    if a.out:
        with open(a.out, "a") as f:
            f.write(out + "\n")
    print(out)


if __name__ == "__main__":
    main()
