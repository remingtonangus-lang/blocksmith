"""Procedural 1899 garments, hats, beards and gun belts fitted to a MakeHuman body (runs inside `bpy`).

All garments are original procedural geometry:
  * body-derived shells (shirt, vest, trousers, coat, bodice, boots): faces of the body region duplicated, offset
    along the normals by the garment's layer thickness, smoothed for drape, folds displaced near joints and hems,
    rim thickness at the hems; skin weights copied 1:1 from the body vertices they came from.
  * lofted tubes (skirts, coat tails, aprons): rings from the waist down whose radius follows the body envelope with
    ease + flare; weights blended pelvis -> thighs with depth so they swing with the legs without tearing.
  * lathed hats (cattleman, boss-of-the-plains, bowler, flat cap, boater) sized to the head at the band line,
    weighted 100 % to the head; hair under a hat is pushed inside the crown.
  * beard / moustache shells (3 alpha layers over the beard region, follow the face blend shapes).
Every garment gets UV2 in metres (fabric tiling), vertex colours (r occlusion, g wear) and a material named
"cloth:<id>:<fabric>" (or "leather:..."/"metal:...") that character_materials.gd turns into the cloth shader.
"""
import math
import os
import numpy as np
import bpy
import bmesh
from mathutils import Vector

import mhcore as C

# ------------------------------------------------------------------------------------------------------------------
# numpy value noise (deterministic)


def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


