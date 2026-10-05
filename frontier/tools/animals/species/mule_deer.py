"""Mule deer (buck; the antlers are a separate mesh the game hides for does).
Reference: shoulder height ~1.0 m, nose-to-rump ~1.6 m, body (point of shoulder to buttock) ~1.1 m, head ~0.32 m,
ears ~0.22 x 0.11 m (the large "mule" ears), rope-like white tail ~0.18 m with a black tip, small cloven hooves,
bifurcated antlers (each beam forks, then forks again) ~0.6 m spread. Gaits: walk, trot, transverse gallop and the
stot (pronk: all four feet together)."""
import math

import numpy as np

from species import common as C

V = C.V
NAME = "mule_deer"
H = 1.0
CONFIG = {"coat_material": "animal_coat", "eyes": ((0.047, 0.607, 1.282), 0.0145), "bbox": ((-0.32, -0.85, -0.005), (0.32, 0.86, 1.82)),
          "tris": 16000, "lods": (5000, 1300), "actions": "generic", "withers": H, "scale": 0.643, "length": 1.6,
          "voxel": (0.0042, 0.007)}

B = {
    "family": "cervid", "scale": 0.643,
    "y_rear": -0.58, "y_front": 0.58,
    "top": [(-0.58, 0.84), (-0.50, 0.96), (-0.36, 1.015), (-0.18, 0.99), (0.05, 0.975), (0.25, 1.0), (0.42, 0.95),
            (0.52, 0.83), (0.58, 0.72)],
    "bottom": [(-0.58, 0.74), (-0.50, 0.67), (-0.36, 0.665), (-0.15, 0.625), (0.05, 0.59), (0.25, 0.575), (0.42, 0.62),
               (0.52, 0.665), (0.58, 0.68)],
    "width": [(-0.58, 0.05), (-0.48, 0.115), (-0.36, 0.145), (-0.15, 0.165), (0.05, 0.172), (0.25, 0.158), (0.42, 0.125),
              (0.52, 0.085), (0.58, 0.05)],
    "neck": [((0.27, 1.0), (0.47, 0.76), 0.08), ((0.39, 1.12), (0.55, 0.94), 0.062), ((0.475, 1.22), (0.60, 1.07), 0.054),
             ((0.535, 1.31), (0.625, 1.18), 0.049), ((0.57, 1.375), (0.625, 1.27), 0.045)],
    "poll": V(0, 0.58, 1.385), "nose": V(0, 0.75, 1.112),
    "head": [(-0.02, 0.115, 0.044, 2.2, 2.0), (0.1, 0.14, 0.05, 2.5, 2.1), (0.28, 0.13, 0.052, 3.0, 2.1),
             (0.45, 0.10, 0.04, 2.8, 2.2), (0.62, 0.082, 0.031, 2.6, 2.2), (0.8, 0.072, 0.027, 2.4, 2.2),
             (0.93, 0.066, 0.029, 2.2, 2.2), (1.0, 0.046, 0.023, 2.0, 2.0)],
    "jaw": (V(0, 0.575, 1.27), V(0, 0.715, 1.095), 0.024, 0.014, 1.4),
    "eye": (0.047, 0.607, 1.282), "eye_r": 0.0145,
    "ear_w": 0.052, "ear_t": 0.3,
    "leg_r": (0.05, 0.04, 0.022, 0.0155, 0.02, 0.017),
    "hleg_r": (0.075, 0.15, 0.045, 0.024, 0.0165, 0.02, 0.017),
    "foot": "cloven", "foot_r": (0.034, 0.032),
    "tail_base": V(0, -0.565, 0.93), "tail_len": 0.19, "tail_angle0": -45.0, "tail_angle1": -85.0,
    "tail_r": [0.028, 0.03, 0.028, 0.024, 0.02, 0.016, 0.01], "tail_flat": 1.0,
    "chest_x": 0.5,
}

