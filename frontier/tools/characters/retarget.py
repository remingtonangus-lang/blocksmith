"""Retarget CMU motion capture (cgspeed BVH conversion) onto the Frontier game rig and export animations.glb.

Method (per clip):
  1. BVH forward kinematics (bvh.py), converted to Blender axes (BVH Y-up/+Z-forward -> Blender Z-up/-Y-forward).
  2. Reference pose: the game rig's rest pose is swung bone-by-bone (top-down) so each mapped bone points like the
     BVH's frame-0 T-pose ("rest alignment"), giving per-bone reference world rotations Tref.
  3. Every frame: target_world(b) = source_world(j) * source_world_frame0(j)^-1 * Tref(b)  (world-space delta
     transfer: chain-length mismatches such as CMU's Neck/Neck1 vs our single Neck do not matter).
  4. Hips translation scaled by leg-length ratio; root motion extracted onto the Root bone (ground projection of the
     hips, smoothed heading); clips canonicalised to face model-forward and start at the origin.
  5. Loops: best cycle found inside the clip window by pose distance + crossfade; non-loop clips trimmed.
  6. Resampled to 30 fps, quaternion keys on every mapped bone (location only on Root and Hips), finger curl constant.
  7. Foot contacts (toe/heel height + speed) and speed metadata written to animations.json.
"""
import os
import json
import math
import numpy as np
import bpy
from mathutils import Matrix, Vector, Quaternion

import mhenv
import mhcore as C
from bvh import BVH

FPS = 30
CMU_SCALE = 0.056444  # CMU length unit -> metres (only used for diagnostics; hips use the leg-length ratio)

# target bone -> (source joint, target direction child, source direction child)
MAP = {
    "Hips": ("Hips", None, None),
    "Spine": ("LowerBack", "Chest", "Spine"),
    "Chest": ("Spine", "UpperChest", "Spine1"),
    "UpperChest": ("Spine1", "Neck", "Neck"),
    "Neck": ("Neck", "Head", "Head"),
    "Head": ("Head", None, None),
}
for S, s in (("Left", "Left"), ("Right", "Right")):
    MAP.update({
        S + "Shoulder": (s + "Shoulder", S + "UpperArm", s + "Arm"),
        S + "UpperArm": (s + "Arm", S + "LowerArm", s + "ForeArm"),
        S + "LowerArm": (s + "ForeArm", S + "Hand", s + "Hand"),
        S + "Hand": (s + "Hand", S + "MiddleProximal", s + "FingerBase"),
        S + "UpperLeg": (s + "UpLeg", S + "LowerLeg", s + "Leg"),
        S + "LowerLeg": (s + "Leg", S + "Foot", s + "Foot"),
        S + "Foot": (s + "Foot", S + "Toes", s + "ToeBase"),
        S + "Toes": (s + "ToeBase", None, None),
    })

