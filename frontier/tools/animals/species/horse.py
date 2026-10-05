"""Horse (15.2 hh stock horse) for the quadruped generator: landmarks, bones, SDF anatomy and gait tables.
Built with `python3 frontier/tools/animals/quadruped.py --species horse` (or horse_gen.py)."""
import math

import numpy as np


def V(*a):
    return np.array(a, dtype=np.float64)


NAME = "horse"
CONFIG = {
    "coat_material": "horse_coat", "hair": "horse", "tack": True, "eyes": ((0.088, 1.217, 1.795), 0.0195),
    "bbox": ((-0.42, -1.12, -0.005), (0.42, 1.66, 2.20)), "tris": 26000, "lods": (8000, 2000),
    "actions": "horse", "withers": 1.555, "scale": 1.0, "length": 2.0, "saddle_bone": "spine_thorax",
}

J = {
    # trunk / spine (vertebral column, inside the body)
    "body": V(0, -0.10, 1.27), "body_t": V(0, 0.16, 1.28),
    "lumbar_t": V(0, -0.42, 1.35),
    "pelvis_t": V(0, -0.80, 1.36),
    "thorax_t": V(0, 0.46, 1.33),
    "withers_t": V(0, 0.74, 1.30),
    "neck1_t": V(0, 0.88, 1.43), "neck2_t": V(0, 1.00, 1.57), "neck3_t": V(0, 1.10, 1.72), "neck4_t": V(0, 1.155, 1.86),
    "head_t": V(0, 1.46, 1.475),
    "jaw": V(0, 1.16, 1.76), "jaw_t": V(0, 1.43, 1.42),
    "ear": V(-0.056, 1.11, 1.965), "ear_t": V(-0.082, 1.145, 2.115),
    "tail0": V(0, -0.80, 1.40), "tail1": V(0, -0.875, 1.335), "tail2": V(0, -0.925, 1.245), "tail3": V(0, -0.955, 1.15),
    "tail4": V(0, -0.972, 1.055), "tail5": V(0, -0.982, 0.965), "tail6": V(0, -0.988, 0.88),
    # fore leg (left)
    "scap": V(-0.115, 0.42, 1.43), "shoulder": V(-0.165, 0.705, 1.125), "elbow": V(-0.17, 0.47, 0.885),
    "knee": V(-0.142, 0.49, 0.50), "ffet": V(-0.135, 0.495, 0.165), "fcoffin": V(-0.135, 0.565, 0.058),
    "fsole": V(-0.135, 0.575, 0.0), "ftoe": V(-0.135, 0.64, 0.0),
    # hind leg (left)
    "hip": V(-0.20, -0.62, 1.28), "stifle": V(-0.205, -0.40, 0.985), "hock": V(-0.145, -0.755, 0.56),
    "hfet": V(-0.135, -0.74, 0.17), "hcoffin": V(-0.135, -0.685, 0.058),
    "hsole": V(-0.135, -0.678, 0.0), "htoe": V(-0.135, -0.615, 0.0),
}

# Bones: name -> (head, tail, parent, deform). Left legs listed; mirrored with _R.
BONES = [
    ("root", V(0, 0, 0), V(0, 0.4, 0), None),
    ("body", J["body"], J["body_t"], "root"),
    ("spine_lumbar", J["body"] + V(0, 0, 0.02), J["lumbar_t"], "body"),
    ("pelvis", J["lumbar_t"], J["pelvis_t"], "spine_lumbar"),
    ("tail_1", J["tail0"], J["tail1"], "pelvis"),
    ("tail_2", J["tail1"], J["tail2"], "tail_1"),
    ("tail_3", J["tail2"], J["tail3"], "tail_2"),
    ("tail_4", J["tail3"], J["tail4"], "tail_3"),
    ("tail_5", J["tail4"], J["tail5"], "tail_4"),
    ("tail_6", J["tail5"], J["tail6"], "tail_5"),
    ("spine_thorax", J["body_t"], J["thorax_t"], "body"),
    ("spine_withers", J["thorax_t"], J["withers_t"], "spine_thorax"),
    ("neck_1", J["withers_t"], J["neck1_t"], "spine_withers"),
    ("neck_2", J["neck1_t"], J["neck2_t"], "neck_1"),
    ("neck_3", J["neck2_t"], J["neck3_t"], "neck_2"),
    ("neck_4", J["neck3_t"], J["neck4_t"], "neck_3"),
    ("head", J["neck4_t"], J["head_t"], "neck_4"),
    ("jaw", J["jaw"], J["jaw_t"], "head"),
    ("ear_L", J["ear"], J["ear_t"], "head"),
    ("scapula_L", J["scap"], J["shoulder"], "spine_withers"),
    ("humerus_L", J["shoulder"], J["elbow"], "scapula_L"),
    ("forearm_L", J["elbow"], J["knee"], "humerus_L"),
    ("fcannon_L", J["knee"], J["ffet"], "forearm_L"),
    ("fpastern_L", J["ffet"], J["fcoffin"], "fcannon_L"),
    ("fhoof_L", J["fcoffin"], J["ftoe"] + V(0, 0, 0.0), "fpastern_L"),
    ("femur_L", J["hip"], J["stifle"], "pelvis"),
    ("tibia_L", J["stifle"], J["hock"], "femur_L"),
    ("hcannon_L", J["hock"], J["hfet"], "tibia_L"),
    ("hpastern_L", J["hfet"], J["hcoffin"], "hcannon_L"),
    ("hhoof_L", J["hcoffin"], J["htoe"], "hpastern_L"),
]



