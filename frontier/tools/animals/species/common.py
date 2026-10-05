"""Shared building blocks for the wildlife species files (everything except the horse, which keeps its own
hand-tuned anatomy in horse.py).

A species file describes an animal with:
  * landmarks `J` (metres, Blender axes: +X right, +Y forward, +Z up, ground at 0; left side x < 0) - the same keys
    as the horse, so every species shares one bone layout (spine, 4 neck bones, head, jaw, ears, 6 tail bones,
    scapula/humerus/forearm/fcannon/fpastern/fhoof and femur/tibia/hcannon/hpastern/hhoof per side). For
    digitigrade feet `fcannon`/`hcannon` are the metapodials, `fpastern`/`hpastern` the toes and `fhoof`/`hhoof` the
    pads; for plantigrade feet the metapodials lie almost flat.
  * a body description `B` (side-profile key points of the top line / under line and half widths of the trunk,
    neck, head, legs, tail, ears, family) turned into SDF primitives by `build_prims`,
  * gait tables from `gait()` with species speeds and footfall phases, and actions from `actions()`.
"""
import math

import numpy as np


def V(*a):
    return np.array(a, dtype=np.float64)


def make_bones(J, root_len=0.4):
    """Bone table shared by every quadruped (left legs; the generator mirrors them)."""
    return [
        ("root", V(0, 0, 0), V(0, root_len, 0), None),
        ("body", J["body"], J["body_t"], "root"),
        ("spine_lumbar", J["body"] + V(0, 0, 0.02 * root_len / 0.4), J["lumbar_t"], "body"),
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
        ("fhoof_L", J["fcoffin"], J["ftoe"], "fpastern_L"),
        ("femur_L", J["hip"], J["stifle"], "pelvis"),
        ("tibia_L", J["stifle"], J["hock"], "femur_L"),
        ("hcannon_L", J["hock"], J["hfet"], "tibia_L"),
        ("hpastern_L", J["hfet"], J["hcoffin"], "hcannon_L"),
        ("hhoof_L", J["hcoffin"], J["htoe"], "hpastern_L"),
    ]


def scaled(J0, B0, k, ky=1.0):
    """Copy a species' landmarks/body description scaled by k (and an extra factor ky along the body)."""
    import copy
    J = {n: V(v[0] * k, v[1] * k * ky, v[2] * k) for n, v in J0.items()}
    B = copy.deepcopy(B0)
    B["scale"] = B0["scale"] * k
    for key in ("y_rear", "y_front"):
        B[key] = B0[key] * k * ky
    for key in ("top", "bottom"):
        B[key] = [(y * k * ky, z * k) for y, z in B0[key]]
    B["width"] = [(y * k * ky, w * k) for y, w in B0["width"]]
    for key in ("ntop", "nbot", "pinch"):
        if key in B0:
            B[key] = [(y * k * ky, v) for y, v in B0[key]]
    B["neck"] = [((cy * k * ky, cz * k), (uy * k * ky, uz * k), hw * k) for (cy, cz), (uy, uz), hw in B0["neck"]]
    for key in ("poll", "nose", "tail_base"):
        B[key] = V(B0[key][0] * k, B0[key][1] * k * ky, B0[key][2] * k)
    B["head"] = [(u, d * k, hw * k, nt, nb) for u, d, hw, nt, nb in B0["head"]]
    j0, j1, r0, r1, sx = B0["jaw"]
    B["jaw"] = (V(j0[0] * k, j0[1] * k * ky, j0[2] * k), V(j1[0] * k, j1[1] * k * ky, j1[2] * k), r0 * k, r1 * k, sx)
    B["eye"] = (B0["eye"][0] * k, B0["eye"][1] * k * ky, B0["eye"][2] * k)
    for key in ("eye_r", "ear_w", "tail_len"):
        B[key] = B0[key] * k
    for key in ("leg_r", "hleg_r", "foot_r", "tail_r"):
        B[key] = type(B0[key])(v * k for v in B0[key])
    return J, B


def move_head(J, B, d):
    """Translate the head (poll, nose, jaw, eye, ears) by d."""
    for key in ("poll", "nose"):
        B[key] = B[key] + d
    j0, j1, r0, r1, sx = B["jaw"]
    B["jaw"] = (j0 + d, j1 + d, r0, r1, sx)
    B["eye"] = tuple(np.array(B["eye"]) + d)
    for key in ("ear", "ear_t", "jaw", "jaw_t"):
        J[key] = J[key] + d


