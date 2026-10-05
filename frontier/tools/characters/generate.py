"""Frontier character pipeline entry point (run with a Python that has the `bpy` module, see run.sh).

  python generate.py [--out DIR] [--only id,id] [--count N] [--no-chars] [--no-anims] [--clips a,b]

Writes DIR/<id>.glb for the town roster (appearance.roster()), DIR/animations.glb + animations.json (retarget.py),
DIR/characters.json (catalogue read by src/actors/character_factory.gd) and DIR/LICENSES.json.
"""
import argparse
import json
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import mhenv  # noqa: E402
import appearance  # noqa: E402

DEFAULT_OUT = os.path.join(mhenv.FRONTIER, "assets", "characters_out")

ROLE_TAGS = {
    "rancher": ["rider", "ranch", "townsfolk"], "cowhand": ["rider", "ranch"], "townsman": ["townsfolk"],
    "gentleman": ["townsfolk", "wealthy"], "worker": ["townsfolk", "labour"], "drifter": ["rider", "outlaw"],
    "lawman": ["rider", "law", "townsfolk"], "elder": ["townsfolk"], "townswoman": ["townsfolk"],
    "lady": ["townsfolk", "wealthy"], "ranchwoman": ["ranch"], "matron": ["townsfolk"], "hero": ["hero"],
}
DIRT = {"rancher": 0.55, "cowhand": 0.6, "drifter": 0.7, "worker": 0.6, "lawman": 0.45, "ranchwoman": 0.45,
        "hero": 0.5}


def _mul(c, k):
    return [round(min(1.0, x * k), 3) for x in c]


def catalogue_entry(spec, report):
    role = spec["role"]
    hc = spec.get("hair_color", [0.2, 0.14, 0.09])
    mats = {
        "skin": {"tint": spec.get("skin_tint", [1, 1, 1]), "weathering": spec.get("weathering", 0.2),
                 "stubble": spec.get("stubble", 0.0) if spec["sex"] == "male" else 0.0,
                 "stubble_color": _mul(hc, 0.9)},
        "hair": {"tint": hc},
        "brows": {"tint": _mul(hc, 0.85)},
        "lashes": {"tint": [0.09, 0.07, 0.06]},
        "beard": {"tint": _mul(hc, 1.15)},
    }
    for g in spec.get("clothes", []):
        if g.get("kind") == "mh":
            g = dict(g, type="mh")
        elif g.get("kind") != "proc" or g["type"] == "beard":
            continue
        key = "%s:%s:%s" % (g.get("material", "cloth"), g["id"], g.get("fabric", "wool"))
        m = {"tint": g.get("tint"), "dirt": DIRT.get(role, 0.3)}
        if g.get("palette"):
            m["palette"] = g["palette"]
        if "fabric_mix" in g:
            m["fabric_mix"] = g["fabric_mix"]
        if g.get("material") == "leather":
            m.update({"roughness": 0.55, "fabric_mix": g.get("fabric_mix", 0.6), "tile": 1.5,
                      "dirt": DIRT.get(role, 0.3) * 0.5})
        elif g.get("fabric") == "wool":
            m["sheen"] = 0.12
        mats[key] = m
    return {
        "id": spec["id"], "file": report["glb"], "role": role, "sex": spec["sex"], "age": spec.get("age"),
        "ethnicity": spec.get("ethnicity"), "lod": spec.get("lod", "npc"),
        "tags": [role, spec["sex"]] + ROLE_TAGS.get(role, []),
        "outfit": [g.get("style", g.get("type", g.get("asset"))) for g in spec.get("clothes", [])],
        "tris": report.get("tris"), "tris_total": report.get("tris_total"), "bytes": report.get("bytes"),
        "materials": mats,
    }


