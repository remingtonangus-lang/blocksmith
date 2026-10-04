#!/usr/bin/env python3
"""Frontier horse generator (Blender 5 as a Python module: `pip install bpy`, run `python3 horse_gen.py`).

Builds an original, procedurally modelled stock horse (~15.2 hands, 1.55 m at the withers) and writes
`horse.glb` + `horse_gaits.json` (gait metadata) to the output folder. Fully deterministic: same code, same file.

Pipeline
  1. Anatomy: one table of rest-pose joint landmarks (metres; Blender axes: +X = horse's right, +Y = forward,
     +Z = up, ground at Z = 0) drives both the skeleton and ~150 signed-distance primitives (tapered capsules,
     ellipsoids, hoof cones) blended with smooth unions/subtractions into one body field.
  2. Field -> marching cubes (scikit-image) -> Blender mesh -> decimate (hero ~26k tris, LOD1 ~8k, LOD2 ~2k)
     -> light relax.  Per-vertex data: UV = rest (x, y), UV2 = rest (z, 0) so the coat shader can paint
     markings/patterns in rest space; COLOR = (ambient occlusion, curvature, hoof mask, 1).
  3. Armature (root/body, lumbar, pelvis, 6-bone tail, thorax/withers, 4 neck, head, jaw, ears; per leg
     scapula/humerus/forearm/cannon/pastern/hoof and femur/tibia/cannon/pastern/hoof).  Skin weights come from
     the same primitives (each primitive belongs to one or more bones), softmaxed and Laplacian-smoothed.
  4. Mane, forelock and tail as skinned hair cards with a painted alpha strand texture; eyes; tack (stock
     saddle with horn/cantle/skirts/fenders, wool blanket, cinch, stirrups, bridle, bit, reins, saddlebags,
     bedroll) as separate skinned meshes.
  5. Gaits: footfall phase tables + hoof trajectories + per-joint style curves solved with a small planar IK
     per frame (scipy) -> keyframed in-place cycles (walk 4-beat lateral, trot 2-beat diagonal, canter 3-beat,
     gallop 4-beat transverse) with spine/neck/head/tail motion, plus idles and one-shot actions.

Usage: python3 horse_gen.py [--out DIR] [--quick] [--preview] [--no-anim]
"""
import json
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTIER = os.path.abspath(os.path.join(HERE, "..", ".."))
ARGS = sys.argv[1:]


def _arg(name, default=None):
    if name in ARGS:
        i = ARGS.index(name)
        if i + 1 < len(ARGS) and not ARGS[i + 1].startswith("--"):
            return ARGS[i + 1]
        return True
    return default


OUT = os.path.abspath(_arg("--out", os.path.join(FRONTIER, "assets", "animals_out")))
QUICK = bool(_arg("--quick", False))
PREVIEW = bool(_arg("--preview", False))
NO_ANIM = bool(_arg("--no-anim", False))
VOXEL = 0.0105 if QUICK else 0.0062
T0 = time.time()


def log(*a):
    print("[horse %6.1fs]" % (time.time() - T0), *a, flush=True)


# =====================================================================================================
# 1. Anatomy: landmarks (left side, x < 0; mirrored to the right).  (x, y, z) metres.
# =====================================================================================================
def V(*a):
    return np.array(a, dtype=np.float64)


J = {
    # trunk / spine (vertebral column, inside the body)
    "body": V(0, -0.10, 1.27), "body_t": V(0, 0.16, 1.28),
    "lumbar_t": V(0, -0.42, 1.35),
    "pelvis_t": V(0, -0.80, 1.36),
    "thorax_t": V(0, 0.46, 1.33),
    "withers_t": V(0, 0.74, 1.30),
    "neck1_t": V(0, 0.88, 1.43), "neck2_t": V(0, 1.00, 1.57), "neck3_t": V(0, 1.10, 1.72), "neck4_t": V(0, 1.155, 1.86),
    "head_t": V(0, 1.46, 1.475),
    "jaw": V(0, 1.16, 1.76), "jaw_t": V(0, 1.43, 1.42),
    "ear": V(-0.056, 1.11, 1.965), "ear_t": V(-0.082, 1.145, 2.115),
    "tail0": V(0, -0.80, 1.40), "tail1": V(0, -0.875, 1.335), "tail2": V(0, -0.925, 1.245), "tail3": V(0, -0.955, 1.15),
    "tail4": V(0, -0.972, 1.055), "tail5": V(0, -0.982, 0.965), "tail6": V(0, -0.988, 0.88),
    # fore leg (left)
    "scap": V(-0.115, 0.42, 1.43), "shoulder": V(-0.165, 0.705, 1.125), "elbow": V(-0.17, 0.47, 0.885),
    "knee": V(-0.142, 0.49, 0.50), "ffet": V(-0.135, 0.495, 0.165), "fcoffin": V(-0.135, 0.565, 0.058),
    "fsole": V(-0.135, 0.575, 0.0), "ftoe": V(-0.135, 0.64, 0.0),
    # hind leg (left)
    "hip": V(-0.20, -0.62, 1.28), "stifle": V(-0.205, -0.40, 0.985), "hock": V(-0.145, -0.755, 0.56),
    "hfet": V(-0.135, -0.74, 0.17), "hcoffin": V(-0.135, -0.685, 0.058),
    "hsole": V(-0.135, -0.678, 0.0), "htoe": V(-0.135, -0.615, 0.0),
}

# Bones: name -> (head, tail, parent, deform). Left legs listed; mirrored with _R.
BONES = [
    ("root", V(0, 0, 0), V(0, 0.4, 0), None),
    ("body", J["body"], J["body_t"], "root"),
    ("spine_lumbar", J["body"] + V(0, 0, 0.02), J["lumbar_t"], "body"),
    ("pelvis", J["lumbar_t"], J["pelvis_t"], "spine_lumbar"),
    ("tail_1", J["tail0"], J["tail1"], "pelvis"),
    ("tail_2", J["tail1"], J["tail2"], "tail_1"),
    ("tail_3", J["tail2"], J["tail3"], "tail_2"),
    ("tail_4", J["tail3"], J["tail4"], "tail_3"),
    ("tail_5", J["tail4"], J["tail5"], "tail_4"),
    ("tail_6", J["tail5"], J["tail6"], "tail_5"),
    ("spine_thorax", J["body_t"], J["thorax_t"], "body"),
    ("spine_withers", J["thorax_t"], J["withers_t"], "spine_thorax"),
    ("neck_1", J["withers_t"], J["neck1_t"], "spine_withers"),
    ("neck_2", J["neck1_t"], J["neck2_t"], "neck_1"),
    ("neck_3", J["neck2_t"], J["neck3_t"], "neck_2"),
    ("neck_4", J["neck3_t"], J["neck4_t"], "neck_3"),
    ("head", J["neck4_t"], J["head_t"], "neck_4"),
    ("jaw", J["jaw"], J["jaw_t"], "head"),
    ("ear_L", J["ear"], J["ear_t"], "head"),
    ("scapula_L", J["scap"], J["shoulder"], "spine_withers"),
    ("humerus_L", J["shoulder"], J["elbow"], "scapula_L"),
    ("forearm_L", J["elbow"], J["knee"], "humerus_L"),
    ("fcannon_L", J["knee"], J["ffet"], "forearm_L"),
    ("fpastern_L", J["ffet"], J["fcoffin"], "fcannon_L"),
    ("fhoof_L", J["fcoffin"], J["ftoe"] + V(0, 0, 0.0), "fpastern_L"),
    ("femur_L", J["hip"], J["stifle"], "pelvis"),
    ("tibia_L", J["stifle"], J["hock"], "femur_L"),
    ("hcannon_L", J["hock"], J["hfet"], "tibia_L"),
    ("hpastern_L", J["hfet"], J["hcoffin"], "hcannon_L"),
    ("hhoof_L", J["hcoffin"], J["htoe"], "hpastern_L"),
]


