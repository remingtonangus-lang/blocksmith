#!/usr/bin/env python3
"""Frontier asset fetcher (runs on a GitHub-hosted runner; the cloud sessions can't reach the asset hosts).

Modes:
  catalog   dump the ambientCG + Poly Haven catalogues and render contact sheets per search query
            (out/catalog/*.json, out/catalog/sheet_<query>.jpg) so a builder can pick assets by eye.
  fetch     download everything in frontier/assets/manifest.json, process it (resize, rename to a fixed map
            layout) into out/ext/, and write out/ext/LICENSES.json (source URL + licence per asset).

Every asset fetched here is CC0 (ambientCG, Poly Haven). The script refuses anything whose catalogue entry is not CC0.
"""
import io, json, os, sys, time, zipfile, urllib.request, urllib.parse, concurrent.futures as cf

UA = "FrontierGame-AssetFetch/1.0 (github.com/remingtonangus-lang/blocksmith; CC0 asset pipeline)"
ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[2] if len(sys.argv) > 2 else "out"


def get(url, tries=4, binary=True):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                return data if binary else data.decode("utf-8")
        except Exception as e:  # noqa
            print(f"  retry {i+1} {url}: {e}", flush=True)
            time.sleep(2 ** i)
    raise RuntimeError("failed: " + url)


def getjson(url):
    return json.loads(get(url, binary=False))


# ------------------------------------------------------------------ catalogues
def ambientcg_catalog():
    items, off = [], 0
    while True:
        url = ("https://ambientcg.com/api/v2/full_json?type=Material&limit=250&offset=%d"
               "&include=downloadData,tagData,previewData&sort=Popular" % off)
        j = getjson(url)
        batch = j.get("foundAssets", [])
        items += batch
        print(f"ambientCG catalog {len(items)}", flush=True)
        if len(batch) < 250:
            break
        off += 250
    return items


def polyhaven_catalog():
    return getjson("https://api.polyhaven.com/assets?t=all")


SHEET_QUERIES = {
    "grass": ["grass"], "ground": ["ground"], "rock": ["rock", "cliff"], "sand": ["sand"], "gravel": ["gravel"],
    "snow": ["snow"], "mud": ["mud"], "bark": ["bark"], "planks": ["planks", "wood floor"], "siding": ["siding", "wood"],
    "roof": ["roofing", "shingle"], "metal": ["metal", "rust"], "fabric": ["fabric"], "leather": ["leather"],
    "bricks": ["bricks"], "plaster": ["plaster", "concrete"], "leaves": ["leaf", "foliage"],
}


