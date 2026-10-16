#!/usr/bin/env python3
"""Fetches texture trial material for the 128x128 texture work (run on the CI runner, which has open internet;
the cloud session's network policy blocks these hosts). Stdlib only. Writes into the directory given (default
assets_trial/): CC0 colour maps from Poly Haven and ambientCG (grass, rock/stone, bark/wood, dirt, ore-like
rock) and three Pollinations image-generation samples (grass, stone, oak log) for a quality comparison.
Licences: Poly Haven and ambientCG are CC0 (public domain). Pollinations output is a trial only; nothing from it
ships until its licence is confirmed. Every file is listed in SOURCES.md with its origin URL."""
import io, json, os, sys, urllib.parse, urllib.request, zipfile

out = sys.argv[1] if len(sys.argv) > 1 else 'assets_trial'
os.makedirs(out, exist_ok=True)
log = ['# Texture trial sources', '']
UA = {'User-Agent': 'blocksmith-ci-asset-trial/1.0'}

def get(url, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

def save(name, data, src, lic):
    with open(os.path.join(out, name), 'wb') as f:
        f.write(data)
    log.append(f'- `{name}`: {src} ({lic})')
    print('saved', name, len(data))

# Poly Haven: top assets per category, 1k diffuse JPG.
try:
    for cat, n in [('grass', 2), ('rock', 2), ('bark', 1), ('wood', 1), ('soil', 1)]:
        lst = json.loads(get(f'https://api.polyhaven.com/assets?t=textures&categories={cat}'))
        ids = sorted(lst, key=lambda k: -lst[k].get('download_count', 0))[:n]
        for i in ids:
            files = json.loads(get(f'https://api.polyhaven.com/files/{i}'))
            diff = files.get('Diffuse') or files.get('diffuse') or files.get('Color')
            url = diff['1k']['jpg']['url']
            save(f'polyhaven_{cat}_{i}.jpg', get(url), f'Poly Haven {i} ({url})', 'CC0')
except Exception as e:
    log.append(f'- Poly Haven failed: {e}'); print('polyhaven failed', e)

# ambientCG: first materials for a query, 1K-JPG zip -> the colour map.
try:
    for q in ['Grass', 'Rock', 'Bark', 'Ground', 'Planks']:
        api = f'https://ambientcg.com/api/v2/full_json?type=Material&q={q}&limit=2&include=downloadData&sort=Popular'
        data = json.loads(get(api))
        for a in data.get('foundAssets', [])[:2]:
            dl = None
            for cat in a.get('downloadFolders', {}).values():
                for d in cat.get('downloadFiletypeCategories', {}).get('zip', {}).get('downloads', []):
                    if d.get('attribute') == '1K-JPG': dl = d.get('downloadLink') or d.get('fullDownloadPath')
            if not dl: continue
            z = zipfile.ZipFile(io.BytesIO(get(dl, 120)))
            col = [n for n in z.namelist() if 'Color' in n and n.endswith('.jpg')]
            if col:
                save(f"ambientcg_{a['assetId']}.jpg", z.read(col[0]), f"ambientCG {a['assetId']} ({dl})", 'CC0')
except Exception as e:
    log.append(f'- ambientCG failed: {e}'); print('ambientcg failed', e)

# Pollinations (no key): three seamless block textures.
prompts = {
    'grass': 'seamless tileable top-down grass block texture for a voxel game, stylized painterly, rich detail, even lighting, no shadows',
    'stone': 'seamless tileable stone block texture for a voxel game, stylized painterly, cracks and speckles, even lighting',
    'oak_log': 'seamless tileable oak tree bark texture for a voxel game, vertical grain, stylized painterly, even lighting',
}
for k, p in prompts.items():
    try:
        url = 'https://image.pollinations.ai/prompt/' + urllib.parse.quote(p) + '?width=512&height=512&seed=7&nologo=true'
        save(f'pollinations_{k}.jpg', get(url, 180), f'Pollinations ({url})', 'trial only, licence unconfirmed')
    except Exception as e:
        log.append(f'- Pollinations {k} failed: {e}'); print('pollinations failed', k, e)

open(os.path.join(out, 'SOURCES.md'), 'w').write('\n'.join(log) + '\n')