def mirror_name(n):
    if n is None:
        return None
    if n.endswith("_L"):
        return n[:-2] + "_R"
    if n.endswith("_R"):
        return n[:-2] + "_L"
    return n


def mx(p):
    return V(-p[0], p[1], p[2])


def all_bones():
    out = []
    for n, h, t, par in BONES:
        out.append((n, h, t, par))
        if n.endswith("_L"):
            out.append((mirror_name(n), mx(h), mx(t), mirror_name(par)))
    return out


# =====================================================================================================
# 2. Signed-distance primitives
# =====================================================================================================
class Prim:
    """kind: 'rc' tapered capsule a->b (ra, rb), 'ell' ellipsoid (c, radii, axis), 'hoof'.
    op: 'u' smooth union, 's' smooth subtract, 'i' smooth intersect.  bones: weight candidates."""

    def __init__(self, kind, op, k, bones, mirror, **kw):
        self.kind, self.op, self.k, self.bones, self.mirror = kind, op, k, bones, mirror
        self.kw = kw

    def mirrored(self):
        kw = dict(self.kw)
        for key in ("a", "b", "c", "axis", "side"):
            if key in kw and kw[key] is not None:
                kw[key] = mx(kw[key])
        if "pts" in kw:
            kw["pts"] = kw["pts"] * V(-1, 1, 1)
        return Prim(self.kind, self.op, self.k, [mirror_name(b) for b in self.bones], False, **kw)


PRIMS = []


def frame_from_axis(axis, side=None):
    """Orthonormal frame: local Y along `axis`, local X as close as possible to `side` (default world X)."""
    y = np.asarray(axis, float)
    y = y / np.linalg.norm(y)
    s = V(1, 0, 0) if side is None else np.asarray(side, float)
    x = s - np.dot(s, y) * y
    if np.linalg.norm(x) < 1e-6:
        x = V(0, 0, 1) - y[2] * y
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z])          # rows: local axes in world coords


def rc(a, b, ra, rb, bones, k=0.03, op="u", mirror=True, sx=1.0, side=None):
    PRIMS.append(Prim("rc", op, k, bones if isinstance(bones, list) else [bones], mirror,
                      a=V(*a), b=V(*b), ra=ra, rb=rb, sx=sx, side=None if side is None else V(*side)))


def ell(c, r, bones, k=0.03, op="u", mirror=True, axis=(0, 1, 0), side=None):
    PRIMS.append(Prim("ell", op, k, bones if isinstance(bones, list) else [bones], mirror,
                      c=V(*c), r=V(*r), axis=V(*axis), side=None if side is None else V(*side)))


def hoof(c, rtop, rbot, h, tilt, bones, k=0.006, mirror=True, length=1.08):
    PRIMS.append(Prim("hoof", "u", k, [bones], mirror, c=V(*c), rtop=rtop, rbot=rbot, h=h, tilt=tilt, length=length))


def P(name):
    return tuple(J[name])


TRUNK = ["spine_lumbar", "body", "spine_thorax", "spine_withers"]
HIND_TRUNK = ["pelvis", "spine_lumbar"]
NECK = ["spine_withers", "neck_1", "neck_2", "neck_3", "neck_4"]


def loft(stations, bones, k=0.05, op="u", mirror=False, sub=6):
    """Generalised cylinder: stations = [(center xyz, half width a, half height b, n_top, n_bot, pinch_top)].
    The path is Catmull-Rom subdivided; cross-sections are superellipses perpendicular to the path, x' = world X."""
    st = [(V(*s[0]), s[1], s[2], s[3], s[4], s[5] if len(s) > 5 else 0.0) for s in stations]
    cs = [s[0] for s in st]
    params = np.array([[s[1], s[2], s[3], s[4], s[5]] for s in st])
    pts, prm = [], []
    n = len(cs)
    for i in range(n - 1):
        p0 = cs[max(i - 1, 0)]
        p1, p2 = cs[i], cs[i + 1]
        p3 = cs[min(i + 2, n - 1)]
        for j in range(sub):
            t = j / sub
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            s = t * t * (3 - 2 * t)
            pts.append(p)
            prm.append(params[i] * (1 - s) + params[i + 1] * s)
    pts.append(cs[-1])
    prm.append(params[-1])
    PRIMS.append(Prim("loft", op, k, bones if isinstance(bones, list) else [bones], mirror,
                      pts=np.array(pts), prm=np.array(prm)))


