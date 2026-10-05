"""Raccoon (scaled and reshaped from the bear: plantigrade). Reference: shoulder ~0.3 m with the hips higher
(hunched back), body ~0.55 m plus a bushy ringed tail ~0.25 m, pointed snout, small rounded ears, black mask, hand-like
front paws. Gaits: walk, trot, rotary gallop (bounding run)."""
from species import common as C
from species import black_bear as BB
from species import wolf as W

V = C.V
NAME = "raccoon"
H = 0.3
J, B = C.scaled(BB.J, BB.B, H / 0.9, ky=1.0)
B["family"] = "procyonid"
B["top"] = [(y, z * (1.18 if y < -0.05 * 0.33 else 1.0)) for y, z in B["top"]]       # hunched: hips higher
B["width"] = [(y, w * 0.85) for y, w in B["width"]]
B["head"] = [(u, d * (0.8 if u > 0.4 else 0.95), hw * (0.7 if u > 0.4 else 0.95), nt, nb) for u, d, hw, nt, nb in B["head"]]
B["tail_len"] = 0.27
B["tail_r"] = [0.022, 0.03, 0.033, 0.033, 0.03, 0.026, 0.016]
B["tail_angle0"] = -15.0
B["tail_angle1"] = -45.0
B["tail_base"] = B["tail_base"] + V(0, 0, 0.04)
J["hip"] = J["hip"] + V(0, 0, 0.035)
C.spine_landmarks(J, B)
C.tail_points(J, B)
BONES = C.make_bones(J, root_len=0.08)
CONFIG = {"coat_material": "animal_coat", "eyes": (B["eye"], B["eye_r"]), "bbox": ((-0.13, -0.6, -0.005), (0.13, 0.36, 0.42)),
          "tris": 9000, "lods": (3000, 800), "actions": "generic", "withers": H, "scale": B["scale"], "length": 0.8,
          "voxel": (0.0016, 0.003)}


def build_prims(Q):
    return C.build_prims(Q, J, B)


GAITS = {
    "walk": C.gait(0.7, 0.45, (0.65, 0.65), C.WALK, H, lift=(0.1, 0.09), knee=0.9, hock=0.6),
    "trot": C.gait(0.4, 0.75, (0.45, 0.45), C.TROT, H, lift=(0.14, 0.12), knee=1.2, hock=0.8, fet=(1.0, 0.9),
                   bob=(0.03, 2, 0.21), reach=(0.03, 0.02)),
    "gallop": C.gait(0.3, 1.6, (0.28, 0.3), C.GALLOP_ROTARY, H, lift=(0.2, 0.18), knee=1.5, hock=1.0, fet=(1.2, 1.0),
                     bob=(0.06, 1, 0.3), pitch=(0.08, 1, 0.05), lumbar=0.25, reach=(0.1, 0.08)),
}
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "gallop": "gallop_rotary"}
META = {"run_gait": "gallop"}


def actions(Q):
    return C.actions(Q, {"H": H, "predator": False, "graze_neck": (-0.6, -0.25, -0.12, -0.05, 0.35), "alert_tail": 0.0,
                         "tail_wag": 0.15, "drop": 0.25, "lie": 0.42})