def vnoise3(p, seed=0):
    """p: [N,3] -> [-1,1] smooth value noise."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3 - 2 * f)
    out = np.zeros(p.shape[0])
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out * 2 - 1


def fbm3(p, seed=0, oct=3):
    s, a = 0.0, 0.5
    for o in range(oct):
        s = s + a * vnoise3(p, seed + o * 17)
        p = p * 2.03 + 3.1
        a *= 0.5
    return s


# ------------------------------------------------------------------------------------------------------------------
class BodyInfo:
    """Per-vertex body data: dominant bone, limb parameters, joint positions (game_engine bone names)."""

    def __init__(self, builder):
        bm = builder.basemesh
        rig = builder.rig
        self.co = C.get_co(bm)
        self.n = self.co.shape[0]
        self.body = C.group_vertex_mask(bm, "body")
        names = [vg.name for vg in bm.vertex_groups]
        W = np.zeros((self.n, len(names)), dtype=np.float32)
        for v in bm.data.vertices:
            for g in v.groups:
                W[v.index, g.group] = g.weight
        bones = set(b.name for b in rig.data.bones)
        cols = [i for i, nm in enumerate(names) if nm in bones]
        self.bone_names = [names[i] for i in cols]
        self.W = W[:, cols]
        self.dom = np.array(self.bone_names)[np.argmax(self.W, axis=1)]
        self.j = {b.name: np.array(b.head_local) for b in rig.data.bones}
        self.t = {b.name: np.array(b.tail_local) for b in rig.data.bones}
        j = self.j
        self.ankle_z = (j["foot_l"][2] + j["foot_r"][2]) / 2
        self.knee_z = (j["calf_l"][2] + j["calf_r"][2]) / 2
        self.hip_z = (j["thigh_l"][2] + j["thigh_r"][2]) / 2
        self.pelvis = j["pelvis"]
        self.neck = j["neck_01"]
        self.head = j["head"]
        self.shoulder_z = (j["upperarm_l"][2] + j["upperarm_r"][2]) / 2
        bodyco = self.co[self.body]
        self.top_z = bodyco[:, 2].max()
        crotch = self.body & (np.abs(self.co[:, 0]) < 0.02) & (self.co[:, 2] < self.hip_z + 0.05)
        self.crotch_z = self.co[crotch, 2].max() if crotch.any() else self.hip_z - 0.08
        self.navel_z = self.hip_z + 0.13 * (self.top_z / 1.75)
        self.arm_p = np.full(self.n, -1.0)
        self.leg_p = np.full(self.n, -1.0)
        for s in ("l", "r"):
            a = self._chain_param([j["upperarm_" + s], j["lowerarm_" + s], j["hand_" + s]])
            side = (self.co[:, 0] > 0) if s == "l" else (self.co[:, 0] <= 0)
            self.arm_p = np.where(side, a, self.arm_p)
            lp = self._chain_param([j["thigh_" + s], j["calf_" + s], j["foot_" + s]])
            self.leg_p = np.where(side, lp, self.leg_p)
        me = bm.data
        e = np.empty(len(me.edges) * 2, dtype=np.int32)
        me.edges.foreach_get("vertices", e)
        self.edges = e.reshape(-1, 2)
        nrm = np.empty(self.n * 3, dtype=np.float32)
        me.vertices.foreach_get("normal", nrm)
        self.nrm = nrm.reshape(-1, 3)
        uv = me.uv_layers.active.data
        luv = np.empty(len(uv) * 2, dtype=np.float32)
        uv.foreach_get("uv", luv)
        self.loop_uv = luv.reshape(-1, 2)

    def _chain_param(self, pts):
        """Projection parameter of every vertex on a 2-segment chain: 0 at pts[0], 1 at pts[1], 2 at pts[2]."""
        best_d = np.full(self.n, 1e9)
        par = np.zeros(self.n)
        for k in range(2):
            a, b = pts[k], pts[k + 1]
            ab = b - a
            L2 = float(ab @ ab)
            t = np.clip(((self.co - a) @ ab) / L2, 0, 1)
            d = np.linalg.norm(self.co - (a + t[:, None] * ab), axis=1)
            m = d < best_d
            best_d = np.where(m, d, best_d)
            par = np.where(m, k + t, par)
        return par

    def dom_in(self, prefixes):
        m = np.zeros(self.n, dtype=bool)
        for p in prefixes:
            m |= np.char.startswith(self.dom.astype(str), p)
        return m

    def erode(self, mask, rings=1):
        e = self.edges
        for _ in range(rings):
            bad = np.zeros_like(mask)
            out_a = mask[e[:, 0]] & ~mask[e[:, 1]]
            out_b = mask[e[:, 1]] & ~mask[e[:, 0]]
            bad[e[out_a, 0]] = True
            bad[e[out_b, 1]] = True
            mask = mask & ~bad
        return mask


# ------------------------------------------------------------------------------------------------------------------
def _shell_from_region(builder, info, vmask, name):
    """Copy of the basemesh keeping faces whose vertices are all in vmask (body only). Keeps vertex groups."""
    bm = builder.basemesh
    obj = bm.copy()
    obj.data = bm.data.copy()
    bpy.context.collection.objects.link(obj)
    obj.shape_key_clear()
    for m in list(obj.modifiers):
        if m.type != "ARMATURE":
            obj.modifiers.remove(m)
    me = obj.data
    oi = me.attributes.get("src_index") or me.attributes.new("src_index", "INT", "POINT")
    oi.data.foreach_set("value", np.arange(len(me.vertices), dtype=np.int32))
    keep = vmask & info.body
    b = bmesh.new()
    b.from_mesh(me)
    dead = [f for f in b.faces if not all(keep[v.index] for v in f.verts)]
    bmesh.ops.delete(b, geom=dead, context="FACES")
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
    b.to_mesh(me)
    b.free()
    me.update()
    obj.name = name
    for vg in list(obj.vertex_groups):
        if vg.name.startswith(("joint-", "helper-", "Delete.", "HelperGeometry", "JointCubes", "body", "Left",
                               "Right", "Mid")):
            obj.vertex_groups.remove(vg)
    return obj


def _src_index(obj):
    a = np.empty(len(obj.data.vertices), dtype=np.int32)
    obj.data.attributes["src_index"].data.foreach_get("value", a)
    return a


def _neighbors(obj):
    me = obj.data
    e = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def _laplacian(co, edges, iters, lam, fixed=None):
    n = co.shape[0]
    for _ in range(iters):
        acc = np.zeros_like(co)
        cnt = np.zeros(n)
        np.add.at(acc, edges[:, 0], co[edges[:, 1]])
        np.add.at(acc, edges[:, 1], co[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        avg = acc / np.maximum(cnt, 1)[:, None]
        new = co + lam * (avg - co)
        if fixed is not None:
            new[fixed] = co[fixed]
        co = new
    return co


def _boundary_verts(obj):
    b = bmesh.new()
    b.from_mesh(obj.data)
    m = np.zeros(len(b.verts), dtype=bool)
    for e in b.edges:
        if e.is_boundary:
            m[e.verts[0].index] = True
            m[e.verts[1].index] = True
    b.free()
    return m


def _boundary_distance(obj, rings=6):
    """Graph distance (in edges) from the open boundary, capped."""
    edges = _neighbors(obj)
    d = np.full(len(obj.data.vertices), rings, dtype=np.float32)
    front = _boundary_verts(obj)
    d[front] = 0
    for r in range(1, rings):
        nxt = np.zeros_like(front)
        nxt[edges[front[edges[:, 0]], 1]] = True
        nxt[edges[front[edges[:, 1]], 0]] = True
        nxt &= d > r
        d[nxt] = r
        front = nxt
    return d


def _vertex_normals(obj):
    obj.data.update()
    n = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("normal", n)
    return n.reshape(-1, 3)


def _finish(builder, obj, g, occl, wear, uv2=None, rim=0.004):
    """UV2 (metres), vertex colours, rim thickness, material."""
    me = obj.data
    if len(me.uv_layers) == 0:
        me.uv_layers.new(name="UVMap")
    me.uv_layers[0].name = "UVMap"
    if uv2 is None:
        # body UVs scaled to metres
        uvl = me.uv_layers[0].data
        luv = np.empty(len(uvl) * 2, dtype=np.float32)
        uvl.foreach_get("uv", luv)
        luv = luv.reshape(-1, 2)
        area3, areauv = 0.0, 0.0
        co = C.get_co(obj)
        for p in me.polygons:
            if p.loop_total < 3:
                continue
            area3 += p.area
            ls = list(range(p.loop_start, p.loop_start + p.loop_total))
            pts = luv[ls]
            x, y = pts[:, 0], pts[:, 1]
            areauv += 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))
        k = math.sqrt(area3 / max(areauv, 1e-9))
        uv2 = luv * k
    lay2 = me.uv_layers.get("UV2") or me.uv_layers.new(name="UV2")
    lay2.data.foreach_set("uv", uv2.astype(np.float32).ravel())
    col = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    c = np.ones((len(me.vertices), 4), dtype=np.float32)
    c[:, 0] = np.clip(occl, 0, 1)
    c[:, 1] = np.clip(wear, 0, 1)
    c[:, 2] = 0.0
    col.data.foreach_set("color", c.ravel())
    me.color_attributes.active_color = col
    if rim > 0:
        mod = obj.modifiers.new("Rim", "SOLIDIFY")
        mod.thickness = rim
        mod.offset = -1.0
        mod.use_rim = True
        mod.use_rim_only = True
        mod.use_even_offset = True
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    kind = g.get("material", "cloth")
    mat = C.make_material("%s:%s:%s" % (kind, g["id"], g.get("fabric", "wool")),
                          color=tuple(g.get("tint", (0.5, 0.5, 0.5))) + (1.0,), roughness=0.85)
    C.assign_single_material(obj, mat)
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        m = obj.modifiers.new("Armature", "ARMATURE")
        m.object = builder.rig
    obj.parent = builder.rig
    for vg in obj.vertex_groups:
        pass
    if "src_index" in me.attributes:
        me.attributes.remove(me.attributes["src_index"])
    return obj


def _mark_covered(builder, info, vmask, rings=2):
    """Hide body under a garment: delete body vertices well inside the garment region."""
    m = info.erode(vmask & info.body, rings)
    if builder.extra_body_delete is None:
        builder.extra_body_delete = np.zeros(info.n, dtype=bool)
    builder.extra_body_delete |= m


# ------------------------------------------------------------------------------------------------------------------
# body-derived shells
def _region(info, g):
    t = g["type"]
    z = info.co[:, 2]
    torso = info.dom_in(("pelvis", "spine_", "clavicle_")) & (z > info.hip_z - 0.12)
    arms = info.dom_in(("upperarm_", "lowerarm_", "clavicle_"))
    neck = info.dom_in(("neck_",)) & (z < info.neck[2] + g.get("collar", 0.03))
    legs = info.dom_in(("thigh_", "calf_", "pelvis"))
    if t in ("shirt", "bodice"):
        sleeve = g.get("sleeve", 1.96)
        r = (torso & (z > info.hip_z - (0.06 if t == "shirt" else 0.0))) | (arms & (info.arm_p <= sleeve)) | neck
        r &= z < info.neck[2] + g.get("collar", 0.03)
        if t == "bodice":
            r &= z > info.navel_z - 0.06
        return r
    if t == "vest":
        r = torso & (z > info.navel_z - 0.08) & (z < info.shoulder_z + 0.05)
        r &= ~(arms & (info.arm_p > 0.05))
        r &= ~info.dom_in(("upperarm_",))
        # V neckline
        front = info.co[:, 1] < info.pelvis[1] - 0.0
        vtop = info.shoulder_z - 0.02
        vbot = info.shoulder_z - g.get("v_depth", 0.2)
        half = np.clip((z - vbot) / max(vtop - vbot, 1e-3), 0, 1) * 0.085
        r &= ~(front & (z > vbot) & (np.abs(info.co[:, 0]) < half))
        return r
    if t == "trousers":
        hem = g.get("hem", 1.97)
        r = (legs | info.dom_in(("spine_01",))) & (z < info.navel_z) & (info.leg_p <= hem)
        r &= ~info.dom_in(("foot_", "ball_"))
        return r
    if t == "boots":
        top = g.get("top", 1.45)
        r = info.dom_in(("foot_", "ball_", "calf_")) & (info.leg_p >= top)
        return r
    if t == "coat":
        hem_z = info.crotch_z - g.get("below_crotch", 0.04)
        sleeve = g.get("sleeve", 1.93)
        r = (info.dom_in(("pelvis", "spine_", "clavicle_", "thigh_")) & (z > hem_z)) | (arms & (info.arm_p <= sleeve))
        r |= info.dom_in(("neck_",)) & (z < info.neck[2] - 0.005)
        r &= z < info.neck[2] + 0.01
        if g.get("open", True):
            front = info.co[:, 1] < info.pelvis[1]
            gap = np.clip((info.shoulder_z - 0.12 - z) / 0.5, 0, 1) * 0.07 + 0.012
            r &= ~(front & (np.abs(info.co[:, 0]) < gap) & (z < info.shoulder_z - 0.1))
        return r
    raise ValueError(t)


def body_shell(builder, info, g):
    vmask = _region(info, g)
    obj = _shell_from_region(builder, info, vmask, g["id"])
    if len(obj.data.vertices) == 0:
        bpy.data.objects.remove(obj)
        return None
    src = _src_index(obj)
    co = C.get_co(obj)
    nrm = info.nrm[src]
    edges = _neighbors(obj)
    off = g.get("offset", 0.006)
    t = g["type"]
    # ease: more offset on the loose parts (coat skirts, trouser legs), less at the shoulders/waistband
    ease = np.full(len(co), off)
    z = co[:, 2]
    if t in ("coat",):
        ease += np.clip((info.shoulder_z - z) / 0.6, 0, 1) * g.get("loose", 0.02)
    if t in ("trousers",):
        ease += np.clip((info.hip_z - z) / 0.5, 0, 1) * g.get("loose", 0.012)
    if t in ("shirt", "bodice"):
        ease += np.clip(info.arm_p[src] - 0.3, 0, 1.6) * g.get("loose", 0.006)
    if t == "boots":
        ease += np.clip(info.leg_p[src] - 1.9, 0, 0.2) * 0.02
    co = co + nrm * ease[:, None]
    bnd = _boundary_verts(obj)
    # drape: smooth (fills creases between muscles, keeps hems in place a bit)
    co = _laplacian(co, edges, g.get("smooth", 4), 0.35)
    # keep outside the body: re-push along body normal if smoothing moved a vertex inward
    body_pos = info.co[src]
    inward = ((co - body_pos) * nrm).sum(axis=1)
    co = co + nrm * np.clip(off * 0.7 - inward, 0, None)[:, None]
    # folds near joints and at the bottom of trousers / sleeves
    seed = g.get("seed", 0)
    fold = np.zeros(len(co))
    ap = info.arm_p[src]
    lp = info.leg_p[src]
    if t in ("shirt", "bodice", "coat"):
        elbow = np.exp(-((ap - 1.0) / 0.25) ** 2) * (ap >= 0)
        cuff = np.clip((ap - 1.6) / 0.35, 0, 1)
        fold += (elbow * 0.004 + cuff * 0.002) * np.sin(ap * 38 + fbm3(co * 9, seed) * 3)
        fold += 0.0025 * np.clip((info.shoulder_z - z) / 0.4, 0, 1) * fbm3(co * np.array([12, 12, 3]), seed + 3)
    if t == "trousers":
        knee = np.exp(-((lp - 1.0) / 0.25) ** 2)
        stack = np.clip((lp - 1.6) / 0.35, 0, 1)
        fold += (knee * 0.004 + stack * 0.006) * np.sin(lp * 34 + fbm3(co * 8, seed) * 3)
        fold += 0.002 * fbm3(co * np.array([10, 10, 2.5]), seed + 5)
    if t == "vest":
        fold += 0.0015 * fbm3(co * 14, seed)
    if t == "boots":
        fold += 0.002 * np.exp(-((lp - 1.95) / 0.08) ** 2) * np.sin(z * 260)
    co = co + nrm * fold[:, None]
    C.set_co(obj, co)
    if t == "boots":
        _boot_sole(obj, info)
    occl = 0.82 + 0.18 * np.clip(fold / 0.006 + 0.5, 0, 1)
    wear = np.zeros(len(co))
    if t in ("shirt", "coat", "bodice"):
        wear += np.exp(-((ap - 1.0) / 0.12) ** 2) * (ap >= 0) * 0.8
    if t == "trousers":
        wear += np.exp(-((lp - 1.0) / 0.15) ** 2) * 0.8
        wear += np.clip((lp - 1.8) / 0.2, 0, 1) * 0.6
    bd = _boundary_distance(obj, 4)
    wear += np.clip(1 - bd / 3, 0, 1) * 0.6
    occl *= 0.9 + 0.1 * np.clip(bd / 3, 0, 1)
    if t != "boots":
        _mark_covered(builder, info, vmask, rings=2 if t != "vest" else 3)
    else:
        _mark_covered(builder, info, vmask & ~info.dom_in(("calf_",)), rings=1)
    return _finish(builder, obj, g, occl, wear, rim=g.get("rim", 0.004))


def _boot_sole(obj, info):
    """Flatten and thicken the sole, add a heel, square off the toes a little."""
    co = C.get_co(obj)
    z = co[:, 2]
    low = z < info.ankle_z - 0.035
    for s, sx in (("l", 1), ("r", -1)):
        side = (co[:, 0] * sx > 0) & low
        if not side.any():
            continue
        foot = info.j["foot_" + s]
        ball = info.j["ball_" + s]
        fwd = ball - foot
        fwd[2] = 0
        fwd /= np.linalg.norm(fwd)
        along = (co[side] - foot) @ fwd
        zs = co[side, 2]
        floor = zs.min()
        # sole: everything near the floor goes to floor - 1.2 cm; heel (behind the ankle) to floor - 2.5 cm
        nearfloor = zs < floor + 0.02
        drop = np.where(along < -0.01, 0.025, 0.012)
        newz = np.where(nearfloor, floor - drop, zs - drop * np.clip(1 - (zs - floor) / 0.05, 0, 1))
        c2 = co[side]
        c2[:, 2] = newz
        co[side] = c2
    C.set_co(obj, co)


# ------------------------------------------------------------------------------------------------------------------
# lofted tubes: skirts, coat tails, aprons
def tube(builder, info, g):
    t = g["type"]
    seed = g.get("seed", 0)
    z_top = {"skirt": info.navel_z - 0.03, "tails": info.crotch_z + 0.1, "apron": info.navel_z - 0.02}[t]
    if t == "skirt":
        z_bot = info.ankle_z - g.get("below_ankle", 0.02) - 0.06
    elif t == "tails":
        z_bot = info.knee_z - g.get("below_knee", 0.25)
    else:
        z_bot = info.knee_z - g.get("below_knee", 0.18)
    rings = g.get("rings", 16)
    K = g.get("segments", 44)
    body = info.body & info.dom_in(("pelvis", "thigh_", "calf_", "spine_01", "foot_"))
    bco = info.co[body]
    cx, cy = 0.0, info.pelvis[1] + 0.005
    thetas = np.linspace(0, 2 * math.pi, K, endpoint=False)
    # angular envelope of the body per ring
    prev_r = None
    ring_pts = []
    zs = np.linspace(z_top, z_bot, rings)
    flare = g.get("flare", 0.18)
    ease = g.get("ease", 0.02)
    for ri, zz in enumerate(zs):
        band = bco[np.abs(bco[:, 2] - zz) < 0.04]
        if band.shape[0] < 8:
            band = bco[np.abs(bco[:, 2] - zz) < 0.12]
        ang = np.arctan2(band[:, 1] - cy, band[:, 0] - cx)
        rad = np.hypot(band[:, 0] - cx, band[:, 1] - cy)
        r = np.zeros(K)
        for k, th in enumerate(thetas):
            d = np.abs((ang - th + math.pi) % (2 * math.pi) - math.pi)
            sel = d < 0.35
            r[k] = rad[sel].max() if sel.any() else (rad.max() if rad.size else 0.15)
        # circular smoothing
        for _ in range(3):
            r = np.maximum(r, (np.roll(r, 1) + np.roll(r, -1) + 2 * r) / 4)
        depth = (z_top - zz) / max(z_top - z_bot, 1e-3)
        r = r + ease + flare * depth ** 1.4 * (0.6 if t == "tails" else 1.0)
        if prev_r is not None:
            r = np.maximum(r, prev_r * (1.0 if t != "skirt" else 1.005))
        prev_r = r
        # gentle hem waves
        r = r * (1 + depth ** 2 * 0.035 * np.sin(thetas * g.get("waves", 7) + seed))
        ring_pts.append(np.stack([cx + r * np.cos(thetas), cy + r * np.sin(thetas), np.full(K, zz)], axis=1))
    P = np.concatenate(ring_pts)
    # which segments exist (front opening for tails, front panel for apron)
    front_angle = -math.pi / 2  # -Y
    def ang_dist(th):
        return abs((th - front_angle + math.pi) % (2 * math.pi) - math.pi)
    if t == "tails":
        keep_seg = [ang_dist(th) > g.get("opening", 0.32) for th in thetas]
        vent = [abs((th - math.pi / 2 + math.pi) % (2 * math.pi) - math.pi) < 0.05 for th in thetas]
    elif t == "apron":
        keep_seg = [ang_dist(th) < g.get("width", 0.95) for th in thetas]
        vent = [False] * K
    else:
        keep_seg = [True] * K
        vent = [False] * K
    faces = []
    for ri in range(rings - 1):
        for k in range(K):
            k2 = (k + 1) % K
            if not (keep_seg[k] and keep_seg[k2]):
                continue
            if vent[k] and ri > rings // 2:
                continue
            a, b = ri * K + k, ri * K + k2
            faces.append((a, b, b + K, a + K))
    me = bpy.data.meshes.new(g["id"])
    me.from_pydata(P.tolist(), [], faces)
    me.update()
    obj = bpy.data.objects.new(g["id"], me)
    bpy.context.collection.objects.link(obj)
    b = bmesh.new()
    b.from_mesh(me)
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    b.to_mesh(me)
    b.free()
    for p in me.polygons:
        p.use_smooth = True
    co = C.get_co(obj)
    # folds: vertical drape folds growing toward the hem
    th = np.arctan2(co[:, 1] - cy, co[:, 0] - cx)
    depth = np.clip((z_top - co[:, 2]) / max(z_top - z_bot, 1e-3), 0, 1)
    fold = depth ** 1.2 * g.get("fold", 0.012) * np.sin(th * g.get("fold_count", 11) + fbm3(co * 4, seed) * 2.5)
    radial = np.stack([np.cos(th), np.sin(th), np.zeros_like(th)], axis=1)
    co = co + radial * fold[:, None]
    C.set_co(obj, co)
    # UVs: u = arc length, v = height (metres)
    arc = th * np.hypot(co[:, 0] - cx, co[:, 1] - cy).mean()
    uvv = np.stack([arc, co[:, 2]], axis=1)
    loops_v = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", loops_v)
    luv = uvv[loops_v]
    # fix the seam wrap (theta jump at +-pi)
    for p in me.polygons:
        ls = list(range(p.loop_start, p.loop_start + p.loop_total))
        u = luv[ls, 0]
        if u.max() - u.min() > 1.0:
            luv[ls, 0] = np.where(u < 0, u + 2 * math.pi * np.hypot(co[:, 0] - cx, co[:, 1] - cy).mean(), u)
    me.uv_layers.new(name="UVMap")
    me.uv_layers[0].data.foreach_set("uv", luv.astype(np.float32).ravel())
    # weights: pelvis at the waist -> thighs/calves with depth, split by side
    gp = obj.vertex_groups.new(name="pelvis")
    gl = obj.vertex_groups.new(name="thigh_l")
    gr = obj.vertex_groups.new(name="thigh_r")
    gcl = obj.vertex_groups.new(name="calf_l")
    gcr = obj.vertex_groups.new(name="calf_r")
    hipw = abs(info.j["thigh_l"][0] - info.j["thigh_r"][0])
    swing = g.get("leg_follow", 0.55 if t == "skirt" else 0.75)
    for i, v in enumerate(co):
        d = depth[i]
        side = np.clip(0.5 + v[0] / (hipw * 1.6), 0, 1)  # character's left is +X
        legw = swing * d ** 0.8
        calfw = legw * np.clip((d - 0.55) / 0.45, 0, 1) * 0.35 if t == "skirt" else 0.0
        thw = legw - calfw
        gp.add([i], max(1.0 - legw, 0.0), "REPLACE")
        if thw > 0:
            gl.add([i], thw * side, "REPLACE")
            gr.add([i], thw * (1 - side), "REPLACE")
        if calfw > 0:
            gcl.add([i], calfw * side, "REPLACE")
            gcr.add([i], calfw * (1 - side), "REPLACE")
    occl = 0.8 + 0.2 * np.clip(fold / 0.012 + 0.5, 0, 1)
    wear = np.clip((depth - 0.85) / 0.15, 0, 1) * 0.8
    if t == "skirt" and g.get("hide_legs", True):
        legs = info.body & info.dom_in(("thigh_", "calf_")) & (info.co[:, 2] > z_bot + 0.12) & (info.co[:, 2] < z_top - 0.05)
        _mark_covered(builder, info, legs, rings=1)
    return _finish(builder, obj, g, occl, wear, uv2=luv, rim=g.get("rim", 0.003))


# ------------------------------------------------------------------------------------------------------------------
# hats (lathe)
HAT_PROFILES = {
    # (r_rel, h) pairs from the brim edge in to the crown top; r_rel: 0 = band, >0 brim (metres outside the band),
    # <0 crown narrowing (metres inside the band). h: metres above the band line.
    "cattleman": dict(brim=0.085, crown_h=0.125, taper=0.012, curl=0.022, crease=0.025, pinch=0.012),
    "plainsman": dict(brim=0.09, crown_h=0.135, taper=0.008, curl=0.008, crease=0.0, pinch=0.0, round_top=0.01),
    "bowler": dict(brim=0.045, crown_h=0.11, taper=-0.004, curl=0.018, crease=0.0, pinch=0.0, dome=True),
    "flatcap": dict(brim=0.0, crown_h=0.055, taper=-0.01, curl=0.0, crease=0.0, pinch=0.0, cap=True),
    "boater": dict(brim=0.075, crown_h=0.075, taper=0.0, curl=0.0, crease=0.0, pinch=0.0),
    "slouch": dict(brim=0.1, crown_h=0.11, taper=0.015, curl=-0.02, crease=0.02, pinch=0.0, droop=0.02),
}


def hat(builder, info, g):
    style = HAT_PROFILES[g.get("style", "cattleman")]
    head_m = info.body & info.dom_in(("head",))
    hco = info.co[head_m]
    top = hco[:, 2].max()
    band_z = top - g.get("depth", 0.07)
    sl = hco[np.abs(hco[:, 2] - band_z) < 0.01]
    cx, cy = sl[:, 0].mean(), sl[:, 1].mean()
    rx = (sl[:, 0].max() - sl[:, 0].min()) / 2 + 0.008
    ry = (sl[:, 1].max() - sl[:, 1].min()) / 2 + 0.008
    tilt = math.radians(g.get("tilt", 4.0))  # brim tipped down at the front
    K = 48
    th = np.linspace(0, 2 * math.pi, K, endpoint=False)
    ex, ey = np.cos(th), np.sin(th)
    rings = []
    bw = style["brim"]
    # brim: outer edge -> band (top surface), then crown wall up, then crown top to centre
    prof = []
    if bw > 0:
        for s in np.linspace(1.0, 0.0, 5):
            prof.append(("brim", s * bw, 0.0))
    if style.get("cap"):
        # flat cap: peak at the front only, low puffy crown
        prof = [("wall", 0.0, 0.0), ("wall", 0.004, 0.02), ("wall", 0.01, 0.04), ("top", -0.03, style["crown_h"]),
                ("top", -0.08, style["crown_h"] + 0.005)]
    else:
        H = style["crown_h"]
        for s in np.linspace(0.0, 1.0, 7):
            if style.get("dome"):
                a = s * math.pi / 2
                prof.append(("wall", -(1 - math.cos(a)) * 0.07 - style["taper"] * s, math.sin(a) * H))
            else:
                prof.append(("wall", -style["taper"] * s, s * H))
        if not style.get("dome"):
            for s in np.linspace(0.25, 1.0, 4):
                prof.append(("top", -style["taper"] - s * 0.075, H + style.get("round_top", 0.0) * s))
    verts = []
    for kind, r_off, h in prof:
        rr_x = np.maximum(rx + r_off, 0.004)
        rr_y = np.maximum(ry + r_off, 0.004)
        x = cx + rr_x * ex
        y = cy + rr_y * ey
        zz = np.full(K, band_z + h)
        if kind == "brim":
            side = np.abs(ex)
            zz = zz + style["curl"] * side ** 2 * (r_off / max(bw, 1e-3)) ** 1.5
            zz = zz - style.get("droop", 0.0) * (1 - side) * (r_off / max(bw, 1e-3)) ** 2
        if kind == "top" and style["crease"] > 0:
            # centre crease front-to-back + front pinch
            zz = zz - style["crease"] * np.exp(-(ex * rr_x / 0.03) ** 2)
            zz = zz - style["pinch"] * np.clip(-ey, 0, 1) ** 3
        if style.get("cap"):
            # peak: extend the front of the low rings forward
            pk = np.clip(-ey, 0, 1) ** 2 * (0.06 if h < 0.025 else 0.0)
            y = y - pk
        verts.append(np.stack([x, y, zz], axis=1))
    V = np.concatenate(verts)
    nr = len(prof)
    faces = []
    for ri in range(nr - 1):
        for k in range(K):
            k2 = (k + 1) % K
            a, b = ri * K + k, ri * K + k2
            faces.append((a, a + K, b + K, b))
    # close the top
    cidx = V.shape[0]
    V = np.vstack([V, [[cx, cy, V[-K:, 2].mean() - (style["crease"] * 0.5)]]])
    for k in range(K):
        k2 = (k + 1) % K
        faces.append(((nr - 1) * K + k, cidx, (nr - 1) * K + k2))
    # front tilt: rotate about X through the band centre
    rel = V - np.array([cx, cy, band_z])
    ct, st = math.cos(tilt), math.sin(tilt)
    y2 = rel[:, 1] * ct - rel[:, 2] * st
    z2 = rel[:, 1] * st + rel[:, 2] * ct
    V = np.stack([rel[:, 0] + cx, y2 + cy, z2 + band_z], axis=1)
    me = bpy.data.meshes.new(g["id"])
    me.from_pydata(V.tolist(), [], faces)
    me.update()
    obj = bpy.data.objects.new(g["id"], me)
    bpy.context.collection.objects.link(obj)
    b = bmesh.new()
    b.from_mesh(me)
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    b.to_mesh(me)
    b.free()
    for p in me.polygons:
        p.use_smooth = True
    # thickness: solidify (felt ~4 mm)
    mod = obj.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = g.get("thickness", 0.004)
    mod.offset = -1
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    co = C.get_co(obj)
    vg = obj.vertex_groups.new(name="head")
    vg.add(list(range(len(co))), 1.0, "REPLACE")
    # UV: planar top-down for the brim/top, cylindrical-ish for the wall (metres)
    uv = np.stack([co[:, 0] + np.arctan2(co[:, 1] - cy, co[:, 0] - cx) * 0.0, co[:, 1] + co[:, 2]], axis=1)
    loops_v = np.empty(len(obj.data.loops), dtype=np.int32)
    obj.data.loops.foreach_get("vertex_index", loops_v)
    luv = uv[loops_v]
    obj.data.uv_layers.new(name="UVMap")
    obj.data.uv_layers[0].data.foreach_set("uv", luv.astype(np.float32).ravel())
    # band ribbon darker (occlusion channel used as darkening), wear on the brim edge and crown crease
    hrel = co[:, 2] - band_z
    occl = np.where((hrel > 0.002) & (hrel < 0.022) & (np.hypot((co[:, 0] - cx) / rx, (co[:, 1] - cy) / ry) < 1.1), 0.45, 1.0)
    rad = np.hypot((co[:, 0] - cx) / rx, (co[:, 1] - cy) / ry)
    wear = np.clip((rad - 1.0) / (bw / rx + 1e-3) - 0.6, 0, 1) * 0.9 if bw > 0 else np.zeros(len(co))
    g = dict(g)
    g["slot"] = "hat"
    builder.hat_info = dict(band_z=band_z, cx=cx, cy=cy, rx=rx - 0.004, ry=ry - 0.004, crown_h=style["crown_h"],
                            taper=style["taper"], tilt=tilt)
    return _finish(builder, obj, g, occl, wear, uv2=luv, rim=0.0)


def squash_hair_under_hat(builder, hair_obj):
    hi = getattr(builder, "hat_info", None)
    if hi is None or hair_obj is None:
        return
    co = C.get_co(hair_obj)
    rel = co - np.array([hi["cx"], hi["cy"], hi["band_z"]])
    # undo tilt for the test
    ct, st = math.cos(-hi["tilt"]), math.sin(-hi["tilt"])
    y = rel[:, 1] * ct - rel[:, 2] * st
    z = rel[:, 1] * st + rel[:, 2] * ct
    x = rel[:, 0]
    above = z > -0.012
    h = np.clip(z / max(hi["crown_h"], 1e-3), 0, 1)
    rx = hi["rx"] - hi["taper"] * h - 0.006
    ry = hi["ry"] - hi["taper"] * h - 0.006
    e = np.hypot(x / rx, y / ry)
    s = np.where(above & (e > 1.0), 1.0 / np.maximum(e, 1e-6), 1.0)
    # band zone: hair just below the band can flare a little but not beyond the brim underside
    x2 = x * s
    y2 = y * s
    z2 = np.minimum(z, hi["crown_h"] - 0.012)
    ct, st = math.cos(hi["tilt"]), math.sin(hi["tilt"])
    yy = y2 * ct - z2 * st
    zz = y2 * st + z2 * ct
    new = np.stack([x2 + hi["cx"], yy + hi["cy"], zz + hi["band_z"]], axis=1)
    C.set_co(hair_obj, new)


# ------------------------------------------------------------------------------------------------------------------
# beards / moustaches: alpha shells over the beard region; follow the face blend shapes
def beard_region(info, style):
    co = info.co
    head_m = info.body & info.dom_in(("head", "neck_"))
    hj = info.head
    z = co[:, 2]
    y = co[:, 1]
    x = co[:, 0]
    # face landmarks from the head joint: the mouth is ~ 0.07 m below the eyes; approximate with ratios
    eye_z = (builder_eye_z := getattr(info, "eye_z", hj[2] + 0.09))
    nose_z = eye_z - 0.045
    mouth_z = eye_z - 0.075
    chin_z = eye_z - 0.125
    front = y < hj[1] - 0.02
    if style == "moustache":
        r = head_m & front & (z < nose_z - 0.003) & (z > mouth_z - 0.002) & (np.abs(x) < 0.03 + (nose_z - z) * 0.4)
        return r
    lips = (np.abs(x) < 0.03) & (z < mouth_z + 0.01) & (z > mouth_z - 0.015) & front
    cheek_top = nose_z - 0.005 + np.abs(x) * 0.25
    r = head_m & (z < cheek_top) & (z > chin_z - 0.06) & (y < hj[1] + 0.035) & ~lips
    if style == "chin":   # goatee / chin beard
        r &= np.abs(x) < 0.035
    if style == "mutton":  # mutton chops: sides only, no chin
        r &= (np.abs(x) > 0.035) & (z > mouth_z - 0.02)
    r &= ~((z < chin_z - 0.02) & (y > hj[1] - 0.01))  # not on the neck back
    return r


def beard(builder, info, g):
    style = g.get("style", "full")
    regs = []
    r = beard_region(info, "full" if style in ("full", "short") else style)
    if style in ("full", "short", "chin", "mutton"):
        regs.append(r)
    if g.get("moustache", True) or style == "moustache":
        regs.append(beard_region(info, "moustache"))
    vmask = np.zeros(info.n, dtype=bool)
    for m in regs:
        vmask |= m
    if not vmask.any():
        return None
    length = g.get("length", 0.012)
    layers = []
    for li, frac in enumerate((0.3, 0.65, 1.0)):
        obj = _shell_from_region(builder, info, vmask, "%s_%d" % (g["id"], li))
        # keep the face blend shapes: re-copy them from the basemesh (shell_from_region cleared them)
        src = _src_index(obj)
        bmk = builder.basemesh.data.shape_keys
        base = C.get_co(builder.basemesh, bmk.key_blocks["Basis"])
        nrm = info.nrm[src]
        z = info.co[src, 2]
        droop = np.array([0, 0, -1.0]) * length * 0.35 * frac
        offv = nrm * (length * frac + 0.0015) + droop
        C.ensure_basis(obj)
        C.set_co(obj, base[src] + offv, obj.data.shape_keys.key_blocks["Basis"])
        C.set_co(obj, base[src] + offv)
        for kb in bmk.key_blocks:
            if kb.name == "Basis":
                continue
            kco = C.get_co(builder.basemesh, kb)
            C.add_shape(obj, kb.name, kco[src] + offv)
        layers.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for o in layers:
        o.select_set(True)
    bpy.context.view_layer.objects.active = layers[0]
    bpy.ops.object.join()
    obj = layers[0]
    obj.name = g["id"]
    tex = beard_texture(g.get("density", 0.8))
    mat = C.make_material("beard", albedo=tex, alpha=True, size=512)
    C.assign_single_material(obj, mat)
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        m = obj.modifiers.new("Armature", "ARMATURE")
        m.object = builder.rig
    me = obj.data
    if "src_index" in me.attributes:
        me.attributes.remove(me.attributes["src_index"])
    me.uv_layers[0].name = "UVMap"
    builder.beard_mask = vmask
    return obj


def beard_texture(density):
    """Procedural hair-strand alpha texture (original), cached on disk."""
    from PIL import Image, ImageDraw
    path = os.path.join(C.cache_dir(), "beard_strands_%d.png" % int(density * 100))
    if os.path.exists(path):
        return path
    rng = np.random.default_rng(1899)
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    n = int(9000 * density)
    for _ in range(n):
        x, y = rng.uniform(0, S, 2)
        L = rng.uniform(8, 26)
        a = rng.normal(math.pi / 2, 0.45)
        c = int(rng.uniform(40, 110))
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=(c, int(c * 0.8), int(c * 0.65), 255),
               width=1)
    img.save(path)
    return path


# ------------------------------------------------------------------------------------------------------------------
def belt(builder, info, g):
    """Leather gun belt (band slung on the hips) + holster block on the right thigh."""
    z = info.hip_z + g.get("height", 0.02)
    body = info.body & (np.abs(info.co[:, 2] - z) < 0.03) & info.dom_in(("pelvis", "spine_01", "thigh_"))
    bco = info.co[body]
    cx, cy = 0.0, bco[:, 1].mean()
    K = 40
    th = np.linspace(0, 2 * math.pi, K, endpoint=False)
    r = np.zeros(K)
    ang = np.arctan2(bco[:, 1] - cy, bco[:, 0] - cx)
    rad = np.hypot(bco[:, 0] - cx, bco[:, 1] - cy)
    for k, t in enumerate(th):
        sel = np.abs((ang - t + math.pi) % (2 * math.pi) - math.pi) < 0.3
        r[k] = rad[sel].max() if sel.any() else rad.mean()
    r += g.get("offset", 0.022)
    tilt = 0.035 * np.cos(th - math.radians(-30))  # slung lower on the gun side
    h = g.get("width", 0.05)
    V = []
    for dz in (-h / 2, h / 2):
        V.append(np.stack([cx + r * np.cos(th), cy + r * np.sin(th), z + dz - tilt], axis=1))
    V = np.concatenate(V)
    faces = [(k, (k + 1) % K, (k + 1) % K + K, k + K) for k in range(K)]
    me = bpy.data.meshes.new(g["id"])
    me.from_pydata(V.tolist(), [], faces)
    obj = bpy.data.objects.new(g["id"], me)
    bpy.context.collection.objects.link(obj)
    b = bmesh.new()
    b.from_mesh(me)
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    b.to_mesh(me)
    b.free()
    mod = obj.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = 0.005
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    co = C.get_co(obj)
    gp = obj.vertex_groups.new(name="pelvis")
    gp.add(list(range(len(co))), 1.0, "REPLACE")
    uv = np.stack([np.arctan2(co[:, 1] - cy, co[:, 0] - cx) * 0.18, co[:, 2]], axis=1)
    loops_v = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", loops_v)
    me.uv_layers.new(name="UVMap")
    me.uv_layers[0].data.foreach_set("uv", uv[loops_v].astype(np.float32).ravel())
    g = dict(g)
    g.setdefault("material", "leather")
    g.setdefault("fabric", "leather")
    return _finish(builder, obj, g, np.ones(len(co)), np.full(len(co), 0.3), uv2=uv[loops_v], rim=0.0)


def build(builder, g):
    if getattr(builder, "_body_info", None) is None:
        builder._body_info = BodyInfo(builder)
        builder._body_info.eye_z = (builder.joint_centers["joint-l-eye"].z + builder.joint_centers["joint-r-eye"].z) / 2
    if getattr(builder, "extra_body_delete", None) is None:
        builder.extra_body_delete = None
    info = builder._body_info
    t = g["type"]
    if t in ("shirt", "bodice", "vest", "trousers", "boots", "coat"):
        return body_shell(builder, info, g)
    if t in ("skirt", "tails", "apron"):
        return tube(builder, info, g)
    if t == "hat":
        return hat(builder, info, g)
    if t == "beard":
        return beard(builder, info, g)
    if t == "belt":
        return belt(builder, info, g)
    raise ValueError("unknown garment type " + t)
