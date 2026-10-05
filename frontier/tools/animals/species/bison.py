"""American bison (bull). Reference: ~1.8 m at the hump, hips ~1.45 m, ~3.0 m nose to rump (body ~2.0 m), very deep
chest (~1.05 m) on short legs, massive head ~0.55 m carried low with a near-vertical forehead, short upcurved black
horns, shaggy cape over the head, hump and forelegs, beard; thin tail ~0.55 m with a tuft. Gaits: walk, trot,
transverse gallop."""
import numpy as np

from species import common as C

V = C.V
NAME = "bison"
H = 1.8
S = H / 1.555
B = {
    "family": "bovid", "scale": S,
    "y_rear": -0.95, "y_front": 0.88,
    "top": [(-0.95, 1.22), (-0.85, 1.38), (-0.6, 1.45), (-0.3, 1.47), (0.0, 1.55), (0.3, 1.74), (0.48, 1.80),
            (0.68, 1.66), (0.88, 1.30)],
    "bottom": [(-0.95, 1.04), (-0.8, 0.95), (-0.5, 0.86), (-0.2, 0.79), (0.1, 0.73), (0.4, 0.71), (0.66, 0.76),
               (0.88, 0.88)],
    "width": [(-0.95, 0.08), (-0.8, 0.24), (-0.5, 0.29), (-0.2, 0.36), (0.1, 0.41), (0.4, 0.41), (0.66, 0.35),
              (0.88, 0.18)],
    "ntop": [(-0.95, 2.4), (0.88, 2.5)], "nbot": [(-0.95, 2.1), (0.88, 2.2)],
    "pinch": [(-0.95, 0.15), (0.3, 0.35), (0.88, 0.3)],
    "neck": [((0.70, 1.60), (0.86, 0.92), 0.25), ((0.80, 1.52), (0.94, 0.98), 0.24), ((0.88, 1.44), (1.0, 1.04), 0.23),
             ((0.94, 1.38), (1.04, 1.08), 0.22), ((0.98, 1.33), (1.06, 1.12), 0.21)],
    "neck_pinch": 0.2,
    "poll": V(0, 0.99, 1.34), "nose": V(0, 1.19, 0.83),
    "atlas_off": V(0, -0.03, -0.1),
    "head": [(-0.04, 0.36, 0.17, 2.4, 2.0), (0.12, 0.42, 0.20, 2.8, 2.1), (0.32, 0.38, 0.19, 3.0, 2.2),
             (0.52, 0.30, 0.15, 2.8, 2.2), (0.72, 0.25, 0.125, 2.6, 2.2), (0.9, 0.22, 0.115, 2.4, 2.2),
             (1.0, 0.16, 0.09, 2.0, 2.0)],
    "jaw": (V(0, 0.92, 1.12), V(0, 1.10, 0.80), 0.08, 0.05, 1.3),
    "eye": (0.155, 1.06, 1.18), "eye_r": 0.022,
    "ear_w": 0.045, "ear_t": 0.35,
    "leg_r": (0.13, 0.11, 0.065, 0.046, 0.05, 0.045),
    "hleg_r": (0.15, 0.3, 0.1, 0.055, 0.045, 0.05, 0.045),
    "foot": "cloven", "foot_r": (0.075, 0.07),
    "tail_base": V(0, -0.93, 1.28), "tail_len": 0.58, "tail_angle0": -70.0, "tail_angle1": -88.0,
    "tail_r": [0.04, 0.03, 0.025, 0.022, 0.022, 0.04, 0.05],
    "chest_x": 0.4, "pec": 0.9,
    "extra": [lambda Q, J_, B_: _shag(Q, J_, B_)],
}
J = {
    "ear": V(-0.2, 1.04, 1.25), "ear_t": V(-0.29, 1.02, 1.21),
    "scap": V(-0.15, 0.40, 1.55), "shoulder": V(-0.21, 0.70, 1.06), "elbow": V(-0.22, 0.48, 0.80),
    "knee": V(-0.2, 0.50, 0.42), "ffet": V(-0.19, 0.51, 0.14), "fcoffin": V(-0.19, 0.57, 0.06),
    "fsole": V(-0.19, 0.59, 0.0), "ftoe": V(-0.19, 0.67, 0.0),
    "hip": V(-0.2, -0.70, 1.22), "stifle": V(-0.23, -0.48, 0.88), "hock": V(-0.17, -0.85, 0.55),
    "hfet": V(-0.165, -0.83, 0.14), "hcoffin": V(-0.165, -0.77, 0.06), "hsole": V(-0.165, -0.75, 0.0),
    "htoe": V(-0.165, -0.68, 0.0),
    "jaw": V(0, 0.93, 1.12), "jaw_t": V(0, 1.10, 0.81),
}