# name, file, start s, end s, loop, kind, extra
# kind: loco (root motion straightened, loop), idle (loop, root fixed), action (trimmed, root motion kept),
#       reverse (played backwards, e.g. get-up -> collapse)
CLIPS = [
    ("idle", "140_07", 0.5, 9.5, True, "idle", {}),
    ("idle_2", "111_28", 1.0, 13.0, True, "idle", {}),
    ("idle_shift", "139_02", 0.5, 7.0, True, "idle", {}),
    ("idle_wait", "40_10", 0.5, 6.0, True, "idle", {}),
    ("walk", "82_11", 2.4, 5.4, True, "loco", {}),
    ("walk_brisk", "104_19", 1.8, 5.2, True, "loco", {}),
    ("walk_relaxed", "91_29", 3.0, 7.5, True, "loco", {}),
    ("walk_old", "142_07", 8.0, 16.0, True, "loco", {}),
    ("walk_wounded", "139_19", 1.2, 4.6, True, "loco", {"cycle": (0.9, 2.2)}),
    ("walk_crouch", "136_09", 3.0, 8.5, True, "loco", {}),
    ("sneak", "139_29", 3.0, 8.0, True, "loco", {}),
    ("jog", "16_35", 0.05, 1.3, True, "loco", {"cycle": (0.5, 0.9)}),
    ("run", "09_01", 0.05, 1.2, True, "loco", {"cycle": (0.5, 0.85)}),
    ("sprint", "143_02", 0.02, 0.8, True, "loco", {"cycle": (0.45, 0.75)}),
    ("carry_walk", "111_36", 1.5, 6.0, True, "loco", {}),
    ("walk_start", "82_11", 0.2, 2.6, False, "action", {}),
    ("walk_stop", "104_19", 5.0, 7.2, False, "action", {}),
    ("jog_start", "104_06", 0.2, 2.6, False, "action", {}),
    ("jog_stop", "104_09", 0.0, 2.6, False, "action", {}),
    ("run_start", "104_53", 0.2, 2.5, False, "action", {}),
    ("run_stop", "104_56", 0.0, 2.6, False, "action", {}),
    ("walk_turn_90_R", "69_20", 0.0, 4.6, False, "action", {}),
    ("walk_turn_90_L", "69_24", 0.0, 3.6, False, "action", {}),
    ("jog_turn_90_L", "16_41", 0.0, 1.3, False, "action", {}),
    ("jog_turn_90_R", "16_43", 0.0, 1.7, False, "action", {}),
    ("turn_in_place_L", "69_16", 0.0, 3.0, False, "action", {}),
    ("turn_in_place_R", "69_18", 0.0, 3.0, False, "action", {}),
    ("talk_1", "18_08", 2.0, 8.0, True, "idle", {}),
    ("talk_2", "18_08", 9.0, 16.0, True, "idle", {}),
    ("talk_directions", "139_25", 0.0, 5.5, False, "action", {}),
    ("shrug", "141_21", 0.0, 2.3, False, "action", {}),
    ("wave", "141_16", 0.0, 2.5, False, "action", {}),
    ("handshake", "141_23", 0.4, 2.1, False, "action", {}),
    ("sit_down", "113_15", 1.2, 3.4, False, "action", {}),
    ("sit_idle", "114_05", 0.5, 10.0, True, "idle", {}),
    ("stand_up", "113_15", 4.6, 7.0, False, "action", {}),
    ("lean_rail", "22_18", 1.8, 4.5, False, "action", {}),
    ("drink", "80_40", 0.0, 7.6, False, "action", {}),
    ("drink_smoke", "80_28", 0.0, 10.2, False, "action", {}),
    ("pistol_draw", "139_05", 0.0, 4.3, False, "action", {}),
    ("pistol_shoot", "79_96", 0.0, 4.7, False, "action", {}),
    ("gun_shoot_2", "80_03", 0.0, 5.5, False, "action", {}),
    ("death_forward", "90_16", 2.8, 6.0, False, "action", {}),
    ("death_back", "90_18", 0.6, 3.3, False, "action", {}),
    ("death_collapse", "140_01", 0.0, 4.2, False, "reverse", {}),
    ("get_up_front", "140_01", 1.8, 6.4, False, "action", {}),
    ("get_up_back", "139_18", 2.6, 6.0, False, "action", {}),
    ("climb_ladder", "13_33", 2.4, 7.4, False, "action", {}),
    ("ladder_up_down", "143_37", 0.0, 4.6, False, "action", {}),
    ("climb_over", "141_07", 0.0, 2.5, False, "action", {}),
    ("jump", "16_01", 0.0, 2.7, False, "action", {}),
    ("jump_forward", "13_11", 1.0, 3.5, False, "action", {}),
    ("run_jump", "75_01", 0.4, 3.1, False, "action", {}),
    ("pick_up", "115_06", 0.0, 3.0, False, "action", {}),
    ("push_heavy", "81_06", 1.0, 7.0, False, "action", {}),
    ("pick_up_box", "143_10", 0.0, 4.8, False, "action", {}),
]


# ------------------------------------------------------------------------------------------------------------------
def canonical_rig():
    """Default MPFB human (all macros 0.5) with the game rig -> armature object with Godot bone names + eyes."""
    C.reset_scene()
    HS = C.mhenv.svc("humanservice").HumanService
    bm = HS.create_human(mask_helpers=False)
    co = C.get_co(bm)
    eyes = {}
    for jn in ("joint-l-eye", "joint-r-eye"):
        m = C.group_vertex_mask(bm, jn)
        eyes[jn] = Vector(co[m].mean(axis=0).tolist())
    HS.add_builtin_rig(bm, "game_engine")
    rig = bm.parent
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for jn, bn in (("joint-l-eye", "LeftEye"), ("joint-r-eye", "RightEye")):
        b = rig.data.edit_bones.new(bn)
        b.head = eyes[jn]
        b.tail = eyes[jn] + Vector((0, -0.025, 0))
        b.parent = rig.data.edit_bones["head"]
    bpy.ops.object.mode_set(mode="OBJECT")
    for old, new in C.GODOT_BONES.items():
        b = rig.data.bones.get(old)
        if b:
            b.name = new
    bpy.data.objects.remove(bm, do_unlink=True)
    rig.name = "Rig"
    rig.data.name = "Rig"
    return rig