def scale_head(J, B, k):
    """Scale the head about the poll."""
    P = B["poll"].copy()
    B["nose"] = P + (B["nose"] - P) * k
    j0, j1, r0, r1, sx = B["jaw"]
    B["jaw"] = (P + (j0 - P) * k, P + (j1 - P) * k, r0 * k, r1 * k, sx)
    e = np.array(B["eye"])
    B["eye"] = tuple(P + (e - P) * k)
    B["eye_r"] *= k
    B["head"] = [(u, d * k, hw * k, nt, nb) for u, d, hw, nt, nb in B["head"]]
    for key in ("jaw", "jaw_t", "ear", "ear_t"):
        J[key] = P + (J[key] - P) * k


def lerp_keys(keys, y):
    """Piecewise-linear interpolation of [(y, value)] key points (sorted by y)."""
    ks = sorted(keys)
    if y <= ks[0][0]:
        return ks[0][1]
    for (y0, v0), (y1, v1) in zip(ks[:-1], ks[1:]):
        if y <= y1:
            f = (y - y0) / max(y1 - y0, 1e-9)
            f = f * f * (3 - 2 * f)
            return v0 + (v1 - v0) * f
    return ks[-1][1]


def spine_landmarks(J, B):
    """Vertebral column + neck/head bone points from the profile (fills the spine keys of J)."""
    yb, yf = B["y_rear"], B["y_front"]
    top = B["top"]
    bot = B["bottom"]

    def mid(y, f=0.62):
        t = lerp_keys(top, y)
        b = lerp_keys(bot, y)
        return t - (t - b) * (1 - f)

    L = yf - yb
    yb0 = yb + 0.42 * L
    J["body"] = V(0, yb0, mid(yb0, 0.7))
    J["body_t"] = V(0, yb0 + 0.15 * L, mid(yb0 + 0.15 * L, 0.7))
    J["lumbar_t"] = V(0, yb + 0.24 * L, mid(yb + 0.24 * L, 0.74))
    J["pelvis_t"] = V(0, yb + 0.03 * L, mid(yb + 0.03 * L, 0.74))
    J["thorax_t"] = V(0, yb + 0.78 * L, mid(yb + 0.78 * L, 0.68))
    J["withers_t"] = V(0, yb + 0.93 * L, mid(yb + 0.93 * L, 0.62))
    # neck: from the withers bone end to the atlas (just under the poll)
    a = J["withers_t"]
    poll = B["poll"]
    atlas = poll + B.get("atlas_off", V(0, 0.02, -0.06)) * B["scale"]
    ctrl = a + (atlas - a) * 0.5 + V(0, -0.06, -0.02) * B["scale"] * B.get("neck_s", 1.0)
    pts = []
    for t in (0.25, 0.5, 0.75, 1.0):
        pts.append((1 - t) ** 2 * a + 2 * (1 - t) * t * ctrl + t * t * atlas)
    J["neck1_t"], J["neck2_t"], J["neck3_t"], J["neck4_t"] = pts
    nose = B["nose"]
    J["head_t"] = atlas + (nose - atlas) * 0.92
    return J


def tail_points(J, B):
    t0 = B["tail_base"]
    L = B["tail_len"]
    ang0 = math.radians(B.get("tail_angle0", -30.0))      # first segment angle below horizontal (backwards)
    ang1 = math.radians(B.get("tail_angle1", -80.0))      # last segment
    p = t0.copy()
    J["tail0"] = p.copy()
    for i in range(1, 7):
        a = ang0 + (ang1 - ang0) * (i - 1) / 5.0
        p = p + V(0, -math.cos(a), math.sin(a)) * (L / 6.0)
        J["tail%d" % i] = p.copy()
    return J


