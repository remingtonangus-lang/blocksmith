#!/usr/bin/env python3
"""Compare two .glb files semantically (node/mesh/animation names, accessor counts, max abs difference of the data).
Used to check that a generator refactor still builds the same horse: python3 glb_compare.py a.glb b.glb"""
import json
import struct
import sys

import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    binc = b[off + 8:off + 8 + bl]
    return j, binc


def accessor(j, binc, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    dt = CT[a["componentType"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(binc, dtype=dt, count=a["count"] * n, offset=start)
    return arr.reshape(a["count"], n).astype(np.float64)


def summary(path):
    j, binc = load(path)
    out = {"nodes": sorted(n.get("name", "") for n in j["nodes"]),
           "anims": sorted(a["name"] for a in j.get("animations", []))}
    data = {}
    for m in j["meshes"]:
        for k, p in enumerate(m["primitives"]):
            for attr, ai in p["attributes"].items():
                data["%s/%d/%s" % (m["name"], k, attr)] = accessor(j, binc, ai)
            data["%s/%d/indices" % (m["name"], k)] = accessor(j, binc, p["indices"])
    for a in j.get("animations", []):
        for c, ch in enumerate(a["channels"]):
            node = j["nodes"][ch["target"]["node"]].get("name", "")
            s = a["samplers"][ch["sampler"]]
            data["anim/%s/%s/%s" % (a["name"], node, ch["target"]["path"])] = accessor(j, binc, s["output"])
    return out, data


def main(a, b):
    sa, da = summary(a)
    sb, db = summary(b)
    ok = sa == sb and set(da) == set(db)
    worst = 0.0
    wk = ""
    for k in da:
        if k not in db or da[k].shape != db[k].shape:
            print("DIFF shape", k, da[k].shape, db.get(k, np.zeros(0)).shape)
            ok = False
            continue
        d = float(np.abs(da[k] - db[k]).max()) if da[k].size else 0.0
        if d > worst:
            worst, wk = d, k
    print("names equal: %s, accessors %d, max abs diff %.3g (%s)" % (sa == sb, len(da), worst, wk))
    print("SAME" if ok and worst < 1e-4 else "DIFFERENT")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
