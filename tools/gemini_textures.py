#!/usr/bin/env python3
"""Generate block textures with Gemini image generation, then import them (tools/teximport.py).

    GEMINI_API_KEY=... python3 tools/gemini_textures.py [--only stone,dirt] [--samples 2] [--model M]
                                                        [--reference docs/textures/style_reference.png]

Prompts come from tools/texture_prompts.json and the locked style text in docs/textures/STYLE_GUIDE.md (see its
prompt rules). Raw images go to build/texgen/raw (not committed), imported 128 px trials to build/texgen/out, and a
comparison sheet (procedural preview | CC0 import if present | each Gemini sample, each tiled 3x3) to
docs/textures/gemini_trial.png. Approve a texture by copying it from build/texgen/out to Resources/Textures.
Standard library + numpy/PIL only; the key is read from the environment and never written anywhere.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import teximport  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STYLE = ("Stylised realism with a hand-painted feel: crisp readable shapes, not photographic noise. One soft light from "
         "the top-left baked in as gentle relief, no cast shadows across the tile, no glare. Moderate saturation, "
         "natural earthy palette. Detail sized so it still reads when the image is shrunk to 128 x 128 pixels.")


def prompt(p, has_ref):
    parts = [
        "Create one seamless, tileable, square texture for a block face in a voxel building game.",
        "Viewed straight on, orthographic, completely flat surface, no perspective.",
        f"Subject: {p['subject']}.",
        f"Scale: {p['scale']}.",
        "Uniform density across the whole tile: no large light or dark patches, no vignette, no single focal feature.",
        "Seamless on all four edges. One tile only: the pattern must not repeat inside the image (no 2x2 grid).",
        "No text, no border, no frame, no watermark.",
        f"Style: {STYLE}",
    ]
    if has_ref:
        parts.append("Match the attached reference image's art style, saturation, lighting and level of detail exactly "
                     "(not its subject).")
    return " ".join(parts)


def generate(key, model, text, ref_png):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    parts = [{"text": text}]
    if ref_png:
        with open(ref_png, 'rb') as f:
            parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(f.read()).decode()}})
    body = json.dumps({"contents": [{"parts": parts}],
                       "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]}}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "x-goog-api-key": key})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                js = json.loads(r.read())
            for c in js.get("candidates", []):
                for part in c.get("content", {}).get("parts", []):
                    d = part.get("inlineData") or part.get("inline_data")
                    if d and d.get("data"):
                        return base64.b64decode(d["data"])
            raise RuntimeError("no image in response: " + json.dumps(js)[:300])
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors='replace')[:300]
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(2 ** (attempt + 2)); continue
            raise RuntimeError(f"HTTP {e.code}: {msg}")
        except urllib.error.URLError:
            if attempt < 3:
                time.sleep(2 ** (attempt + 2)); continue
            raise


def sheet(rows, out):
    import numpy as np
    from PIL import Image, ImageDraw
    n = 128; cell = n * 3 + 8
    cols = max(len(r[1]) for r in rows)
    im = Image.new('RGB', (cols * cell + 8, len(rows) * (cell + 18) + 8), (40, 40, 44))
    dr = ImageDraw.Draw(im)
    for ri, (name, items) in enumerate(rows):
        for ci, (label, path) in enumerate(items):
            t = Image.open(path).convert('RGBA').resize((n, n), Image.LANCZOS)
            a = np.asarray(t).astype(np.float32) / 255
            chk = ((np.indices((n, n)).sum(0) // 8) % 2)[..., None] * 0.15 + 0.35
            rgb = a[..., :3] * a[..., 3:4] + chk * (1 - a[..., 3:4])
            tile = Image.fromarray((np.tile(rgb, (3, 3, 1)) * 255).astype(np.uint8))
            x0, y0 = 4 + ci * cell, 4 + ri * (cell + 18) + 16
            im.paste(tile, (x0, y0)); dr.text((x0, y0 - 14), f"{name}: {label}", fill=(230, 230, 230))
    im.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only'); ap.add_argument('--samples', type=int, default=2)
    ap.add_argument('--model', default=os.environ.get('GEMINI_IMAGE_MODEL', 'gemini-2.5-flash-image'))
    ap.add_argument('--reference', default=os.path.join(ROOT, 'docs/textures/style_reference.png'))
    ap.add_argument('--work', default=os.path.join(ROOT, 'build/texgen'))
    ap.add_argument('--sheet', default=os.path.join(ROOT, 'docs/textures/gemini_trial.png'))
    ap.add_argument('--baselines', help='dir with <name>.png baselines (procedural previews / CC0 imports)')
    a = ap.parse_args()
    key = os.environ.get('GEMINI_API_KEY')
    if not key:
        print("GEMINI_API_KEY is not set: nothing generated (the import pipeline works on any PNG: tools/teximport.py)")
        return 2
    prompts = json.load(open(os.path.join(ROOT, 'tools/texture_prompts.json')))
    if a.only:
        want = set(a.only.split(','))
        prompts = [p for p in prompts if p['name'] in want]
    ref = a.reference if os.path.exists(a.reference) else None
    raw = os.path.join(a.work, 'raw'); out = os.path.join(a.work, 'out')
    os.makedirs(raw, exist_ok=True); os.makedirs(out, exist_ok=True)
    rows = []
    log = []
    for p in prompts:
        items = []
        if a.baselines and os.path.exists(os.path.join(a.baselines, p['name'] + '.png')):
            items.append(('baseline', os.path.join(a.baselines, p['name'] + '.png')))
        for k in range(a.samples):
            try:
                png = generate(key, a.model, prompt(p, ref is not None), ref)
            except Exception as e:  # noqa: BLE001
                print(f"{p['name']} #{k}: {e}"); log.append(f"- {p['name']} #{k}: FAILED {e}"); continue
            rp = os.path.join(raw, f"{p['name']}_{k}.png")
            with open(rp, 'wb') as f:
                f.write(png)
            dst, notes, sr = teximport.process(rp, f"{p['name']}_{k}", out, 128, p['mode'], 0.85, p.get('mean'))
            items.append((f"gemini #{k}", dst))
            log.append(f"- {p['name']} #{k}: " + "; ".join(notes))
        if items:
            rows.append((p['name'], items))
    if rows:
        sheet(rows, a.sheet)
        print("sheet:", a.sheet)
    with open(os.path.join(a.work, 'log.md'), 'w') as f:
        f.write(f"# Gemini texture run ({a.model}, reference: {ref or 'none'})\n\n" + "\n".join(log) + "\n")
    print("\n".join(log))
    return 0


if __name__ == '__main__':
    sys.exit(main())