def build_prims(Q):
    Q.PRIMS.clear()
    # ---------------- trunk: side profile (top line / under line) and half widths, buttock -> chest
    T = [  # y, top z, bottom z, half width, n_top, n_bot, top pinch
        (-0.90, 1.33, 1.17, 0.07, 2.2, 2.2, 0.0),
        (-0.84, 1.42, 1.11, 0.15, 2.4, 2.2, 0.1),
        (-0.72, 1.495, 1.06, 0.22, 3.0, 2.3, 0.12),
        (-0.56, 1.535, 1.01, 0.25, 3.4, 2.3, 0.15),
        (-0.40, 1.505, 0.90, 0.27, 3.2, 2.2, 0.15),
        (-0.20, 1.48, 0.81, 0.29, 2.8, 2.1, 0.15),
        (0.02, 1.47, 0.775, 0.305, 2.6, 2.1, 0.15),
        (0.24, 1.495, 0.78, 0.285, 2.5, 2.1, 0.25),
        (0.42, 1.52, 0.80, 0.245, 2.4, 2.1, 0.4),
        (0.60, 1.47, 0.88, 0.215, 2.4, 2.2, 0.45),
        (0.74, 1.36, 0.99, 0.18, 2.3, 2.3, 0.3),
        (0.82, 1.24, 1.04, 0.13, 2.2, 2.2, 0.2),
        (0.87, 1.19, 1.07, 0.07, 2.0, 2.0, 0.0),
    ]
    stations = [((0, y, 0.5 * (t + b)), hw, 0.5 * (t - b), nt, nb, pt) for (y, t, b, hw, nt, nb, pt) in T]
    Q.loft(stations, ["pelvis", "spine_lumbar", "body", "spine_thorax", "spine_withers"], k=0.05)
    Q.rc((0, 0.62, 1.545), (0, 0.22, 1.505), 0.045, 0.05, ["spine_withers", "spine_thorax"], k=0.08, mirror=False, sx=1.3)  # withers ridge
    # ---------------- neck: crest / throat profile, half widths, withers -> poll
    N = [  # crest (y, z), under (y, z), half width
        ((0.50, 1.56), (0.75, 1.12), 0.185),
        ((0.64, 1.61), (0.86, 1.27), 0.15),
        ((0.78, 1.69), (0.95, 1.40), 0.125),
        ((0.91, 1.79), (1.04, 1.49), 0.115),
        ((1.01, 1.885), (1.03, 1.60), 0.10),
        ((1.09, 1.955), (1.065, 1.715), 0.094),
    ]
    stations = []
    for (cy, cz), (uy, uz), hw in N:
        c = (0, 0.5 * (cy + uy), 0.5 * (cz + uz))
        half = 0.5 * math.hypot(cy - uy, cz - uz)
        stations.append((c, hw, half, 2.3, 2.2, 0.45))
    Q.loft(stations, Q.NECK, k=0.08)
    Q.ell((-0.07, 0.82, 1.36), (0.06, 0.20, 0.16), Q.NECK, k=0.1, axis=(0, 0.72, 0.69))                # brachiocephalic
    # ---------------- head: lofted along the face line from the poll to the nose (dorsal line + depth)
    Pp, Np = Q.V(0, 1.115, 1.985), Q.V(0, 1.50, 1.50)
    fd = (Np - Pp) / np.linalg.norm(Np - Pp)
    zp = Q.V(0, -fd[2], fd[1])                        # perpendicular to the face, pointing dorsal
    L = np.linalg.norm(Np - Pp)
    HU = [  # u along the face, depth below the face line, half width, n_top, n_bot
        (-0.02, 0.18, 0.085, 2.2, 2.0),
        (0.08, 0.25, 0.104, 3.4, 2.1),
        (0.24, 0.255, 0.114, 4.0, 2.1),
        (0.40, 0.215, 0.100, 3.4, 2.2),
        (0.56, 0.185, 0.074, 2.7, 2.2),
        (0.72, 0.168, 0.063, 2.6, 2.2),
        (0.86, 0.160, 0.063, 2.4, 2.2),
        (0.95, 0.142, 0.068, 2.3, 2.2),
        (1.00, 0.10, 0.054, 2.0, 2.0),
    ]
    Q.loft([(tuple(Pp + fd * u * L - zp * d * 0.5), hw, d * 0.5, nt, nb, 0.0) for u, d, hw, nt, nb in HU], ["head"], k=0.03)
    Q.ell((-0.056, 1.14, 1.765), (0.05, 0.115, 0.105), ["head", "jaw"], k=0.05, axis=(0, 0.75, -0.66))   # jowl / masseter
    Q.rc((0, 1.115, 1.73), (0, 1.425, 1.445), 0.05, 0.034, ["jaw", "head"], k=0.05, mirror=False, sx=1.55)  # mandible
    Q.ell((0, 1.445, 1.418), (0.04, 0.055, 0.027), ["jaw"], k=0.025, mirror=False, axis=(0, 1, -0.25))   # lower lip
    Q.ell((0, 1.415, 1.418), (0.032, 0.038, 0.03), ["jaw"], k=0.025, mirror=False)                       # chin
    Q.ell((-0.041, 1.468, 1.508), (0.021, 0.03, 0.026), ["head"], k=0.02, axis=tuple(fd))                 # nostril flare
    Q.ell((-0.045, 1.48, 1.51), (0.009, 0.022, 0.012), ["head"], k=0.008, op="s", axis=tuple(fd), side=(1, 0.0, -0.4))  # nostril
    Q.rc((-0.032, 1.395, 1.452), (-0.012, 1.485, 1.442), 0.0055, 0.004, ["head"], k=0.006, op="s")      # mouth line
    Q.ell((0, 1.205, 1.848), (0.092, 0.11, 0.028), ["head"], k=0.03, mirror=False, axis=(0, 0.62, -0.78))  # flat forehead
    Q.ell((-0.094, 1.195, 1.828), (0.024, 0.05, 0.02), ["head"], k=0.025, axis=(0, 0.85, -0.2))           # orbit ridge
    Q.ell((-0.097, 1.215, 1.795), (0.019, 0.022, 0.02), ["head"], k=0.008, op="s")                        # eye socket
    ear_a, ear_b = Q.V(-0.056, 1.11, 1.965), Q.V(-0.082, 1.145, 2.115)
    ax = ear_b - ear_a
    Q.rc(tuple(ear_a - ax * 0.15), tuple(ear_a + ax * 0.45), 0.024, 0.026, ["ear_L"], k=0.025, sx=1.25)
    Q.rc(tuple(ear_a + ax * 0.45), tuple(ear_b), 0.026, 0.004, ["ear_L"], k=0.02, sx=1.25)
    Q.rc(tuple(ear_a + ax * 0.25 + Q.V(0, 0.018, 0)), tuple(ear_b + Q.V(0, 0.006, -0.01)), 0.016, 0.002, ["ear_L"], k=0.008,
       op="s", sx=1.25)
    # ---------------- hindquarters (thigh lofted top -> gaskin, cross-section: x' = width, z' = front/back depth)
    TH = [  # center (x, y, z), half width, half depth
        ((-0.135, -0.62, 1.32), 0.10, 0.24),
        ((-0.155, -0.62, 1.16), 0.118, 0.245),
        ((-0.165, -0.63, 1.02), 0.112, 0.21),
        ((-0.16, -0.66, 0.90), 0.088, 0.15),
        ((-0.155, -0.70, 0.77), 0.062, 0.10),
    ]
    Q.loft([(c, a, b, 2.2, 2.2, 0.0) for c, a, b in TH], ["femur_L", "pelvis", "tibia_L"], k=0.07, mirror=True)
    Q.ell((-0.115, -0.53, 1.40), (0.12, 0.27, 0.13), ["pelvis"], k=0.08, axis=(0, 1, 0.12))            # gluteals
    Q.ell((-0.205, -0.38, 1.40), (0.04, 0.06, 0.045), ["pelvis"], k=0.07)                               # point of hip
    Q.ell((-0.20, -0.42, 1.04), (0.06, 0.13, 0.10), ["femur_L"], k=0.08, axis=(0, 0.45, -1))           # quadriceps / stifle
    Q.rc((-0.165, -0.55, 0.90), (-0.152, -0.71, 0.66), 0.07, 0.046, ["tibia_L"], k=0.06)              # gaskin
    Q.rc((-0.148, -0.785, 0.80), (-0.145, -0.805, 0.625), 0.03, 0.024, ["tibia_L"], k=0.04, sx=0.75)  # hamstring tendon
    Q.ell((-0.145, -0.755, 0.56), (0.046, 0.064, 0.066), ["tibia_L", "hcannon_L"], k=0.03)            # hock
    Q.ell((-0.145, -0.806, 0.612), (0.024, 0.032, 0.032), ["tibia_L"], k=0.025)                        # point of hock
    Q.rc((-0.145, -0.74, 0.53), (-0.137, -0.735, 0.19), 0.028, 0.027, ["hcannon_L"], k=0.02, sx=0.92)  # hind cannon bone
    Q.rc((-0.142, -0.772, 0.50), (-0.136, -0.768, 0.20), 0.019, 0.021, ["hcannon_L"], k=0.02, sx=0.8)  # flexor tendons
    Q.ell((-0.135, -0.745, 0.165), (0.040, 0.047, 0.044), ["hcannon_L", "hpastern_L"], k=0.018)        # hind fetlock
    Q.ell((-0.135, -0.785, 0.145), (0.017, 0.02, 0.017), ["hpastern_L"], k=0.012)                      # ergot
    Q.rc((-0.135, -0.735, 0.155), (-0.135, -0.69, 0.07), 0.033, 0.037, ["hpastern_L"], k=0.015)        # hind pastern
    Q.hoof((-0.135, -0.680, 0.0), 0.040, 0.057, 0.072, 0.30, "hhoof_L", length=1.12)
    # ---------------- shoulder / foreleg
    Q.ell((-0.17, 0.56, 1.28), (0.05, 0.20, 0.11), ["scapula_L", "spine_withers"], k=0.1, axis=(0, 0.55, -0.85))  # scapular muscles
    Q.ell((-0.165, 0.50, 1.04), (0.075, 0.13, 0.13), ["humerus_L", "scapula_L"], k=0.09, axis=(0, 1, -0.4))  # triceps
    Q.ell((-0.155, 0.77, 1.12), (0.06, 0.065, 0.07), ["scapula_L", "humerus_L"], k=0.07)                 # point of shoulder
    Q.rc((-0.16, 0.70, 1.12), (-0.165, 0.50, 0.90), 0.065, 0.058, ["humerus_L"], k=0.07)               # upper arm
    Q.ell((-0.075, 0.745, 1.06), (0.08, 0.12, 0.075), ["spine_withers", "humerus_L"], k=0.08, axis=(0, 0.35, -1))  # pectorals
    Q.rc((-0.152, 0.455, 0.915), (-0.152, 0.46, 0.88), 0.036, 0.032, ["forearm_L", "humerus_L"], k=0.06)  # point of elbow
    Q.rc((-0.158, 0.485, 0.85), (-0.145, 0.49, 0.56), 0.066, 0.04, ["forearm_L"], k=0.04, sx=0.88)     # forearm
    Q.rc((-0.16, 0.515, 0.82), (-0.148, 0.505, 0.62), 0.042, 0.027, ["forearm_L"], k=0.04)             # extensor bulge
    Q.ell((-0.142, 0.495, 0.50), (0.047, 0.042, 0.06), ["forearm_L", "fcannon_L"], k=0.02)            # knee
    Q.ell((-0.142, 0.456, 0.515), (0.021, 0.028, 0.03), ["fcannon_L"], k=0.015)                        # accessory carpal
    Q.rc((-0.14, 0.505, 0.47), (-0.136, 0.505, 0.19), 0.027, 0.026, ["fcannon_L"], k=0.018, sx=0.92)  # fore cannon bone
    Q.rc((-0.139, 0.471, 0.45), (-0.136, 0.469, 0.20), 0.018, 0.02, ["fcannon_L"], k=0.018, sx=0.8)   # flexor tendons
    Q.ell((-0.135, 0.495, 0.162), (0.042, 0.048, 0.045), ["fcannon_L", "fpastern_L"], k=0.018)        # fore fetlock
    Q.ell((-0.135, 0.455, 0.14), (0.017, 0.02, 0.017), ["fpastern_L"], k=0.012)                        # ergot
    Q.rc((-0.135, 0.505, 0.15), (-0.135, 0.56, 0.07), 0.034, 0.038, ["fpastern_L"], k=0.015)          # fore pastern
    Q.hoof((-0.135, 0.575, 0.0), 0.043, 0.064, 0.077, 0.38, "fhoof_L", length=1.05)
    # ---------------- tail dock
    pts = [Q.J["tail%d" % i] for i in range(7)]
    radii = [0.055, 0.048, 0.042, 0.037, 0.033, 0.029, 0.024]
    for i in range(6):
        Q.rc(tuple(pts[i]), tuple(pts[i + 1]), radii[i], radii[i + 1], ["tail_%d" % (i + 1)], k=0.03, mirror=False)
    out = []
    for p in Q.PRIMS:
        out.append(p)
        if p.mirror:
            out.append(p.mirrored())
    return out


