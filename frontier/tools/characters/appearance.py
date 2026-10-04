"""Seeded appearance specs for Frontier humans (pure Python; consumed by build_character.py).

spec = make_spec(seed, role)  ->  dict with body macros, face/body modelling targets, skin, eyes, hair, beard, and an
ordered (inner -> outer) list of 1899 garments with fabrics and tints. The same (seed, role) always yields the same
person. ROSTER lists the town's NPC set (roles cycle so every role is represented) plus the protagonist.
"""
import json
import os
import random
import hashlib

import mhenv

# --- palettes (sRGB 0..1) ------------------------------------------------------------------------------------------
P = {
    "shirt": [(0.83, 0.79, 0.69), (0.88, 0.86, 0.80), (0.56, 0.63, 0.72), (0.62, 0.33, 0.27), (0.62, 0.61, 0.58),
              (0.72, 0.62, 0.44), (0.47, 0.52, 0.42)],
    "trousers": [(0.22, 0.27, 0.40), (0.45, 0.35, 0.22), (0.38, 0.37, 0.35), (0.16, 0.15, 0.14), (0.60, 0.52, 0.38),
                 (0.30, 0.26, 0.21)],
    "vest": [(0.13, 0.12, 0.11), (0.31, 0.21, 0.14), (0.36, 0.35, 0.33), (0.36, 0.13, 0.13), (0.26, 0.24, 0.17),
             (0.20, 0.22, 0.28)],
    "coat": [(0.12, 0.11, 0.10), (0.27, 0.20, 0.14), (0.24, 0.24, 0.24), (0.16, 0.18, 0.26), (0.33, 0.30, 0.22)],
    "duster": [(0.62, 0.54, 0.40), (0.48, 0.40, 0.29), (0.30, 0.27, 0.22), (0.55, 0.50, 0.42)],
    "hat_felt": [(0.36, 0.28, 0.21), (0.13, 0.12, 0.11), (0.68, 0.62, 0.52), (0.42, 0.40, 0.37), (0.48, 0.36, 0.24)],
    "straw": [(0.80, 0.70, 0.48), (0.74, 0.64, 0.44)],
    "boots": [(0.27, 0.17, 0.10), (0.12, 0.10, 0.09), (0.36, 0.24, 0.14), (0.20, 0.14, 0.10)],
    "belt": [(0.22, 0.14, 0.08), (0.12, 0.09, 0.07), (0.33, 0.22, 0.12)],
    "dress": [(0.35, 0.42, 0.58), (0.60, 0.43, 0.43), (0.36, 0.23, 0.31), (0.26, 0.34, 0.26), (0.14, 0.13, 0.13),
              (0.42, 0.31, 0.23), (0.64, 0.55, 0.31), (0.47, 0.50, 0.55)],
    "blouse": [(0.90, 0.88, 0.82), (0.86, 0.80, 0.70), (0.70, 0.74, 0.80)],
    "apron": [(0.90, 0.88, 0.82), (0.80, 0.76, 0.66), (0.62, 0.66, 0.70)],
}
HAIR = {"black": (0.06, 0.05, 0.045), "dark_brown": (0.14, 0.09, 0.06), "brown": (0.25, 0.16, 0.10),
        "light_brown": (0.40, 0.28, 0.17), "auburn": (0.42, 0.18, 0.09), "blond": (0.62, 0.50, 0.32),
        "grey": (0.50, 0.48, 0.45), "white": (0.76, 0.74, 0.71)}