# =====================================================================================================
# SDF body from the description
# =====================================================================================================
def build_prims(Q, J, B):
    Q.PRIMS.clear()
    s = B["scale"]
    fam = B["family"]
    TRUNK = ["spine_lumbar", "body", "spine_thorax", "spine_withers"]
    NECK = ["spine_withers", "neck_1", "neck_2", "neck_3", "neck_4"]
    # ---------------- trunk loft from top/bottom key points and half widths
    yb, yf = B["y_rear"], B["y_front"]
    ys = np.linspace(yb, yf, 13)
    st = []
    for i, y in enumerate(ys):
        t = lerp_keys(B["top"], y)
        b = lerp_keys(B["bottom"], y)
        hw = lerp_keys(B["width"], y)
        ntop = lerp_keys(B.get("ntop", [(yb, 2.6), (yf, 2.4)]), y)
        nbot = lerp_keys(B.get("nbot", [(yb, 2.2), (yf, 2.1)]), y)
        pin = lerp_keys(B.get("pinch", [(yb, 0.15), (yf, 0.3)]), y)
        st.append(((0, y, 0.5 * (t + b)), hw, max(0.5 * (t - b), 0.01), ntop, nbot, pin))
    Q.loft(st, ["pelvis", "spine_lumbar", "body", "spine_thorax", "spine_withers"], k=0.05 * s)
    # ---------------- neck loft (crest / under line)
    stations = []
    for (cy, cz), (uy, uz), hw in B["neck"]:
        c = (0, 0.5 * (cy + uy), 0.5 * (cz + uz))
        half = 0.5 * math.hypot(cy - uy, cz - uz)
        stations.append((c, hw, half, 2.3, 2.2, B.get("neck_pinch", 0.4)))
    Q.loft(stations, NECK + ["head"], k=0.07 * s)
    # ---------------- head loft along the face, poll -> nose
    Pp, Np = B["poll"], B["nose"]
    fd = (Np - Pp) / np.linalg.norm(Np - Pp)
    zp = V(0, -fd[2], fd[1])
    L = np.linalg.norm(Np - Pp)
    Q.loft([(tuple(Pp + fd * u * L - zp * d * 0.5), hw, d * 0.5, nt, nb, 0.0) for u, d, hw, nt, nb in B["head"]],
           ["head"], k=0.025 * s)
    for p in B.get("head_extra", []):
        p(Q, Pp, fd, zp, L, B)
    # jaw / mandible
    jw = B["jaw"]
    Q.rc(tuple(jw[0]), tuple(jw[1]), jw[2], jw[3], ["jaw", "head"], k=0.04 * s, mirror=False, sx=jw[4])
    # eyes, ears: snapped onto the head surface built so far (eye half sunk in, ear bases rooted in the skull)
    head_prims = list(Q.PRIMS)
    ec, er = B["eye"], B["eye_r"]
    ec = surface_x(Q, head_prims, ec[1], ec[2], er, s)
    B["eye"] = ec
    ea0 = J["ear"].copy()
    for dz in np.arange(0.0, 0.25, 0.002) * s / 0.643:
        if Q.eval_points(head_prims, np.array([[ea0[0], ea0[1], ea0[2] - dz]]))[0] < -0.006 * s / 0.643:
            break
    d = V(0, 0, -dz)
    J["ear"][:] = ea0 + d
    J["ear_t"][:] = J["ear_t"] + d
    Q.ell((-ec[0] - er * 0.4, ec[1], ec[2]), (er * 1.05, er * 1.15, er), ["head"], k=0.008 * s, op="s")
    Q.ell((-ec[0] + er * 0.5, ec[1] - er * 0.5, ec[2] + er * 1.1), (er * 0.9, er * 1.7, er * 0.6), ["head"], k=0.014 * s,
          axis=(0, 0.85, -0.2))                                                                      # brow
    ea, eb = J["ear"], J["ear_t"]
    ax = eb - ea
    ew, et = B["ear_w"], B.get("ear_t", 0.25)
    fwd = (0, 1, 0)
    Q.rc(tuple(ea - ax * 0.12), tuple(ea + ax * 0.5), ew * 0.6, ew, ["ear_L"], k=0.012 * s, sx=et, side=fwd)
    Q.rc(tuple(ea + ax * 0.5), tuple(eb), ew, ew * 0.12, ["ear_L"], k=0.01 * s, sx=et, side=fwd)
    Q.rc(tuple(ea + ax * 0.22 + V(0, ew * et * 0.9, 0)), tuple(eb + V(0, ew * et * 0.6, 0) - ax * 0.06), ew * 0.7,
         ew * 0.05, ["ear_L"], k=0.005 * s, op="s", sx=et * 0.8, side=fwd)
    # ---------------- shoulder / foreleg
    R = B["leg_r"]          # radii: upper arm, forearm top, forearm bottom, cannon, fetlock, pastern
    sc, sh, el, kn, fe, co = (J[k] for k in ("scap", "shoulder", "elbow", "knee", "ffet", "fcoffin"))
    Q.ell(tuple((sc + sh) * 0.5 + V(-R[0] * 0.25, 0, 0)), (R[0] * 0.75, np.linalg.norm(sh - sc) * 0.62, R[0] * 1.5),
          ["scapula_L", "spine_withers"], k=0.08 * s, axis=tuple(sh - sc))                         # scapular muscles
    Q.ell(tuple(el * 0.55 + sh * 0.45 + V(-0.01 * s, -R[0] * 0.6, 0.02 * s)), (R[0] * 1.0, R[0] * 1.7, R[0] * 1.5),
          ["humerus_L", "scapula_L"], k=0.07 * s, axis=(0, 1, -0.4))                               # triceps
    Q.rc(tuple(sh), tuple(el), R[0], R[0] * 0.85, ["humerus_L"], k=0.06 * s)                       # upper arm
    Q.rc(tuple(el + V(0, 0.01 * s, -0.01 * s)), tuple(kn + V(0, 0, 0.04 * s)), R[1], R[2], ["forearm_L"], k=0.035 * s, sx=0.9)
    Q.ell(tuple(kn), (R[2] * 1.1, R[2] * 1.0, R[2] * 1.3), ["forearm_L", "fcannon_L"], k=0.02 * s)  # knee / carpus
    Q.rc(tuple(kn), tuple(fe), R[3], R[3] * 0.95, ["fcannon_L"], k=0.02 * s, sx=0.9)
    Q.ell(tuple(fe), (R[4], R[4] * 1.1, R[4]), ["fcannon_L", "fpastern_L"], k=0.016 * s)
    Q.rc(tuple(fe), tuple(co), R[5], R[5] * 1.05, ["fpastern_L"], k=0.014 * s)
    foot(Q, J, B, "f")
    pk = B.get("pec", 1.0)
    Q.ell((-B.get("chest_x", 0.45) * R[0] * 2.0, sh[1] + 0.02 * s - R[0] * (1 - pk), sh[2] - 0.12 * s * pk),
          (R[0] * 1.4 * pk, R[0] * 1.4 * pk, R[0] * 2.2 * pk),
          ["spine_withers", "humerus_L"], k=0.07 * s, axis=(0, 0.35, -1))                          # pectorals
    # ---------------- hindquarters / hind leg
    HR = B["hleg_r"]        # thigh width, thigh depth, gaskin top, gaskin bottom, cannon, fetlock, pastern
    hp, sf, hk, hf, hc = (J[k] for k in ("hip", "stifle", "hock", "hfet", "hcoffin"))
    top = V(hp[0] * 0.8, hp[1], hp[2] + HR[0] * 0.5)
    mid = (hp + sf) * 0.5 + V(0, -HR[1] * 0.35, 0)
    low = sf * 0.45 + hk * 0.55 + V(0, -HR[1] * 0.2, 0)
    low2 = sf * 0.2 + hk * 0.8 + V(0, -HR[3] * 0.5, 0)
    Q.loft([(tuple(top), HR[0] * 0.85, HR[1] * 0.95, 2.1, 2.1, 0.0), (tuple(mid), HR[0], HR[1], 2.1, 2.1, 0.0),
            (tuple(low), HR[0] * 0.6, HR[1] * 0.5, 2.0, 2.0, 0.0), (tuple(low2), HR[3] * 1.1, HR[3] * 1.5, 2.0, 2.0, 0.0)],
           ["femur_L", "pelvis", "tibia_L"], k=0.08 * s, mirror=True)                              # thigh
    Q.ell((hp[0] * 0.55, hp[1] + 0.05 * s, hp[2] + HR[0] * 0.6), (HR[0] * 0.95, HR[1] * 1.1, HR[0] * 1.0), ["pelvis"],
          k=0.07 * s, axis=(0, 1, 0.12))                                                           # gluteals
    Q.rc(tuple(sf + V(0, -0.02 * s, 0)), tuple(hk + V(0, 0.01 * s, 0.03 * s)), HR[2], HR[3], ["tibia_L"], k=0.045 * s)  # gaskin
    Q.ell(tuple(hk), (HR[3] * 1.05, HR[3] * 1.3, HR[3] * 1.3), ["tibia_L", "hcannon_L"], k=0.025 * s)  # hock
    Q.ell(tuple(hk + V(0, -HR[3] * 1.0, HR[3] * 0.9)), (HR[3] * 0.55, HR[3] * 0.7, HR[3] * 0.7), ["tibia_L"], k=0.02 * s)  # point of hock
    Q.rc(tuple(hk), tuple(hf), HR[4], HR[4] * 0.95, ["hcannon_L"], k=0.02 * s, sx=0.9)
    Q.ell(tuple(hf), (HR[5], HR[5] * 1.1, HR[5]), ["hcannon_L", "hpastern_L"], k=0.016 * s)
    Q.rc(tuple(hf), tuple(hc), HR[6], HR[6] * 1.05, ["hpastern_L"], k=0.014 * s)
    foot(Q, J, B, "h")
    # ---------------- tail
    tr = B["tail_r"]
    pts = [J["tail%d" % i] for i in range(7)]
    for i in range(6):
        r0 = lerp_keys(list(enumerate(tr)), i)
        r1 = lerp_keys(list(enumerate(tr)), i + 1)
        Q.rc(tuple(pts[i]), tuple(pts[i + 1]), r0, r1, ["tail_%d" % (i + 1)], k=0.02 * s, mirror=False,
             sx=B.get("tail_flat", 1.0))
    for p in B.get("extra", []):
        p(Q, J, B)
    out = []
    for p in Q.PRIMS:
        out.append(p)
        if p.mirror:
            out.append(p.mirrored())
    return out


