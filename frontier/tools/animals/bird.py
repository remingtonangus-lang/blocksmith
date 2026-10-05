"""Procedural birds for Frontier on the quadruped engine (quadruped.py): SDF body, head, beak and legs; wing and
tail feather cards skinned to the wing/tail bones; an FK rig; ground and flight clips keyed with the same
key_action. Output: <out>/<species>.glb + <species>_gaits.json (meta "kind": "bird").

  python3 frontier/tools/animals/bird.py --species turkey,sage_grouse,red_tailed_hawk,crow [--out DIR] [--preview]

Species (adult references, metres):
  turkey           wild tom: ~1.0 m tall to the crown, body ~0.6 m, span ~1.35 m; bronze body, barred wings, bare
                   red-blue head with snood and wattle, breast beard; walks and runs, flushes in short bursts.
  sage_grouse      ~0.6 m long incl. spiky tail, round body, span ~0.85 m; mottled grey-brown, black belly.
  red_tailed_hawk  ~0.5 m long, span ~1.2 m, broad wings with splayed primaries, rufous tail, pale belly with a
                   dark band; soars in circles, stoops on prey.
  crow             ~0.45 m long, span ~0.9 m, glossy black; flocks on fences and fields.
Rig (left side; _R mirrored): root, body, neck_1, neck_2, head, tail_1, wing1_L (shoulder->elbow), wing2_L
(elbow->wrist), wing3_L (wrist->tip), thigh_L, shank_L, foot_L. Rest pose: wings spread level.
Bone rotation conventions (checked with wildlife_test --only wingcheck): + about local X = wings down (the clips
pass + = up through _wings), legs forward, neck/head/body pitch up, tail down; + side z = left wing sweeps back
(right wing: -).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if "--species" not in sys.argv:
    sys.argv += ["--species", "turkey"]
import numpy as np  # noqa: E402
import quadruped as Q  # noqa: E402

V = Q.V
log = Q.log


def _bird_arg(name, default):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


# ----------------------------------------------------------------------------------------------------------
# species parameters (Blender axes: +x right, +y forward, +z up; ground at z = 0; left side x < 0)
# ----------------------------------------------------------------------------------------------------------
BIRDS = {
    "turkey": dict(
        H=1.0, body_c=(0.0, 0.0, 0.52), body_r=(0.17, 0.3, 0.2), breast=((0.0, 0.14, 0.47), (0.15, 0.17, 0.17)),
        neck=[(0.0, 0.2, 0.6), (0.0, 0.26, 0.75), (0.0, 0.29, 0.86)], neck_r=(0.065, 0.04, 0.03),
        head_c=(0.0, 0.32, 0.9), head_r=(0.03, 0.05, 0.035), beak=((0.0, 0.365, 0.895), (0.0, 0.405, 0.88), 0.011, 0.004),
        eye=(0.026, 0.335, 0.905), eye_r=0.0075,
        hip=(-0.08, 0.02, 0.43), knee=(-0.09, 0.07, 0.3), ankle=(-0.08, 0.03, 0.14), toe=(-0.08, 0.12, 0.0),
        shank_r=(0.04, 0.018), tarsus_r=0.012, toe_r=0.007, toe_len=0.08,
        tail_base=(0.0, -0.27, 0.52), tail_tip=(0.0, -0.58, 0.38), tail_w=(0.12, 0.2),
        shoulder=(-0.14, 0.12, 0.6), elbow=(-0.36, 0.08, 0.62), wrist=(-0.53, 0.06, 0.62), tip=(-0.68, 0.0, 0.62),
        chord=(0.26, 0.24, 0.2, 0.08), fingers=0, extras="turkey",
        flap_T=0.16, cruise=11.0, walk=(1.0, 0.75), voxel=0.003, tris=9000, lods=(3000, 800)),
    "sage_grouse": dict(
        H=0.32, body_c=(0.0, 0.0, 0.2), body_r=(0.1, 0.16, 0.1), breast=((0.0, 0.08, 0.2), (0.09, 0.09, 0.09)),
        neck=[(0.0, 0.11, 0.25), (0.0, 0.14, 0.29), (0.0, 0.16, 0.31)], neck_r=(0.045, 0.035, 0.03),
        head_c=(0.0, 0.18, 0.32), head_r=(0.028, 0.038, 0.03), beak=((0.0, 0.212, 0.315), (0.0, 0.232, 0.305), 0.008, 0.003),
        eye=(0.022, 0.19, 0.33), eye_r=0.0055,
        hip=(-0.05, 0.0, 0.15), knee=(-0.055, 0.03, 0.09), ankle=(-0.05, 0.02, 0.045), toe=(-0.05, 0.07, 0.0),
        shank_r=(0.03, 0.015), tarsus_r=0.009, toe_r=0.005, toe_len=0.045,
        tail_base=(0.0, -0.15, 0.2), tail_tip=(0.0, -0.33, 0.17), tail_w=(0.05, 0.13),
        shoulder=(-0.08, 0.06, 0.25), elbow=(-0.2, 0.04, 0.26), wrist=(-0.31, 0.03, 0.26), tip=(-0.42, -0.02, 0.26),
        chord=(0.15, 0.14, 0.12, 0.05), fingers=0, extras="",
        flap_T=0.11, cruise=12.0, walk=(0.7, 0.5), voxel=0.0018, tris=6000, lods=(2000, 600)),
    "red_tailed_hawk": dict(
        H=0.5, body_c=(0.0, 0.0, 0.3), body_r=(0.08, 0.15, 0.085), breast=((0.0, 0.07, 0.31), (0.075, 0.08, 0.08)),
        neck=[(0.0, 0.1, 0.37), (0.0, 0.12, 0.42), (0.0, 0.13, 0.45)], neck_r=(0.045, 0.04, 0.036),
        head_c=(0.0, 0.15, 0.47), head_r=(0.035, 0.045, 0.036), beak=((0.0, 0.19, 0.465), (0.0, 0.212, 0.445), 0.011, 0.003),
        eye=(0.027, 0.17, 0.48), eye_r=0.0085, eye_fwd=0.6,
        hip=(-0.04, 0.0, 0.25), knee=(-0.045, 0.03, 0.16), ankle=(-0.04, 0.03, 0.07), toe=(-0.04, 0.07, 0.0),
        shank_r=(0.032, 0.02), tarsus_r=0.008, toe_r=0.005, toe_len=0.04, hooked=True,
        tail_base=(0.0, -0.14, 0.27), tail_tip=(0.0, -0.36, 0.2), tail_w=(0.06, 0.13),
        shoulder=(-0.07, 0.05, 0.36), elbow=(-0.24, 0.04, 0.37), wrist=(-0.4, 0.04, 0.37), tip=(-0.6, 0.0, 0.37),
        chord=(0.24, 0.24, 0.21, 0.13), fingers=5, extras="",
        flap_T=0.34, cruise=12.0, walk=(0.6, 0.35), voxel=0.002, tris=7000, lods=(2400, 700)),
    "crow": dict(
        H=0.42, body_c=(0.0, 0.0, 0.25), body_r=(0.065, 0.12, 0.07), breast=((0.0, 0.06, 0.25), (0.06, 0.065, 0.065)),
        neck=[(0.0, 0.08, 0.3), (0.0, 0.1, 0.34), (0.0, 0.115, 0.36)], neck_r=(0.04, 0.034, 0.03),
        head_c=(0.0, 0.135, 0.37), head_r=(0.028, 0.04, 0.031), beak=((0.0, 0.17, 0.37), (0.0, 0.215, 0.358), 0.011, 0.002),
        eye=(0.024, 0.15, 0.38), eye_r=0.0055,
        hip=(-0.035, 0.0, 0.2), knee=(-0.04, 0.02, 0.13), ankle=(-0.035, 0.02, 0.06), toe=(-0.035, 0.06, 0.0),
        shank_r=(0.025, 0.012), tarsus_r=0.006, toe_r=0.004, toe_len=0.035,
        tail_base=(0.0, -0.11, 0.24), tail_tip=(0.0, -0.3, 0.2), tail_w=(0.04, 0.08),
        shoulder=(-0.055, 0.04, 0.29), elbow=(-0.18, 0.03, 0.3), wrist=(-0.3, 0.03, 0.3), tip=(-0.45, -0.01, 0.3),
        chord=(0.17, 0.17, 0.15, 0.09), fingers=5, extras="",
        flap_T=0.26, cruise=10.0, walk=(0.5, 0.4), voxel=0.0016, tris=6000, lods=(2000, 600)),
}
ALL = list(BIRDS)


class Spec:
    """A species-module stand-in for the quadruped engine (NAME, J, B, BONES, CONFIG, build_prims)."""

    def __init__(self, name):
        self.NAME = name
        self.P = P = BIRDS[name]
        J = {k: V(*P[k]) for k in ("hip", "knee", "ankle", "toe", "shoulder", "elbow", "wrist", "tip", "tail_base", "tail_tip")}
        bc = V(*P["body_c"])
        br = P["body_r"]
        J["pelvis"] = bc + V(0, -br[1] * 0.6, 0)
        J["chest"] = bc + V(0, br[1] * 0.6, br[2] * 0.15)
        n = [V(*p) for p in P["neck"]]
        J["neck0"], J["neck1"], J["neck2"] = n
        J["head_t"] = V(*P["beak"][1])
        self.J = J
        self.BONES = [
            ("root", V(0, 0, 0), V(0, 0.1 * P["H"], 0), None),
            ("body", J["pelvis"], J["chest"], "root"),
            ("neck_1", J["neck0"], J["neck1"], "body"),
            ("neck_2", J["neck1"], J["neck2"], "neck_1"),
            ("head", J["neck2"], J["head_t"], "neck_2"),
            ("tail_1", J["tail_base"], J["tail_tip"], "body"),
            ("wing1_L", J["shoulder"], J["elbow"], "body"),
            ("wing2_L", J["elbow"], J["wrist"], "wing1_L"),
            ("wing3_L", J["wrist"], J["tip"], "wing2_L"),
            ("thigh_L", J["hip"], J["knee"], "body"),
            ("shank_L", J["knee"], J["ankle"], "thigh_L"),
            ("foot_L", J["ankle"], J["toe"], "shank_L"),
        ]
        H = P["H"]
        self.B = {"eye": tuple(P["eye"]), "eye_r": P["eye_r"], "eye_fwd": P.get("eye_fwd", 0.15), "scale": H / 1.555}
        span = abs(P["tip"][0]) + 0.05
        self.CONFIG = {"eyes": (tuple(P["eye"]), P["eye_r"]), "bbox": ((-span * 0.45, -H * 0.75 - 0.05, -0.01), (span * 0.45, H * 0.6, H * 1.02)),
                       "withers": H, "length": H * 1.2, "tris": P["tris"], "lods": P["lods"]}

    def build_prims(self, Qm):
        P, J = self.P, self.J
        Qm.PRIMS.clear()
        s = P["H"]
        BODY = ["body"]
        Qm.ell(P["body_c"], P["body_r"], BODY, k=0.03 * s, mirror=False)
        Qm.ell(P["breast"][0], P["breast"][1], ["body", "neck_1"], k=0.03 * s, mirror=False)
        nr = P["neck_r"]
        Qm.rc(tuple(J["neck0"]), tuple(J["neck1"]), nr[0], nr[1], ["neck_1", "body"], k=0.02 * s, mirror=False)
        Qm.rc(tuple(J["neck1"]), tuple(J["neck2"]), nr[1], nr[2], ["neck_2", "neck_1"], k=0.015 * s, mirror=False)
        Qm.ell(P["head_c"], P["head_r"], ["head"], k=0.012 * s, mirror=False)
        b0, b1, r0, r1 = P["beak"]
        if P.get("hooked"):
            mid = (V(*b0) * 0.4 + V(*b1) * 0.6) + V(0, 0, 0.006)
            Qm.rc(b0, tuple(mid), r0, r1 * 2.2, ["head"], k=0.003 * s, mirror=False)
            Qm.rc(tuple(mid), b1, r1 * 2.2, r1, ["head"], k=0.002 * s, mirror=False)
        else:
            Qm.rc(b0, b1, r0, r1, ["head"], k=0.004 * s, mirror=False, sx=0.8)
        # tail base (the fan is a feather card)
        Qm.rc(tuple(V(*P["body_c"]) + V(0, -P["body_r"][1] * 0.7, 0)), tuple(J["tail_base"]), P["body_r"][2] * 0.55,
              P["tail_w"][0] * 0.35, ["tail_1", "body"], k=0.02 * s, mirror=False, sx=1.6)
        # legs: feathered thigh/shank, scaly tarsus, toes (3 forward + 1 back)
        sr = P["shank_r"]
        Qm.ell(tuple(J["hip"]), (sr[0] * 1.3, sr[0] * 1.5, sr[0] * 1.6), ["thigh_L", "body"], k=0.02 * s)
        Qm.rc(tuple(J["hip"]), tuple(J["knee"]), sr[0], sr[0] * 0.85, ["thigh_L", "body"], k=0.015 * s)
        Qm.rc(tuple(J["knee"]), tuple(J["ankle"]), sr[0] * 0.85, sr[1], ["shank_L"], k=0.01 * s)
        Qm.rc(tuple(J["ankle"]), tuple(J["toe"] + V(0, -P["toe_len"] * 0.3, P["toe_r"])), P["tarsus_r"], P["tarsus_r"] * 0.85,
              ["foot_L"], k=0.004 * s)
        foot = J["toe"] + V(0, -P["toe_len"] * 0.3, P["toe_r"])
        for ang in (-0.45, 0.0, 0.45, math.pi):
            L = P["toe_len"] * (0.7 if ang == math.pi else 1.0)
            tip = foot + V(math.sin(ang) * L, math.cos(ang) * L, -P["toe_r"] * 0.8)
            Qm.rc(tuple(foot), tuple(tip), P["toe_r"], P["toe_r"] * 0.55, ["foot_L"], k=0.002 * s)
        if P["extras"] == "turkey":
            hc = V(*P["head_c"])
            Qm.rc(tuple(hc + V(0, 0.035, 0.01)), tuple(hc + V(0, 0.065, -0.05)), 0.008, 0.005, ["head"], k=0.004, mirror=False)   # snood
            Qm.ell(tuple(hc + V(0, 0.0, -0.06)), (0.022, 0.02, 0.04), ["head", "neck_2"], k=0.01, mirror=False)               # wattle
            Qm.rc(tuple(V(*P["breast"][0]) + V(0, 0.1, 0.05)), tuple(V(*P["breast"][0]) + V(0, 0.15, -0.12)), 0.012, 0.006,
                  ["body"], k=0.01, mirror=False)                                                                           # beard
        return list(Qm.PRIMS)


# ----------------------------------------------------------------------------------------------------------
# feather cards
# ----------------------------------------------------------------------------------------------------------
def wing_card(spec, arm):
    """Both wings as one card mesh: leading edge along shoulder-elbow-wrist-tip, trailing edge back by the chord.
    UV0 = (span u 0..1, chord v 0..1) for the feather shader; weights blend across the elbow and wrist."""
    P, J = spec.P, spec.J
    lead = [J["shoulder"], J["elbow"], J["wrist"], J["tip"]]
    seg = [np.linalg.norm(lead[i + 1] - lead[i]) for i in range(3)]
    total = sum(seg)
    cum = np.concatenate([[0.0], np.cumsum(seg)]) / total
    chord = P["chord"]
    nu, nv = 24, 4
    verts, faces, uvs, groups = [], [], [], []
    for sx in (-1.0, 1.0):
        o = len(verts)
        for i in range(nu + 1):
            u = i / nu
            k = min(int(np.searchsorted(cum, u, side="right") - 1), 2)
            f = (u - cum[k]) / max(cum[k + 1] - cum[k], 1e-9)
            p = lead[k] + (lead[k + 1] - lead[k]) * f
            c = float(np.interp(u, cum, chord))
            for j in range(nv + 1):
                v = j / nv
                q = p + V(0, -c * v, -0.004 * P["H"] * math.sin(math.pi * v))
                verts.append(V(q[0] * (1 if sx < 0 else -1), q[1], q[2]))
                uvs.append((u, 1.0 - v))
                side = "_L" if sx < 0 else "_R"
                w = {}
                # weights: body near the root, then the three wing bones with blends at the joints
                if u < 0.06:
                    w["body"] = 1.0 - u / 0.06
                    w["wing1" + side] = u / 0.06
                else:
                    for b, (a0, a1) in enumerate(zip(cum[:-1], cum[1:])):
                        lo, hi = a0 - 0.05, a1 + 0.05
                        if lo <= u <= hi:
                            t = 1.0 - min(abs(u - (a0 + a1) * 0.5) / ((a1 - a0) * 0.5 + 0.05), 1.0)
                            w["wing%d%s" % (b + 1, side)] = w.get("wing%d%s" % (b + 1, side), 0.0) + max(t, 0.01)
                s = sum(w.values())
                groups.append({k2: v2 / s for k2, v2 in w.items()})
        for i in range(nu):
            for j in range(nv):
                a = o + i * (nv + 1) + j
                b = a + nv + 1
                faces.append((a, b, b + 1, a + 1) if sx < 0 else (a, a + 1, b + 1, b))
    return _card("Plumage_Wings", verts, faces, uvs, groups, arm)


def tail_card(spec, arm):
    P, J = spec.P, spec.J
    b0, b1 = J["tail_base"], J["tail_tip"]
    w0, w1 = P["tail_w"]
    nu, nv = 8, 6
    verts, faces, uvs, groups = [], [], [], []
    for i in range(nu + 1):
        u = i / nu
        c = b0 + (b1 - b0) * u
        w = w0 + (w1 - w0) * u ** 0.8
        for j in range(nv + 1):
            v = j / nv
            verts.append(c + V((v - 0.5) * 2.0 * w, 0, 0.003 * P["H"] * (1 - (2 * v - 1) ** 2)))
            uvs.append((u, v))
            groups.append({"tail_1": min(1.0, u * 4.0 + 0.2), "body": max(0.0, 0.8 - u * 4.0)})
    for i in range(nu):
        for j in range(nv):
            a = i * (nv + 1) + j
            b = a + nv + 1
            faces.append((a, a + 1, b + 1, b))
    return _card("Plumage_Tail", verts, faces, uvs, groups, arm)


def _card(name, verts, faces, uvs, groups, arm):
    ob = Q.make_mesh(name, np.array(verts), faces)
    me = ob.data
    lay = me.uv_layers.new(name="UVMap")
    li = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", li)
    lay.data.foreach_set("uv", np.array(uvs, dtype=np.float64)[li].ravel())
    names = sorted({k for g in groups for k in g})
    vgs = {n: ob.vertex_groups.new(name=n) for n in names}
    for i, g in enumerate(groups):
        for n, w in g.items():
            if w > 0.0:
                vgs[n].add([i], float(w), "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    Q.shade_smooth(ob)
    ob.data.materials.append(Q.make_material(name.lower(), (0.3, 0.25, 0.2, 1), rough=0.8))
    return ob


# ----------------------------------------------------------------------------------------------------------
# clips (FK pose functions: (angles about local X, body location (forward, up), side rotations {bone: (z, y)}))
# ----------------------------------------------------------------------------------------------------------
FOLD = {"wing1": (1.45, -0.25), "wing2": (-2.75, 0.0), "wing3": (2.6, 0.0)}      # (side z, flap) folded at rest


def _wings(ang, side, flap=None, sweep=None, fold=0.0, splay=0.0):
    """Wing pose: fold 1 = folded on the back, 0 = spread; flap = up/down about the body axis (+ up) for
    (wing1, wing2, wing3); sweep adds side-z per segment (+ back)."""
    flap = flap or (0.0, 0.0, 0.0)
    sweep = sweep or (0.0, 0.0, 0.0)
    for k, b in enumerate(("wing1", "wing2", "wing3")):
        fz, fx = FOLD[b]
        z = fz * fold + sweep[k]
        x = fx * fold - flap[k] * (1.0 - fold)          # + about local X lowers the wing; the clips use + = up
        if b == "wing3":
            x -= splay
        ang[b + "_L"] = x
        ang[b + "_R"] = x
        side[b + "_L"] = (z, 0.0)
        side[b + "_R"] = (-z, 0.0)


def _legs(ang, l_ph=None, tuck=0.0, H=1.0, step=0.0):
    """Legs: tuck 1 = drawn up under the body (flight); l_ph = walking phase per leg (radians) or None."""
    for sd, off in (("L", 0.0), ("R", math.pi)):
        sw = math.sin(l_ph + off) if l_ph is not None else 0.0
        lift = max(0.0, math.sin(l_ph + off + math.pi * 0.5)) if l_ph is not None else 0.0
        ang["thigh_" + sd] = 0.35 * step * sw - 0.9 * tuck
        ang["shank_" + sd] = -0.5 * step * lift + 1.6 * tuck
        ang["foot_" + sd] = 0.4 * step * lift - 1.2 * tuck


def clips(spec):
    P = spec.P
    H = P["H"]
    fps = Q.ACTION_FPS
    T_flap = P["flap_T"]

    def solve(T, f, loop=True):
        n = max(int(round(T * fps)), 2)
        poses, sides = [], []
        for i in range(n + (0 if loop else 1)):
            t = i / fps
            ang, loc, side = f(t)
            poses.append((ang, loc))
            sides.append(side)
        return poses, sides

    def idle(T=3.0):
        def f(t):
            ang, side = {}, {}
            _wings(ang, side, fold=1.0)
            _legs(ang)
            look = math.sin(2 * math.pi * t / T)
            ang["neck_1"] = 0.03 * math.sin(2 * math.pi * t / 1.5)
            side["head"] = (0.5 * look * (abs(look) > 0.6), 0.0)
            ang["tail_1"] = 0.05 * math.sin(2 * math.pi * t / 1.0)
            return ang, (0.0, 0.002 * H * math.sin(2 * math.pi * t / 1.2)), side
        return solve(T, f)

    def walk(T=None):
        T = P["walk"][0] if T is None else T

        def f(t):
            ph = 2 * math.pi * t / T
            ang, side = {}, {}
            _wings(ang, side, fold=1.0)
            _legs(ang, ph, H=H, step=1.0)
            bob = math.sin(2 * ph)
            ang["neck_1"] = -0.12 * bob          # the head-bob: neck thrusts forward and back twice per stride
            ang["neck_2"] = 0.1 * bob
            ang["head"] = 0.03 * bob
            ang["body"] = 0.03 * math.sin(ph)
            side["body"] = (0.05 * math.sin(ph), 0.04 * math.sin(ph))
            ang["tail_1"] = 0.06 * math.sin(2 * ph)
            return ang, (0.0, 0.01 * H * abs(math.sin(ph))), side
        return solve(T, f)

    def peck(T=2.4):
        def f(t):
            ang, side = {}, {}
            _wings(ang, side, fold=1.0)
            _legs(ang)
            down = Q.env(t, 0.2, 0.6, 1.6, 2.0)
            jab = 0.12 * math.sin(2 * math.pi * t * 3.0) * down
            ang["body"] = -0.35 * down
            ang["neck_1"] = -0.6 * down
            ang["neck_2"] = -0.4 * down + jab
            ang["head"] = 0.3 * down
            ang["tail_1"] = -0.25 * down
            return ang, (0.0, -0.03 * H * down), side
        return solve(T, f)

    def alert(T=2.0):
        def f(t):
            ang, side = {}, {}
            _wings(ang, side, fold=1.0)
            _legs(ang)
            e = Q.env(t, 0.0, 0.25, 9.0, 10.0)
            ang["neck_1"] = 0.3 * e
            ang["neck_2"] = 0.15 * e
            ang["head"] = -0.3 * e
            side["head"] = (0.6 * math.sin(2 * math.pi * t / T) * e, 0.0)
            ang["tail_1"] = -0.2 * e
            return ang, (0.0, 0.01 * H * e), side
        return solve(T, f)

    def flap(T=None):
        T = T_flap if T is None else T

        def f(t):
            ph = 2 * math.pi * t / T
            ang, side = {}, {}
            s = math.sin(ph)
            up = max(0.0, math.cos(ph))                       # upstroke: the hand folds back (less drag)
            _wings(ang, side, flap=(0.75 * s, 0.25 * math.sin(ph - 0.5), 0.35 * math.sin(ph - 0.9)),
                   sweep=(0.15 * up, 0.25 * up, 0.35 * up), fold=0.0)
            _legs(ang, tuck=1.0)
            ang["body"] = 0.04 - 0.03 * s
            ang["neck_1"] = -0.25
            ang["head"] = 0.25
            ang["tail_1"] = -0.1 * s
            return ang, (0.0, -0.01 * H * s), side
        return solve(T, f)

    def glide(T=2.0):
        def f(t):
            ang, side = {}, {}
            wob = math.sin(2 * math.pi * t / T)
            _wings(ang, side, flap=(0.12 + 0.03 * wob, -0.04, 0.08), sweep=(0.05, 0.05, 0.1), fold=0.0)
            _legs(ang, tuck=1.0)
            ang["neck_1"] = -0.25
            ang["head"] = 0.25
            ang["tail_1"] = -0.05
            side["tail_1"] = (0.05 * wob, 0.0)
            return ang, (0.0, 0.0), side
        return solve(T, f)

    def soar(T=3.0):
        # broad wings held in a slight dihedral, primaries upturned and splayed, tail fanned
        def f(t):
            ang, side = {}, {}
            wob = math.sin(2 * math.pi * t / T)
            _wings(ang, side, flap=(0.2 + 0.03 * wob, -0.06, 0.05), sweep=(-0.05, 0.0, -0.05), fold=0.0, splay=0.25)
            _legs(ang, tuck=1.0)
            ang["neck_1"] = -0.3
            ang["head"] = 0.32 + 0.05 * wob
            side["head"] = (0.3 * math.sin(2 * math.pi * t / (T * 0.7)), 0.0)
            ang["tail_1"] = -0.08
            return ang, (0.0, 0.0), side
        return solve(T, f)

    def dive(T=1.0):
        # the stoop: wings swept back and half folded, legs reaching forward at the end
        def f(t):
            ang, side = {}, {}
            _wings(ang, side, flap=(0.15, -0.3, 0.2), sweep=(0.55, -0.4, 0.6), fold=0.12)
            _legs(ang, tuck=0.7)
            ang["body"] = -0.15
            ang["neck_1"] = -0.1
            ang["head"] = 0.1
            ang["tail_1"] = -0.1
            return ang, (0.0, 0.0), side
        return solve(T, f)

    def takeoff(T=0.7):
        def f(t):
            ang, side = {}, {}
            crouch = Q.env(t, 0.0, 0.12, 0.15, 0.25)
            beat = math.sin(2 * math.pi * t / (T_flap * 1.1))
            open_ = min(t / 0.15, 1.0)
            _wings(ang, side, flap=(0.95 * beat, 0.3 * beat, 0.4 * beat), fold=1.0 - open_)
            _legs(ang, tuck=min(max((t - 0.25) / 0.3, 0.0), 1.0))
            for sd in ("L", "R"):
                ang["thigh_" + sd] += 0.4 * crouch
                ang["shank_" + sd] -= 0.8 * crouch
            ang["body"] = 0.35 * min(t / 0.25, 1.0) - 0.2 * crouch
            ang["neck_1"] = -0.2
            ang["tail_1"] = 0.2 * crouch - 0.2
            return ang, (0.0, -0.05 * H * crouch), side
        return solve(T, f, loop=False)

    def land(T=0.6):
        def f(t):
            ang, side = {}, {}
            brake = Q.env(t, 0.0, 0.1, 0.35, 0.55)
            beat = math.sin(2 * math.pi * t / (T_flap * 1.3))
            _wings(ang, side, flap=(0.6 + 0.4 * beat * brake, 0.2, 0.3), fold=max(0.0, (t - 0.4) / 0.2))
            _legs(ang, tuck=0.0)
            for sd in ("L", "R"):
                ang["thigh_" + sd] = 0.6 * brake
            ang["body"] = 0.45 * brake
            ang["tail_1"] = -0.4 * brake
            return ang, (0.0, -0.03 * H * Q.env(t, 0.4, 0.5, 0.55, 0.6)), side
        return solve(T, f, loop=False)

    def death(T=1.2):
        def f(t):
            ang, side = {}, {}
            k = Q.env(t, 0.0, 0.6, 9.0, 10.0)
            _wings(ang, side, flap=(-0.3, 0.2, 0.1), fold=1.0 - 0.6 * k)
            _legs(ang, tuck=0.3 * k)
            ang["neck_1"] = -0.8 * k
            ang["neck_2"] = -0.6 * k
            ang["head"] = 0.5 * k
            side["body"] = (0.0, 1.45 * k)                      # rolls onto its side
            return ang, (0.0, -P["hip"][2] * 0.85 * k), side
        return solve(T, f, loop=False)

    def fall(T=0.8):
        # shot in the air: limp tumble (looped while falling)
        def f(t):
            ang, side = {}, {}
            r = math.sin(2 * math.pi * t / T)
            _wings(ang, side, flap=(0.5 + 0.4 * r, -0.4, 0.3 * r), fold=0.2)
            _legs(ang, tuck=0.2)
            ang["neck_1"] = -0.5
            ang["head"] = 0.6
            side["body"] = (0.0, 0.6 * r)
            return ang, (0.0, 0.0), side
        return solve(T, f)

    return {"idle": (idle, True), "walk": (walk, True), "peck": (peck, True), "alert": (alert, True),
            "flap": (flap, True), "glide": (glide, True), "soar": (soar, True), "dive": (dive, True),
            "fall": (fall, True), "takeoff": (takeoff, False), "land": (land, False), "death": (death, False)}


# ----------------------------------------------------------------------------------------------------------
def use_bird(name):
    spec = Spec(name)
    Q.SPEC = spec
    Q.J = spec.J
    Q.BONES = spec.BONES
    Q.SC = spec.B["scale"]
    Q.REST2 = None
    Q.BONE_SEGS = None
    Q.VOXEL = spec.P["voxel"] * (1.8 if Q.QUICK else 1.0)
    Q.LOGTAG = name[:6]
    return spec


def build_bird(name):
    spec = use_bird(name)
    P = spec.P
    cfg = spec.CONFIG
    os.makedirs(Q.OUT, exist_ok=True)
    Q.reset_scene()
    import bpy
    bpy.context.scene.render.fps = Q.FPS
    body, prims = Q.build_body()
    Q.decimate_to(body, cfg["tris"])
    Q.shade_smooth(body)
    log("%s body: %d tris" % (name, Q.tri_count(body)))
    arm = Q.build_armature()
    verts, _ = Q.mesh_arrays(body)
    A, deg = Q.mesh_adjacency(body)
    names, W = Q.compute_weights(verts, prims, A, deg, tau=0.006 * P["H"], tau_b=0.03 * P["H"])
    Q.assign_weights(body, names, W, arm)
    Q.set_rest_uvs(body)
    Q.bake_ao_curv(body, A, deg, rays=8 if Q.QUICK else 16, dist=0.25 * P["H"])
    body.data.materials.append(Q.make_material("bird_body", (0.3, 0.25, 0.2, 1), rough=0.7))
    wing_card(spec, arm)
    tail_card(spec, arm)
    Q.build_eyes(arm)
    Q.build_lods(body, arm, cfg["lods"])
    log("cards, eyes, LODs done")
    meta = {"fps": Q.FPS, "kind": "bird", "species": name, "gaits": {}, "anims": {}, "legs": {}}
    span = 2.0 * abs(P["tip"][0])
    meta["rest"] = {"withers_height": P["H"], "length": P["H"] * 1.2, "span": span}
    meta["flight"] = {"flap_period": P["flap_T"], "cruise": P["cruise"]}
    meta["gaits"]["walk"] = {"anim": "walk", "cycle": P["walk"][0], "stride": P["walk"][1],
                             "speed": P["walk"][1] / P["walk"][0], "type": "walk_biped"}
    if not Q.NO_ANIM:
        for aname, (builder, loop) in clips(spec).items():
            poses, sides = builder()
            Q.key_action(arm, aname, poses, side=sides, loop=loop, step=Q.ACTION_STEP)
            meta["anims"][aname] = {"length": (len(poses) if loop else len(poses) - 1) / Q.ACTION_FPS, "loop": loop}
        log("clips: %s" % ", ".join(meta["anims"]))
    meta["anchors"] = {"scale": spec.B["scale"] / 0.643, "eye": list(spec.B["eye"]), "head": list(P["head_c"]),
                       "body": list(P["body_c"]), "body_r": list(P["body_r"]), "tail_base": list(P["tail_base"]),
                       "tail_tip": list(P["tail_tip"]), "hip_z": P["hip"][2]}
    path = os.path.join(Q.OUT, name + ".glb")
    Q.export_glb(path)
    with open(os.path.join(Q.OUT, name + "_gaits.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    log("wrote %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))


def main():
    sp = _bird_arg("--species", "all")
    names = ALL if sp == "all" else sp.split(",")
    for n in names:
        build_bird(n)


if __name__ == "__main__":
    main()