def build_prims():
    PRIMS.clear()
    # ---------------- trunk: side profile (top line / under line) and half widths, buttock -> chest
    T = [  # y, top z, bottom z, half width, n_top, n_bot, top pinch
        (-0.90, 1.33, 1.17, 0.07, 2.2, 2.2, 0.0),
        (-0.84, 1.42, 1.11, 0.15, 2.4, 2.2, 0.1),
        (-0.72, 1.495, 1.06, 0.22, 3.0, 2.3, 0.12),
        (-0.56, 1.535, 1.01, 0.25, 3.4, 2.3, 0.15),
        (-0.40, 1.505, 0.90, 0.27, 3.2, 2.2, 0.15),
        (-0.20, 1.48, 0.81, 0.29, 2.8, 2.1, 0.15),
        (0.02, 1.47, 0.775, 0.305, 2.6, 2.1, 0.15),
        (0.24, 1.495, 0.78, 0.285, 2.5, 2.1, 0.25),
        (0.42, 1.52, 0.80, 0.245, 2.4, 2.1, 0.4),
        (0.60, 1.47, 0.88, 0.215, 2.4, 2.2, 0.45),
        (0.74, 1.36, 0.99, 0.18, 2.3, 2.3, 0.3),
        (0.82, 1.24, 1.04, 0.13, 2.2, 2.2, 0.2),
        (0.87, 1.19, 1.07, 0.07, 2.0, 2.0, 0.0),
    ]
    stations = [((0, y, 0.5 * (t + b)), hw, 0.5 * (t - b), nt, nb, pt) for (y, t, b, hw, nt, nb, pt) in T]
    loft(stations, ["pelvis", "spine_lumbar", "body", "spine_thorax", "spine_withers"], k=0.05)
    rc((0, 0.62, 1.545), (0, 0.22, 1.505), 0.045, 0.05, ["spine_withers", "spine_thorax"], k=0.08, mirror=False, sx=1.3)  # withers ridge
    # ---------------- neck: crest / throat profile, half widths, withers -> poll
    N = [  # crest (y, z), under (y, z), half width
        ((0.50, 1.56), (0.75, 1.12), 0.185),
        ((0.64, 1.61), (0.86, 1.27), 0.15),
        ((0.78, 1.69), (0.95, 1.40), 0.125),
        ((0.91, 1.79), (1.04, 1.49), 0.115),
        ((1.01, 1.885), (1.03, 1.60), 0.10),
        ((1.09, 1.955), (1.065, 1.715), 0.094),
    ]
    stations = []
    for (cy, cz), (uy, uz), hw in N:
        c = (0, 0.5 * (cy + uy), 0.5 * (cz + uz))
        half = 0.5 * math.hypot(cy - uy, cz - uz)
        stations.append((c, hw, half, 2.3, 2.2, 0.45))
    loft(stations, NECK, k=0.08)
    ell((-0.07, 0.82, 1.36), (0.06, 0.20, 0.16), NECK, k=0.1, axis=(0, 0.72, 0.69))                # brachiocephalic
    # ---------------- head: lofted along the face line from the poll to the nose (dorsal line + depth)
    Pp, Np = V(0, 1.115, 1.985), V(0, 1.50, 1.50)
    fd = (Np - Pp) / np.linalg.norm(Np - Pp)
    zp = V(0, -fd[2], fd[1])                        # perpendicular to the face, pointing dorsal
    L = np.linalg.norm(Np - Pp)
    HU = [  # u along the face, depth below the face line, half width, n_top, n_bot
        (-0.02, 0.18, 0.085, 2.2, 2.0),
        (0.08, 0.25, 0.098, 2.4, 2.1),
        (0.24, 0.255, 0.106, 2.6, 2.1),
        (0.40, 0.215, 0.094, 2.6, 2.2),
        (0.56, 0.185, 0.074, 2.7, 2.2),
        (0.72, 0.168, 0.063, 2.6, 2.2),
        (0.86, 0.160, 0.058, 2.4, 2.2),
        (0.95, 0.142, 0.060, 2.2, 2.2),
        (1.00, 0.10, 0.048, 2.0, 2.0),
    ]
    loft([(tuple(Pp + fd * u * L - zp * d * 0.5), hw, d * 0.5, nt, nb, 0.08) for u, d, hw, nt, nb in HU], ["head"], k=0.03)
    ell((-0.056, 1.14, 1.765), (0.05, 0.115, 0.105), ["head", "jaw"], k=0.05, axis=(0, 0.75, -0.66))   # jowl / masseter
    rc((0, 1.115, 1.73), (0, 1.425, 1.445), 0.05, 0.034, ["jaw", "head"], k=0.05, mirror=False, sx=1.55)  # mandible
    ell((0, 1.445, 1.418), (0.04, 0.055, 0.027), ["jaw"], k=0.025, mirror=False, axis=(0, 1, -0.25))   # lower lip
    ell((0, 1.415, 1.418), (0.032, 0.038, 0.03), ["jaw"], k=0.025, mirror=False)                       # chin
    ell((-0.041, 1.468, 1.508), (0.021, 0.03, 0.026), ["head"], k=0.02, axis=tuple(fd))                 # nostril flare
    ell((-0.045, 1.48, 1.51), (0.009, 0.022, 0.012), ["head"], k=0.008, op="s", axis=tuple(fd), side=(1, 0.0, -0.4))  # nostril
    rc((-0.032, 1.395, 1.452), (-0.012, 1.485, 1.442), 0.0055, 0.004, ["head"], k=0.006, op="s")      # mouth line
    ell((-0.086, 1.185, 1.848), (0.024, 0.05, 0.02), ["head"], k=0.025, axis=(0, 0.85, -0.2))           # orbit ridge
    ell((-0.099, 1.205, 1.815), (0.021, 0.023, 0.021), ["head"], k=0.008, op="s")                       # eye socket
    ear_a, ear_b = V(-0.056, 1.11, 1.965), V(-0.082, 1.145, 2.115)
    ax = ear_b - ear_a
    rc(tuple(ear_a - ax * 0.15), tuple(ear_a + ax * 0.45), 0.024, 0.026, ["ear_L"], k=0.025, sx=1.25)
    rc(tuple(ear_a + ax * 0.45), tuple(ear_b), 0.026, 0.004, ["ear_L"], k=0.02, sx=1.25)
    rc(tuple(ear_a + ax * 0.25 + V(0, 0.018, 0)), tuple(ear_b + V(0, 0.006, -0.01)), 0.016, 0.002, ["ear_L"], k=0.008,
       op="s", sx=1.25)
    # ---------------- hindquarters (thigh lofted top -> gaskin, cross-section: x' = width, z' = front/back depth)
    TH = [  # center (x, y, z), half width, half depth
        ((-0.135, -0.62, 1.32), 0.10, 0.24),
        ((-0.155, -0.62, 1.16), 0.118, 0.245),
        ((-0.165, -0.63, 1.02), 0.112, 0.21),
        ((-0.16, -0.66, 0.90), 0.088, 0.15),
        ((-0.155, -0.70, 0.77), 0.062, 0.10),
    ]
    loft([(c, a, b, 2.2, 2.2, 0.0) for c, a, b in TH], ["femur_L", "pelvis", "tibia_L"], k=0.07, mirror=True)
    ell((-0.115, -0.53, 1.40), (0.12, 0.27, 0.13), ["pelvis"], k=0.08, axis=(0, 1, 0.12))            # gluteals
    ell((-0.205, -0.38, 1.40), (0.04, 0.06, 0.045), ["pelvis"], k=0.07)                               # point of hip
    ell((-0.20, -0.42, 1.04), (0.06, 0.13, 0.10), ["femur_L"], k=0.08, axis=(0, 0.45, -1))           # quadriceps / stifle
    rc((-0.165, -0.55, 0.90), (-0.152, -0.71, 0.66), 0.07, 0.046, ["tibia_L"], k=0.06)              # gaskin
    rc((-0.148, -0.785, 0.80), (-0.145, -0.805, 0.625), 0.03, 0.024, ["tibia_L"], k=0.04, sx=0.75)  # hamstring tendon
    ell((-0.145, -0.755, 0.56), (0.046, 0.064, 0.066), ["tibia_L", "hcannon_L"], k=0.03)            # hock
    ell((-0.145, -0.806, 0.612), (0.024, 0.032, 0.032), ["tibia_L"], k=0.025)                        # point of hock
    rc((-0.145, -0.74, 0.53), (-0.137, -0.735, 0.19), 0.028, 0.027, ["hcannon_L"], k=0.02, sx=0.92)  # hind cannon bone
    rc((-0.142, -0.772, 0.50), (-0.136, -0.768, 0.20), 0.019, 0.021, ["hcannon_L"], k=0.02, sx=0.8)  # flexor tendons
    ell((-0.135, -0.745, 0.165), (0.040, 0.047, 0.044), ["hcannon_L", "hpastern_L"], k=0.018)        # hind fetlock
    ell((-0.135, -0.785, 0.145), (0.017, 0.02, 0.017), ["hpastern_L"], k=0.012)                      # ergot
    rc((-0.135, -0.735, 0.155), (-0.135, -0.69, 0.07), 0.033, 0.037, ["hpastern_L"], k=0.015)        # hind pastern
    hoof((-0.135, -0.680, 0.0), 0.040, 0.057, 0.072, 0.30, "hhoof_L", length=1.12)
    # ---------------- shoulder / foreleg
    ell((-0.17, 0.56, 1.28), (0.05, 0.20, 0.11), ["scapula_L", "spine_withers"], k=0.1, axis=(0, 0.55, -0.85))  # scapular muscles
    ell((-0.165, 0.50, 1.04), (0.075, 0.13, 0.13), ["humerus_L", "scapula_L"], k=0.09, axis=(0, 1, -0.4))  # triceps
    ell((-0.155, 0.77, 1.12), (0.06, 0.065, 0.07), ["scapula_L", "humerus_L"], k=0.07)                 # point of shoulder
    rc((-0.16, 0.70, 1.12), (-0.165, 0.50, 0.90), 0.065, 0.058, ["humerus_L"], k=0.07)               # upper arm
    ell((-0.08, 0.745, 1.0), (0.085, 0.15, 0.08), ["spine_withers", "humerus_L"], k=0.07, axis=(0, 0.35, -1))  # pectorals
    rc((-0.165, 0.45, 0.91), (-0.163, 0.455, 0.87), 0.048, 0.044, ["forearm_L", "humerus_L"], k=0.05)  # point of elbow
    rc((-0.158, 0.485, 0.85), (-0.145, 0.49, 0.56), 0.066, 0.04, ["forearm_L"], k=0.04, sx=0.88)     # forearm
    rc((-0.16, 0.515, 0.82), (-0.148, 0.505, 0.62), 0.042, 0.027, ["forearm_L"], k=0.04)             # extensor bulge
    ell((-0.142, 0.495, 0.50), (0.047, 0.042, 0.06), ["forearm_L", "fcannon_L"], k=0.02)            # knee
    ell((-0.142, 0.456, 0.515), (0.021, 0.028, 0.03), ["fcannon_L"], k=0.015)                        # accessory carpal
    rc((-0.14, 0.505, 0.47), (-0.136, 0.505, 0.19), 0.027, 0.026, ["fcannon_L"], k=0.018, sx=0.92)  # fore cannon bone
    rc((-0.139, 0.471, 0.45), (-0.136, 0.469, 0.20), 0.018, 0.02, ["fcannon_L"], k=0.018, sx=0.8)   # flexor tendons
    ell((-0.135, 0.495, 0.162), (0.042, 0.048, 0.045), ["fcannon_L", "fpastern_L"], k=0.018)        # fore fetlock
    ell((-0.135, 0.455, 0.14), (0.017, 0.02, 0.017), ["fpastern_L"], k=0.012)                        # ergot
    rc((-0.135, 0.505, 0.15), (-0.135, 0.56, 0.07), 0.034, 0.038, ["fpastern_L"], k=0.015)          # fore pastern
    hoof((-0.135, 0.575, 0.0), 0.043, 0.064, 0.077, 0.38, "fhoof_L", length=1.05)
    # ---------------- tail dock
    pts = [J["tail%d" % i] for i in range(7)]
    radii = [0.055, 0.048, 0.042, 0.037, 0.033, 0.029, 0.024]
    for i in range(6):
        rc(tuple(pts[i]), tuple(pts[i + 1]), radii[i], radii[i + 1], ["tail_%d" % (i + 1)], k=0.03, mirror=False)
    out = []
    for p in PRIMS:
        out.append(p)
        if p.mirror:
            out.append(p.mirrored())
    return out


