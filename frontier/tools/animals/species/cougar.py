"""Cougar / mountain lion (felid). Reference: shoulder height ~0.70 m with the hips slightly higher (~0.74 m), long
body (~1.15 m point of shoulder to buttock; nose to rump ~1.5 m), small round head ~0.2 m with a short muzzle and
small rounded ears, powerful forelegs, big round paws (claws retracted), thick tail ~0.75 m hanging low with an
upturned black tip. Gaits: walk, trot, rotary gallop."""
import numpy as np

from species import common as C
from species import wolf as W

V = C.V
NAME = "cougar"
H = 0.70
S = H / 1.555
B = {
    "family": "felid", "scale": S,
    "y_rear": -0.62, "y_front": 0.52,
    "top": [(-0.62, 0.62), (-0.54, 0.72), (-0.40, 0.75), (-0.22, 0.73), (0.0, 0.70), (0.2, 0.70), (0.34, 0.715),
            (0.45, 0.66), (0.52, 0.56)],
    "bottom": [(-0.62, 0.52), (-0.52, 0.47), (-0.36, 0.45), (-0.15, 0.42), (0.05, 0.40), (0.22, 0.39), (0.36, 0.41),
               (0.46, 0.45), (0.52, 0.49)],
    "width": [(-0.62, 0.05), (-0.52, 0.125), (-0.38, 0.14), (-0.15, 0.145), (0.05, 0.155), (0.22, 0.155), (0.38, 0.135),
              (0.47, 0.1), (0.52, 0.05)],
    "ntop": [(-0.62, 2.3), (0.52, 2.3)], "nbot": [(-0.62, 2.0), (0.52, 2.2)],
    "neck": [((0.30, 0.71), (0.46, 0.50), 0.085), ((0.40, 0.75), (0.53, 0.58), 0.078), ((0.48, 0.79), (0.58, 0.65), 0.072),
             ((0.535, 0.82), (0.615, 0.70), 0.068), ((0.57, 0.84), (0.64, 0.735), 0.064)],
    "neck_pinch": 0.2,
    "poll": V(0, 0.575, 0.86), "nose": V(0, 0.725, 0.775),
    "atlas_off": V(0, 0.02, -0.06),
    "head": [(-0.04, 0.12, 0.065, 2.3, 2.0), (0.18, 0.145, 0.08, 2.7, 2.1), (0.4, 0.13, 0.075, 2.8, 2.2),
             (0.6, 0.105, 0.062, 2.6, 2.2), (0.8, 0.088, 0.054, 2.4, 2.2), (0.94, 0.075, 0.046, 2.2, 2.2),
             (1.0, 0.058, 0.036, 2.0, 2.0)],
    "jaw": (V(0, 0.595, 0.78), V(0, 0.71, 0.735), 0.032, 0.024, 1.5),
    "eye": (0.04, 0.655, 0.83), "eye_r": 0.011, "eye_fwd": 0.8, "teeth": True,
    "ear_w": 0.027, "ear_t": 0.45,
    "leg_r": (0.058, 0.052, 0.033, 0.025, 0.025, 0.023),
    "hleg_r": (0.078, 0.15, 0.055, 0.03, 0.024, 0.025, 0.023),
    "foot": "paw", "foot_r": (0.05, 0.046), "claws": False,
    "tail_base": V(0, -0.60, 0.66), "tail_len": 0.75, "tail_angle0": -55.0, "tail_angle1": -40.0,
    "tail_r": [0.035, 0.032, 0.03, 0.028, 0.027, 0.027, 0.026],
    "chest_x": 0.35, "pec": 0.6,
    "head_extra": [lambda Q, Pp, fd, zp, L, B_: W.snout(Q, Pp, fd, zp, L * 0.75, B_),
                   lambda Q, Pp, fd, zp, L, B_: _whisker_pads(Q, Pp, fd, zp, L, B_)],
}
J = {
    "ear": V(-0.045, 0.575, 0.86), "ear_t": V(-0.056, 0.58, 0.905),
    "scap": V(-0.055, 0.30, 0.66), "shoulder": V(-0.08, 0.44, 0.50), "elbow": V(-0.085, 0.30, 0.38),
    "knee": V(-0.075, 0.33, 0.13), "ffet": V(-0.072, 0.35, 0.04), "fcoffin": V(-0.072, 0.40, 0.022),
    "fsole": V(-0.072, 0.38, 0.0), "ftoe": V(-0.072, 0.425, 0.0),
    "hip": V(-0.075, -0.45, 0.62), "stifle": V(-0.09, -0.30, 0.40), "hock": V(-0.075, -0.56, 0.18),
    "hfet": V(-0.07, -0.50, 0.04), "hcoffin": V(-0.07, -0.45, 0.022), "hsole": V(-0.07, -0.47, 0.0),
    "htoe": V(-0.07, -0.425, 0.0),
    "jaw": V(0, 0.60, 0.785), "jaw_t": V(0, 0.705, 0.738),
}


def _whisker_pads(Q, Pp, fd, zp, L, B_):
    s = B_["scale"]
    m = Pp + fd * L * 0.85 - zp * 0.03
    Q.ell((-0.022, m[1], m[2]), (0.024, 0.026, 0.022), ["head"], k=0.012 * s / S * 0.5)


C.spine_landmarks(J, B)
C.tail_points(J, B)
# the tip curls up
J["tail5"] = J["tail5"] + V(0, -0.03, 0.02)
J["tail6"] = J["tail5"] + V(0, -0.09, 0.07)
BONES = C.make_bones(J, root_len=0.2)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.24, -1.45, -0.005), (0.24, 0.85, 1.0)),
          "tris": 14000, "lods": (4500, 1100), "actions": "generic", "withers": H, "scale": S, "length": 1.5,
          "voxel": (0.0032, 0.0058)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(1.0, 1.25, (0.64, 0.64), C.WALK, H, lift=(0.08, 0.07), knee=1.0, hock=0.6, nod=(0.04, 2, 0.06),
                   tail=(0.05, 0.05)),
    "trot": C.gait(0.55, 2.0, (0.45, 0.45), C.TROT, H, lift=(0.12, 0.1), knee=1.3, hock=0.9, fet=(1.2, 1.0),
                   bob=(0.02, 2, 0.21), nod=(0.01, 2, 0.21), reach=(0.03, 0.02)),
    "gallop": C.gait(0.38, 4.6, (0.2, 0.22), C.GALLOP_ROTARY, H, lift=(0.2, 0.18), knee=1.8, hock=1.1,
                     fet=(1.4, 1.2), bob=(0.05, 1, 0.30), pitch=(0.07, 1, 0.05), nod=(0.06, 1, 0.05), lumbar=0.28,
                     tail=(-0.1, 0.1), reach=(0.10, 0.09)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_rotary"}
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": True, "graze_neck": (-0.6, -0.25, -0.1, -0.05, 0.3), "alert_tail": 0.15,
                         "flee_tail": 0.0, "tail_wag": 0.3, "drop": 0.3, "lie": 0.5})