GAITS = {
    # T cycle seconds, L stride metres, duty (fore, hind), footfall phase per leg, lift (fore, hind),
    # knee/hock/fetlock swing flexion, body bob/pitch, neck nod, lumbar flex, tail carriage
    "walk": dict(T=1.05, L=1.75, duty=(0.62, 0.62), ph={"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},
                 lift=(0.09, 0.08), knee=0.95, hock=0.5, fet=(1.0, 0.9), bob=(0.012, 2, 0.12), pitch=(0.012, 2, 0.0),
                 nod=(0.07, 2, 0.06), lumbar=0.02, tail=(0.0, 0.05), reach=(0.03, 0.0)),
    "trot": dict(T=0.72, L=2.7, duty=(0.42, 0.42), ph={"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},
                 lift=(0.16, 0.13), knee=1.45, hock=0.75, fet=(1.5, 1.3), bob=(0.035, 2, 0.21), pitch=(0.012, 2, 0.1),
                 nod=(0.015, 2, 0.21), lumbar=0.02, tail=(-0.15, 0.06), reach=(0.05, 0.02)),
    "canter": dict(T=0.55, L=3.5, duty=(0.35, 0.37), ph={"RH": 0.0, "LH": 0.27, "RF": 0.27, "LF": 0.50},
                   lift=(0.2, 0.17), knee=1.7, hock=0.85, fet=(1.7, 1.5), bob=(0.055, 1, 0.42), pitch=(0.08, 1, 0.12),
                   nod=(0.2, 1, 0.12), lumbar=0.14, tail=(-0.35, 0.1), reach=(0.06, 0.04), withers_flex=0.05,
                   head_counter=0.35),
    "gallop": dict(T=0.47, L=6.0, duty=(0.21, 0.22), ph={"RH": 0.0, "LH": 0.10, "RF": 0.38, "LF": 0.48},
                   lift=(0.24, 0.21), knee=2.0, hock=1.0, fet=(1.8, 1.6), bob=(0.07, 1, 0.30), pitch=(0.1, 1, 0.05),
                   nod=(0.27, 1, 0.05), lumbar=0.26, tail=(-0.45, 0.12), reach=(0.10, 0.07), withers_flex=0.08,
                   head_counter=0.45),
}


def mirror_gait(g):
    g = dict(g)
    sw = {"LH": "RH", "RH": "LH", "LF": "RF", "RF": "LF"}
    g["ph"] = {sw[k]: v for k, v in g["ph"].items()}
    return g


GAITS["canter_r"] = mirror_gait(GAITS["canter"])
GAITS["gallop_r"] = mirror_gait(GAITS["gallop"])
GAIT_TYPES = {"walk": "walk_lateral", "trot": "trot_diagonal", "canter": "canter", "canter_r": "canter",
              "gallop": "gallop_transverse", "gallop_r": "gallop_transverse"}