# ethnicity -> MakeHuman race weights, skin family, skin tint, hair colours, eye colours
ETHNIC = {
    "anglo": ({"caucasian": 0.94, "african": 0.03, "asian": 0.03}, "caucasian", (1.0, 1.0, 1.0),
              ["brown", "dark_brown", "light_brown", "blond", "auburn", "black"],
              ["lightblue", "blue", "grey", "green", "brownlight", "bluegreen"]),
    "irish": ({"caucasian": 0.97, "african": 0.015, "asian": 0.015}, "caucasian", (1.02, 0.98, 0.96),
              ["auburn", "brown", "dark_brown", "light_brown"], ["lightblue", "blue", "green", "grey"]),
    "hispano": ({"caucasian": 0.72, "african": 0.08, "asian": 0.2}, "caucasian", (0.86, 0.76, 0.66),
                ["black", "dark_brown"], ["brownlight"]),
    "black": ({"caucasian": 0.12, "african": 0.86, "asian": 0.02}, "african", (1.0, 1.0, 1.0),
              ["black"], ["brownlight"]),
    "chinese": ({"caucasian": 0.03, "african": 0.02, "asian": 0.95}, "asian", (1.0, 1.0, 1.0),
                ["black"], ["brownlight"]),
    "native": ({"caucasian": 0.25, "african": 0.08, "asian": 0.67}, "asian", (0.9, 0.76, 0.64),
               ["black"], ["brownlight"]),
}
ETHNIC_WEIGHTS = [("anglo", 50), ("irish", 14), ("hispano", 14), ("black", 12), ("chinese", 4), ("native", 6)]

ROLES = {
    # role: (sex, age range, weight bias, outfit fn name)
    "rancher": ("male", (20, 55), 0.0, "work_rider"),
    "cowhand": ("male", (17, 35), -0.1, "work_rider"),
    "townsman": ("male", (22, 60), 0.1, "town"),
    "gentleman": ("male", (30, 65), 0.15, "gentleman"),
    "worker": ("male", (18, 50), 0.05, "worker"),
    "drifter": ("male", (22, 50), -0.15, "drifter"),
    "lawman": ("male", (28, 55), 0.0, "work_rider"),
    "elder": ("male", (60, 80), 0.05, "town"),
    "townswoman": ("female", (18, 55), 0.05, "dress"),
    "lady": ("female", (22, 50), 0.0, "lady"),
    "ranchwoman": ("female", (20, 50), 0.0, "ranch_dress"),
    "matron": ("female", (50, 75), 0.15, "dress"),
}

# The town roster: 36 NPCs (seeds 0..35) + the protagonist.
ROSTER_ROLES = (["rancher"] * 5 + ["cowhand"] * 3 + ["townsman"] * 5 + ["gentleman"] * 2 + ["worker"] * 4 +
                ["drifter"] * 2 + ["lawman"] * 1 + ["elder"] * 2 + ["townswoman"] * 5 + ["lady"] * 2 +
                ["ranchwoman"] * 3 + ["matron"] * 2)


def _rng(*key):
    h = hashlib.sha256(("|".join(str(k) for k in key)).encode()).hexdigest()
    return random.Random(int(h[:16], 16))


def _pick_w(r, items):
    tot = sum(w for _, w in items)
    x = r.uniform(0, tot)
    for v, w in items:
        x -= w
        if x <= 0:
            return v
    return items[-1][0]


def age_macro(years):
    if years < 25:
        return 0.1875 + (years - 11) / 14.0 * (0.5 - 0.1875)
    return min(1.0, 0.5 + (years - 25) / 65.0 * 0.5)


_CATS = None


def _categories():
    global _CATS
    if _CATS is None:
        with open(os.path.join(mhenv.MPFB_DATA, "targets", "target.json")) as f:
            _CATS = json.load(f)
    return _CATS


FACE_GROUPS = {"head": 0.35, "nose": 0.45, "mouth": 0.35, "chin": 0.45, "cheek": 0.45, "eyes": 0.3, "ears": 0.4,
               "eyebrows": 0.35, "forehead": 0.35, "neck": 0.25}
BODY_GROUPS = {"torso": 0.2, "hip": 0.2, "stomach": 0.25, "buttocks": 0.25, "arms": 0.15, "legs": 0.15}