def surface_x(Q, prims, y, z, er, s):
    """Eye centre on the side of the head at (y, z): x where the head surface is, sunk in by 40 % of the radius;
    if (y, z) is above the head the eye moves down until it meets the surface."""
    for dz in np.arange(0.0, 0.2, 0.002) * s / 0.643:
        xs = np.linspace(0.0, 0.3, 301) * s / 0.643
        pts = np.stack([xs, np.full_like(xs, y), np.full_like(xs, z - dz)], 1)
        d = Q.eval_points(prims, pts)
        if d[0] < 0:
            i = int(np.argmax(d > 0))
            if i > 0:
                return (float(xs[i] - er * 0.4), float(y), float(z - dz))
    return (0.05 * s / 0.643, y, z)


def foot(Q, J, B, fh):
    s = B["scale"]
    kind = B["foot"]
    co, sole, toe = J[fh + "coffin"], J[fh + "sole"], J[fh + "toe"]
    bone = ("fhoof_L" if fh == "f" else "hhoof_L")
    fr = B["foot_r"][0 if fh == "f" else 1]
    if kind == "hoof":
        Q.hoof(tuple(sole), fr * 0.7, fr, fr * 1.15, 0.38, bone, k=0.005 * s, length=1.08)
    elif kind == "cloven":
        # two pointed claws with a cleft, plus dewclaws behind the fetlock
        for dx in (-0.48, 0.48):
            c = sole + V(dx * fr, 0.0, 0.0)
            Q.hoof(tuple(c), fr * 0.36, fr * 0.55, fr * 1.25, 0.55, bone, k=0.004 * s, length=1.45)
        fet = J[fh + "fet"]
        for dx in (-0.6, 0.6):
            Q.ell(tuple(fet + V(dx * fr, -fr * 0.9, -fr * 0.5)), (fr * 0.18, fr * 0.22, fr * 0.3), [bone.replace("hoof", "pastern")],
                  k=0.006 * s)
    else:
        # paw: toe pads + palm pad, toes splayed slightly (digitigrade) or a long sole (plantigrade)
        L = np.linalg.norm(toe - sole) * 2.0
        if kind == "plantigrade":
            heel = J[fh + "fet"] + (J[fh + "fet"] - sole) * 0.0
            Q.rc(tuple(V(sole[0], sole[1] - L * 0.6, fr * 0.55)), tuple(V(sole[0], sole[1] + L * 0.2, fr * 0.6)),
                 fr * 0.55, fr * 0.65, [bone], k=0.02 * s, sx=1.6)
        Q.ell(tuple(sole + V(0, 0, fr * 0.42)), (fr * 0.95, fr * 1.05, fr * 0.48), [bone], k=0.015 * s)
        for i, dx in enumerate((-0.62, -0.2, 0.2, 0.62)):
            dy = 0.55 if abs(dx) < 0.5 else 0.38
            Q.ell(tuple(sole + V(dx * fr, dy * fr + fr * 0.15, fr * 0.33)), (fr * 0.3, fr * 0.36, fr * 0.33), [bone], k=0.012 * s)
        if B.get("claws"):
            for dx in (-0.62, -0.2, 0.2, 0.62):
                dy = 0.55 if abs(dx) < 0.5 else 0.38
                Q.rc(tuple(sole + V(dx * fr, dy * fr + fr * 0.45, fr * 0.35)), tuple(sole + V(dx * fr * 1.1, dy * fr + fr * 0.95, fr * 0.08)),
                     fr * 0.09, fr * 0.02, [bone], k=0.004 * s)


