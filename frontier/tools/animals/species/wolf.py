"""Grey wolf (canid template; coyote and fox are scaled from it). Reference: shoulder height ~0.8 m, nose to rump
~1.3 m (body ~0.95 m point of shoulder to buttock), deep narrow chest (~0.36 m), long legs, digitigrade feet with
large paws (~0.11 m), head ~0.27 m with a long muzzle and pointed upright ears (~0.11 m), bushy tail ~0.45 m hanging
to the hocks. Gaits: walk, trot (the travelling gait), rotary gallop."""
import numpy as np

from species import common as C

V = C.V
NAME = "wolf"
H = 0.8
S = H / 1.555
B = {
    "family": "canid", "scale": S,
    "y_rear": -0.55, "y_front": 0.50,
    "top": [(-0.55, 0.64), (-0.48, 0.73), (-0.36, 0.765), (-0.2, 0.755), (0.0, 0.765), (0.2, 0.79), (0.33, 0.80),
            (0.44, 0.72), (0.50, 0.60)],
    "bottom": [(-0.55, 0.56), (-0.46, 0.53), (-0.32, 0.53), (-0.15, 0.50), (0.02, 0.46), (0.2, 0.43), (0.34, 0.45),
               (0.44, 0.50), (0.50, 0.54)],
    "width": [(-0.55, 0.04), (-0.45, 0.085), (-0.32, 0.095), (-0.12, 0.10), (0.05, 0.115), (0.22, 0.12), (0.36, 0.10),
              (0.45, 0.075), (0.50, 0.04)],
    "ntop": [(-0.55, 2.4), (0.5, 2.3)], "nbot": [(-0.55, 2.0), (0.5, 2.2)],
    "neck": [((0.30, 0.80), (0.46, 0.55), 0.09), ((0.40, 0.85), (0.54, 0.65), 0.085), ((0.48, 0.90), (0.60, 0.74), 0.08),
             ((0.54, 0.935), (0.635, 0.80), 0.072), ((0.585, 0.955), (0.655, 0.845), 0.062)],
    "neck_pinch": 0.25,
    "poll": V(0, 0.585, 0.965), "nose": V(0, 0.84, 0.87),
    "atlas_off": V(0, 0.03, -0.07),
    "head": [(-0.02, 0.12, 0.055, 2.2, 2.0), (0.12, 0.135, 0.076, 2.7, 2.1), (0.3, 0.115, 0.072, 3.0, 2.2),
             (0.45, 0.082, 0.046, 2.6, 2.2), (0.62, 0.07, 0.037, 2.4, 2.2), (0.8, 0.064, 0.034, 2.3, 2.2),
             (0.94, 0.058, 0.032, 2.2, 2.2), (1.0, 0.045, 0.025, 2.0, 2.0)],
    "jaw": (V(0, 0.60, 0.89), V(0, 0.835, 0.83), 0.028, 0.016, 1.35),
    "eye": (0.047, 0.675, 0.905), "eye_r": 0.0105,
    "ear_w": 0.033, "ear_t": 0.38,
    "leg_r": (0.042, 0.034, 0.02, 0.016, 0.017, 0.016),
    "hleg_r": (0.06, 0.12, 0.04, 0.02, 0.016, 0.017, 0.016),
    "foot": "paw", "foot_r": (0.042, 0.038), "claws": True,
    "tail_base": V(0, -0.53, 0.70), "tail_len": 0.46, "tail_angle0": -40.0, "tail_angle1": -82.0,
    "tail_r": [0.035, 0.05, 0.058, 0.058, 0.052, 0.04, 0.018],
    "chest_x": 0.35, "pec": 0.55,
    "head_extra": [lambda Q, Pp, fd, zp, L, B_: snout(Q, Pp, fd, zp, L, B_)],
}
J = {
    "ear": V(-0.048, 0.60, 0.97), "ear_t": V(-0.066, 0.615, 1.05),
    "scap": V(-0.05, 0.30, 0.74), "shoulder": V(-0.075, 0.44, 0.565), "elbow": V(-0.08, 0.31, 0.44),
    "knee": V(-0.07, 0.33, 0.17), "ffet": V(-0.068, 0.355, 0.045), "fcoffin": V(-0.068, 0.405, 0.02),
    "fsole": V(-0.068, 0.385, 0.0), "ftoe": V(-0.068, 0.425, 0.0),
    "hip": V(-0.07, -0.40, 0.67), "stifle": V(-0.085, -0.28, 0.45), "hock": V(-0.07, -0.49, 0.21),
    "hfet": V(-0.066, -0.45, 0.045), "hcoffin": V(-0.066, -0.40, 0.02), "hsole": V(-0.066, -0.42, 0.0),
    "htoe": V(-0.066, -0.38, 0.0),
    "jaw": V(0, 0.61, 0.89), "jaw_t": V(0, 0.83, 0.835),
}


def snout(Q, Pp, fd, zp, L, B_):
    """Carnivore nose pad (leather) at the muzzle tip, with nostrils."""
    k = L / 0.3
    nose = Pp + fd * L
    Q.ell(tuple(nose - fd * 0.006 * k + zp * 0.006 * k), (0.016 * k, 0.013 * k, 0.012 * k), ["head"], k=0.008 * k, mirror=False)
    Q.ell((-0.008 * k, nose[1] + 0.012 * k, nose[2] + 0.009 * k), (0.005 * k, 0.007 * k, 0.005 * k), ["head"], k=0.003 * k,
          op="s")


C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.22)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.22, -1.25, -0.005), (0.22, 0.95, 1.15)),
          "tris": 14000, "lods": (4500, 1100), "actions": "generic", "withers": H, "scale": S, "length": 1.3,
          "voxel": (0.0034, 0.006)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


def gaits(H, walk=(0.95, 1.3), trot=(0.55, 2.3), gallop=(0.36, 4.2)):
    return {
        "walk": C.gait(walk[0], walk[1], (0.62, 0.62), C.WALK, H, lift=(0.09, 0.08), knee=1.0, hock=0.6,
                       nod=(0.05, 2, 0.06), tail=(0.1, 0.06)),
        "trot": C.gait(trot[0], trot[1], (0.44, 0.44), C.TROT, H, lift=(0.13, 0.11), knee=1.4, hock=0.9, fet=(1.3, 1.1),
                       bob=(0.02, 2, 0.21), nod=(0.01, 2, 0.21), tail=(0.15, 0.04), reach=(0.03, 0.02)),
        "gallop": C.gait(gallop[0], gallop[1], (0.2, 0.22), C.GALLOP_ROTARY, H, lift=(0.2, 0.18), knee=1.8, hock=1.1,
                         fet=(1.4, 1.2), bob=(0.05, 1, 0.30), pitch=(0.06, 1, 0.05), nod=(0.08, 1, 0.05), lumbar=0.22,
                         tail=(-0.2, 0.08), reach=(0.10, 0.08)),
    }


GAITS = gaits(H)
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_rotary"}
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": True, "graze_neck": (-0.75, -0.3, -0.15, -0.05, 0.35), "alert_tail": 0.3,
                         "flee_tail": -0.3, "tail_wag": 0.25, "drop": 0.3, "lie": 0.48})