# -------- distance functions (numpy, vectorised on (N,3) arrays)
def d_rc(p, a, b, ra, rb, sx=1.0, side=None):
    ba = b - a
    L = np.linalg.norm(ba)
    if sx != 1.0:
        R = frame_from_axis(ba, side)
        q = (p - a) @ R.T
        q[:, 0] /= sx
        t = np.clip(q[:, 1] / L, 0.0, 1.0)
        r = ra + (rb - ra) * t
        q[:, 1] -= t * L
        return (np.linalg.norm(q, axis=1) - r) * min(1.0, sx)
    pa = p - a
    t = np.clip(pa @ ba / (L * L), 0.0, 1.0)
    r = ra + (rb - ra) * t
    return np.linalg.norm(pa - np.outer(t, ba), axis=1) - r


def d_ell(p, c, r, axis, side=None):
    R = frame_from_axis(axis, side)
    q = (p - c) @ R.T
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def d_hoof(p, c, rtop, rbot, h, tilt, length):
    """Hoof capsule: sloped front wall, steeper heels, flat sole at z=0 (c is the sole centre)."""
    q = p - c
    # shear forward with height so the dorsal wall slopes (toe angle ~52 deg), heels more upright
    z = q[:, 2]
    y = q[:, 1] + z * tilt
    x = q[:, 0]
    t = np.clip(z / h, 0.0, 1.0)
    r = rbot + (rtop - rbot) * t
    rr = np.sqrt(x * x + (y / length) ** 2) - r
    d_side = rr * 0.92
    d_top = z - h
    d_bot = -z
    d = np.maximum(d_side, np.maximum(d_top, d_bot))
    out = np.minimum(np.maximum(d_side, np.maximum(d_top, d_bot)), 0.0) + np.sqrt(
        np.maximum(d_side, 0) ** 2 + np.maximum(d_top, 0) ** 2 + np.maximum(d_bot, 0) ** 2)
    return np.where(d < 0, d, out)


def d_loft(p, pts, prm):
    A, B = pts[:-1], pts[1:]
    AB = B - A
    L2 = np.maximum((AB * AB).sum(1), 1e-12)
    out = np.empty(len(p))
    S = len(A)
    for c0 in range(0, len(p), 150000):
        q = p[c0:c0 + 150000]
        PA = q[:, None, :] - A[None, :, :]
        traw = (PA * AB[None]).sum(2) / L2[None]
        t = np.clip(traw, 0.0, 1.0)
        D = PA - t[..., None] * AB[None]
        d2 = (D * D).sum(2)
        s = np.argmin(d2, axis=1)
        idx = np.arange(len(q))
        ts, tr = t[idx, s], traw[idx, s]
        dv = D[idx, s]
        ab = AB[s]
        L = np.sqrt(L2[s])
        yv = ab / L[:, None]
        xv = np.array([1.0, 0.0, 0.0])[None, :] - yv[:, 0:1] * yv
        xv /= np.linalg.norm(xv, axis=1, keepdims=True)
        zv = np.cross(xv, yv)
        qx = (dv * xv).sum(1)
        qz = (dv * zv).sum(1)
        pr = prm[s] * (1 - ts)[:, None] + prm[s + 1] * ts[:, None]
        a, b, nt, nb, pinch = pr[:, 0], pr[:, 1], pr[:, 2], pr[:, 3], pr[:, 4]
        a = a * (1.0 - pinch * np.clip(qz / b, 0.0, 1.0) ** 2)
        n = np.where(qz > 0, nt, nb)
        f = (np.abs(qx / a) ** n + np.abs(qz / b) ** n) ** (1.0 / n)
        r = np.sqrt(qx * qx + qz * qz)
        dc = (f - 1.0) * r / np.maximum(f, 1e-6)
        ax = np.where(s == 0, -tr * L, np.where(s == S - 1, (tr - 1.0) * L, -1.0))
        ax = np.where((s == 0) & (tr >= 0), -1.0, ax)
        ax = np.where((s == S - 1) & (tr <= 1), np.where(s == 0, ax, -1.0), ax)
        cap = np.sqrt(np.maximum(dc, 0) ** 2 + np.maximum(ax, 0) ** 2) + np.minimum(np.maximum(dc, ax), 0)
        out[c0:c0 + 150000] = np.where(ax > 0, cap, dc)
    return out


def prim_dist(pr, p):
    kw = pr.kw
    if pr.kind == "loft":
        return d_loft(p, kw["pts"], kw["prm"])
    if pr.kind == "rc":
        return d_rc(p, kw["a"], kw["b"], kw["ra"], kw["rb"], kw.get("sx", 1.0), kw.get("side"))
    if pr.kind == "ell":
        return d_ell(p, kw["c"], kw["r"], kw["axis"], kw.get("side"))
    return d_hoof(p, kw["c"], kw["rtop"], kw["rbot"], kw["h"], kw["tilt"], kw["length"])


def prim_bbox(pr, pad):
    kw = pr.kw
    if pr.kind == "loft":
        r = kw["prm"][:, :2].max()
        return kw["pts"].min(0) - r - pad, kw["pts"].max(0) + r + pad
    if pr.kind == "rc":
        r = max(kw["ra"], kw["rb"])
        lo = np.minimum(kw["a"], kw["b"]) - r
        hi = np.maximum(kw["a"], kw["b"]) + r
    elif pr.kind == "ell":
        r = kw["r"].max()
        lo, hi = kw["c"] - r, kw["c"] + r
    else:
        r = kw["rbot"] * kw["length"] + kw["h"] * kw["tilt"]
        lo = kw["c"] - V(r, r, 0.01)
        hi = kw["c"] + V(r, r, kw["h"] + 0.01)
    return lo - pad, hi + pad


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def eval_field(prims, lo, hi, vox):
    n = np.ceil((hi - lo) / vox).astype(int) + 1
    field = np.full(tuple(n), 1.0, dtype=np.float32)
    xs = [lo[i] + np.arange(n[i]) * vox for i in range(3)]
    for pr in prims:
        a, b = prim_bbox(pr, pr.k * 2.0 + 0.02)
        i0 = np.clip(np.floor((a - lo) / vox).astype(int), 0, n - 1)
        i1 = np.clip(np.ceil((b - lo) / vox).astype(int) + 1, 1, n)
        sl = tuple(slice(i0[i], i1[i]) for i in range(3))
        gx, gy, gz = np.meshgrid(xs[0][sl[0]], xs[1][sl[1]], xs[2][sl[2]], indexing="ij")
        pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
        d = prim_dist(pr, pts).reshape(gx.shape).astype(np.float32)
        cur = field[sl]
        if pr.op == "u":
            field[sl] = smin(cur, d, pr.k)
        elif pr.op == "s":
            field[sl] = smax(cur, -d, pr.k)
        else:
            field[sl] = smax(cur, d, pr.k)
    return field, xs