# =====================================================================================================
# Antlers / horns (separate skinned meshes on the head bone)
# =====================================================================================================
def tube_branch(Q, pts, r0, r1, segs=7):
    rad = np.linspace(r0, r1, len(pts))
    return Q.tube_mesh(np.array(pts), rad, flat=1.0, segs=segs)


def curve(p0, d0, length, bend, n=8, twist=None):
    """Polyline from p0 heading d0, bending by `bend` (vector added per unit length)."""
    pts = [p0]
    d = d0 / np.linalg.norm(d0)
    p = p0.copy()
    for i in range(n):
        p = p + d * (length / n)
        d = d + bend * (length / n)
        d /= np.linalg.norm(d)
        pts.append(p.copy())
    return pts


def emit_tubes(Q, arm, name, tubes, color, rough=0.7, cap=True):
    verts, faces = [], []
    for v, f in tubes:
        o = sum(len(x) for x in verts)
        verts.append(v)
        faces.extend([tuple(i + o for i in q) for q in f])
    ob = Q.make_mesh(name, np.concatenate(verts), faces)
    Q.shade_smooth(ob)
    Q._box_uv(ob)
    ob.data.materials.append(Q.make_material(name.lower(), color, rough=rough))
    Q.rigid_weights(ob, "head", arm)
    return ob


