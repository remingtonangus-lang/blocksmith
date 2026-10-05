"""Red fox (scaled from the wolf template). Reference: shoulder height ~0.4 m, nose to rump ~0.7 m, relatively short
legs with black "stockings", long body, narrow muzzle, big ears, very bushy white-tipped tail ~0.42 m. Gaits: walk,
trot, rotary gallop."""
import numpy as np

from species import common as C
from species import wolf as W

V = C.V
NAME = "fox"
H = 0.4
J, B = C.scaled(W.J, W.B, H / 0.8, ky=1.12)
B["leg_r"] = tuple(r * 0.95 for r in B["leg_r"])
B["head"] = [(u, d * (0.92 if u > 0.4 else 1.0), hw * (0.88 if u > 0.4 else 1.0), nt, nb) for u, d, hw, nt, nb in B["head"]]
# the body stretch (ky) must not stretch the face: a fox's muzzle is fine but not needle-long
_P = B["poll"].copy()
_k = 0.8
B["nose"] = _P + (B["nose"] - _P) * _k
_j0, _j1, _r0, _r1, _sx = B["jaw"]
B["jaw"] = (_P + (_j0 - _P) * _k, _P + (_j1 - _P) * _k, _r0, _r1, _sx)
B["eye"] = tuple(_P + (np.array(B["eye"]) - _P) * 0.95)
J["jaw"] = _P + (J["jaw"] - _P) * _k
J["jaw_t"] = _P + (J["jaw_t"] - _P) * _k
J["ear_t"] = J["ear"] + (J["ear_t"] - J["ear"]) * 1.3
B["ear_w"] *= 1.3
B["tail_len"] = 0.42
B["tail_r"] = [r * 1.55 for r in B["tail_r"]]
B["tail_angle0"] = -25.0
B["tail_angle1"] = -60.0
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.12)
CONFIG = dict(W.CONFIG, eyes=(B["eye"], B["eye_r"]), bbox=((-0.14, -0.95, -0.005), (0.14, 0.58, 0.62)), tris=11000,
              lods=(3500, 900), withers=H, scale=B["scale"], length=0.75, voxel=(0.002, 0.0038))


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = W.gaits(H, walk=(0.7, 0.75), trot=(0.38, 1.3), gallop=(0.26, 2.2), gallop_duty=(0.15, 0.16))
GAIT_TYPES = W.GAIT_TYPES
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": True, "graze_neck": (-0.75, -0.3, -0.15, -0.05, 0.35), "alert_tail": 0.1,
                         "flee_tail": -0.2, "tail_wag": 0.2, "drop": 0.3, "lie": 0.5})