def _shag(Q, J_, B_):
    """Shaggy cape: woolly mass over the forehead and poll, the beard, and the long hair on the forelegs."""
    s = B_["scale"]
    poll = B_["poll"]
    Q.ell((0, poll[1] + 0.03, poll[2] + 0.02), (0.24, 0.18, 0.16), ["head"], k=0.08 * s, mirror=False)        # topknot
    Q.ell((0, 1.02, 0.86), (0.09, 0.16, 0.2), ["jaw", "head"], k=0.06 * s, mirror=False, axis=(0, 0.3, -1))   # beard
    Q.ell((0, 0.86, 0.86), (0.14, 0.16, 0.2), ["neck_1", "spine_withers"], k=0.08 * s, mirror=False)        # dewlap mane
    for dz in (0.0,):
        Q.rc((-0.22, 0.47, 0.80), (-0.21, 0.49, 0.50), 0.12, 0.08, ["forearm_L"], k=0.05 * s)                   # leg chaps


C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.5)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.62, -1.62, -0.005), (0.62, 1.42, 1.98)),
          "tris": 20000, "lods": (6500, 1600), "actions": "generic", "withers": H, "scale": S, "length": 3.0,
          "voxel": (0.0072, 0.012)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(1.3, 1.4, (0.65, 0.65), C.WALK, H, lift=(0.07, 0.06), knee=0.9, hock=0.5, nod=(0.05, 2, 0.06)),
    "trot": C.gait(0.75, 2.6, (0.45, 0.45), C.TROT, H, lift=(0.1, 0.09), knee=1.3, hock=0.7, fet=(1.2, 1.0),
                   bob=(0.02, 2, 0.21), nod=(0.01, 2, 0.21), reach=(0.03, 0.02)),
    "gallop": C.gait(0.55, 5.5, (0.26, 0.28), C.GALLOP_TRANSVERSE, H, lift=(0.15, 0.13), knee=1.6, hock=0.9,
                     fet=(1.4, 1.2), bob=(0.04, 1, 0.30), pitch=(0.05, 1, 0.05), nod=(0.06, 1, 0.05), lumbar=0.06,
                     tail=(-0.6, 0.15), reach=(0.08, 0.05)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_transverse"}
META = {"run_gait": "gallop", "variants": {"cow": {"hide": [], "scale": 0.86}}}


def actions(Q):
    return C.actions(Q, {"H": H, "graze_neck": (-0.45, -0.2, -0.12, -0.06, 0.3), "alert_tail": -0.6, "drop": 0.28, "lie": 0.36})


def build_extras(Q, prims, arm):
    """Short black horns: out sideways from the skull, curving up and slightly in."""
    tubes = []
    poll = B["poll"]
    for sx in (-1.0, 1.0):
        base = V(sx * 0.17, poll[1] + 0.02, poll[2] - 0.06)
        horn = C.curve(base, V(sx * 1.0, 0.1, 0.2), 0.3, V(sx * -2.4, 0.4, 3.6), n=7)
        tubes.append(C.tube_branch(Q, horn, 0.04, 0.006, segs=8))
    C.emit_tubes(Q, arm, "Horns", tubes, (0.05, 0.045, 0.04, 1), rough=0.4)