# =====================================================================================================
# Gaits
# =====================================================================================================
def gait(T, L, duty, ph, H, lift=(0.1, 0.09), knee=1.0, hock=0.6, fet=(1.0, 0.9), bob=(0.012, 2, 0.12),
         pitch=(0.012, 2, 0.0), nod=(0.05, 2, 0.06), lumbar=0.02, tail=(0.0, 0.05), reach=(0.03, 0.0)):
    """Gait table entry; lengths given for a 1 m animal are scaled by H (withers height)."""
    return dict(T=T, L=L, duty=duty, ph=ph, lift=(lift[0] * H, lift[1] * H), knee=knee, hock=hock, fet=fet,
                bob=(bob[0] * H, bob[1], bob[2]), pitch=pitch, nod=nod, lumbar=lumbar, tail=tail,
                reach=(reach[0] * H, reach[1] * H))


WALK = {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75}
TROT = {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5}
GALLOP_TRANSVERSE = {"RH": 0.0, "LH": 0.10, "RF": 0.38, "LF": 0.48}
GALLOP_ROTARY = {"RH": 0.0, "LH": 0.10, "LF": 0.40, "RF": 0.50}
BOUND = {"LF": 0.0, "RF": 0.08, "LH": 0.45, "RH": 0.47}         # half-bound: fores staggered, hinds together