def _cat_targets(c, v, out, r=None):
    o = c.get("opposites")
    if o is None:  # single shape target (e.g. head-oval): positive only
        out[c["targets"][0]] = round(abs(v), 3)
        return
    if c["has_left_and_right"]:
        neg = [o.get("negative-left"), o.get("negative-right")]
        pos = [o.get("positive-left"), o.get("positive-right")]
    else:
        neg = [o.get("negative-unsided")]
        pos = [o.get("positive-unsided")]
    if not any(neg):
        v = abs(v)
    names = pos if v > 0 else neg
    for i, n in enumerate(names):
        if n:
            out[n] = round(abs(v) * (1.0 + (r.uniform(-0.08, 0.08) if (i and r) else 0.0)), 3)


def details_from_categories(values):
    """{"cheek-bones-decr-incr": 0.4, "head-oval": 0.3, ...} -> target weights (symmetric)."""
    cats = _categories()
    index = {c["name"]: c for g in cats.values() if isinstance(g, dict) for c in g.get("categories", [])}
    out = {}
    for name, v in values.items():
        _cat_targets(index[name], v, out)
    return out


def random_details(r, strength=1.0, groups=None):
    """Random face/body shape via MakeHuman modelling targets (opposite pairs, symmetric sides)."""
    cats = _categories()
    out = {}
    for gname, sd in (groups or dict(FACE_GROUPS, **BODY_GROUPS)).items():
        for c in cats[gname]["categories"]:
            if r.random() > 0.55:
                continue
            v = max(-1.0, min(1.0, r.gauss(0, sd * strength)))
            if "opposites" not in c:
                if r.random() < 0.5:
                    out[c["targets"][0]] = round(abs(v), 3)
                continue
            _cat_targets(c, v, out, r)
            continue
            if c["has_left_and_right"]:
                neg = [o.get("negative-left"), o.get("negative-right")]
                pos = [o.get("positive-left"), o.get("positive-right")]
            else:
                neg = [o.get("negative-unsided")]
                pos = [o.get("positive-unsided")]
            if not any(neg):
                v = abs(v)
            names = pos if v > 0 else neg
            for i, n in enumerate(names):
                if n:
                    out[n] = round(abs(v) * (1.0 + (r.uniform(-0.08, 0.08) if i else 0.0)), 3)
    return out


def skin_for(family, sex, years):
    band = "young" if years < 36 else ("middleage" if years < 58 else "old")
    name = "%s_%s_%s" % (band, family, sex)
    if not os.path.isdir(os.path.join(mhenv.MH_ASSETS, "skins", name)):
        name = "middleage_%s_%s" % (family, sex)
    return "skins/%s/%s.mhmat" % (name, name)


def _g(gid, typ, fabric, tint, palette=None, **kw):
    d = {"kind": "proc", "type": typ, "id": gid, "fabric": fabric, "tint": [round(x, 3) for x in tint]}
    if palette:
        d["palette"] = [[round(x, 3) for x in p] for p in palette]
    d.update(kw)
    return d


