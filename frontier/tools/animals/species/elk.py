"""Elk / wapiti (bull; antlers hidden for cows). Reference: shoulder height ~1.5 m, body ~1.6 m point of shoulder to
buttock (2.4 m nose to rump), deep chest (~0.7 m), long heavy head ~0.55 m, small ears for its size, dark shaggy
neck mane, pale straw rump patch and a short tail, antlers with long beams swept back and 6 tines a side (~1.2 m
beams). Gaits: walk, trot, transverse gallop."""
import numpy as np

from species import common as C
from species import mule_deer as D

V = C.V
NAME = "elk"
H = 1.5
K = 1.5
J, B = C.scaled(D.J, D.B, K, ky=1.04)
B["family"] = "cervid"
# heavier, deeper body, thick maned neck, longer head, smaller ears
B["bottom"] = [(y, z - 0.06 * (1 if -0.5 < y < 0.6 else 0)) for y, z in B["bottom"]]
B["width"] = [(y, w * 1.12) for y, w in B["width"]]
B["neck"] = [((cy, cz), (uy, uz - 0.05), hw * 1.35) for (cy, cz), (uy, uz), hw in B["neck"]]
C.scale_head(J, B, 1.18)
C.move_head(J, B, V(0, 0.02, -0.06))
J["ear"] = J["ear"] + V(0, 0.0, 0.0)
J["ear_t"] = J["ear"] + (J["ear_t"] - J["ear"]) * 0.62 + V(0.0, -0.03, 0.03)
B["ear_w"] *= 0.68
B["leg_r"] = tuple(r * 1.12 for r in B["leg_r"])
B["hleg_r"] = tuple(r * 1.12 for r in B["hleg_r"])
B["tail_len"] = 0.12
B["tail_r"] = [0.04, 0.042, 0.04, 0.034, 0.028, 0.022, 0.014]
B["extra"] = [lambda Q, J_, B_: _mane(Q, J_, B_)]
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.45)
CONFIG = {"coat_material": "animal_coat", "eyes": (tuple(abs(c) for c in B["eye"]), B["eye_r"]),
          "bbox": ((-0.48, -1.3, -0.005), (0.48, 1.42, 2.6)), "tris": 20000, "lods": (6500, 1600), "actions": "generic",
          "withers": H, "scale": B["scale"], "length": 2.4, "voxel": (0.0058, 0.0095)}


def _mane(Q, J_, B_):
    """Shaggy throat mane: a hanging fringe under the neck."""
    s = B_["scale"]
    for (cy, cz), (uy, uz), hw in B_["neck"][:4]:
        Q.ell((0, uy - 0.01, uz - 0.035), (hw * 0.8, 0.09, 0.07), ["neck_1", "neck_2", "neck_3"], k=0.05 * s, mirror=False,
              axis=(0, 0.6, 0.8))


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(1.15, 1.6, (0.62, 0.62), C.WALK, H, lift=(0.1, 0.09), knee=1.0, hock=0.55, nod=(0.06, 2, 0.06)),
    "trot": C.gait(0.7, 2.7, (0.42, 0.42), C.TROT, H, lift=(0.15, 0.12), knee=1.45, hock=0.8, fet=(1.5, 1.3),
                   bob=(0.03, 2, 0.21), nod=(0.015, 2, 0.21), tail=(-0.2, 0.05), reach=(0.04, 0.02)),
    "gallop": C.gait(0.5, 5.2, (0.22, 0.24), C.GALLOP_TRANSVERSE, H, lift=(0.22, 0.2), knee=1.9, hock=1.0,
                     fet=(1.7, 1.5), bob=(0.06, 1, 0.30), pitch=(0.07, 1, 0.05), nod=(0.12, 1, 0.05), lumbar=0.1,
                     tail=(-0.5, 0.1), reach=(0.10, 0.06)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_transverse"}
META = {"run_gait": "gallop", "variants": {"cow": {"hide": ["Antlers"], "scale": 0.88}}}


def actions(Q):
    return C.actions(Q, {"H": H, "graze_neck": (-1.0, -0.42, -0.28, -0.14, 0.55), "alert_tail": -0.3})


def build_extras(Q, prims, arm):
    """6x6 bull antlers: long beams sweeping up and back, brow and bez tines forward, royal and crown tines up."""
    tubes = []
    poll = B["poll"]
    for sx in (-1.0, 1.0):
        base = V(sx * 0.06, poll[1] + 0.02, poll[2] + 0.03)
        beam = C.curve(base, V(sx * 0.45, -0.75, 0.75), 1.15, V(sx * -0.1, 0.45, 0.25), n=12)
        tubes.append(C.tube_branch(Q, beam, 0.03, 0.014, segs=8))
        for idx, L, d in ((1, 0.32, V(sx * 0.15, 1.0, 0.25)), (2, 0.28, V(sx * 0.2, 1.0, 0.45)),
                          (5, 0.3, V(sx * 0.15, 0.6, 1.0)), (7, 0.26, V(sx * 0.2, 0.45, 1.0)), (9, 0.2, V(sx * 0.25, 0.2, 1.0))):
            t = C.curve(beam[idx], d, L, V(0, -0.4, 0.8), n=5)
            tubes.append(C.tube_branch(Q, t, 0.017, 0.003, segs=6))
        tubes.append(Q.tube_mesh(np.array([base - V(0, 0, 0.015), base + V(0, 0, 0.02)]), 0.038, segs=8))
    C.emit_tubes(Q, arm, "Antlers", tubes, (0.40, 0.32, 0.22, 1), rough=0.75)
