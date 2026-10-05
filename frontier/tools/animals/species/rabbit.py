"""Black-tailed jackrabbit (the game's "rabbit"). Reference: ~0.3 m at the shoulder standing on all fours, body
~0.5 m, very long black-tipped ears (~0.13 m), large eyes set high, thin short forelegs, long hind legs with long
hind feet (~0.12 m) that rest flat, short tail (black on top, white below). Gaits: hop (slow half-bound) and bound
(the fast leaping run, fores staggered, hinds together)."""
import numpy as np

from species import common as C
from species import wolf as W

V = C.V
NAME = "rabbit"
H = 0.3
S = H / 1.555
B = {
    "family": "lagomorph", "scale": S,
    "y_rear": -0.24, "y_front": 0.20,
    "top": [(-0.24, 0.20), (-0.20, 0.27), (-0.12, 0.31), (-0.02, 0.305), (0.08, 0.29), (0.15, 0.27), (0.20, 0.22)],
    "bottom": [(-0.24, 0.12), (-0.18, 0.10), (-0.08, 0.13), (0.04, 0.15), (0.12, 0.16), (0.20, 0.18)],
    "width": [(-0.24, 0.04), (-0.18, 0.075), (-0.08, 0.075), (0.04, 0.07), (0.12, 0.06), (0.20, 0.035)],
    "ntop": [(-0.24, 2.2), (0.2, 2.2)], "nbot": [(-0.24, 2.0), (0.2, 2.0)],
    "neck": [((0.12, 0.28), (0.17, 0.18), 0.045), ((0.16, 0.30), (0.20, 0.21), 0.04), ((0.19, 0.32), (0.22, 0.24), 0.036),
             ((0.21, 0.335), (0.235, 0.26), 0.034), ((0.225, 0.345), (0.245, 0.275), 0.033)],
    "neck_pinch": 0.1,
    "poll": V(0, 0.225, 0.35), "nose": V(0, 0.31, 0.29),
    "atlas_off": V(0, 0.01, -0.025),
    "head": [(-0.05, 0.06, 0.03, 2.2, 2.0), (0.15, 0.072, 0.036, 2.5, 2.1), (0.4, 0.07, 0.034, 2.5, 2.2),
             (0.65, 0.055, 0.026, 2.4, 2.2), (0.88, 0.045, 0.022, 2.2, 2.2), (1.0, 0.032, 0.016, 2.0, 2.0)],
    "jaw": (V(0, 0.23, 0.315), V(0, 0.30, 0.275), 0.014, 0.009, 1.3),
    "eye": (0.03, 0.257, 0.335), "eye_r": 0.0085, "eye_fwd": 0.1,
    "ear_w": 0.022, "ear_t": 0.28,
    "leg_r": (0.016, 0.012, 0.008, 0.007, 0.008, 0.008),
    "hleg_r": (0.04, 0.07, 0.022, 0.011, 0.009, 0.01, 0.009),
    "foot": "paw", "foot_r": (0.014, 0.017), "claws": False,
    "tail_base": V(0, -0.235, 0.20), "tail_len": 0.06, "tail_angle0": 20.0, "tail_angle1": -10.0,
    "tail_r": [0.02, 0.024, 0.024, 0.022, 0.02, 0.016, 0.01],
    "chest_x": 0.3, "pec": 0.4,
    "head_extra": [lambda Q, Pp, fd, zp, L, B_: W.snout(Q, Pp, fd, zp, L * 0.6, B_)],
}
J = {
    "ear": V(-0.018, 0.215, 0.37), "ear_t": V(-0.035, 0.18, 0.50),
    "scap": V(-0.02, 0.10, 0.28), "shoulder": V(-0.03, 0.17, 0.2), "elbow": V(-0.032, 0.12, 0.14),
    "knee": V(-0.03, 0.14, 0.055), "ffet": V(-0.03, 0.15, 0.015), "fcoffin": V(-0.03, 0.17, 0.008),
    "fsole": V(-0.03, 0.16, 0.0), "ftoe": V(-0.03, 0.18, 0.0),
    "hip": V(-0.035, -0.16, 0.25), "stifle": V(-0.045, -0.08, 0.13), "hock": V(-0.04, -0.21, 0.045),
    "hfet": V(-0.04, -0.09, 0.012), "hcoffin": V(-0.04, -0.06, 0.008), "hsole": V(-0.04, -0.12, 0.0),
    "htoe": V(-0.04, -0.05, 0.0),
    "jaw": V(0, 0.235, 0.315), "jaw_t": V(0, 0.295, 0.28),
}
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.08)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.1, -0.3, -0.005), (0.1, 0.34, 0.53)),
          "tris": 7000, "lods": (2400, 700), "actions": "generic", "withers": H, "scale": S, "length": 0.55,
          "voxel": (0.0013, 0.0025)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "hop": C.gait(0.45, 0.5, (0.45, 0.4), C.BOUND, H, lift=(0.15, 0.2), knee=0.9, hock=0.9, fet=(0.8, 0.8),
                  bob=(0.12, 1, 0.6), pitch=(0.12, 1, 0.55), nod=(0.05, 1, 0.5), lumbar=0.15, reach=(0.05, 0.1)),
    "bound": C.gait(0.22, 1.4, (0.16, 0.15), C.BOUND, H, lift=(0.3, 0.35), knee=1.4, hock=1.3, fet=(1.0, 1.0),
                    bob=(0.08, 1, 0.65), pitch=(0.12, 1, 0.55), nod=(0.06, 1, 0.5), lumbar=0.35, reach=(0.0, 0.0)),
}
GAIT_TYPES = {"hop": "bound", "bound": "bound"}
META = {"run_gait": "bound", "walk_gait": "hop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": False, "graze_neck": (-0.4, -0.2, -0.1, -0.05, 0.3), "alert_tail": 0.0,
                         "tail_wag": 0.05, "drop": 0.2, "lie": 0.35})