# --- outfits (lists are inner -> outer) -----------------------------------------------------------------------------
def outfit_male(r, kind, years):
    G = []
    rolled = kind in ("worker", "work_rider") and r.random() < 0.4
    G.append(_g("shirt", "shirt", r.choice(["linen", "linen", "canvas"]), r.choice(P["shirt"]), P["shirt"],
                sleeve=1.5 if rolled else 1.95, offset=0.004, seed=r.randrange(999)))
    tall_boots = kind in ("work_rider", "drifter") or (kind == "worker" and r.random() < 0.5)
    tfab = {"work_rider": ["denim", "canvas", "wool"], "drifter": ["canvas", "wool", "denim"],
            "worker": ["denim", "canvas"], "town": ["wool"], "gentleman": ["wool"]}[kind]
    fab = r.choice(tfab)
    tcol = P["trousers"][0] if fab == "denim" else r.choice(P["trousers"][1:])
    G.append(_g("trousers", "trousers", fab, tcol, P["trousers"], hem=1.68 if tall_boots else 1.97, offset=0.007,
                seed=r.randrange(999)))
    vest_p = {"work_rider": 0.6, "drifter": 0.5, "worker": 0.3, "town": 0.85, "gentleman": 1.0}[kind]
    if r.random() < vest_p:
        leather = kind in ("work_rider", "drifter") and r.random() < 0.3
        G.append(_g("vest", "vest", "leather" if leather else "wool",
                    (0.45, 0.33, 0.21) if leather else r.choice(P["vest"]), P["vest"], offset=0.011,
                    material="leather" if leather else "cloth", seed=r.randrange(999)))
    G.append(_g("boots", "boots", "leather", r.choice(P["boots"]), P["boots"], top=1.42 if tall_boots else 1.72,
                offset=0.012, material="leather"))
    G.append(_g("belt", "belt", "leather", r.choice(P["belt"]), material="leather"))
    if kind in ("work_rider", "drifter") and r.random() < 0.6:
        G.append(_g("gunbelt", "belt", "leather", r.choice(P["belt"]), material="leather", style="gun"))
    if kind == "town" and r.random() < 0.55 or kind == "gentleman":
        G.append(_g("coat", "coat", "wool", r.choice(P["coat"]), P["coat"], offset=0.02,
                    below_crotch=0.06 if kind == "town" else 0.1, open=True, seed=r.randrange(999)))
        if kind == "gentleman":
            G.append(_g("coattails", "tails", "wool", G[-1]["tint"], below_knee=0.08, flare=0.03, opening=0.4,
                        ease=0.022))
    if kind == "drifter" or (kind == "work_rider" and r.random() < 0.2):
        col = r.choice(P["duster"])
        G.append(_g("duster", "coat", "canvas", col, P["duster"], offset=0.024, loose=0.025, below_crotch=0.02,
                    open=True, seed=r.randrange(999)))
        G.append(_g("dustertails", "tails", "canvas", col, below_knee=0.22, flare=0.14, opening=0.3, ease=0.035))
    # hat
    styles = {"work_rider": [("cattleman", 5), ("plainsman", 3), ("slouch", 2)], "drifter": [("slouch", 3), ("cattleman", 3)],
              "worker": [("slouch", 3), ("flatcap", 3), ("plainsman", 1), (None, 1)],
              "town": [("bowler", 4), ("plainsman", 2), (None, 2)], "gentleman": [("bowler", 4), ("plainsman", 1)]}[kind]
    st = _pick_w(r, styles)
    if st:
        fab = "wool"
        G.append(_g("hat", "hat", fab, r.choice(P["hat_felt"]), P["hat_felt"], style=st,
                    tilt=r.uniform(2, 7), fabric_mix=0.3))
    return G


def outfit_female(r, kind, years):
    G = []
    if kind == "ranch_dress" and r.random() < 0.6:
        G.append(_g("blouse", "shirt", "linen", r.choice(P["blouse"]), P["blouse"], sleeve=1.6 if r.random() < 0.5 else 1.95,
                    offset=0.005, collar=0.04, smooth_chest=True))
        skirt_fab, skirt_col = r.choice([("canvas", (0.45, 0.38, 0.28)), ("denim", (0.25, 0.3, 0.42)),
                                         ("wool", r.choice(P["dress"]))])
    else:
        col = r.choice(P["dress"])
        G.append(_g("bodice", "bodice", "wool" if kind == "lady" else "linen", col, P["dress"], sleeve=1.95,
                    offset=0.005, collar=0.055, smooth_chest=True))
        skirt_fab, skirt_col = ("wool" if kind == "lady" else "linen"), col
    G.append(_g("boots", "boots", "leather", r.choice(P["boots"][:2]), top=1.7, offset=0.008, material="leather"))
    G.append(_g("skirt", "skirt", skirt_fab, skirt_col, P["dress"], flare=0.22 if kind == "lady" else 0.16,
                ease=0.025, below_ankle=0.0, seed=r.randrange(999)))
    G.append(_g("sash", "belt", "wool", r.choice([(0.12, 0.11, 0.1), (0.3, 0.2, 0.14)]) if r.random() < 0.5 else skirt_col,
                material="cloth", width=0.04, offset=0.032, dz=0.012))
    if kind in ("dress", "ranch_dress") and r.random() < 0.45:
        G.append(_g("apron", "apron", "linen", r.choice(P["apron"]), P["apron"], below_knee=0.12, width=0.95,
                    ease=0.035, flare=0.1))
    if kind == "lady" and r.random() < 0.6:
        G.append(_g("hat", "hat", "canvas", r.choice(P["straw"]), style="boater", tilt=r.uniform(0, 6), fabric_mix=0.6))
    elif kind == "ranch_dress" and r.random() < 0.4:
        G.append(_g("hat", "hat", "wool", r.choice(P["hat_felt"]), style="slouch", tilt=3, fabric_mix=0.3))
    elif kind == "dress" and r.random() < 0.3:
        G.append(_g("hat", "hat", "canvas", r.choice(P["straw"]), style="boater", tilt=3, fabric_mix=0.6))
    return G