AX = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=np.float64)  # BVH -> Blender axes


def swing(a, b):
    """Shortest-arc rotation (3x3) taking unit vector a onto b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.9999:
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return np.array(Matrix.Rotation(math.pi, 3, Vector(axis)))
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def quat_from_mats(M):
    """[N,3,3] rotation matrices -> [N,4] quaternions (w,x,y,z), sign-continuous."""
    out = np.zeros((M.shape[0], 4))
    for i in range(M.shape[0]):
        q = Matrix(M[i].tolist()).to_quaternion()
        out[i] = (q.w, q.x, q.y, q.z)
        if i and np.dot(out[i], out[i - 1]) < 0:
            out[i] = -out[i]
    return out


def slerp_rows(q0, q1, t):
    a = Quaternion(q0)
    b = Quaternion(q1)
    r = a.slerp(b, t)
    return np.array((r.w, r.x, r.y, r.z))


def yaw_of(R):
    """Heading (radians about +Z) of a Blender-space rotation whose forward is -Y."""
    f = R @ np.array([0.0, -1.0, 0.0])
    return math.atan2(f[0], -f[1])  # 0 when facing -Y; rotz(a) -> a


def rotz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])


class Retargeter:
    def __init__(self, rig):
        self.rig = rig
        bones = rig.data.bones
        self.order = []

        def walk(b):
            self.order.append(b.name)
            for c in b.children:
                walk(c)
        for b in bones:
            if b.parent is None:
                walk(b)
        self.rest = {b.name: np.array(b.matrix_local) for b in bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.head = {b.name: np.array(b.head_local) for b in bones}
        # leg length (hip joint to ankle) for hips scaling
        self.leg = (np.linalg.norm(self.head["LeftUpperLeg"] - self.head["LeftLowerLeg"]) +
                    np.linalg.norm(self.head["LeftLowerLeg"] - self.head["LeftFoot"]))
        self.hips_h = self.head["Hips"][2]

    def reference(self, Rs0, Ps0, jidx):
        """Per-bone reference world rotations: rest pose swung to the source frame-0 directions."""
        A = {}
        Tref = {}
        for b in self.order:
            p = self.parent[b]
            acc = A[p] if p is not None else np.eye(3)
            m = MAP.get(b)
            if m and m[1] and m[2] in jidx and m[1] in self.head:
                dt = acc @ (self.head[m[1]] - self.head[b])
                ds = Ps0[jidx[m[2]]] - Ps0[jidx[m[0]]]
                if np.linalg.norm(ds) > 1e-6 and np.linalg.norm(dt) > 1e-6:
                    acc = swing(dt, ds) @ acc
            A[b] = acc
            Tref[b] = acc @ self.rest[b][:3, :3]
        return Tref

    def retarget(self, bvh, start, end, kind, loop, extra):
        R, P, ends = bvh.fk()
        jidx = bvh.index
        # Blender axes
        Rb = np.einsum("ij,fkjl,ml->fkim", AX, R, AX)
        Pb = np.einsum("ij,fkj->fki", AX, P)
        Eb = {k: np.einsum("ij,fj->fi", AX, v) for k, v in ends.items()}
        Tref = self.reference(Rb[0], Pb[0], jidx)
        # source leg length from the T-pose frame
        sl = (np.linalg.norm(Pb[0, jidx["LeftUpLeg"]] - Pb[0, jidx["LeftLeg"]]) +
              np.linalg.norm(Pb[0, jidx["LeftLeg"]] - Pb[0, jidx["LeftFoot"]]))
        scale = self.leg / sl
        src_ground = min(Eb["LeftToeBase"][0, 2], Eb["RightToeBase"][0, 2], Pb[0, jidx["LeftFoot"], 2])
        # resample window (skip T-pose frame 0)
        dt = bvh.frame_time
        f0 = 1 + int(round(start / dt))
        f1 = min(bvh.nframes - 1, 1 + int(round(end / dt)))
        times = np.arange(f0 * dt, f1 * dt, 1.0 / FPS)
        idx = np.clip(np.round(times / dt).astype(int), 1, bvh.nframes - 1)
        if kind == "reverse":
            idx = idx[::-1]
        n = len(idx)
        # world rotations per target bone
        Rinv0 = {}
        W = {}
        for b in self.order:
            m = MAP.get(b)
            if not m:
                continue
            j = jidx[m[0]]
            W[b] = np.einsum("fij,jk,kl->fil", Rb[idx, j], Rb[0, j].T, Tref[b])
        hips = (Pb[idx, jidx["Hips"]] - np.array([0, 0, src_ground])) * scale
        # --- root motion: ground projection + heading
        heading = np.array([yaw_of(W["Hips"][i] @ np.linalg.inv(self.rest["Hips"][:3, :3])) for i in range(n)])
        heading = np.unwrap(heading)
        if kind in ("loco",):
            travel = hips[-1, :2] - hips[0, :2]
            base_yaw = math.atan2(travel[0], -travel[1]) if np.linalg.norm(travel) > 0.2 else heading[0]
        else:
            base_yaw = heading[:min(n, 8)].mean()
        # canonicalise: rotate everything by -base_yaw about Z and move start to origin
        Rc = rotz(-base_yaw)
        origin = hips[0].copy()
        origin[2] = 0.0
        hips = (hips - origin) @ Rc.T
        for b in W:
            W[b] = np.einsum("ij,fjk->fik", Rc, W[b])
        heading = heading - base_yaw
        # smoothed root trajectory
        k = max(1, int(0.25 * FPS))
        ker = np.ones(2 * k + 1) / (2 * k + 1)
        def smooth(x):
            xp = np.pad(x, (k, k), mode="edge")
            return np.convolve(xp, ker, mode="valid")
        root_xy = np.stack([smooth(hips[:, 0]), smooth(hips[:, 1])], axis=1)
        root_yaw = smooth(heading)
        if kind == "idle":
            root_xy[:] = root_xy.mean(axis=0)
            root_yaw[:] = root_yaw.mean()
        # --- loop extraction
        loop_range = None
        if loop:
            loop_range = self._find_loop(W, hips, root_xy, extra.get("cycle", (0.8, 1.8) if kind == "loco" else (2.0, 9.0)), n)
        return dict(W=W, hips=hips, root_xy=root_xy, root_yaw=root_yaw, n=n, loop=loop_range, kind=kind)

    def _find_loop(self, W, hips, root_xy, cycle, n):
        keys = [b for b in ("LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftUpperArm",
                            "RightUpperArm", "Spine", "Hips") if b in W]
        # pose features relative to hips heading
        feats = []
        for b in keys:
            rel = np.einsum("fji,fjk->fik", W["Hips"], W[b]) if b != "Hips" else W["Hips"]
            feats.append(rel.reshape(n, 9))
        hips_rel = hips - np.concatenate([root_xy, np.zeros((n, 1))], axis=1)
        vel = np.gradient(hips_rel, axis=0) * FPS
        F = np.concatenate(feats + [hips_rel * 4.0, vel * 0.3], axis=1)
        lo, hi = int(cycle[0] * FPS), int(cycle[1] * FPS)
        best = (1e9, 0, min(n - 1, hi))
        for a in range(0, max(1, n - lo)):
            for b in range(a + lo, min(n, a + hi + 1)):
                d = np.sum((F[a] - F[b]) ** 2) + 0.5 * np.sum((F[min(a + 1, n - 1)] - F[min(b + 1, n - 1)]) ** 2)
                if d < best[0]:
                    best = (d, a, b)
        return best[1], best[2], best[0]

    # --------------------------------------------------------------------------------------------------------------
    def bake(self, name, res):
        """Write an action on the canonical rig; returns metadata."""
        W, hips, root_xy, root_yaw = res["W"], res["hips"], res["root_xy"], res["root_yaw"]
        n = res["n"]
        frames = list(range(n))
        loop = res["loop"]
        if loop:
            a, b, _ = loop
            frames = list(range(a, b + 1))
        L = len(frames)
        rest = self.rest
        out_q = {bn: np.zeros((L, 4)) for bn in self.order}
        root_loc = np.zeros((L, 3))
        hips_loc = np.zeros((L, 3))
        world_pos = {bn: np.zeros((L, 3)) for bn in ("LeftFoot", "RightFoot", "LeftToes", "RightToes")}
        speed = 0.0
        if loop:
            a, b, _ = loop
            dur = (b - a) / FPS
            disp = root_xy[b] - root_xy[a]
            speed = float(np.linalg.norm(disp) / max(dur, 1e-3)) if res["kind"] == "loco" else 0.0
        curl = self._finger_curl()
        for fi, f in enumerate(frames):
            if loop and res["kind"] == "loco":
                # straight constant-velocity root along -Y (model forward)
                t = (f - frames[0]) / FPS
                rxy = np.array([0.0, -speed * t])
                ryaw = 0.0
                # hips relative to the actual (smoothed) root, re-expressed on the straight root
                hrel = hips[f] - np.array([root_xy[f][0], root_xy[f][1], 0.0])
                Rfix = rotz(-root_yaw[f])
                hrel = Rfix @ hrel
                hp = np.array([rxy[0], rxy[1], 0.0]) + hrel
                Wf = {bn: Rfix @ W[bn][f] for bn in W}
            else:
                rxy = root_xy[f] - (root_xy[frames[0]] if res["kind"] != "idle" else 0.0)
                ryaw = root_yaw[f] - (root_yaw[frames[0]] if res["kind"] != "idle" else 0.0)
                hp = hips[f] - np.array([root_xy[frames[0]][0], root_xy[frames[0]][1], 0.0]) if res["kind"] != "idle" \
                    else hips[f] - np.array([root_xy[f][0], root_xy[f][1], 0.0])
                Wf = {bn: W[bn][f] for bn in W}
                if res["kind"] == "idle":
                    Ry = rotz(-root_yaw[f])
                    hp = Ry @ hp
                    Wf = {bn: Ry @ Wf[bn] for bn in Wf}
                    rxy = np.zeros(2)
                    ryaw = 0.0
            M = {}
            for bn in self.order:
                p = self.parent[bn]
                if bn == "Root":
                    Mr = np.eye(4)
                    Mr[:3, :3] = rotz(ryaw) @ rest[bn][:3, :3]
                    Mr[:3, 3] = (rest[bn][:3, 3] + np.array([rxy[0], rxy[1], 0.0]))
                    M[bn] = Mr
                    basis = np.linalg.inv(rest[bn]) @ Mr
                    root_loc[fi] = basis[:3, 3]
                    out_q[bn][fi] = _q(basis[:3, :3])
                    continue
                Mp = M[p] if p else np.eye(4)
                off = np.linalg.inv(rest[p]) @ rest[bn] if p else rest[bn]
                if bn in Wf:
                    Mw = np.eye(4)
                    Mw[:3, :3] = Wf[bn]
                    if bn == "Hips":
                        Mw[:3, 3] = hp
                    else:
                        Mw[:3, 3] = (Mp @ off)[:3, 3]
                    basis = np.linalg.inv(off) @ np.linalg.inv(Mp) @ Mw
                else:
                    basis = np.eye(4)
                    if bn in curl:
                        basis[:3, :3] = curl[bn]
                    Mw = Mp @ off @ basis
                if bn == "Hips":
                    hips_loc[fi] = basis[:3, 3]
                M[bn] = Mw
                out_q[bn][fi] = _q(basis[:3, :3])
            for bn in world_pos:
                tail = M[bn] @ np.array([0.0, 0.0, 0.0, 1.0])
                world_pos[bn][fi] = tail[:3]
        # loop seam: the cycle search picks matching poses; the remaining end/start mismatch is spread linearly
        if loop:
            ramp = np.linspace(0.0, 1.0, L)[:, None]
            for bn in self.order:
                q = out_q[bn]
                for i in range(1, L):
                    if np.dot(q[i], q[i - 1]) < 0:
                        q[i] = -q[i]
                q += (q[0] - q[-1]) * ramp
                q /= np.linalg.norm(q, axis=1, keepdims=True)
            hips_loc += (hips_loc[0] - hips_loc[-1]) * ramp
        act = self._write_action(name, out_q, root_loc, hips_loc, L)
        contacts = self._contacts(world_pos, L)
        return {"name": name, "frames": L, "fps": FPS, "duration": round((L - 1) / FPS, 3),
                "loop": bool(loop), "speed": round(speed, 3),
                "root_motion": [round(float(x), 3) for x in (root_loc[-1] - root_loc[0])],
                "contacts": contacts}

    def _finger_curl(self):
        """Relaxed hand: small curl on every finger joint (local X rotation)."""
        out = {}
        for S in ("Left", "Right"):
            for f, base in (("Index", 12), ("Middle", 15), ("Ring", 18), ("Little", 21)):
                for k, mul in (("Proximal", 1.0), ("Intermediate", 1.4), ("Distal", 1.0)):
                    out[S + f + k] = np.array(Matrix.Rotation(math.radians(base * mul), 3, "X"))
            out[S + "ThumbProximal"] = np.array(Matrix.Rotation(math.radians(10), 3, "X"))
        return out

    def _write_action(self, name, out_q, root_loc, hips_loc, L):
        rig = self.rig
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        slot = act.slots.new(id_type="OBJECT", name="Rig")
        layer = act.layers.new("Layer")
        strip = layer.strips.new(type="KEYFRAME")
        cb = strip.channelbag(slot, ensure=True)
        frames = np.arange(L, dtype=np.float32)

        def put(path, idx, vals, group):
            fc = cb.fcurves.new(path, index=idx, group_name=group)
            fc.keyframe_points.add(L)
            co = np.empty(L * 2, dtype=np.float32)
            co[0::2] = frames
            co[1::2] = vals
            fc.keyframe_points.foreach_set("co", co)
            fc.keyframe_points.foreach_set("interpolation", [2] * L)  # LINEAR
            fc.update()
        for bn in self.order:
            pb = rig.pose.bones[bn]
            pb.rotation_mode = "QUATERNION"
            path = 'pose.bones["%s"].rotation_quaternion' % bn
            for i in range(4):
                put(path, i, out_q[bn][:, i], bn)
        for bn, loc in (("Root", root_loc), ("Hips", hips_loc)):
            path = 'pose.bones["%s"].location' % bn
            for i in range(3):
                put(path, i, loc[:, i], bn)
        return act

    def _contacts(self, wp, L):
        out = {}
        for side in ("Left", "Right"):
            heel = wp[side + "Foot"]
            toe = wp[side + "Toes"]
            h = np.minimum(heel[:, 2], toe[:, 2])
            g = np.percentile(h, 5)
            v = np.linalg.norm(np.gradient(toe[:, :2], axis=0), axis=1) * FPS
            c = (h - g < 0.05) & (v < 0.6)
            # intervals in normalised time
            iv = []
            st = None
            for i, x in enumerate(c):
                if x and st is None:
                    st = i
                if (not x or i == L - 1) and st is not None:
                    en = i if not x else i
                    if en - st >= 2:
                        iv.append([round(st / max(L - 1, 1), 3), round(en / max(L - 1, 1), 3)])
                    st = None
            out[side.lower()] = iv
        return out


def _q(m):
    q = Matrix(m.tolist()).to_quaternion()
    return np.array((q.w, q.x, q.y, q.z))


def build_library(out_dir, clips=None, only=None):
    rig = canonical_rig()
    rt = Retargeter(rig)
    bpy.context.scene.render.fps = FPS
    meta = []
    actions = []
    for name, f, a, b, loop, kind, extra in CLIPS:
        if only and name not in only:
            continue
        subj = f.split("_")[0]
        p = os.path.join(mhenv.CMU, "data", "%03d" % int(subj), f + ".bvh")
        if not os.path.exists(p):
            print("WARN missing", p)
            continue
        bvh = BVH(p)
        res = rt.retarget(bvh, a, b, kind, loop, extra)
        m = rt.bake(name, res)
        m["source"] = "CMU %s" % f
        meta.append(m)
        print("clip %-18s %4d frames loop=%s speed=%.2f" % (name, m["frames"], m["loop"], m["speed"]))
    # assign each action to the rig through NLA tracks so the exporter writes one glTF animation per action
    rig.animation_data_create()
    for act in bpy.data.actions:
        tr = rig.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, 0, act)
        st.action_slot = act.slots[0]
    rig.animation_data.action = None
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "animations.glb")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_frame_range=False, export_anim_single_armature=True, export_yup=True,
                              export_def_bones=False, export_optimize_animation_size=True,
                              export_skins=True, export_morph=False, export_bake_animation=False,
                              export_reset_pose_bones=True)
    info = {"file": "animations.glb", "fps": FPS, "rest_hips_height": round(float(rt.hips_h), 4),
            "source": "CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), cgspeed BVH conversion",
            "clips": meta}
    with open(os.path.join(out_dir, "animations.json"), "w") as f:
        json.dump(info, f, indent=1)
    return info
