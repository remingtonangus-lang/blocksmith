"""American black bear (ursid, plantigrade). Reference: shoulder height ~0.9 m, nose to rump ~1.6 m, heavy round
body, rump about as high as the shoulders, short thick neck, round head ~0.33 m with a straight tan muzzle and small
round ears, thick legs, long flat hind feet (~0.2 m), short claws, tiny tail. Gaits: walk, (amble-like) trot and a
rotary gallop; attack rears up into a swipe."""
import numpy as np

from species import common as C
from species import wolf as W

V = C.V
NAME = "black_bear"
H = 0.9
S = H / 1.555
B = {
    "family": "ursid", "scale": S,
    "y_rear": -0.62, "y_front": 0.55,
    "top": [(-0.62, 0.70), (-0.54, 0.84), (-0.40, 0.90), (-0.2, 0.88), (0.0, 0.87), (0.2, 0.89), (0.36, 0.90),
            (0.47, 0.80), (0.55, 0.66)],
    "bottom": [(-0.62, 0.52), (-0.52, 0.44), (-0.36, 0.40), (-0.15, 0.37), (0.05, 0.36), (0.22, 0.37), (0.38, 0.41),
               (0.48, 0.46), (0.55, 0.52)],
    "width": [(-0.62, 0.06), (-0.52, 0.18), (-0.38, 0.22), (-0.15, 0.235), (0.05, 0.24), (0.22, 0.23), (0.38, 0.2),
              (0.48, 0.15), (0.55, 0.07)],
    "ntop": [(-0.62, 2.4), (0.55, 2.4)], "nbot": [(-0.62, 2.1), (0.55, 2.2)],
    "neck": [((0.34, 0.88), (0.50, 0.52), 0.15), ((0.44, 0.88), (0.58, 0.60), 0.13), ((0.52, 0.88), (0.63, 0.66), 0.115),
             ((0.58, 0.88), (0.67, 0.71), 0.105), ((0.62, 0.885), (0.70, 0.74), 0.1)],
    "neck_pinch": 0.15,
    "poll": V(0, 0.64, 0.90), "nose": V(0, 0.92, 0.74),
    "atlas_off": V(0, 0.02, -0.07),
    "head": [(-0.04, 0.18, 0.085, 2.3, 2.0), (0.12, 0.21, 0.11, 2.5, 2.1), (0.3, 0.18, 0.105, 2.6, 2.2),
             (0.48, 0.145, 0.085, 2.5, 2.2), (0.66, 0.122, 0.072, 2.4, 2.2), (0.84, 0.108, 0.064, 2.3, 2.2),
             (0.96, 0.098, 0.058, 2.2, 2.2), (1.0, 0.075, 0.045, 2.0, 2.0)],
    "jaw": (V(0, 0.66, 0.79), V(0, 0.92, 0.70), 0.045, 0.028, 1.4),
    "eye": (0.06, 0.765, 0.86), "eye_r": 0.011, "eye_fwd": 0.5, "teeth": True,
    "ear_w": 0.042, "ear_t": 0.4,
    "leg_r": (0.085, 0.075, 0.052, 0.045, 0.045, 0.04),
    "hleg_r": (0.11, 0.2, 0.08, 0.05, 0.045, 0.045, 0.04),
    "foot": "plantigrade", "foot_r": (0.065, 0.065), "claws": True,
    "tail_base": V(0, -0.60, 0.70), "tail_len": 0.1, "tail_angle0": -40.0, "tail_angle1": -70.0,
    "tail_r": [0.04, 0.04, 0.035, 0.03, 0.025, 0.02, 0.012],
    "chest_x": 0.3, "pec": 0.7,
    "head_extra": [lambda Q, Pp, fd, zp, L, B_: W.snout(Q, Pp, fd, zp, L * 0.98, B_)],
}
J = {
    "ear": V(-0.075, 0.66, 0.955), "ear_t": V(-0.095, 0.66, 1.02),
    "scap": V(-0.1, 0.32, 0.80), "shoulder": V(-0.13, 0.46, 0.58), "elbow": V(-0.14, 0.30, 0.42),
    "knee": V(-0.13, 0.33, 0.12), "ffet": V(-0.125, 0.41, 0.04), "fcoffin": V(-0.125, 0.47, 0.025),
    "fsole": V(-0.125, 0.40, 0.0), "ftoe": V(-0.125, 0.49, 0.0),
    "hip": V(-0.13, -0.42, 0.74), "stifle": V(-0.15, -0.28, 0.46), "hock": V(-0.13, -0.50, 0.10),
    "hfet": V(-0.125, -0.32, 0.035), "hcoffin": V(-0.125, -0.27, 0.025), "hsole": V(-0.125, -0.38, 0.0),
    "htoe": V(-0.125, -0.25, 0.0),
    "jaw": V(0, 0.67, 0.79), "jaw_t": V(0, 0.91, 0.705),
}
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.25)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.36, -0.9, -0.005), (0.36, 1.05, 1.1)),
          "tris": 15000, "lods": (5000, 1200), "actions": "generic", "withers": H, "scale": S, "length": 1.6,
          "voxel": (0.0042, 0.0072)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(1.1, 1.3, (0.65, 0.65), C.WALK, H, lift=(0.08, 0.07), knee=0.9, hock=0.6, nod=(0.06, 2, 0.06)),
    "trot": C.gait(0.6, 2.0, (0.45, 0.45), C.TROT, H, lift=(0.12, 0.1), knee=1.2, hock=0.8, fet=(1.0, 0.9),
                   bob=(0.025, 2, 0.21), nod=(0.02, 2, 0.21), reach=(0.03, 0.02)),
    "gallop": C.gait(0.42, 4.0, (0.25, 0.27), C.GALLOP_ROTARY, H, lift=(0.18, 0.16), knee=1.6, hock=1.0,
                     fet=(1.2, 1.0), bob=(0.06, 1, 0.30), pitch=(0.07, 1, 0.05), nod=(0.08, 1, 0.05), lumbar=0.18,
                     tail=(0.0, 0.0), reach=(0.10, 0.08)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_rotary"}
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": False, "bear": True, "graze_neck": (-0.55, -0.25, -0.12, -0.05, 0.3),
                         "alert_tail": 0.0, "flee_tail": 0.0, "tail_wag": 0.0, "drop": 0.3, "lie": 0.45})