def make_spec(seed, role=None, cid=None):
    r = _rng("frontier-npc", seed, role)
    role = role or r.choice(list(ROLES))
    sex, (a0, a1), wbias, kind = ROLES[role]
    years = r.randint(a0, a1)
    eth = _pick_w(r, ETHNIC_WEIGHTS)
    if kind in ("gentleman", "lady") and eth in ("chinese", "native"):
        eth = "anglo"
    race, family, stint, hairs, eyes = ETHNIC[eth]
    male = sex == "male"
    macro = {
        "gender": 1.0 if male else 0.0,
        "age": round(age_macro(years), 3),
        "muscle": round(min(1, max(0, r.gauss(0.6 if male and kind in ("work_rider", "worker") else 0.5, 0.12))), 3),
        "weight": round(min(1, max(0, r.gauss(0.5 + wbias + (0.08 if years > 45 else 0), 0.12))), 3),
        "proportions": round(r.uniform(0.45, 0.8), 3),
        "height": round(min(1, max(0, r.gauss(0.55 if male else 0.45, 0.16))), 3),
        "cupsize": round(r.uniform(0.35, 0.65), 3), "firmness": round(r.uniform(0.35, 0.6), 3),
        "race": race,
    }
    hcol = r.choice(hairs)
    if years > 62:
        hcol = r.choice(["grey", "white"])
    elif years > 48 and r.random() < 0.5:
        hcol = "grey"
    if male:
        hair = r.choice(["short02", "short03", "short01", "short04"]) if eth != "black" else r.choice(["afro01", "short04", "short03"])
        if years > 55 and r.random() < 0.3:
            hair = "short04"
    else:
        hair = r.choice(["braid01", "ponytail01", "long01", "braid01"])
    spec = {
        "id": cid or ("npc_%03d" % seed), "seed": seed, "role": role, "sex": sex, "age": years, "ethnicity": eth,
        "lod": "npc", "macro": macro,
        "details": random_details(r),
        "skin": skin_for(family, sex, years),
        "skin_tint": [round(x * r.uniform(0.96, 1.04), 3) for x in stint],
        "weathering": round(min(1, r.uniform(0.15, 0.4) + (0.3 if kind in ("work_rider", "worker", "drifter", "ranch_dress") else 0)
                                + (years - 30) / 120), 3),
        "eye_color": r.choice(eyes),
        "eyebrows": r.choice(["eyebrow%03d" % i for i in ((1, 2, 4, 5, 6, 7, 8, 9, 10, 11) if male else (3, 5, 7, 9, 10, 12))]),
        "eyelashes": r.choice(["eyelashes01", "eyelashes02"] if male else ["eyelashes03", "eyelashes04"]),
        "hair": hair, "hair_color": list(HAIR[hcol]), "hair_grey": 0.0,
        "clothes": outfit_male(r, kind, years) if male else outfit_female(r, kind, years),
    }
    if male:
        b = _pick_w(r, [("moustache", 30), ("full", 14), ("short", 16), ("chin", 4), ("mutton", 6), (None, 30)])
        spec["stubble"] = round(r.uniform(0.25, 0.8), 2)
        if b and not (eth == "chinese" and b != "chin"):
            spec["clothes"].insert(0, {"kind": "proc", "type": "beard", "id": "beard", "style": b,
                                       "moustache": b not in ("chin",), "length": round(r.uniform(0.006, 0.013), 4)})
    return spec