J = {
    "ear": V(-0.04, 0.565, 1.395), "ear_t": V(-0.175, 0.555, 1.505),
    "scap": V(-0.06, 0.30, 0.93), "shoulder": V(-0.09, 0.455, 0.72), "elbow": V(-0.095, 0.31, 0.605),
    "knee": V(-0.08, 0.325, 0.35), "ffet": V(-0.075, 0.33, 0.09), "fcoffin": V(-0.075, 0.365, 0.035),
    "fsole": V(-0.075, 0.38, 0.0), "ftoe": V(-0.075, 0.42, 0.0),
    "hip": V(-0.10, -0.38, 0.88), "stifle": V(-0.11, -0.22, 0.64), "hock": V(-0.075, -0.48, 0.42),
    "hfet": V(-0.072, -0.465, 0.09), "hcoffin": V(-0.072, -0.425, 0.035), "hsole": V(-0.072, -0.41, 0.0),
    "htoe": V(-0.072, -0.37, 0.0),
    "jaw": V(0, 0.585, 1.27), "jaw_t": V(0, 0.71, 1.10),
}
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.3)


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(0.95, 1.25, (0.62, 0.62), C.WALK, H, lift=(0.1, 0.09), knee=1.0, hock=0.55, nod=(0.06, 2, 0.06)),
    "trot": C.gait(0.55, 1.95, (0.42, 0.42), C.TROT, H, lift=(0.16, 0.13), knee=1.5, hock=0.8, fet=(1.5, 1.3),
                   bob=(0.03, 2, 0.21), nod=(0.015, 2, 0.21), tail=(-0.3, 0.06), reach=(0.04, 0.02)),
    "gallop": C.gait(0.42, 4.4, (0.22, 0.24), C.GALLOP_TRANSVERSE, H, lift=(0.24, 0.21), knee=2.0, hock=1.0,
                     fet=(1.8, 1.6), bob=(0.07, 1, 0.30), pitch=(0.08, 1, 0.05), nod=(0.12, 1, 0.05), lumbar=0.12,
                     tail=(-0.9, 0.12), reach=(0.10, 0.06)),
    "stot": C.gait(0.62, 3.0, (0.26, 0.26), {"LF": 0.0, "RF": 0.0, "LH": 0.0, "RH": 0.0}, H, lift=(0.30, 0.28),
                   knee=0.6, hock=0.4, fet=(0.8, 0.8), bob=(0.18, 1, 0.13), pitch=(0.03, 1, 0.0), nod=(0.05, 1, 0.1),
                   lumbar=0.03, tail=(-0.9, 0.05)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_transverse", "stot": "pronk"}
META = {"run_gait": "gallop", "flee_gait": "stot", "variants": {"doe": {"hide": ["Antlers"], "scale": 0.92}}}


def actions(Q):
    return C.actions(Q, {"H": H, "graze_neck": (-1.05, -0.45, -0.3, -0.15, 0.6), "alert_tail": -0.9, "flee_tail": -1.0})


def build_extras(Q, prims, arm):
    """Bifurcated antlers: each beam rises back and out, forks; each branch forks again (4 points a side)."""
    tubes = []
    s = 1.0
    for sx in (-1.0, 1.0):
        base = V(sx * 0.038, 0.585, 1.41)
        beam = C.curve(base, V(sx * 1.0, -0.45, 0.8), 0.22, V(sx * -0.4, 2.6, 0.6), n=6)
        tubes.append(C.tube_branch(Q, beam, 0.02, 0.015))
        brow = C.curve(beam[1], V(sx * 0.2, 1.0, 0.7), 0.05, V(0, 0, 2.0), n=3)        # small brow tine
        tubes.append(C.tube_branch(Q, brow, 0.007, 0.002, segs=5))
        f1 = beam[-1]
        for k, (d, bend, L) in enumerate(((V(sx * 0.5, -0.3, 1.0), V(0, 1.6, -0.3), 0.20),
                                         (V(sx * 0.3, 1.0, 0.7), V(0, 0.6, 1.0), 0.16))):
            br = C.curve(f1, d, L, bend, n=5)
            tubes.append(C.tube_branch(Q, br, 0.014, 0.009))
            f2 = br[-1]
            for d2, L2 in ((V(sx * 0.25, 0.1, 1.0), 0.11), (V(sx * 0.35, 1.0, 0.45), 0.09)):
                tip = C.curve(f2, d2, L2, V(0, 0.8, -0.2), n=4)
                tubes.append(C.tube_branch(Q, tip, 0.007, 0.0015, segs=5))
        tubes.append(C.burr(Q, base, V(sx * 1.0, -0.45, 0.8), 0.021))
    C.emit_tubes(Q, arm, "Antlers", tubes, (0.42, 0.34, 0.24, 1), rough=0.75)