def field_to_mesh(field, lo, vox):
    from skimage import measure
    verts, faces, _n, _v = measure.marching_cubes(field, level=0.0, spacing=(vox, vox, vox), allow_degenerate=False)
    verts = verts + lo
    return verts, faces


def eval_points(prims, pts):
    """Exact (non-gridded) field at points (for tack conforming and weights)."""
    d = np.full(len(pts), 1.0)
    for pr in prims:
        di = prim_dist(pr, pts)
        if pr.op == "u":
            d = smin(d, di, pr.k)
        elif pr.op == "s":
            d = smax(d, -di, pr.k)
        else:
            d = smax(d, di, pr.k)
    return d


# =====================================================================================================
# Blender helpers
# =====================================================================================================
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, Matrix, Quaternion  # noqa: E402


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.armatures, bpy.data.actions,
              bpy.data.images, bpy.data.curves):
        for item in list(c):
            c.remove(item)


def make_mesh(name, verts, faces, link=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in verts], [], [tuple(map(int, f)) for f in faces])
    me.validate(clean_customdata=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    if link:
        bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_modifier(ob, mod):
    activate(ob)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def decimate_to(ob, tris):
    n = len(ob.data.polygons)
    if n <= tris:
        return
    m = ob.modifiers.new("dec", "DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = tris / n
    m.use_collapse_triangulate = True
    apply_modifier(ob, m)


def shade_smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def mesh_arrays(ob):
    me = ob.data
    v = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", v)
    f = np.zeros(len(me.polygons) * 3, dtype=np.int64)
    me.polygons.foreach_get("vertices", f)
    return v.reshape(-1, 3), f.reshape(-1, 3)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# =====================================================================================================
# Preview renders (Cycles, CPU) for quick anatomy iteration
# =====================================================================================================
PV = {
    "side": ((-6.5, 0.28, 1.1), (0, 0.28, 1.08), 36),
    "right": ((6.5, 0.28, 1.1), (0, 0.28, 1.08), 36),
    "front34": ((-3.4, 4.4, 1.7), (0, 0.25, 1.05), 36),
    "rear34": ((-3.4, -4.4, 1.8), (0, 0.0, 1.0), 36),
    "head": ((-1.25, 2.05, 1.85), (0, 1.33, 1.70), 30),
    "front": ((0, 5.2, 1.3), (0, 0.4, 1.05), 32),
    "rear": ((0, -4.6, 1.2), (0, -0.4, 1.0), 30),
    "top": ((0, 0.28, 7.5), (0, 0.28, 0.9), 34),
    "legs": ((-2.6, 0.0, 0.55), (0, 0.0, 0.45), 34),
    "headside": ((-1.7, 1.25, 1.72), (0, 1.25, 1.70), 34),
}


def preview_render(path_prefix, views=("side", "front34", "rear34", "head", "front", "top"), res=(640, 400)):
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = res
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.6, 0.68, 1)
    bg.inputs[1].default_value = 0.6
    if "psun" not in bpy.data.objects:
        sun = bpy.data.objects.new("psun", bpy.data.lights.new("psun", "SUN"))
        sun.data.energy = 3.5
        sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
        sc.collection.objects.link(sun)
        gp = make_mesh("pground", [(-6, -6, 0), (6, -6, 0), (6, 6, 0), (-6, 6, 0)], [(0, 1, 2, 3)])
        gm = bpy.data.materials.new("pground")
        gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.32, 0.28, 1)
        gp.data.materials.append(gm)
    cam = bpy.data.objects.get("pcam")
    if cam is None:
        cam = bpy.data.objects.new("pcam", bpy.data.cameras.new("pcam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    out = []
    for v in views:
        loc, tgt, fov = PV[v]
        cam.location = loc
        d = Vector(tgt) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam.data.angle = math.radians(fov)
        sc.render.filepath = "%s_%s.png" % (path_prefix, v)
        bpy.ops.render.render(write_still=True)
        out.append(sc.render.filepath)
    return out


def preview_cleanup():
    for n in ("psun", "pground", "pcam"):
        ob = bpy.data.objects.get(n)
        if ob is not None:
            bpy.data.objects.remove(ob)


def ortho_sheet(field, lo, vox, out):
    """Orthographic silhouettes (side / front / top) with a 10 cm grid, for checking proportions."""
    from PIL import Image, ImageDraw
    os.makedirs(os.path.dirname(out), exist_ok=True)
    inside = field < 0
    side = inside.any(axis=0).T[::-1]          # rows z (top first), cols y
    front = inside.any(axis=1).T[::-1]         # rows z, cols x
    top = inside.any(axis=2).T[::-1]           # rows y (front first), cols x
    def depth_shade(mask, d):
        img = np.zeros(mask.shape + (3,), np.uint8) + 235
        img[mask] = (120, 80, 50)
        return img
    ims = [depth_shade(side, 0)[:, ::-1], depth_shade(front, 1), depth_shade(top, 2)]
    scale = 2
    W = sum(i.shape[1] for i in ims) * scale + 40
    H = max(i.shape[0] for i in ims) * scale
    sheet = Image.new("RGB", (W, H), (255, 255, 255))
    x0 = 0
    for k, im in enumerate(ims):
        pim = Image.fromarray(im).resize((im.shape[1] * scale, im.shape[0] * scale), Image.NEAREST)
        dr = ImageDraw.Draw(pim)
        step = 0.1 / vox * scale
        for gx in np.arange(0, pim.size[0], step):
            dr.line([(gx, 0), (gx, pim.size[1])], fill=(170, 190, 255) if int(round(gx / step)) % 5 else (60, 90, 255))
        for gy in np.arange(pim.size[1], 0, -step):
            dr.line([(0, gy), (pim.size[0], gy)], fill=(170, 190, 255) if int(round((pim.size[1] - gy) / step)) % 5 else (60, 90, 255))
        sheet.paste(pim, (x0, H - pim.size[1]))
        x0 += pim.size[0] + 20
    sheet.save(out)
    return out


def contact_sheet(paths, out, cols=3):
    from PIL import Image
    ims = [Image.open(p) for p in paths]
    w, h = ims[0].size
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows), (30, 30, 30))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    sheet.save(out)
    return out


# =====================================================================================================
# 3. Body mesh
# =====================================================================================================
def build_body():
    prims = build_prims()
    lo = V(-0.42, -1.12, -0.005)
    hi = V(0.42, 1.66, 2.20)
    t = time.time()
    field, _ = eval_field(prims, lo, hi, VOXEL)
    log("field %s voxels in %.1fs" % (field.shape, time.time() - t))
    if PREVIEW:
        ortho_sheet(field, lo, VOXEL, os.path.join(OUT, "preview", "ortho.png"))
    verts, faces = field_to_mesh(field, lo, VOXEL)
    log("marching cubes: %d verts %d tris" % (len(verts), len(faces)))
    ob = make_mesh("Body", verts, faces[:, ::-1])
    return ob, prims


# =====================================================================================================
# 4. Armature, skin weights, per-vertex data
# =====================================================================================================
def build_armature():
    arm = bpy.data.armatures.new("HorseRig")
    ob = bpy.data.objects.new("Horse", arm)
    bpy.context.scene.collection.objects.link(ob)
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = {}
    for name, h, t, par in all_bones():
        eb = arm.edit_bones.new(name)
        eb.head = Vector(h)
        eb.tail = Vector(t)
        d = (Vector(t) - Vector(h)).normalized()
        z = Vector((1, 0, 0)).cross(d)
        if z.length < 1e-4:
            z = Vector((0, 0, 1))
        eb.align_roll(z.normalized())
        ebs[name] = eb
    for name, h, t, par in all_bones():
        if par:
            ebs[name].parent = ebs[par]
            ebs[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)