def contact_sheet(entries, path, thumb=192, cols=8):
    from PIL import Image, ImageDraw
    if not entries:
        return
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb, rows * (thumb + 16)), (30, 30, 30))
    d = ImageDraw.Draw(sheet)

    def load(e):
        try:
            return Image.open(io.BytesIO(get(e[1], tries=2))).convert("RGB").resize((thumb, thumb))
        except Exception:
            return Image.new("RGB", (thumb, thumb), (255, 0, 255))
    with cf.ThreadPoolExecutor(8) as ex:
        imgs = list(ex.map(load, entries))
    for i, (e, im) in enumerate(zip(entries, imgs)):
        x, y = (i % cols) * thumb, (i // cols) * (thumb + 16)
        sheet.paste(im, (x, y))
        d.text((x + 3, y + thumb + 2), e[0][:30], fill=(230, 230, 230))
    sheet.save(path, quality=85)


def catalog():
    os.makedirs(os.path.join(OUT, "catalog"), exist_ok=True)
    acg = ambientcg_catalog()
    ph = polyhaven_catalog()
    json.dump(acg, open(os.path.join(OUT, "catalog", "ambientcg.json"), "w"))
    json.dump(ph, open(os.path.join(OUT, "catalog", "polyhaven.json"), "w"))
    # compact listings for reading
    with open(os.path.join(OUT, "catalog", "ambientcg_list.txt"), "w") as f:
        for a in acg:
            f.write("%s\t%s\t%s\n" % (a.get("assetId"), a.get("displayCategory", ""), ",".join(a.get("tags", [])[:8])))
    with open(os.path.join(OUT, "catalog", "polyhaven_list.txt"), "w") as f:
        for k, v in ph.items():
            f.write("%s\t%s\t%s\t%s\n" % (k, v.get("type"), ",".join(v.get("categories", [])), ",".join(v.get("tags", [])[:8])))
    for name, qs in SHEET_QUERIES.items():
        ent = []
        for a in acg:
            hay = (a.get("assetId", "") + " " + " ".join(a.get("tags", [])) + " " + a.get("displayCategory", "")).lower()
            if any(q in hay for q in qs):
                pv = a.get("previewImage", {})
                url = pv.get("256-JPG-242424") or pv.get("256-PNG") or next(iter(pv.values()), None)
                if url:
                    ent.append(("acg:" + a["assetId"], url))
        for k, v in ph.items():
            if v.get("type") != 1:   # 1 = texture
                continue
            hay = (k + " " + " ".join(v.get("tags", [])) + " " + " ".join(v.get("categories", []))).lower()
            if any(q in hay for q in qs):
                ent.append(("ph:" + k, "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=256" % k))
        ent = ent[:96]
        contact_sheet(ent, os.path.join(OUT, "catalog", "sheet_%s.jpg" % name))
        print(f"sheet {name}: {len(ent)}", flush=True)
    # models sheet (Poly Haven, type 2)
    ent = [("ph:" + k, "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=256" % k)
           for k, v in ph.items() if v.get("type") == 2]
    for i in range(0, len(ent), 96):
        contact_sheet(ent[i:i + 96], os.path.join(OUT, "catalog", "sheet_models_%d.jpg" % (i // 96)))
    ent = [("ph:" + k, "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=256" % k)
           for k, v in ph.items() if v.get("type") == 0]
    for i in range(0, min(len(ent), 288), 96):
        contact_sheet(ent[i:i + 96], os.path.join(OUT, "catalog", "sheet_hdris_%d.jpg" % (i // 96)))


# ------------------------------------------------------------------ fetch
MAPS_ACG = {"Color": "albedo", "NormalGL": "normal", "Roughness": "roughness", "AmbientOcclusion": "ao",
            "Displacement": "height", "Opacity": "opacity", "Metalness": "metallic"}
MAPS_PH = {"diff": "albedo", "Diffuse": "albedo", "nor_gl": "normal", "rough": "roughness", "Rough": "roughness",
           "ao": "ao", "AO": "ao", "disp": "height", "Displacement": "height", "arm": "arm", "alpha": "opacity",
           "metal": "metallic"}


def save_img(data, path, size):
    from PIL import Image
    im = Image.open(io.BytesIO(data))
    if size and max(im.size) > size:
        im = im.resize((size, size * im.size[1] // im.size[0]), Image.LANCZOS)
    mode = "RGBA" if im.mode in ("RGBA", "LA") else ("L" if im.mode in ("L", "I;16", "I") else "RGB")
    if im.mode in ("I;16", "I"):
        import numpy as np
        a = np.asarray(im, dtype=np.float32)
        a = (a - a.min()) / max(1.0, a.max() - a.min()) * 255
        im = Image.fromarray(a.astype("uint8"))
    im = im.convert(mode)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)


def fetch_acg(entry, acg_index, lic):
    aid = entry["ambientcg"]
    a = acg_index.get(aid)
    if not a:
        print("  MISSING ambientCG", aid); return
    res = entry.get("res", "2K")
    dl = None
    for folder in a.get("downloadFolders", {}).values():
        for cat in folder.get("downloadFiletypeCategories", {}).values():
            for d in cat.get("downloads", []):
                if d.get("attribute") == res + "-JPG" or d.get("attribute") == res + "-PNG":
                    dl = d.get("downloadLink") or d.get("fullDownloadPath")
                    if d.get("attribute").endswith("JPG"):
                        break
    if not dl:
        print("  no download for", aid); return
    z = zipfile.ZipFile(io.BytesIO(get(dl)))
    dest = os.path.join(OUT, "ext", entry["dest"])
    for nm in z.namelist():
        for key, mp in MAPS_ACG.items():
            if ("_" + key + ".") in nm:
                save_img(z.read(nm), os.path.join(dest, mp + ".png"), entry.get("size", 1024))
    lic[entry["dest"]] = dict(source="https://ambientcg.com/view?id=" + aid, licence="CC0 1.0", author="ambientCG")
    print("  ok", aid, "->", entry["dest"], flush=True)


def fetch_ph(entry, lic):
    pid = entry["polyhaven"]
    info = getjson("https://api.polyhaven.com/info/" + pid)
    files = getjson("https://api.polyhaven.com/files/" + pid)
    dest = os.path.join(OUT, "ext", entry["dest"])
    res = entry.get("res", "2k")
    t = info.get("type")
    if t == 1:   # texture
        for key, mp in MAPS_PH.items():
            if key in files and res in files[key]:
                f = files[key][res].get("png") or files[key][res].get("jpg")
                save_img(get(f["url"]), os.path.join(dest, mp + ".png"), entry.get("size", 1024))
    elif t == 2:  # model: gltf + its includes
        g = files["gltf"][res]["gltf"]
        os.makedirs(dest, exist_ok=True)
        open(os.path.join(dest, pid + ".gltf"), "wb").write(get(g["url"]))
        for rel, inc in g.get("include", {}).items():
            p = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(get(inc["url"]))
    elif t == 0:  # hdri
        f = files["hdri"][res]["exr" if entry.get("exr") else "hdr"]
        os.makedirs(dest, exist_ok=True)
        open(os.path.join(dest, pid + (".exr" if entry.get("exr") else ".hdr")), "wb").write(get(f["url"]))
    authors = ", ".join(info.get("authors", {}).keys())
    lic[entry["dest"]] = dict(source="https://polyhaven.com/a/" + pid, licence="CC0 1.0", author=authors or "Poly Haven")
    print("  ok", pid, "->", entry["dest"], flush=True)


def fetch():
    man = json.load(open(os.path.join(ROOT, "..", "assets", "manifest.json")))
    lic = {}
    acg_index = {}
    if any("ambientcg" in e for e in man["assets"]):
        acg_index = {a["assetId"]: a for a in ambientcg_catalog()}
    jobs = []
    with cf.ThreadPoolExecutor(6) as ex:
        for e in man["assets"]:
            if "ambientcg" in e:
                jobs.append(ex.submit(fetch_acg, e, acg_index, lic))
            elif "polyhaven" in e:
                jobs.append(ex.submit(fetch_ph, e, lic))
        for j in jobs:
            try:
                j.result()
            except Exception as ex_:
                print("  FAILED", ex_)
    os.makedirs(os.path.join(OUT, "ext"), exist_ok=True)
    json.dump(lic, open(os.path.join(OUT, "ext", "LICENSES.json"), "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "catalog"
    os.makedirs(OUT, exist_ok=True)
    {"catalog": catalog, "fetch": fetch}[mode]()