def ruth_spec(lod="hero", duster=False):
    """Ruth Caddell, 34: former trick-shooter and county deputy; lean, weathered, auburn-brown braid."""
    r = _rng("ruth")
    spec = {
        "id": "ruth_caddell" + ("_duster" if duster else ""), "seed": -1, "role": "hero", "sex": "female", "age": 34,
        "ethnicity": "irish", "lod": lod,
        "macro": {"gender": 0.0, "age": round(age_macro(34), 3), "muscle": 0.68, "weight": 0.33, "proportions": 0.72,
                  "height": 0.62, "cupsize": 0.4, "firmness": 0.55,
                  "race": {"caucasian": 0.96, "african": 0.02, "asian": 0.02}},
        "details": details_from_categories({
            "cheek-bones-decr-incr": 0.45, "cheek-volume-decr-incr": -0.35, "chin-prominent-decr-incr": 0.2,
            "chin-width-decr-incr": 0.1, "nose-hump-decr-incr": 0.2, "nose-scale-horiz-decr-incr": -0.15,
            "eye-bag-decr-incr": 0.25, "mouth-scale-horiz-decr-incr": -0.1, "head-square": 0.2,
            "forehead-temple-decr-incr": -0.2, "eyebrows-angle-down-up": -0.25,
            "torso-vshape-decr-incr": 0.2, "stomach-tone-decr-incr": 0.4}),
        "skin": "skins/young_caucasian_female/young_caucasian_female.mhmat",
        "skin_tint": [0.97, 0.9, 0.84], "weathering": 0.62,
        "eye_color": "grey", "eyebrows": "eyebrow007", "eyelashes": "eyelashes04",
        "hair": "braid01", "hair_color": list((0.33, 0.17, 0.09)),
        "clothes": [
            _g("shirt", "shirt", "linen", (0.80, 0.75, 0.64), sleeve=1.95, offset=0.005, collar=0.035, seed=7,
               smooth_chest=True),
            _g("trousers", "trousers", "canvas", (0.40, 0.32, 0.22), hem=1.68, offset=0.006, seed=8),
            _g("vest", "vest", "leather", (0.30, 0.20, 0.13), offset=0.010, material="leather", v_depth=0.11, seed=9),
            _g("boots", "boots", "leather", (0.24, 0.15, 0.09), top=1.4, offset=0.011, material="leather"),
            _g("belt", "belt", "leather", (0.18, 0.11, 0.07), material="leather"),
            _g("gunbelt", "belt", "leather", (0.28, 0.18, 0.1), material="leather", style="gun"),
            _g("hat", "hat", "wool", (0.27, 0.21, 0.16), style="cattleman", tilt=5, fabric_mix=0.3),
        ],
    }
    if duster:
        spec["clothes"].insert(6, _g("duster", "coat", "canvas", (0.50, 0.42, 0.30), offset=0.024, loose=0.025,
                                     below_crotch=0.02, open=True, seed=11))
        spec["clothes"].insert(7, _g("dustertails", "tails", "canvas", (0.50, 0.42, 0.30), below_knee=0.24, flare=0.14,
                                     opening=0.3, ease=0.035))
    return spec


def roster(count=None):
    specs = [make_spec(i, role) for i, role in enumerate(ROSTER_ROLES[:count] if count else ROSTER_ROLES)]
    specs.append(ruth_spec())
    specs.append(ruth_spec(duster=True))
    return specs


if __name__ == "__main__":
    for s in roster():
        print(s["id"], s["role"], s["sex"], s["age"], s["ethnicity"], s["hair"],
              [g.get("style", g["type"]) for g in s["clothes"]])