# =====================================================================================================
# Actions (generic, scaled by the animal's size)
# =====================================================================================================
def actions(Q, cfg):
    """Idles and one-shots for a wild animal. cfg: {"H": withers height, "predator": bool, "graze": bool, ...}"""
    H = cfg["H"]
    pred = cfg.get("predator", False)
    sole = {leg: Q.LEGS[leg][1] for leg in Q.LEGS}

    def idle(T=4.0):
        def f(t, i):
            ang = {"neck_1": 0.02 * math.sin(2 * math.pi * t / T), "head": -0.015 * math.sin(2 * math.pi * t / T),
                   "ear_L": 0.06 + 0.35 * Q.env(t, 2.4, 2.5, 2.6, 2.8), "ear_R": 0.06}
            side = {}
            sw = Q.env(t, 0.8, 1.1, 1.3, 1.8)
            for k in range(1, 7):
                side["tail_%d" % k] = (cfg.get("tail_wag", 0.12) * sw * math.sin(2 * math.pi * (t - 0.8) - k * 0.3), 0.0)
            return ang, (0.0, Q.breathe(t, 0.004 * H, 2.2 if H < 0.7 else 2.6)), side, {}
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def graze(T=6.0):
        # grazers: head to the grass and chew; predators/omnivores: nose down, sniffing the ground
        d = cfg.get("graze_neck", (-0.95, -0.38, -0.22, -0.12, 0.55))

        def f(t, i):
            chew = math.sin(2 * math.pi * t * (1.6 if not pred else 3.5))
            sway = 0.07 * math.sin(2 * math.pi * t / T)
            ang = {"neck_1": d[0], "neck_2": d[1], "neck_3": d[2], "neck_4": d[3], "head": d[4] + (0.04 * chew if pred else 0.0),
                   "jaw": (0.05 + 0.05 * chew) if not pred else 0.0, "ear_L": 0.05, "ear_R": -0.1, "spine_withers": -0.04}
            side = {"neck_2": (sway, 0.0), "neck_3": (sway, 0.0), "head": (0.0, 0.04 * chew)}
            legs = {"LF": Q.planted("LF", dy=0.14 * H), "RF": Q.planted("RF", dy=-0.04 * H)}
            return ang, (0.0, -0.02 * H), side, legs
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def alert(T=3.0):
        # head high, ears pricked toward the sound, body still, a stamp of a fore foot
        def f(t, i):
            e = Q.env(t, 0.0, 0.3, 9.0, 10.0)
            ang = {"neck_1": 0.28 * e, "neck_2": 0.08 * e, "head": -0.22 * e, "ear_L": 0.3 * e, "ear_R": 0.3 * e,
                   "tail_1": cfg.get("alert_tail", -0.25) * e}
            stamp = Q.env(t, 1.6, 1.75, 1.8, 2.0)
            legs = {}
            if stamp > 0.05 and not pred:
                legs["LF"] = Q.free("LF", {"fcannon": -0.9 * stamp}, tgt=(sole["LF"][1], 0.08 * H * stamp), wp=6e3)
            return ang, (0.0, Q.breathe(t, 0.006 * H, 1.2)), {}, legs
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def look(T=4.0):
        # looks around: head and neck turn left, then right, ears follow
        def f(t, i):
            turn = math.sin(2 * math.pi * t / T)
            e = Q.env(t, 0.0, 0.4, T - 0.4, T)
            ang = {"neck_1": 0.15 * e, "head": -0.1 * e, "ear_L": 0.2, "ear_R": 0.2}
            side = {"neck_1": (0.25 * turn * e, 0.0), "neck_2": (0.25 * turn * e, 0.0), "neck_3": (0.2 * turn * e, 0.0),
                    "head": (0.3 * turn * e, 0.0), "ear_L": (0.3 * turn, 0.0), "ear_R": (0.3 * turn, 0.0)}
            return ang, (0.0, 0.0), side, {}
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def flee_start(T=0.7):
        # wheel and spring away: crouch on the hind legs, front end lifts, then the push
        piv = (sole["LH"][1], 0.5 * H)

        def f(t, i):
            crouch = Q.env(t, 0.0, 0.18, 0.25, 0.4)
            spring = Q.env(t, 0.22, 0.38, 0.45, 0.7)
            phi = 0.22 * spring + 0.05 * crouch
            ang = {"body": phi, "neck_1": 0.25 * crouch - 0.1 * spring, "head": -0.1, "ear_L": -0.3, "ear_R": -0.3,
                   "tail_1": cfg.get("flee_tail", -0.6) * max(crouch, spring), "spine_lumbar": 0.12 * crouch - 0.08 * spring}
            loc = Q.pivot_body(phi, piv)
            loc = (loc[0], loc[1] - 0.08 * H * crouch)
            legs = {"LH": Q.planted("LH", dy=0.12 * H * crouch - 0.2 * H * spring),
                    "RH": Q.planted("RH", dy=0.1 * H * crouch - 0.2 * H * spring)}
            if spring > 0.2:
                for leg in ("LF", "RF"):
                    legs[leg] = Q.free(leg, {"forearm": 0.9 * spring, "fcannon": -1.6 * spring, "fpastern": -0.9 * spring})
            return ang, loc, {"body": (0.18 * spring, 0.0)}, legs
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def attack(T=0.9):
        # predators: crouch, lunge forward with forelegs reaching and jaws open; bears swipe up on the hind legs
        bear = cfg.get("bear", False)
        piv = (sole["LH"][1], 0.45 * H)

        def f(t, i):
            crouch = Q.env(t, 0.0, 0.2, 0.25, 0.4)
            lunge = Q.env(t, 0.25, 0.42, 0.55, 0.85)
            phi = (0.55 if bear else 0.25) * lunge - 0.06 * crouch
            ang = {"body": phi, "neck_1": -0.15 * crouch + (0.05 if bear else -0.2) * lunge, "head": 0.15 * lunge,
                   "jaw": 0.45 * lunge, "ear_L": -0.5, "ear_R": -0.5, "tail_1": -0.2,
                   "spine_lumbar": 0.15 * crouch - 0.1 * lunge}
            loc = Q.pivot_body(phi, piv)
            loc = (loc[0] + 0.25 * H * lunge, loc[1] - 0.1 * H * crouch)
            legs = {"LH": Q.planted("LH", dy=0.1 * H * crouch + 0.2 * H * lunge),
                    "RH": Q.planted("RH", dy=0.08 * H * crouch + 0.2 * H * lunge)}
            if lunge > 0.1:
                for k, leg in enumerate(("LF", "RF")):
                    legs[leg] = Q.free(leg, {"humerus": -0.5 * lunge, "forearm": 0.2 * lunge,
                                             "fcannon": -0.5 * lunge * (1.6 if k == 0 and bear else 1.0), "fpastern": -0.6 * lunge})
            return ang, loc, {}, legs
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def death(T=1.8):
        def f(t, i):
            drop = Q.env(t, 0.0, 0.55, 9.0, 10.0)
            roll = Q.env(t, 0.35, 1.25, 9.0, 10.0)
            ang = {"body": -0.1 * drop + 0.08 * roll, "neck_1": -0.5 * drop + 0.3 * roll, "neck_2": -0.1 * roll, "head": 0.3 * drop,
                   "ear_L": -0.4 * roll, "ear_R": -0.4 * roll, "jaw": 0.08 * roll, "tail_1": 0.3 * roll}
            side = {"body": (0.0, 1.42 * roll), "neck_2": (0.15 * roll, 0.0), "neck_3": (0.12 * roll, 0.0)}
            legs = {}
            for leg in Q.LEGS:
                k = max(drop, roll)
                if leg.endswith("F"):
                    legs[leg] = Q.free(leg, {"forearm": 0.5 * drop * (1 - roll) + 0.15 * roll, "fcannon": -1.3 * drop * (1 - roll) - 0.15 * roll,
                                             "fpastern": -0.3 * k, "scapula": 0.1 * roll}, w=1.0)
                else:
                    legs[leg] = Q.free(leg, {"tibia": -0.6 * drop * (1 - roll) - 0.1 * roll, "hcannon": 0.9 * drop * (1 - roll) + 0.1 * roll,
                                             "hpastern": -0.3 * k, "femur": 0.3 * drop * (1 - roll)}, w=1.0)
                if t < 0.12:
                    legs[leg] = Q.planted(leg)
            z = -cfg.get("drop", 0.42) * H * drop - cfg.get("lie", 0.5) * H * roll
            return ang, (0.0, z), side, legs
        return Q.solve_custom(int(T * Q.ACTION_FPS), f)

    def carcass(T=0.5):
        # lying on the side, still (the final death pose, held): used for skinned carcasses
        poses, sides = death()
        return [poses[-1]] * int(T * Q.ACTION_FPS), [sides[-1]] * int(T * Q.ACTION_FPS)

    out = {"idle": (idle, True), "graze": (graze, True), "alert": (alert, True), "look": (look, True),
           "flee_start": (flee_start, False), "death": (death, False), "carcass": (carcass, False)}
    if pred or cfg.get("bear"):
        out["attack"] = (attack, False)
    return out
