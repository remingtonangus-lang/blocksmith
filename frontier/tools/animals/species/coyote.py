"""Coyote (scaled from the wolf template). Reference: shoulder height ~0.58 m, nose to rump ~1.0 m, slender legs,
narrow pointed muzzle, large ears (~0.1 m), bushy black-tipped tail carried low (~0.35 m). Gaits: walk, trot, rotary
gallop."""
from species import common as C
from species import wolf as W

V = C.V
NAME = "coyote"
H = 0.58
J, B = C.scaled(W.J, W.B, H / 0.8, ky=1.02)
B["width"] = [(y, w * 0.9) for y, w in B["width"]]
B["leg_r"] = tuple(r * 0.9 for r in B["leg_r"])
B["hleg_r"] = tuple(r * 0.9 for r in B["hleg_r"])
B["head"] = [(u, d * (0.95 if u > 0.4 else 1.0), hw * (0.88 if u > 0.4 else 0.95), nt, nb) for u, d, hw, nt, nb in B["head"]]
J["ear_t"] = J["ear"] + (J["ear_t"] - J["ear"]) * 1.25
B["ear_w"] *= 1.15
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.16)
CONFIG = dict(W.CONFIG, eyes=(B["eye"], B["eye_r"]), bbox=((-0.17, -0.95, -0.005), (0.17, 0.72, 0.9)), tris=12000,
              lods=(4000, 1000), withers=H, scale=B["scale"], length=1.0, voxel=(0.0026, 0.0048))


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = W.gaits(H, walk=(0.8, 1.05), trot=(0.45, 1.75), gallop=(0.3, 2.9), gallop_duty=(0.15, 0.16))
GAIT_TYPES = W.GAIT_TYPES
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": True, "graze_neck": (-0.75, -0.3, -0.15, -0.05, 0.35), "alert_tail": 0.2,
                         "flee_tail": -0.3, "tail_wag": 0.25, "drop": 0.3, "lie": 0.48})
