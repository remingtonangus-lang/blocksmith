"""Pronghorn. Reference: shoulder height ~0.87 m, body ~1.3 m nose to rump, very slender long legs, large eyes set
high, medium ears, short black horns with a forward prong (~0.3 m), tan body with white belly, flanks, rump patch and
two white throat bands. The fastest runner in the West (transverse gallop, ~17 m/s in bursts)."""
import numpy as np

from species import common as C
from species import mule_deer as D

V = C.V
NAME = "pronghorn"
H = 0.87
J, B = C.scaled(D.J, D.B, 0.87, ky=1.0)
B["family"] = "bovid"
B["width"] = [(y, w * 0.95) for y, w in B["width"]]
B["leg_r"] = tuple(r * 0.88 for r in B["leg_r"])
B["hleg_r"] = tuple(r * 0.9 for r in B["hleg_r"])
J["ear_t"] = J["ear"] + (J["ear_t"] - J["ear"]) * 0.72 + V(0.02, 0.0, 0.03)
B["ear_w"] *= 0.7
B["eye_r"] *= 1.25
B["tail_len"] = 0.1
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.26)
CONFIG = {"coat_material": "animal_coat", "eyes": (tuple(abs(c) for c in B["eye"]), B["eye_r"]),
          "bbox": ((-0.28, -0.75, -0.005), (0.28, 0.76, 1.6)), "tris": 15000, "lods": (5000, 1200), "actions": "generic",
          "withers": H, "scale": B["scale"], "length": 1.35, "voxel": (0.0038, 0.0065)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(0.85, 1.2, (0.62, 0.62), C.WALK, H, lift=(0.1, 0.09), knee=1.0, hock=0.55),
    "trot": C.gait(0.5, 1.9, (0.42, 0.42), C.TROT, H, lift=(0.15, 0.12), knee=1.5, hock=0.8, fet=(1.5, 1.3),
                   bob=(0.03, 2, 0.21), nod=(0.015, 2, 0.21), reach=(0.04, 0.02)),
    "gallop": C.gait(0.38, 4.9, (0.2, 0.22), C.GALLOP_TRANSVERSE, H, lift=(0.24, 0.21), knee=2.0, hock=1.0,
                     fet=(1.8, 1.6), bob=(0.06, 1, 0.30), pitch=(0.07, 1, 0.05), nod=(0.08, 1, 0.05), lumbar=0.12,
                     tail=(-0.6, 0.1), reach=(0.10, 0.06)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_transverse"}
META = {"run_gait": "gallop", "variants": {"doe": {"hide": [], "scale": 0.94}}}


def actions(Q):
    return C.actions(Q, {"H": H, "graze_neck": (-1.0, -0.42, -0.28, -0.14, 0.58), "alert_tail": -0.6})


def build_extras(Q, prims, arm):
    """Short black horns: rise straight up from above the eyes, a forward prong halfway, tips hook back and in."""
    tubes = []
    poll = B["poll"]
    for sx in (-1.0, 1.0):
        base = V(sx * 0.035, poll[1] + 0.025, poll[2] - 0.005)
        horn = C.curve(base, V(sx * 0.12, 0.05, 1.0), 0.24, V(sx * -0.6, -1.6, 0.0), n=7)
        tubes.append(C.tube_branch(Q, horn, 0.016, 0.004, segs=7))
        prong = C.curve(horn[3], V(sx * 0.05, 1.0, 0.35), 0.06, V(0, 0, 1.5), n=3)
        tubes.append(C.tube_branch(Q, prong, 0.008, 0.002, segs=5))
    C.emit_tubes(Q, arm, "Horns", tubes, (0.06, 0.05, 0.045, 1), rough=0.45)