def mesh_adjacency(ob):
    import scipy.sparse as sp
    me = ob.data
    e = np.zeros(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    n = len(me.vertices)
    A = sp.coo_matrix((np.ones(len(e) * 2), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(n, n)).tocsr()
    deg = np.asarray(A.sum(1)).ravel()
    return A, np.maximum(deg, 1)


def smooth_vals(A, deg, vals, iters, lam=0.5):
    for _ in range(iters):
        vals = vals * (1 - lam) + lam * (A @ vals) / deg[:, None]
    return vals


BONE_SEGS = None


def bone_segments():
    global BONE_SEGS
    if BONE_SEGS is None:
        BONE_SEGS = {n: (h, t) for n, h, t, p in all_bones()}
    return BONE_SEGS


def compute_weights(verts, prims, A, deg, tau=0.012, tau_b=0.05, smooth=5, restrict=None):
    """Bone weights from the primitives that built the surface: soft membership of each vertex to each
    primitive, split among the primitive's candidate bones by distance to the bone segments."""
    segs = bone_segments()
    names = [n for n, h, t, p in all_bones()]
    idx = {n: i for i, n in enumerate(names)}
    up = [p for p in prims if p.op == "u"]
    D = np.stack([prim_dist(p, verts) for p in up], axis=1)
    dmin = D.min(1, keepdims=True)
    alpha = np.exp(-(D - dmin) / tau)
    alpha /= alpha.sum(1, keepdims=True)
    W = np.zeros((len(verts), len(names)))
    for j, p in enumerate(up):
        bones = [b for b in p.bones if restrict is None or b in restrict]
        if not bones:
            continue
        if len(bones) == 1:
            W[:, idx[bones[0]]] += alpha[:, j]
            continue
        sd = np.stack([seg_dist(verts, *segs[b]) for b in bones], axis=1)
        beta = np.exp(-(sd - sd.min(1, keepdims=True)) / tau_b)
        beta /= beta.sum(1, keepdims=True)
        for k, b in enumerate(bones):
            W[:, idx[b]] += alpha[:, j] * beta[:, k]
    if A is not None and smooth:
        W = smooth_vals(A, deg, W, smooth)
    return names, limit_weights(W)


def limit_weights(W, n=4, floor=0.02):
    order = np.argsort(-W, axis=1)
    keep = np.zeros_like(W, dtype=bool)
    rows = np.arange(len(W))[:, None]
    keep[rows, order[:, :n]] = True
    W = np.where(keep & (W > floor), W, 0.0)
    s = W.sum(1, keepdims=True)
    W = W / np.maximum(s, 1e-9)
    return W


def assign_weights(ob, names, W, arm_ob):
    for i, n in enumerate(names):
        col = W[:, i]
        nz = np.nonzero(col > 0)[0]
        if len(nz) == 0:
            continue
        vg = ob.vertex_groups.new(name=n)
        for v in nz:
            vg.add([int(v)], float(col[v]), "REPLACE")
    ob.parent = arm_ob
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm_ob


def rigid_weights(ob, bone, arm_ob):
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    ob.parent = arm_ob
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm_ob


def set_rest_uvs(ob):
    """UV0 = rest (x, y_forward), UV1 = rest (z_up, 0). Blender's glTF exporter writes v' = 1 - v, so the
    stored v is pre-flipped and the shader reads the exact metres."""
    me = ob.data
    v, _ = mesh_arrays(ob)
    li = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", li)
    p = v[li]
    uv0 = me.uv_layers.new(name="rest_xy")
    uv1 = me.uv_layers.new(name="rest_z")
    uv0.data.foreach_set("uv", np.stack([p[:, 0], 1.0 - p[:, 1]], 1).ravel())
    uv1.data.foreach_set("uv", np.stack([p[:, 2], np.ones(len(p))], 1).ravel())


def vertex_normals(ob):
    me = ob.data
    n = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", n)
    return n.reshape(-1, 3)


def bake_ao_curv(ob, A, deg, rays=20, dist=0.35):
    """Per-vertex ambient occlusion (BVH ray casts) and mean curvature -> COLOR (ao, curvature, hoof, 1)."""
    from mathutils.bvhtree import BVHTree
    v, f = mesh_arrays(ob)
    n = vertex_normals(ob)
    bvh = BVHTree.FromPolygons([tuple(x) for x in v], [tuple(x) for x in f])
    rng = np.random.default_rng(7)
    dirs = rng.normal(size=(rays, 3))
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    ao = np.zeros(len(v))
    for i in range(len(v)):
        nn = n[i]
        o = Vector(v[i] + nn * 0.004)
        hits = 0.0
        for d in dirs:
            if d @ nn < 0:
                d = -d
            r = bvh.ray_cast(o, Vector(d), dist)
            if r[0] is not None:
                hits += 1.0 - r[3] / dist
        ao[i] = 1.0 - hits / rays
    ao = smooth_vals(A, deg, ao[:, None], 2)[:, 0]
    lap = (A @ v) / deg[:, None] - v
    curv = -(lap * n).sum(1)
    el = 0.008
    curv = smooth_vals(A, deg, (curv / el)[:, None], 3)[:, 0]
    curv = np.clip(0.5 + curv * 0.5, 0, 1)
    hoofm = (v[:, 2] < 0.085).astype(float) * (np.abs(v[:, 1]) > 0.45)
    me = ob.data
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    cols = np.stack([ao, curv, hoofm, np.ones(len(v))], 1)
    ca.data.foreach_set("color", cols.ravel())
    me.color_attributes.active_color = ca
    return ao


def make_material(name, color, rough=0.6, metal=0.0, image=None, alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if image is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        if alpha:
            m.node_tree.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
            m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
    return m


def numpy_image(name, arr):
    """arr: HxWx4 float in [0,1] (top row first) -> packed Blender image."""
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    img.file_format = "PNG"
    img.pack()
    return img


# =====================================================================================================
# 5. Gaits and actions: planar (sagittal) kinematics + per-frame IK from footfall phase tables
# =====================================================================================================
FPS = 60
FRONT = ["scapula", "humerus", "forearm", "fcannon", "fpastern", "fhoof"]
HIND = ["femur", "tibia", "hcannon", "hpastern", "hhoof"]
LEGS = {  # leg id -> (chain bone names, sole rest, toe rest, parent)
    "LF": ([b + "_L" for b in FRONT], J["fsole"], J["ftoe"], "spine_withers"),
    "RF": ([b + "_R" for b in FRONT], mx(J["fsole"]), mx(J["ftoe"]), "spine_withers"),
    "LH": ([b + "_L" for b in HIND], J["hsole"], J["htoe"], "pelvis"),
    "RH": ([b + "_R" for b in HIND], mx(J["hsole"]), mx(J["htoe"]), "pelvis"),
}
BOUNDS = {
    "scapula": (-0.7, 0.7), "humerus": (-0.9, 0.9), "forearm": (-0.4, 1.8), "fcannon": (-2.2, 0.05),
    "fpastern": (-2.0, 0.65), "fhoof": (-0.7, 0.6),
    "femur": (-1.0, 1.0), "tibia": (-1.4, 0.5), "hcannon": (-0.12, 1.9), "hpastern": (-2.0, 0.65),
    "hhoof": (-0.7, 0.6),
}


def base(n):
    return n[:-2] if n.endswith("_L") or n.endswith("_R") else n


def R2(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s], [s, c]])


REST2 = None


def rest2():
    global REST2
    if REST2 is None:
        REST2 = {n: (np.array([h[1], h[2]]), np.array([t[1], t[2]]), p) for n, h, t, p in all_bones()}
    return REST2


def fk_trunk(ang, loc=(0.0, 0.0)):
    """2D forward kinematics of every bone: name -> (global angle, posed head). `ang` = relative X angles."""
    r = rest2()
    out = {}
    for n, h, t, p in all_bones():
        h2 = r[n][0]
        a = ang.get(n, 0.0)
        if p is None:
            out[n] = (a, h2.copy())
            continue
        pa, ph = out[p]
        ph_rest = r[p][0]
        head = R2(pa) @ (h2 - ph_rest) + ph
        if n == "body":
            head = head + np.array(loc)
        out[n] = (pa + a, head)
    return out


LEGDATA = {}


def legdata(leg):
    if leg not in LEGDATA:
        chain, sole, toe, par = LEGS[leg]
        r = rest2()
        heads = np.array([r[b][0] for b in chain])
        s2 = np.array([sole[1], sole[2]])
        t2 = np.array([toe[1], toe[2]])
        h2 = s2 - (t2 - s2) * 0.9
        offs = np.vstack([heads[0] - r[par][0], heads[1:] - heads[:-1]])
        ends = np.array([s2, t2, h2]) - heads[-1]
        LEGDATA[leg] = (offs, ends, par)
    return LEGDATA[leg]


def leg_fk(leg, th, parent_pose):
    """Posed sole centre, toe, heel and hoof angle for chain angles th (list)."""
    offs, ends, par = legdata(leg)
    A, H = parent_pose
    c, s_ = math.cos(A), math.sin(A)
    H = np.array([H[0] + c * offs[0][0] - s_ * offs[0][1], H[1] + s_ * offs[0][0] + c * offs[0][1]])
    for i in range(len(th)):
        A += th[i]
        if i + 1 < len(th):
            o = offs[i + 1]
            c, s_ = math.cos(A), math.sin(A)
            H = H + np.array([c * o[0] - s_ * o[1], s_ * o[0] + c * o[1]])
    c, s_ = math.cos(A), math.sin(A)
    M = np.array([[c, -s_], [s_, c]])
    e = ends @ M.T + H
    return e[0], e[1], e[2], A


def solve_leg(leg, parent_pose, target, tang, style, wstyle, wpos, wang, prev):
    from scipy.optimize import least_squares
    chain = LEGS[leg][0]
    lo = np.array([BOUNDS[base(b)][0] for b in chain])
    hi = np.array([BOUNDS[base(b)][1] for b in chain])
    style = np.asarray(style)
    sw = np.sqrt(np.asarray(wstyle))
    prev = np.clip(np.asarray(prev, float), lo + 1e-6, hi - 1e-6)
    swp, swa = math.sqrt(wpos), math.sqrt(wang)
    wprev = 0.1 if wpos > 1e4 else 0.63

    def res(th):
        sp, tp, hp, A = leg_fk(leg, th, parent_pose)
        g = 200.0 * np.array([min(tp[1], 0.0), min(hp[1], 0.0)])
        return np.concatenate([swp * (sp - target), [swa * (A - tang)], sw * (th - style), wprev * (th - prev), g])

    r = least_squares(res, prev, bounds=(lo, hi), method="trf", xtol=1e-10, ftol=1e-10, max_nfev=60)
    return r.x


def smooth_pulse(x):
    return math.sin(math.pi * min(max(x, 0.0), 1.0))


GAITS = {
    # T cycle seconds, L stride metres, duty (fore, hind), footfall phase per leg, lift (fore, hind),
    # knee/hock/fetlock swing flexion, body bob/pitch, neck nod, lumbar flex, tail carriage
    "walk": dict(T=1.05, L=1.75, duty=(0.62, 0.62), ph={"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
                 lift=(0.09, 0.08), knee=0.95, hock=0.5, fet=(1.0, 0.9), bob=(0.012, 2, 0.12), pitch=(0.012, 2, 0.0),
                 nod=(0.07, 2, 0.06), lumbar=0.02, tail=(0.0, 0.05), reach=(0.03, 0.0)),
    "trot": dict(T=0.72, L=2.7, duty=(0.42, 0.42), ph={"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},
                 lift=(0.16, 0.13), knee=1.45, hock=0.75, fet=(1.5, 1.3), bob=(0.035, 2, 0.21), pitch=(0.012, 2, 0.1),
                 nod=(0.015, 2, 0.21), lumbar=0.02, tail=(-0.15, 0.06), reach=(0.05, 0.02)),
    "canter": dict(T=0.55, L=3.5, duty=(0.35, 0.37), ph={"RH": 0.0, "LH": 0.27, "RF": 0.27, "LF": 0.50},
                   lift=(0.2, 0.17), knee=1.7, hock=0.85, fet=(1.7, 1.5), bob=(0.055, 1, 0.42), pitch=(0.07, 1, 0.12),
                   nod=(0.13, 1, 0.12), lumbar=0.05, tail=(-0.35, 0.1), reach=(0.06, 0.02)),
    "gallop": dict(T=0.47, L=6.0, duty=(0.21, 0.22), ph={"RH": 0.0, "LH": 0.10, "RF": 0.38, "LF": 0.48},
                   lift=(0.24, 0.21), knee=2.0, hock=1.0, fet=(1.8, 1.6), bob=(0.07, 1, 0.30), pitch=(0.08, 1, 0.05),
                   nod=(0.15, 1, 0.05), lumbar=0.10, tail=(-0.45, 0.12), reach=(0.10, 0.04)),
}


def mirror_gait(g):
    g = dict(g)
    sw = {"LH": "RH", "RH": "LH", "LF": "RF", "RF": "LF"}
    g["ph"] = {sw[k]: v for k, v in g["ph"].items()}
    return g


GAITS["canter_r"] = mirror_gait(GAITS["canter"])
GAITS["gallop_r"] = mirror_gait(GAITS["gallop"])


def beats_of(ph, tol=0.06):
    """Group footfall phases into beats (within tol of a cycle), in order of occurrence from the first leg."""
    items = sorted(ph.items(), key=lambda kv: kv[1])
    beats = []
    for leg, p in items:
        if beats and abs(p - beats[-1][1]) <= tol:
            beats[-1][0].append(leg)
        else:
            beats.append([[leg], p])
    if len(beats) > 1 and (beats[0][1] + 1.0 - beats[-1][1]) <= tol:
        beats[0][0].extend(beats.pop()[0])
    return [sorted(b[0]) for b in beats]


def cyc(x, f, phase):
    return math.cos(2 * math.pi * (f * x - phase))


def gait_trunk_angles(g, x):
    """Relative X rotations of trunk/neck/head/tail/ears + body location for cycle phase x in [0, 1)."""
    bob_a, bob_f, bob_p = g["bob"]
    pit_a, pit_f, pit_p = g["pitch"]
    nod_a, nod_f, nod_p = g["nod"]
    dz = -bob_a * cyc(x, bob_f, bob_p * bob_f)
    pitch = pit_a * cyc(x, pit_f, pit_p * pit_f)
    nod = nod_a * cyc(x, nod_f, nod_p * nod_f)
    ang = {"body": pitch}
    lum = g["lumbar"] * cyc(x, 1, 0.15)
    ang["spine_lumbar"] = -lum
    ang["pelvis"] = -lum * 0.6
    ang["spine_thorax"] = lum * 0.3
    ang["spine_withers"] = 0.0
    # neck nods (distributed), head keeps its angle partly; whole neck carriage compensates body pitch
    ang["neck_1"] = nod * 0.45 - pitch * 0.5
    ang["neck_2"] = nod * 0.25
    ang["neck_3"] = nod * 0.15
    ang["neck_4"] = nod * 0.1
    ang["head"] = -nod * 0.55
    t0, tsw = g["tail"]
    for i in range(1, 7):
        ang["tail_%d" % i] = (t0 if i == 1 else t0 * 0.25) + tsw * cyc(x, bob_f, 0.1 * i + bob_p) * (0.4 + 0.12 * i)
    ear = 0.12 - 0.25 * (g["L"] / g["T"]) / 12.0
    ang["ear_L"] = ear
    ang["ear_R"] = ear
    return ang, (0.0, dz)


def leg_targets(g, leg, x):
    """Sole target (y, z), hoof angle, stance flag, style vector and weights for phase x."""
    front = leg.endswith("F")
    duty = g["duty"][0 if front else 1]
    S = duty * g["L"]
    chain, sole, toe, par = LEGS[leg]
    y0 = sole[1] + g["reach"][0 if front else 1]
    lift = g["lift"][0 if front else 1]
    p = (x - g["ph"][leg]) % 1.0
    n = len(chain)
    style = np.zeros(n)
    w = np.full(n, 0.15)
    if p < duty:  # stance: hoof planted, moving back relative to the body
        s = p / duty
        ty = y0 + S * 0.5 - S * s
        tz = 0.0
        tang = 0.0
        if s > 0.82:                                   # breakover: heel rises about the toe
            a = -0.55 * (s - 0.82) / 0.18
            toe_y = ty + (toe[1] - sole[1])
            off = R2(a) @ np.array([sole[1] - toe[1], 0.0])
            ty, tz, tang = toe_y + off[0], off[1], a
        if front:
            style[3], w[3] = 0.0, 2.0
            style[4], w[4] = 0.32 * smooth_pulse(s), 0.6
        else:
            style[2], w[2] = 0.14 * smooth_pulse(s), 0.5
            style[3], w[3] = 0.3 * smooth_pulse(s), 0.6
        return np.array([ty, tz]), tang, True, style, w, 2.5e4, 30.0
    u = (p - duty) / (1.0 - duty)                      # swing: lift, fold, reach forward
    ty = y0 - S * 0.5 + S * (u - math.sin(2 * math.pi * u) / (2 * math.pi))
    tz = lift * math.sin(math.pi * u ** 0.8) + 0.004
    fold = math.sin(math.pi * min(u * 1.15, 1.0) ** 0.85)
    fet_f, fet_h = g["fet"]
    if front:
        style[3], w[3] = -g["knee"] * fold, 1.2
        style[2], w[2] = 0.45 * g["knee"] * fold, 0.4
        style[4], w[4] = -fet_f * fold, 0.8
        style[5], w[5] = -0.25 * fold, 0.3
    else:
        style[2], w[2] = g["hock"] * fold, 1.0
        style[1], w[1] = -0.55 * g["hock"] * fold, 0.4
        style[3], w[3] = -fet_h * fold, 0.8
        style[4], w[4] = -0.25 * fold, 0.3
    tang = -0.4 * fold
    return np.array([ty, tz]), tang, False, style, w, 3.0e3, 1.0


def solve_cycle(g, frames):
    """Per-frame relative angles for every bone over one cycle (closed loop: frame `frames` == frame 0)."""
    poses = []
    prev = {leg: np.zeros(len(LEGS[leg][0])) for leg in LEGS}
    stats = {leg: [] for leg in LEGS}
    for rep in range(2):                               # second pass warm-starts from the end of the first
        poses = []
        for fi in range(frames):
            x = fi / frames
            ang, loc = gait_trunk_angles(g, x)
            tr = fk_trunk(ang, loc)
            for leg in LEGS:
                tgt, tang, stance, style, w, wp, wa = leg_targets(g, leg, x)
                par = LEGS[leg][3]
                th = solve_leg(leg, tr[par], tgt, tang, style, w, wp, wa, prev[leg])
                prev[leg] = th
                for b, a in zip(LEGS[leg][0], th):
                    ang[b] = a
                if rep == 1:
                    sp, tp, hp, A = leg_fk(leg, th, tr[par])
                    stats[leg].append((stance, float(np.linalg.norm(sp - tgt)), sp[0], sp[1]))
            poses.append((ang, loc))
    return poses, stats


def key_action(arm_ob, name, poses, side=None, loop=True, fps=FPS):
    """Keyframe a list of (angles, loc) poses (one per frame). side: optional per-frame dict of extra
    rotations about local Z / Y: {bone: (z_angle, y_angle)}."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm_ob.animation_data_create()
    arm_ob.animation_data.action = act
    n = len(poses)
    frames = list(range(n)) + ([n] if loop else [])
    for fi in frames:
        ang, loc = poses[fi % n]
        ex = side[fi % n] if side else {}
        for pb in arm_ob.pose.bones:
            a = ang.get(pb.name, 0.0)
            q = Quaternion((1, 0, 0), a)
            if pb.name in ex:
                zr, yr = ex[pb.name]
                q = q @ Quaternion((0, 0, 1), zr) @ Quaternion((0, 1, 0), yr)
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=fi, group=pb.name)
            if pb.name == "body":
                pb.location = (0.0, loc[0], loc[1]) if len(loc) == 2 else loc
                pb.keyframe_insert("location", frame=fi, group=pb.name)
    for fc in iter_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    arm_ob.animation_data.action = None
    return act


def iter_fcurves(act):
    try:
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        yield fc
    except AttributeError:
        for fc in act.fcurves:
            yield fc


def pose_strip(arm_ob, act_name, n, out, view="side", res=(360, 260)):
    """Render n evenly spaced frames of an action side by side (Cycles preview)."""
    act = bpy.data.actions[act_name]
    arm_ob.animation_data_create()
    arm_ob.animation_data.action = act
    f0, f1 = act.frame_range
    paths = []
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        bpy.context.scene.frame_set(int(round(f)))
        paths.extend(preview_render(out + "_%d" % i, views=(view,), res=res))
    arm_ob.animation_data.action = None
    contact_sheet(paths, out + ".png", cols=n)
    for pth in paths:
        os.remove(pth)
    return out + ".png"


def export_glb(path):
    preview_cleanup()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_yup=True,
                              export_apply=False, export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_texcoords=True, export_normals=True, export_force_sampling=True,
                              export_optimize_animation_size=False, export_def_bones=False,
                              export_image_format="AUTO", export_rest_position_armature=True,
                              export_anim_slide_to_zero=True, export_extras=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    reset_scene()
    bpy.context.scene.render.fps = FPS
    body, prims = build_body()
    decimate_to(body, 26000)
    shade_smooth(body)
    log("body: %d tris" % tri_count(body))
    arm = build_armature()
    verts, _ = mesh_arrays(body)
    A, deg = mesh_adjacency(body)
    names, W = compute_weights(verts, prims, A, deg)
    assign_weights(body, names, W, arm)
    log("weights done")
    set_rest_uvs(body)
    bake_ao_curv(body, A, deg, rays=8 if QUICK else 20)
    log("ao/curvature baked")
    coat = make_material("horse_coat", (0.36, 0.2, 0.11, 1), rough=0.5)
    body.data.materials.append(coat)
    meta = {"fps": FPS, "gaits": {}, "anims": {}, "legs": {}}
    if not NO_ANIM:
        for gname, g in GAITS.items():
            frames = int(round(g["T"] * FPS))
            t = time.time()
            poses, stats = solve_cycle(g, frames)
            key_action(arm, gname, poses)
            err = max(e for leg in stats for (st, e, y, z) in stats[leg] if st)
            meta["gaits"][gname] = {"anim": gname, "cycle": frames / FPS, "stride": g["L"], "speed": g["L"] / (frames / FPS),
                                    "duty": {"fore": g["duty"][0], "hind": g["duty"][1]}, "footfalls": g["ph"],
                                    "beats": beats_of(g["ph"])}
            meta["anims"][gname] = {"length": frames / FPS, "loop": True}
            log("gait %-8s %d frames, max stance IK error %.1f mm (%.1fs)" % (gname, frames, err * 1000, time.time() - t))
    for leg, (chain, sole, toe, par) in LEGS.items():
        meta["legs"][leg] = {"hoof_bone": chain[-1], "sole_rest": [float(sole[0]), float(sole[2]), float(-sole[1])]}
    meta["rest"] = {"withers_height": 1.555, "length": 2.0, "saddle_bone": "spine_thorax"}
    if PREVIEW:
        pdir = os.path.join(OUT, "preview")
        os.makedirs(pdir, exist_ok=True)
        ps = preview_render(os.path.join(pdir, "body"), views=("side", "front34", "rear34", "headside", "head", "legs", "front", "rear", "top"))
        contact_sheet(ps, os.path.join(pdir, "sheet.png"))
        if not NO_ANIM:
            for gname in ("walk", "trot", "canter", "gallop"):
                pose_strip(arm, gname, 6, os.path.join(pdir, "gait_" + gname))
        log("previews in", pdir)
    path = os.path.join(OUT, "horse.glb")
    export_glb(path)
    with open(os.path.join(OUT, "horse_gaits.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    log("wrote %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))


if __name__ == "__main__":
    main()