def licences():
    return {
        "generated_by": "frontier/tools/characters (original code); output = CC0 assets + original procedural work",
        "sources": [
            {"what": "MakeHuman base mesh, modelling targets, game_engine rig + weights, expression units",
             "source": "https://github.com/makehumancommunity/mpfb2 (src/mpfb/data)", "licence": "CC0 1.0 (assets); "
             "MPFB2 code is GPL-3.0 and is only run as a tool, not shipped"},
            {"what": "MakeHuman system assets: skins, eyes, eyebrows, eyelashes, teeth, tongue, hair",
             "source": "makehuman_system_assets_cc0.zip (mirror1.makehuman.net / files2.makehumancommunity.org)",
             "licence": "CC0 1.0 (packs/makehuman_system_assets.json lists every asset as CC0)"},
            {"what": "ARKit face units (faceunits01) and visemes (visemes02)",
             "source": "https://github.com/makehumancommunity/extra-targets", "licence": "CC0 1.0"},
            {"what": "Motion capture (animations.glb)",
             "source": "CMU Graphics Lab Motion Capture Database, mocap.cs.cmu.edu (cgspeed BVH conversion, "
                       "github.com/una-dinosauria/cmu-mocap)",
             "licence": "Free for research and commercial use (CMU); no extra restrictions from the BVH converter. "
                        "Acknowledgement: The data used in this project was obtained from mocap.cs.cmu.edu. "
                        "The database was created with funding from NSF EIA-0196217."},
            {"what": "Procedural garments, hats, beards, belts, strand texture, shaders",
             "source": "frontier/tools/characters/garments.py, frontier/shaders/characters", "licence": "original"},
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--only", default="")
    ap.add_argument("--count", type=int, default=0)
    ap.add_argument("--no-chars", action="store_true")
    ap.add_argument("--no-anims", action="store_true")
    ap.add_argument("--clips", default="")
    a = ap.parse_args()
    missing = mhenv.check_sources()
    if missing:
        print("missing sources (run tools/characters/fetch_sources.sh):\n  " + "\n  ".join(missing))
        sys.exit(2)
    os.makedirs(a.out, exist_ok=True)
    cat_path = os.path.join(a.out, "characters.json")
    cat = {"characters": []}
    if os.path.exists(cat_path):
        with open(cat_path) as f:
            cat = json.load(f)
    by_id = {c["id"]: c for c in cat.get("characters", [])}
    failures = []
    if not a.no_chars:
        import build_character
        specs = appearance.roster(a.count or None)
        only = set(x for x in a.only.split(",") if x)
        for spec in specs:
            if only and spec["id"] not in only:
                continue
            t = time.time()
            try:
                rep = build_character.CharacterBuilder(spec, a.out).build()
            except Exception:
                traceback.print_exc()
                failures.append(spec["id"])
                continue
            by_id[spec["id"]] = catalogue_entry(spec, rep)
            print("built %-22s %-10s tris %6d  %.1f MB  %.1fs" % (spec["id"], spec["role"], rep["tris_total"],
                                                                  rep["bytes"] / 1e6, time.time() - t), flush=True)
            with open(os.path.join(a.out, spec["id"] + ".spec.json"), "w") as f:
                json.dump(spec, f, indent=1)
    cat["characters"] = sorted(by_id.values(), key=lambda c: (c["role"] == "hero", c["id"]))
    if not a.no_anims:
        import retarget
        only = [x for x in a.clips.split(",") if x] or None
        info = retarget.build_library(a.out, only=only)
        print("animations: %d clips" % len(info["clips"]))
    cat["animations"] = {"file": "animations.glb", "json": "animations.json"}
    cat["generator"] = {"version": 1, "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    with open(cat_path, "w") as f:
        json.dump(cat, f, indent=1)
    with open(os.path.join(a.out, "LICENSES.json"), "w") as f:
        json.dump(licences(), f, indent=1)
    print("catalogue: %d characters -> %s" % (len(cat["characters"]), cat_path))
    if failures:
        print("FAILED:", ",".join(failures))
        sys.exit(1)


if __name__ == "__main__":
    main()
