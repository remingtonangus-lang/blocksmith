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
        fr = self.body & (np.abs(self.co[:, 0]) < 0.14) & (self.co[:, 2] > self.navel_z + 0.05) & \
            (self.co[:, 2] < self.shoulder_z - 0.04)
        self.bust_z = float(self.co[fr][np.argmin(self.co[fr][:, 1]), 2]) if fr.any() else self.shoulder_z - 0.15
        # outermost offset (m, along the body normal) of the garment layers already built; -1 = none yet
        self.occ = np.full(self.n, -1.0)
        self.arm_p = np.full(self.n, -1.0)
        self.leg_p = np.full(self.n, -1.0)
        for s in ("l", "r"):
            a = self._chain_param([j["upperarm_" + s], j["lowerarm_" + s], j["hand_" + s]])
            side = (self.co[:, 0] > 0) if s == "l" else (self.co[:, 0] <= 0)
            self.arm_p = np.where(side, a, self.arm_p)
            lp = self._chain_param([j["thigh_" + s], j["calf_" + s], j["foot_" + s]])
            self.leg_p = np.where(side, lp, self.leg_p)
        # face landmarks: mouth line from the teeth helpers, nose tip = front-most midline vertex above it
        ut = C.group_vertex_mask(bm, "helper-upper-teeth")
        lt = C.group_vertex_mask(bm, "helper-lower-teeth")
        self.mouth_z = float((self.co[ut, 2].min() + self.co[lt, 2].max()) / 2) if ut.any() and lt.any() else self.head[2]
        self.mouth_y = float(self.co[ut, 1].min()) if ut.any() else self.head[1] - 0.08
        mid = self.body & (np.abs(self.co[:, 0]) < 0.006) & (self.co[:, 2] > self.mouth_z + 0.01) & \
            (self.co[:, 2] < self.mouth_z + 0.07) & (self.co[:, 1] < self.head[1])
        if mid.any():
            k = np.argmin(np.where(mid, self.co[:, 1], 9))
            self.nose_tip = self.co[k].copy()
        else:
            self.nose_tip = np.array([0, self.mouth_y - 0.02, self.mouth_z + 0.035])
        chin = self.body & (np.abs(self.co[:, 0]) < 0.01) & (self.co[:, 2] < self.mouth_z) & \
            (self.co[:, 2] > self.mouth_z - 0.09) & (self.co[:, 1] < self.mouth_y + 0.03)
        self.chin_z = float(self.co[chin, 2].min()) if chin.any() else self.mouth_z - 0.06
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


def _inflate(co, edges, nrm, iters, mask, lam=0.6):
    """Laplacian smoothing that only ever moves vertices outward (along the body normal), on masked vertices."""
    n = co.shape[0]
    for _ in range(iters):
        acc = np.zeros_like(co)
        cnt = np.zeros(n)
        np.add.at(acc, edges[:, 0], co[edges[:, 1]])
        np.add.at(acc, edges[:, 1], co[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        avg = acc / np.maximum(cnt, 1)[:, None]
        d = ((avg - co) * nrm).sum(axis=1)
        step = np.clip(d, 0, None) * lam * mask
        co = co + nrm * step[:, None]
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


def _finish(builder, obj, g, occl, wear, uv2=None, rim=0.004, hem=None):
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
    c[:, 2] = 1.0 if hem is None else np.clip(hem / 0.05, 0, 1)   # b: distance to the hem (stitching)
    col.data.foreach_set("color", c.ravel())
    me.color_attributes.active_color = col
    if hem is not None:
        # protect garment edges from decimation (mhcore.decimate reads "keep_edge") -> hems stay straight
        w = np.clip(1.0 - np.asarray(hem) / 0.014, 0.0, 1.0)
        vg = obj.vertex_groups.get(C.KEEP_EDGE) or obj.vertex_groups.new(name=C.KEEP_EDGE)
        q = np.round(w * 4) / 4
        for lvl in (0.25, 0.5, 0.75, 1.0):
            idx = np.nonzero(np.isclose(q, lvl))[0].tolist()
            if idx:
                vg.add(idx, float(lvl), "REPLACE")
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
def _collar(info, g, drop=0.0):
    """Collar plane through a point just under the chin (front) and one on the nape (back); "collar" raises it."""
    hi = g.get("collar", 0.03)
    yf, yb = info.neck[1] - 0.07, info.neck[1] + 0.06
    zf = info.chin_z - 0.03 + hi * 0.6 - drop
    zb = info.neck[2] - 0.05 + hi - drop
    tilt = (zb - zf) / (yb - yf)
    pt = np.array([0.0, yf, zf])
    n = np.array([0.0, -tilt, 1.0]) / math.sqrt(1 + tilt * tilt)
    return pt, n


def _region(info, g, margin=0.0):
    """-> (vertex mask, cuts). The mask is taken `margin` metres past every edge; the cuts then bisect the offset shell
    exactly (clean hems). Cuts: ("zmin", z) keep above, ("zmax", z) keep below, ("plane", pt, n) keep the negative
    side, ("arm", p) / ("leg", p) keep the body side of the limb parameter p, ("armhole", p) keep the torso side,
    ("vneck", vbot, vtop, half_top) cut a V neckline, ("open", ztop, gap_top, zbot, gap_bot) coat front opening."""
    t = g["type"]
    z = info.co[:, 2]
    m = margin
    torso = info.dom_in(("pelvis", "spine_", "clavicle_")) & (z > info.hip_z - 0.14)
    arms = info.dom_in(("upperarm_", "lowerarm_", "clavicle_"))
    cpt, cn = _collar(info, g)
    below_collar_m = ((info.co - cpt) @ cn) < m
    neck = (info.dom_in(("neck_",)) | (info.dom_in(("head",)) & (z < info.chin_z - 0.005))) & below_collar_m
    legs = info.dom_in(("thigh_", "calf_", "pelvis"))
    arm_len = np.linalg.norm(info.j["lowerarm_l"] - info.j["upperarm_l"])
    leg_len = np.linalg.norm(info.j["calf_l"] - info.j["thigh_l"])
    if t in ("shirt", "bodice"):
        sleeve = g.get("sleeve", 1.96)
        bottom = info.hip_z - 0.06 if t == "shirt" else info.navel_z - 0.1
        r = (torso & (z > bottom - m)) | (arms & (info.arm_p <= sleeve + m / arm_len)) | neck
        r &= below_collar_m
        r &= ~info.dom_in(("hand_",)) | (info.arm_p <= sleeve + m / arm_len)
        return r, [("zmin", bottom), ("plane", cpt, cn), ("arm", sleeve)]
    if t == "vest":
        bottom = info.navel_z - 0.08
        vpt, vn = _collar(info, g, drop=0.035)      # vest neckline follows the shirt collar, a little lower
        top = info.shoulder_z + 0.06
        r = (torso | neck) & (z > bottom - m) & (((info.co - vpt) @ vn) < m)
        r &= ~(info.dom_in(("upperarm_", "lowerarm_")) & (info.arm_p > 0.05 + m / arm_len))
        vbot = info.shoulder_z - g.get("v_depth", 0.12)
        half_top = g.get("v_width", 0.085)
        return r, [("zmin", bottom), ("plane", vpt, vn), ("vneck", vbot, top, half_top), ("armhole", 0.05)]
    if t == "trousers":
        hem = g.get("hem", 1.97)
        top = info.navel_z
        r = (legs | info.dom_in(("spine_01",))) & (z < top + m) & (info.leg_p <= hem + m / leg_len)
        r &= ~info.dom_in(("ball_",))
        return r, [("zmax", top), ("leg", hem)]
    if t == "boots":
        top = g.get("top", 1.45)
        r = info.dom_in(("foot_", "ball_", "calf_")) & (info.leg_p >= top - m / leg_len)
        if g.get("shaft_only"):
            r &= ~info.dom_in(("ball_",)) & (z > info.ankle_z - 0.02)
            return r, [("legtop", top), ("zmin", info.ankle_z + 0.005)]
        return r, [("legtop", top)]
    if t == "coat":
        hem_z = info.crotch_z - g.get("below_crotch", 0.04)
        sleeve = g.get("sleeve", 1.93)
        r = (info.dom_in(("pelvis", "spine_", "clavicle_", "thigh_")) & (z > hem_z - m)) | \
            (arms & (info.arm_p <= sleeve + m / arm_len))
        cpt2, cn2 = _collar(info, g, drop=0.012)
        r |= neck
        r &= ((info.co - cpt2) @ cn2) < m
        r &= ~info.dom_in(("head",))
        r &= ~info.dom_in(("hand_",)) | (info.arm_p <= sleeve + m / arm_len)
        cuts = [("zmin", hem_z), ("plane", cpt2, cn2), ("arm", sleeve)]
        if g.get("open", True):
            # lapel V from the collar down to the waist, then the fronts hang apart
            ztop = info.shoulder_z + 0.03
            cuts.append(("open", ztop, 0.022, ztop - 0.6, 0.022 + g.get("open_width", 0.11)))
        return r, cuts
    raise ValueError(t)


def _chain_point(info, names, side, p):
    pts = [info.j[n + side] for n in names]
    k = min(int(p), 1)
    f = p - k
    a, b = pts[k], pts[k + 1]
    return a + (b - a) * f, (b - a) / np.linalg.norm(b - a)


def _bisect_cuts(obj, info, cuts):
    """Cut the shell exactly along every garment edge (bmesh bisect, outer part removed) -> straight, clean hems."""
    me = obj.data
    b = bmesh.new()
    b.from_mesh(me)
    lay = b.verts.layers.int.get("src_index")
    planes = []   # (point, normal pointing to the part to REMOVE, selector(co)->bool)
    for c in cuts:
        k = c[0]
        if k == "zmin":
            planes.append((np.array([0, 0, c[1]]), np.array([0, 0, -1.0]), None))
        elif k == "zmax":
            planes.append((np.array([0, 0, c[1]]), np.array([0, 0, 1.0]), None))
        elif k == "plane":
            planes.append((c[1], c[2], None))
        elif k in ("arm", "leg", "legtop", "armhole"):
            names = ["upperarm_", "lowerarm_", "hand_"] if k in ("arm", "armhole") else ["thigh_", "calf_", "foot_"]
            dom = {"arm": ("upperarm_", "lowerarm_", "hand_"), "armhole": ("upperarm_", "clavicle_"),
                   "leg": ("thigh_", "calf_", "foot_", "ball_"), "legtop": ("thigh_", "calf_", "foot_", "ball_")}[k]
            ok = info.dom_in(dom)
            for side, sx in (("l", 1.0), ("r", -1.0)):
                pt, ax = _chain_point(info, names, side, c[1])
                n = ax if k in ("arm", "leg", "armhole") else -ax   # legtop keeps the foot side
                planes.append((pt, n, (lambda co, si, sx=sx, ok=ok: co[0] * sx > 0.0 and ok[si])))
        elif k == "vneck":
            vbot, vtop, half = c[1], c[2], c[3]
            H = vtop - vbot
            for sx in (1.0, -1.0):
                n = np.array([-H * sx, 0.0, half])
                n /= np.linalg.norm(n)
                planes.append((np.array([0.0, 0.0, vbot]), n,
                               (lambda co, si, sx=sx: co[0] * sx > -0.002 and co[1] < info.pelvis[1] and co[2] > vbot - 0.04)))
        elif k == "open":
            ztop, gtop, zbot, gbot = c[1], c[2], c[3], c[4]
            for sx in (1.0, -1.0):
                # edge line from (gtop, ztop) down to (gbot, zbot); remove the inner side (toward x = 0)
                d = np.array([(gbot - gtop) * sx, 0.0, zbot - ztop])
                n = np.array([-d[2], 0.0, d[0]])
                if n[0] * sx > 0:
                    n = -n
                n /= np.linalg.norm(n)
                planes.append((np.array([gtop * sx, 0.0, ztop]), n,
                               (lambda co, si, sx=sx: co[0] * sx > -0.002 and co[1] < info.pelvis[1] and co[2] < ztop)))
    for pt, n, sel in planes:
        b.faces.ensure_lookup_table()
        if sel is None:
            geom = list(b.verts) + list(b.edges) + list(b.faces)
        else:
            fs = [f for f in b.faces if all(sel(v.co, min(max(v[lay], 0), info.n - 1)) for v in f.verts)]
            if not fs:
                continue
            es = set()
            vs = set()
            for f in fs:
                es.update(f.edges)
                vs.update(f.verts)
            geom = list(vs) + list(es) + fs
        bmesh.ops.bisect_plane(b, geom=geom, dist=0.0002, plane_co=Vector(pt.tolist()),
                               plane_no=Vector(n.tolist()), clear_outer=True)
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
    b.to_mesh(me)
    b.free()
    me.update()


def _clean_islands(obj, min_faces=40):
    b = bmesh.new()
    b.from_mesh(obj.data)
    b.faces.ensure_lookup_table()
    seen = set()
    dead = []
    for f in b.faces:
        if f.index in seen:
            continue
        stack = [f]
        comp = []
        seen.add(f.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.edges:
                for y in e.link_faces:
                    if y.index not in seen:
                        seen.add(y.index)
                        stack.append(y)
        if len(comp) < min_faces:
            dead.extend(comp)
    if dead:
        bmesh.ops.delete(b, geom=dead, context="FACES")
        bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context="VERTS")
        b.to_mesh(obj.data)
        obj.data.update()
    b.free()


def _hang(co, src, info, zmin, zmax, taper, sel, front_only=False, fade=0.07):
    """Drape: below zmax the garment falls from the widest point above instead of following every concavity
    (coats hang off the shoulders/chest, bodices bridge the under-bust). Works per angular sector around the torso
    axis; `taper` lets the hang narrow by that many metres per metre of drop (0 = plumb)."""
    cx, cy = 0.0, info.pelvis[1]
    idx = np.nonzero(sel & (co[:, 2] <= zmax + 0.06) & (co[:, 2] >= zmin - fade))[0]
    if front_only:
        idx = idx[co[idx, 1] < cy + 0.02]
    if len(idx) < 10:
        return co
    rel = co[idx, :2] - np.array([cx, cy])
    th = np.arctan2(rel[:, 1], rel[:, 0])
    r = np.linalg.norm(rel, axis=1)
    K = 48
    sec = ((th + math.pi) / (2 * math.pi) * K).astype(int) % K
    order = np.argsort(-co[idx, 2])
    run = np.zeros(K)
    runz = np.full(K, np.nan)
    newr = r.copy()
    for o in order:
        k = sec[o]
        z = co[idx[o], 2]
        if z > zmax:
            if r[o] > run[k]:
                run[k] = r[o]
                runz[k] = z
            continue
        if not np.isnan(runz[k]):
            # neighbouring sectors share their hang so the drape stays smooth around the body
            lim = max(run[k], 0.5 * (run[(k - 1) % K] + run[(k + 1) % K])) - taper * (runz[k] - z)
            if z < zmin:
                # below the hang zone the drape eases back onto the body instead of stepping (no ledge)
                u = float(np.clip((z - (zmin - fade)) / max(fade, 1e-6), 0, 1))
                lim = r[o] + (lim - r[o]) * u * u * (3 - 2 * u)
            if lim > r[o]:
                newr[o] = lim
        if newr[o] > run[k]:
            run[k] = newr[o]
            runz[k] = z
    scale = newr / np.maximum(r, 1e-6)
    co = co.copy()
    co[idx, 0] = cx + rel[:, 0] * scale
    co[idx, 1] = cy + rel[:, 1] * scale
    return co


def _front_hull(co, mask, info, z0, z1, edges):
    """Per horizontal slice, push the front of the garment out to the convex hull of the slice: a corseted bodice
    front (one smooth bust line, no cleavage or under-bust fold)."""
    co = co.copy()
    idx = np.nonzero(mask & (co[:, 2] > z0) & (co[:, 2] < z1))[0]
    if len(idx) < 20:
        return co
    zb = np.round((co[idx, 2] - z0) / 0.012).astype(int)
    moved = np.zeros(len(co), dtype=bool)
    for b in np.unique(zb):
        sl = idx[zb == b]
        if len(sl) < 6:
            continue
        pts = co[sl, :2]
        order = np.argsort(pts[:, 0])
        P = pts[order]
        # lower hull in (x, y) (the front is -y): monotone chain keeping the most negative y envelope
        hull = []
        for q in P:
            while len(hull) >= 2:
                a, b2 = hull[-2], hull[-1]
                cross = (b2[0] - a[0]) * (q[1] - a[1]) - (b2[1] - a[1]) * (q[0] - a[0])
                if cross <= 0:
                    hull.pop()
                else:
                    break
            hull.append(q)
        H = np.array(hull)
        if len(H) < 2:
            continue
        hy = np.interp(pts[:, 0], H[:, 0], H[:, 1])
        front = pts[:, 1] < info.pelvis[1]
        newy = np.where(front & (hy < pts[:, 1]), hy, pts[:, 1])
        moved[sl] = newy != pts[:, 1]
        co[sl, 1] = newy
    sm = _laplacian(co, edges, 4, 0.35, fixed=~(mask & (co[:, 2] > z0) & (co[:, 2] < z1)))
    return sm


def _lower_hull(P):
    """Min-y envelope of 2D points sorted by their first coordinate (monotone chain)."""
    hull = []
    for q in P:
        while len(hull) >= 2:
            a, b2 = hull[-2], hull[-1]
            if (b2[0] - a[0]) * (q[1] - a[1]) - (b2[1] - a[1]) * (q[0] - a[0]) <= 0:
                hull.pop()
            else:
                break
        hull.append(q)
    return np.array(hull)


def _flatten_front(co, chest, w, edges, body_pos, info, sink=0.035):
    """Corseted 1899 front (one smooth 'pigeon' bust line): smooth away small features (inward allowed, the skin
    under the garment is deleted, never more than `sink` behind it), then push the front out to the convex hull of
    every vertical column (fills the under-bust and the upper-chest hollow) and of every horizontal slice
    (fills the cleavage)."""
    n = len(co)
    m = chest & (w > 0)
    idx = np.nonzero(m)[0]
    if len(idx) < 30:
        return co
    co_in = co
    # untangle first: under a sagging bust the surface curls back up into the fold, so the same (x, z) holds two
    # sheets and a depth-only hull would fold the cloth over itself; plain 3D smoothing unrolls the curl
    co = _laplacian(co, edges, 40, 0.5, fixed=~m)
    y0 = co[:, 1].copy()
    y = y0.copy()
    for _ in range(20):
        acc = np.zeros(n)
        cnt = np.zeros(n)
        np.add.at(acc, edges[:, 0], y[edges[:, 1]])
        np.add.at(acc, edges[:, 1], y[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        y = np.where(m, y + 0.5 * (acc / np.maximum(cnt, 1) - y), y0)
    y = np.where(m, np.minimum(y, body_pos[:, 1] + sink), y)
    for _ in range(2):
        # vertical columns: hull over (z, y)
        xb = np.round(co[idx, 0] / 0.012).astype(int)
        for b in np.unique(xb):
            sl = idx[xb == b]
            if len(sl) < 4:
                continue
            o = np.argsort(co[sl, 2])
            P = np.stack([co[sl[o], 2], y[sl[o]]], axis=1)
            H = _lower_hull(P)
            if len(H) >= 2:
                y[sl] = np.minimum(y[sl], np.interp(co[sl, 2], H[:, 0], H[:, 1]))
        # horizontal slices: hull over (x, y)
        zb = np.round(co[idx, 2] / 0.012).astype(int)
        for b in np.unique(zb):
            sl = idx[zb == b]
            if len(sl) < 4:
                continue
            o = np.argsort(co[sl, 0])
            P = np.stack([co[sl[o], 0], y[sl[o]]], axis=1)
            H = _lower_hull(P)
            if len(H) >= 2:
                y[sl] = np.minimum(y[sl], np.interp(co[sl, 0], H[:, 0], H[:, 1]))
    co = co.copy()
    co[:, 1] = y
    k = (w * m)[:, None]
    co = co_in * (1 - k) + co * k
    # feather the fill into the flanks: diffuse the displacement past the chest mask (and smooth its jumps), keeping
    # the fuller (more forward) of the raw and diffused fill on the chest itself
    D = co - co_in
    band = (co_in[:, 2] > info.navel_z - 0.15) & (co_in[:, 2] < info.shoulder_z + 0.02) & (co_in[:, 1] < info.pelvis[1] + 0.06)
    Ds = D.copy()
    cnt = np.zeros(n)
    np.add.at(cnt, edges[:, 0], 1)
    np.add.at(cnt, edges[:, 1], 1)
    for _ in range(30):
        acc = np.zeros_like(Ds)
        np.add.at(acc, edges[:, 0], Ds[edges[:, 1]])
        np.add.at(acc, edges[:, 1], Ds[edges[:, 0]])
        Ds = np.where(band[:, None], 0.5 * Ds + 0.5 * acc / np.maximum(cnt, 1)[:, None], 0.0)
    Df = np.where(m[:, None], D, Ds)
    Df[:, 1] = np.where(m, np.minimum(D[:, 1], Ds[:, 1]), Ds[:, 1])
    co = co_in + Df
    return _laplacian(co, edges, 3, 0.35, fixed=~band)


def _shell_normals(obj, co, fallback):
    """Area-weighted vertex normals of the shell at positions `co` (outward like the body's)."""
    me = obj.data
    me.calc_loop_triangles()
    tri = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get("vertices", tri)
    tri = tri.reshape(-1, 3)
    fn = np.cross(co[tri[:, 1]] - co[tri[:, 0]], co[tri[:, 2]] - co[tri[:, 0]])
    vn = np.zeros_like(co)
    for k in range(3):
        np.add.at(vn, tri[:, k], fn)
    ln = np.linalg.norm(vn, axis=1)
    vn = np.where(ln[:, None] > 1e-12, vn / np.maximum(ln, 1e-12)[:, None], fallback)
    # keep the body's orientation convention
    flip = (vn * fallback).sum(axis=1).mean() < 0
    return -vn if flip else vn


def _despike(co, edges, gn, keep, thresh=0.012, iters=8, axis=None, radial_ok=None):
    """Relax vertices left behind by a masked drape pass (a hang/hull moved their neighbours out, not them): a
    vertex whose neighbour average lies more than `thresh` outward (along the cloth normal gn) moves onto it.
    `keep` (shell boundary) is never moved."""
    n = len(co)
    cnt = np.zeros(n)
    np.add.at(cnt, edges[:, 0], 1)
    np.add.at(cnt, edges[:, 1], 1)
    for _ in range(iters):
        acc = np.zeros_like(co)
        np.add.at(acc, edges[:, 0], co[edges[:, 1]])
        np.add.at(acc, edges[:, 1], co[edges[:, 0]])
        avg = acc / np.maximum(cnt, 1)[:, None]
        d = avg - co
        bad = ((d * gn).sum(axis=1) > thresh)
        if axis is not None:
            # dents: the neighbourhood sits clearly further out from the torso axis than the vertex
            r0 = np.hypot(co[:, 0], co[:, 1] - axis)
            r1 = np.hypot(avg[:, 0], avg[:, 1] - axis)
            bad |= (r1 - r0 > 0.01) & (np.linalg.norm(d, axis=1) > 0.025) & radial_ok
        bad &= (cnt > 2) & ~keep
        if not bad.any():
            break
        co = co.copy()
        co[bad] = avg[bad]
    return co


def _scale_groups(obj, prefixes, f, fallback):
    """Scale the weights of bone groups starting with `prefixes` by per-vertex f (0..1), renormalise; a vertex left
    without weight goes to `fallback`."""
    if np.all(f >= 0.999):
        return
    gs = [vg for vg in obj.vertex_groups if vg.name.startswith(prefixes)]
    if not gs:
        return
    gi = {vg.index for vg in gs}
    fb = obj.vertex_groups.get(fallback) or obj.vertex_groups.new(name=fallback)
    for v in obj.data.vertices:
        k = f[v.index]
        if k >= 0.999:
            continue
        tot, kept = 0.0, 0.0
        for e in v.groups:
            tot += e.weight
            if e.group in gi:
                e.weight *= k
            kept += e.weight
        if tot <= 0:
            continue
        if kept < 1e-4:
            fb.add([v.index], tot, "REPLACE")
            continue
        for e in v.groups:
            e.weight *= tot / kept


def _smooth_weights(obj, edges, mask, iters, lam=0.5):
    """Laplacian-blur the skin weights of the masked vertices (all groups together, renormalised)."""
    if iters <= 0 or not mask.any():
        return
    n = len(obj.data.vertices)
    groups = list(obj.vertex_groups)
    arm = obj.parent if obj.parent is not None and obj.parent.type == "ARMATURE" else None
    if arm is not None:
        groups = [vg for vg in groups if vg.name in arm.data.bones]
    if not groups:
        return
    Wt = np.zeros((n, len(groups)), dtype=np.float64)
    gidx = {vg.index: k for k, vg in enumerate(groups)}
    for v in obj.data.vertices:
        for e in v.groups:
            k = gidx.get(e.group)
            if k is not None:
                Wt[v.index, k] = e.weight
    W0 = Wt.copy()
    cnt = np.zeros(n)
    np.add.at(cnt, edges[:, 0], 1)
    np.add.at(cnt, edges[:, 1], 1)
    for _ in range(iters):
        acc = np.zeros_like(Wt)
        np.add.at(acc, edges[:, 0], Wt[edges[:, 1]])
        np.add.at(acc, edges[:, 1], Wt[edges[:, 0]])
        avg = acc / np.maximum(cnt, 1)[:, None]
        Wt = np.where(mask[:, None], Wt + lam * (avg - Wt), W0)
    Wt /= np.maximum(Wt.sum(axis=1, keepdims=True), 1e-9)
    idx = np.nonzero(mask)[0]
    for k, vg in enumerate(groups):
        col = Wt[idx, k]
        nz = col > 1e-4
        if nz.any():
            # bucket by weight to keep the number of add() calls small
            q = np.round(col[nz], 3)
            ids = idx[nz]
            for w in np.unique(q):
                vg.add(ids[q == w].tolist(), float(w), "REPLACE")
        z = ~nz
        if z.any():
            vg.remove(idx[z].tolist())


def body_shell(builder, info, g):
    t = g["type"]
    vmask, cuts = _region(info, g, margin=0.025)
    obj = _shell_from_region(builder, info, vmask, g["id"])
    _clean_islands(obj, g.get("min_island", 60))
    if len(obj.data.vertices) == 0:
        bpy.data.objects.remove(obj)
        return None
    src = _src_index(obj)
    co = C.get_co(obj)
    nrm = info.nrm[src]
    edges = _neighbors(obj)
    off = g.get("offset", 0.006)
    body_pos = info.co[src]
    z = body_pos[:, 2]
    ap = info.arm_p[src]
    lp = info.leg_p[src]
    torso_v = (ap < 0.25) | info.dom_in(("pelvis", "spine_", "neck_"))[src]
    # ease: thickness of the layer + looseness that grows away from the fitted parts
    ease = np.full(len(co), off)
    if t == "coat":
        ease += np.clip((info.shoulder_z - z) / 0.5, 0, 1) * g.get("loose", 0.02)
        ease += np.clip(ap - 0.2, 0, 1.7) * 0.008
    if t == "trousers":
        ease += np.clip((info.hip_z - z) / 0.45, 0, 1) * g.get("loose", 0.014)
    if t in ("shirt", "bodice"):
        ease += np.clip(ap - 0.2, 0, 1.7) * g.get("loose", 0.007)
        ease += torso_v * 0.003
    if t == "vest":
        ease += 0.002
    if t == "boots":
        ease += np.clip(lp - 1.9, 0, 0.2) * 0.02
    co = co + nrm * ease[:, None]
    # drape: smooth (fills creases between muscles), then never inside the body
    co = _laplacian(co, edges, g.get("smooth", 5), 0.35)
    inward = ((co - body_pos) * nrm).sum(axis=1)
    if t != "boots":
        co = co + nrm * np.clip(off * 0.7 - inward, 0, None)[:, None]
    seed = g.get("seed", 0)
    if t in ("shirt", "bodice", "vest", "coat"):
        # bridge the under-bust / pectoral fold and the small of the back
        bz = info.bust_z
        co = _hang(co, src, info, bz - 0.12, bz, 0.25 if t != "coat" else 0.0, torso_v, front_only=False,
                   fade=0.10 if g.get("smooth_chest") else 0.06)
    sink_ok = np.zeros(len(co))
    if g.get("smooth_chest"):
        chest = torso_v & (z > info.navel_z - 0.04) & (z < info.shoulder_z) & (body_pos[:, 1] < info.pelvis[1] + 0.02)
        w = np.clip((z - (info.navel_z - 0.04)) / 0.06, 0, 1) * np.clip((info.shoulder_z - z) / 0.06, 0, 1)
        sm = _inflate(co, edges, nrm, 250, chest, lam=0.8)
        sm = _laplacian(sm, edges, 8, 0.4, fixed=~chest)
        co = co * (1 - w[:, None] * chest[:, None]) + sm * (w[:, None] * chest[:, None])
        co = _front_hull(co, torso_v, info, info.navel_z - 0.02, info.shoulder_z - 0.01, edges)
        co = _flatten_front(co, chest, w, edges, body_pos, info)
        sink_ok = 0.035 * w * chest
    if t == "coat":
        # coats hang straight from the chest and shoulder blades down to the hem
        co = _hang(co, src, info, info.crotch_z - 0.3, info.bust_z, -0.03, torso_v)
    if t == "shirt" and g.get("blouse", 0.012) > 0:
        # shirt blousing over the waistband: a soft bulge just above the belt, more at front and back
        belt = info.navel_z - 0.012
        u = np.clip((z - belt) / 0.11, 0, 1)
        prof = np.clip(np.sin(u * math.pi), 0, None) ** 0.8 * (z > belt - 0.02)
        rel = co[:, :2] - np.array([0.0, info.pelvis[1]])
        th = np.arctan2(rel[:, 1], rel[:, 0])
        amt = g.get("blouse", 0.012) * prof * (0.7 + 0.3 * np.abs(np.sin(th))) * torso_v
        amt *= 1.0 + 0.4 * fbm3(co * 9, seed + 11)
        rn = rel / np.maximum(np.linalg.norm(rel, axis=1), 1e-6)[:, None]
        co[:, :2] += rn * amt[:, None]
        co[:, 2] -= amt * 0.35
    if t == "trousers":
        hem = g.get("hem", 1.97)
        if hem >= 1.9:
            # break over the shoes: the hem flares a little and sits lower at the back
            f = np.clip((lp - 1.72) / 0.25, 0, 1)
            for side, sx in (("l", 1), ("r", -1)):
                m = (co[:, 0] * sx > 0) & (f > 0)
                a, b = info.j["calf_" + side], info.j["foot_" + side]
                ax = (b - a) / np.linalg.norm(b - a)
                rel = co[m] - a
                rel -= np.outer(rel @ ax, ax)
                rn = rel / np.maximum(np.linalg.norm(rel, axis=1), 1e-6)[:, None]
                co[m] += rn * (0.009 * f[m])[:, None]
                back = np.clip(rel[:, 1] / 0.06, 0, 1)
                co[m, 2] -= 0.012 * f[m] * back
        else:
            # tucked into boots: fabric bunches above the boot top
            f = np.exp(-((lp - (hem - 0.06)) / 0.08) ** 2)
            co += nrm * (0.006 * f)[:, None]
    if t == "boots":
        co = _boot_shape(co, src, info, edges, off, feet=not g.get("shaft_only"))
    # displacements from here on follow the draped cloth's own normal (the body normal under a filled bust or a
    # hanging coat points down/back and would fold the cloth over itself)
    gn = _shell_normals(obj, co, nrm)
    # folds: elbow and wrist bunching on sleeves, knee and ankle stacks on trousers, drape ripples on bodies
    fold = np.zeros(len(co))
    if t in ("shirt", "bodice", "coat"):
        elbow = np.exp(-((ap - 1.0) / 0.22) ** 2) * (ap >= 0)
        cuff = np.clip((ap - 1.55) / 0.4, 0, 1)
        fold += (elbow * 0.006 + cuff * 0.004) * np.sin(ap * 42 + fbm3(co * 9, seed) * 3) * (ap > 0.3)
        fold += 0.003 * np.clip((info.shoulder_z - z) / 0.4, 0, 1) * fbm3(co * np.array([14, 14, 3.5]), seed + 3) * torso_v
    if t == "trousers":
        knee = np.exp(-((lp - 1.0) / 0.22) ** 2)
        stack = np.clip((lp - 1.6) / 0.35, 0, 1)
        fold += (knee * 0.005 + stack * 0.008) * np.sin(lp * 36 + fbm3(co * 8, seed) * 3)
        fold += 0.003 * fbm3(co * np.array([11, 11, 2.5]), seed + 5)
    if t == "vest":
        fold += 0.0015 * fbm3(co * 14, seed)
    if t == "coat":
        fold += 0.004 * np.clip((info.bust_z - z) / 0.4, 0, 1) * fbm3(co * np.array([9, 9, 1.8]), seed + 7) * torso_v
    if t == "boots":
        fold += 0.002 * np.exp(-((lp - 1.95) / 0.08) ** 2) * np.sin(z * 260)
    co = co + gn * fold[:, None]
    # layering: stay at least `gap` outside every inner garment over the same body vertex, then record our layer
    gap = g.get("gap", 0.004)
    inward = ((co - body_pos) * nrm).sum(axis=1)
    # floor: the inner layers, else the body itself (a flattened chest may sink into the deleted skin)
    push = np.clip(np.maximum(info.occ[src], -sink_ok) + gap - inward, 0, None)
    if t == "boots":
        push[lp >= 1.86] = 0.0
    co = co + gn * push[:, None]
    if t != "boots":
        co = _despike(co, edges, gn, _boundary_verts(obj), axis=info.pelvis[1],
                      radial_ok=torso_v | ((ap < 0.3) & (lp < 0.2)))
    inward = ((co - body_pos) * nrm).sum(axis=1)
    np.maximum.at(info.occ, src, inward + 0.0015)
    C.set_co(obj, co)
    if t in ("shirt", "bodice", "vest", "coat"):
        # the drape bridged folds the body weights don't know about: blur the skin weights over the torso (and much
        # more over a flattened chest) so the cloth bends as one piece instead of creasing under the bust
        # torso cloth below the armpit must not follow the arm (MakeHuman gives the upper flank upper-arm weight):
        # with hands on hips that pinched notches into bodices under the bust
        sx = abs(float(info.j["upperarm_l"][0]))
        flank = (np.abs(body_pos[:, 0]) < sx - 0.005)
        keep_arm = np.where(flank, np.clip((z - (info.shoulder_z - 0.13)) / 0.08, 0, 1), 1.0)
        _scale_groups(obj, ("upperarm_", "lowerarm_", "hand_"), keep_arm, fallback="spine_03")
        tw = torso_v & (z > info.crotch_z) & (z < info.shoulder_z - 0.02) & (ap < 0.15)
        _smooth_weights(obj, edges, tw, 4)
        if g.get("smooth_chest"):
            ch = tw & (z > info.navel_z - 0.06) & (body_pos[:, 1] < info.pelvis[1] + 0.02)
            _smooth_weights(obj, edges, ch, 16)
    if t == "boots" and not g.get("shaft_only"):
        _boot_sole(obj, info)
    # per-vertex shading data before the cut (bisect interpolates point attributes)
    occl = 0.8 + 0.2 * np.clip(fold / 0.008 + 0.5, 0, 1)
    wear = np.zeros(len(co))
    if t in ("shirt", "coat", "bodice"):
        wear += np.exp(-((ap - 1.0) / 0.12) ** 2) * (ap >= 0) * 0.8
    if t == "trousers":
        wear += np.exp(-((lp - 1.0) / 0.15) ** 2) * 0.8 + np.clip((lp - 1.8) / 0.2, 0, 1) * 0.6
    me = obj.data
    for name, vals in (("pre_occl", occl), ("pre_wear", wear)):
        a = me.attributes.new(name, "FLOAT", "POINT")
        a.data.foreach_set("value", vals.astype(np.float32))
    _bisect_cuts(obj, info, cuts)
    n = len(me.vertices)
    occl = np.empty(n, dtype=np.float32)
    wear = np.empty(n, dtype=np.float32)
    me.attributes["pre_occl"].data.foreach_get("value", occl)
    me.attributes["pre_wear"].data.foreach_get("value", wear)
    me.attributes.remove(me.attributes["pre_occl"])
    me.attributes.remove(me.attributes["pre_wear"])
    hem = _hem_distance(obj)
    wear = wear + np.clip(1 - hem / 0.03, 0, 1) * 0.5
    occl = occl * (0.88 + 0.12 * np.clip(hem / 0.02, 0, 1))
    if t != "boots":
        _mark_covered(builder, info, _region(info, g, 0.0)[0], rings=2 if t != "vest" else 3)
    else:
        _mark_covered(builder, info, vmask & ~info.dom_in(("calf_",)), rings=1)
    return _finish(builder, obj, g, occl, wear, rim=g.get("rim", 0.005), hem=hem)


def _hem_distance(obj, maxd=0.05):
    """Approximate surface distance (m) from the open edge, for hem stitching / wear (vertex colour b)."""
    me = obj.data
    co = C.get_co(obj)
    e = _neighbors(obj)
    L = np.linalg.norm(co[e[:, 0]] - co[e[:, 1]], axis=1)
    d = np.full(len(co), maxd)
    d[_boundary_verts(obj)] = 0.0
    for _ in range(30):
        nd = d.copy()
        np.minimum.at(nd, e[:, 0], d[e[:, 1]] + L)
        np.minimum.at(nd, e[:, 1], d[e[:, 0]] + L)
        if np.allclose(nd, d):
            break
        d = nd
    return np.minimum(d, maxd)


def _boot_shape(co, src, info, edges, off, feet=True):
    """Boots: heavy smoothing (no toes), shaft made a clean tube around the calf axis."""
    lp = info.leg_p[src]
    body_pos = info.co[src]
    nrm = info.nrm[src]
    co = co + nrm * 0.006
    for _ in range(10):   # Taubin smoothing: removes the toes without shrinking the boot
        co = _laplacian(co, edges, 1, 0.55)
        co = _laplacian(co, edges, 1, -0.58)
    co = _laplacian(co, edges, 6, 0.5)
    inward = ((co - body_pos) * nrm).sum(axis=1)
    co = co + nrm * np.clip(0.003 - inward, 0, None)[:, None]
    for s_, sx in (("l", 1), ("r", -1)):
        a, b = info.j["calf_" + s_], info.j["foot_" + s_]
        axis = b - a
        L = np.linalg.norm(axis)
        side = (co[:, 0] * sx > 0) & (lp < 1.88)
        if not side.any():
            continue
        t = np.clip((lp[side] - 1.0), 0, 1)
        centre = a + t[:, None] * axis
        rel = co[side] - centre
        rel -= (rel @ (axis / L))[:, None] * (axis / L)
        r = np.linalg.norm(rel, axis=1)
        bins = np.round(t * 20).astype(int)
        rt = r.copy()
        for bi in np.unique(bins):
            m = bins == bi
            rt[m] = r[m].max() + 0.003
        # boots widen slightly toward the top (stovepipe)
        rt += np.clip((1.75 - lp[side]) / 0.3, 0, 1) * 0.01
        new = centre + rel / np.maximum(r, 1e-6)[:, None] * rt[:, None] + \
            ((co[side] - centre) @ (axis / L))[:, None] * (axis / L)
        co[side] = co[side] * 0.25 + new * 0.75
    # foot: per-slice star-convex envelope along the heel->toe axis (no toes, a boot "last")
    for s_, sx in (("l", 1), ("r", -1)):
        foot = (co[:, 0] * sx > 0) & (lp >= 1.86)
        if foot.sum() < 20 or not feet:
            continue
        a = info.j["foot_" + s_].copy()
        bvec = info.j["ball_" + s_] - a
        bvec[2] = 0
        ax = bvec / np.linalg.norm(bvec)
        up = np.array([0, 0, 1.0])
        lat = np.cross(ax, up)
        P = co[foot]
        sp = (P - a) @ ax
        bins = np.clip(((sp - sp.min()) / max(np.ptp(sp), 1e-6) * 18).astype(int), 0, 18)
        cen = np.zeros_like(P)
        for bi in np.unique(bins):
            m = bins == bi
            cen[m] = P[m].mean(axis=0)
        rel = P - cen
        rel -= np.outer(rel @ ax, ax)
        ang = np.arctan2(rel @ up, rel @ lat)
        rad = np.linalg.norm(rel, axis=1)
        K = 9
        sec = ((ang + math.pi) / (2 * math.pi) * K).astype(int) % K
        env = np.zeros((19, K))
        for bi, si, r in zip(bins, sec, rad):
            env[bi, si] = max(env[bi, si], r)
        for _ in range(3):  # fill and smooth around the section and along the foot
            env = np.maximum(env, (np.roll(env, 1, 1) + np.roll(env, -1, 1)) / 2)
            env = (env + np.roll(env, 1, 1) + np.roll(env, -1, 1)) / 3
        env = (env + np.vstack([env[:1], env[:-1]]) + np.vstack([env[1:], env[-1:]])) / 3
        # interpolate between sector centres (smooth around the section)
        fpos = (ang + math.pi) / (2 * math.pi) * K - 0.5
        i0 = np.floor(fpos).astype(int) % K
        i1 = (i0 + 1) % K
        fr = fpos - np.floor(fpos)
        target = env[bins, i0] * (1 - fr) + env[bins, i1] * fr + 0.002
        newP = cen + np.outer(P @ ax - cen @ ax, ax) * 0 + rel / np.maximum(rad, 1e-6)[:, None] * target[:, None] + \
            np.outer((P - cen) @ ax, ax)
        co[foot] = newP
    co = _laplacian(co, edges, 3, 0.4)
    return co


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
def _spring_weights(builder, obj, g, co, depth, ring_pts, zs, thetas, keep_seg, cx, cy, info):
    """Skirts / coat tails / duster tails: chains of spring bones (children of the pelvis) hang down the tube; the
    cloth is skinned to them (blend between the two nearest chains, along the chain by depth) with a little thigh
    follow. Godot's SpringBoneSimulator3D (FrontierCharacter) swings them, with leg capsules pushing them away.
    Bone names: <garment>_c<chain>_<bone>."""
    gid = g["id"]
    R = len(ring_pts)
    K = len(thetas)
    nch = g.get("chains", 8 if g["type"] == "skirt" else 6)
    nb = g.get("chain_bones", 3)
    # chain angles: evenly over the segments that exist (tails have a front opening)
    seg = [k for k in range(K) if keep_seg[k]]
    if g["type"] == "skirt":
        ks = [int(round(i * K / nch)) % K for i in range(nch)]
    else:
        ks = [seg[int(round(i * (len(seg) - 1) / max(nch - 1, 1)))] for i in range(nch)]
    r_start = 1
    rows = [r_start + int(round(i * (R - 1 - r_start) / nb)) for i in range(nb + 1)]
    rig = builder.rig
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    names = []
    for ci, k in enumerate(ks):
        prev = eb["pelvis"]
        chain = []
        for bi in range(nb):
            bn = "%s_c%d_%d" % (gid, ci, bi)
            b = eb.new(bn)
            b.head = Vector(ring_pts[rows[bi]][k].tolist())
            b.tail = Vector(ring_pts[rows[bi + 1]][k].tolist())
            b.parent = prev
            b.use_connect = bi > 0
            b.use_deform = True
            prev = b
            chain.append(bn)
        names.append(chain)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.selected_objects:
        o.select_set(False)
    chain_th = np.array([thetas[k] for k in ks])
    groups = {}

    def grp(n):
        if n not in groups:
            groups[n] = obj.vertex_groups.new(name=n)
        return groups[n]
    th_v = np.arctan2(co[:, 1] - cy, co[:, 0] - cx)
    dr = depth * (R - 1)
    follow = g.get("leg_follow", 0.12)
    hipw = abs(info.j["thigh_l"][0] - info.j["thigh_r"][0])
    for i in range(len(co)):
        # two nearest chains by angle
        dth = np.abs((th_v[i] - chain_th + math.pi) % (2 * math.pi) - math.pi)
        o2 = np.argsort(dth)[:2]
        a0, a1 = dth[o2[0]], dth[o2[1]]
        wa = np.array([a1, a0]) / max(a0 + a1, 1e-6)
        if g["type"] != "skirt" and a0 > 2 * math.pi / len(thetas) * 3:
            wa = np.array([1.0, 0.0])
        q = (dr[i] - r_start) / ((R - 1 - r_start) / nb)
        w_pel = float(np.clip(0.6 - q, 0, 1))
        qb = min(max(q, 0.0), nb - 1e-3)
        b0 = int(qb)
        f = qb - b0
        legw = follow * depth[i]
        rest = max(1.0 - w_pel - legw, 0.0)
        if w_pel > 0:
            grp("pelvis").add([i], w_pel, "ADD")
        side = float(np.clip(0.5 + co[i, 0] / (hipw * 1.6), 0, 1))
        if legw > 0:
            grp("thigh_l").add([i], legw * side, "ADD")
            grp("thigh_r").add([i], legw * (1 - side), "ADD")
        for j, cw in zip(o2, wa):
            if cw <= 0:
                continue
            ch = names[j]
            if f < 0.3 and b0 > 0:
                blend = 0.5 - f / 0.6
                grp(ch[b0 - 1]).add([i], rest * cw * blend, "ADD")
                grp(ch[b0]).add([i], rest * cw * (1 - blend), "ADD")
            else:
                grp(ch[b0]).add([i], rest * cw, "ADD")
    builder.spring_chains = getattr(builder, "spring_chains", []) + [{"garment": gid, "chains": names}]


def tube(builder, info, g):
    t = g["type"]
    seed = g.get("seed", 0)
    z_top = {"skirt": info.navel_z + 0.025, "tails": info.crotch_z + 0.1, "apron": info.navel_z + 0.02}[t]
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
    # an apron over a skirt must clear the skirt's flare, waves and folds everywhere
    under = None
    if t == "apron":
        under = next((c for c in builder.spec.get("clothes", []) if c.get("type") == "skirt"), None)
    if under is not None:
        s_top = info.navel_z + 0.025
        s_bot = info.ankle_z - under.get("below_ankle", 0.02) - 0.06
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
        env = r
        r = r + ease + flare * depth ** 1.4 * (0.6 if t == "tails" else 1.0)
        if under is not None:
            sd = np.clip((s_top - zz) / max(s_top - s_bot, 1e-3), 0, 1)
            r_skirt = (env + under.get("ease", 0.02) + under.get("flare", 0.18) * sd ** 1.4) * 1.005 ** ri
            r = np.maximum(r, r_skirt * (1 + 0.035 * sd ** 2) + under.get("fold", 0.012) + 0.012)
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
    if g.get("spring", t in ("skirt", "tails")):
        _spring_weights(builder, obj, g, co, depth, ring_pts, zs, thetas, keep_seg, cx, cy, info)
        occl = 0.8 + 0.2 * np.clip(fold / 0.012 + 0.5, 0, 1)
        wear = np.clip((depth - 0.85) / 0.15, 0, 1) * 0.8
        if t == "skirt" and g.get("hide_legs", True):
            legs = info.body & info.dom_in(("thigh_", "calf_")) & (info.co[:, 2] > z_bot + 0.12) & (info.co[:, 2] < z_top - 0.05)
            _mark_covered(builder, info, legs, rings=1)
        return _finish(builder, obj, g, occl, wear, uv2=luv, rim=g.get("rim", 0.003), hem=_hem_distance(obj))
    # weights: pelvis at the waist -> thighs/calves with depth, split by side
    gp = obj.vertex_groups.new(name="pelvis")
    gl = obj.vertex_groups.new(name="thigh_l")
    gr = obj.vertex_groups.new(name="thigh_r")
    gcl = obj.vertex_groups.new(name="calf_l")
    gcr = obj.vertex_groups.new(name="calf_r")
    hipw = abs(info.j["thigh_l"][0] - info.j["thigh_r"][0])
    swing = g.get("leg_follow", 0.55 if t == "skirt" else (0.15 if under is not None else 0.75))
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
    return _finish(builder, obj, g, occl, wear, uv2=luv, rim=g.get("rim", 0.003), hem=_hem_distance(obj))


# ------------------------------------------------------------------------------------------------------------------
# hats (lathe)
HAT_PROFILES = {
    # (r_rel, h) pairs from the brim edge in to the crown top; r_rel: 0 = band, >0 brim (metres outside the band),
    # <0 crown narrowing (metres inside the band). h: metres above the band line.
    "cattleman": dict(brim=0.08, crown_h=0.082, taper=0.016, curl=0.026, crease=0.02, pinch=0.014),
    "plainsman": dict(brim=0.085, crown_h=0.08, taper=0.01, curl=0.01, crease=0.0, pinch=0.0, round_top=0.022),
    "bowler": dict(brim=0.045, crown_h=0.11, taper=-0.004, curl=0.018, crease=0.0, pinch=0.0, dome=True),
    "flatcap": dict(brim=0.0, crown_h=0.055, taper=-0.01, curl=0.0, crease=0.0, pinch=0.0, cap=True),
    "boater": dict(brim=0.075, crown_h=0.075, taper=0.0, curl=0.0, crease=0.0, pinch=0.0),
    "slouch": dict(brim=0.095, crown_h=0.075, taper=0.004, curl=-0.012, crease=0.022, pinch=0.008, droop=0.028,
                   round_top=0.012),
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
        # crown-top rings never collapse to a point: a degenerate ring folded the top fan and showed its dark inside
        floor_r = 0.3 if kind == "top" else 0.0
        rr_x = np.maximum(rx + r_off, max(0.004, floor_r * rx))
        rr_y = np.maximum(ry + r_off, max(0.004, floor_r * ry))
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
    # the crown top (last profile rings + centre fan) must face up
    top0 = next((i for i, p in enumerate(prof) if p[0] == "top"), nr)
    b.faces.ensure_lookup_table()
    for fi, f in enumerate(b.faces):
        on_top = fi >= (top0 - 1) * K if top0 < nr else fi >= (nr - 1) * K
        if on_top and f.normal.z < 0:
            f.normal_flip()
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
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    head_m = info.body & info.dom_in(("head", "neck_"))
    mz, my = info.mouth_z, info.mouth_y
    nose = info.nose_tip
    sub_z = nose[2] - 0.014          # under the nose
    chin_z = info.chin_z
    hj = info.head
    front = y < hj[1] - 0.015
    # lips: an ellipse around the mouth line (kept bare)
    lips = front & (((x / 0.027) ** 2 + ((z - mz) / 0.0105) ** 2) < 1.0)
    if style == "moustache":
        w = 0.026 + np.clip(sub_z - z, 0, 0.03) * 0.5
        return head_m & front & (z < sub_z) & (z > mz + 0.004) & (np.abs(x) < w) & ~lips
    cheek_top = sub_z + 0.004 + np.abs(x) * 0.35
    low = {"full": 0.045, "short": 0.018}.get(style, 0.03)
    r = head_m & (z < cheek_top) & (z > chin_z - low) & (y < hj[1] + 0.03) & ~lips
    r &= ~((z < chin_z - 0.015) & (y > hj[1] - 0.025))      # throat / neck back stays clean
    if style == "chin":
        r &= (np.abs(x) < 0.03) & (z < mz - 0.006)
    if style == "mutton":
        r &= (np.abs(x) > 0.032) & (z > mz - 0.025)
    return r


def beard(builder, info, g):
    style = g.get("style", "full")
    regs = []
    r = beard_region(info, style)
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
    # five shells: dense dark roots -> sparse light tips; per-vertex length jitter breaks up the silhouette
    layer_alpha = (1.0, 0.86, 0.72, 0.56, 0.4)
    for li, frac in enumerate((0.15, 0.35, 0.55, 0.78, 1.0)):
        obj = _shell_from_region(builder, info, vmask, "%s_%d" % (g["id"], li))
        # keep the face blend shapes: re-copy them from the basemesh (shell_from_region cleared them)
        src = _src_index(obj)
        bmk = builder.basemesh.data.shape_keys
        base = C.get_co(builder.basemesh, bmk.key_blocks["Basis"])
        nrm = info.nrm[src]
        z = info.co[src, 2]
        jit = 0.7 + 0.6 * (fbm3(info.co[src] * 70.0, 41) * 0.5 + 0.5)
        droop = np.array([0, 0, -1.0]) * length * 0.4 * frac * jit[:, None]
        offv = nrm * (length * frac * jit + 0.0012)[:, None] + droop
        C.ensure_basis(obj)
        C.set_co(obj, base[src] + offv, obj.data.shape_keys.key_blocks["Basis"])
        C.set_co(obj, base[src] + offv)
        for kb in bmk.key_blocks:
            if kb.name == "Basis":
                continue
            kco = C.get_co(builder.basemesh, kb)
            C.add_shape(obj, kb.name, kco[src] + offv)
        col = obj.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        cc = np.ones((len(obj.data.vertices), 4), dtype=np.float32)
        bd = _boundary_distance(obj, 4)
        cc[:, 3] = layer_alpha[li] * (0.3 + 0.7 * np.clip(bd / 3.0, 0, 1))
        cc[:, :3] = 0.5 + 0.5 * frac          # inner shells darker (self-shadowing of the hair mass)
        uvl = obj.data.uv_layers[0].data      # each shell samples the strand texture at a different offset
        a = np.empty(len(uvl) * 2, dtype=np.float32)
        uvl.foreach_get("uv", a)
        uvl.foreach_set("uv", a + np.float32(li * 0.0137))
        col.data.foreach_set("color", cc.ravel())
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
    # tile the strand texture every ~4 cm (body atlas: ~1.6 m per UV unit)
    uvl = me.uv_layers[0].data
    a = np.empty(len(uvl) * 2, dtype=np.float32)
    uvl.foreach_get("uv", a)
    uvl.foreach_set("uv", a * (1.6 / 0.04))
    builder.beard_mask = vmask
    return obj


def beard_texture(density):
    """Procedural hair-strand texture (original): grey-scale strands whose alpha falls off along each strand, dense
    enough that the inner shell reads as a solid mass and the outer shells as a fuzzy edge. Cached on disk."""
    from PIL import Image, ImageDraw, ImageFilter
    path = os.path.join(C.cache_dir(), "beard_strands_v5_%d.png" % int(density * 100))
    if os.path.exists(path):
        return path
    rng = np.random.default_rng(1899)
    S = 512
    alpha = Image.new("L", (S, S), 125)   # inner shells read as a dense mass, outer shells only show strands
    lum = Image.new("L", (S, S), 150)
    da = ImageDraw.Draw(alpha)
    dl = ImageDraw.Draw(lum)
    n = int(5200 * density)
    for _ in range(n):
        x, y = rng.uniform(0, S, 2)
        L = rng.uniform(40, 110)
        a = rng.normal(math.pi / 2, 0.35)
        v = int(rng.uniform(150, 255))
        for ox in (-S, 0, S):           # wrap so the texture tiles
            for oy in (-S, 0, S):
                pts = [(x + ox, y + oy), (x + ox + math.cos(a) * L, y + oy + math.sin(a) * L)]
                da.line(pts, fill=v, width=3)
                dl.line(pts, fill=int(rng.uniform(170, 255)), width=2)
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    img = Image.merge("RGBA", (lum, lum, lum, alpha))
    img.save(path)
    return path


# ------------------------------------------------------------------------------------------------------------------
def belt(builder, info, g):
    """Leather gun belt (band slung on the hips) + holster block on the right thigh."""
    gun = g.get("style", "waist") == "gun"
    z = (info.hip_z + 0.02) if gun else (info.navel_z + g.get("dz", -0.012))
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
    r += g.get("offset", 0.026 if gun else 0.014)
    tilt = (0.035 * np.cos(th - math.radians(-30))) if gun else np.zeros(K)  # gun belt slung low on the right
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


# ------------------------------------------------------------------------------------------------------------------
# period women's hair: pinned-up styles (hair cap swept up from the hairline + bun / Gibson roll), original geometry
def hair_texture():
    """Procedural strand texture (original): long, slightly wavy strands along V with varied brightness."""
    from PIL import Image, ImageDraw, ImageFilter
    path = os.path.join(C.cache_dir(), "hair_strands_v1.png")
    if os.path.exists(path):
        return path
    rng = np.random.default_rng(1899)
    S = 512
    lum = Image.new("L", (S, S), 150)
    alpha = Image.new("L", (S, S), 200)
    dl = ImageDraw.Draw(lum)
    da = ImageDraw.Draw(alpha)
    for _ in range(9000):
        x = rng.uniform(0, S)
        y0 = rng.uniform(0, S)
        L = rng.uniform(120, 400)
        amp = rng.uniform(0, 4)
        ph = rng.uniform(0, 6.28)
        v = int(rng.uniform(80, 255))
        pts = []
        for k in range(12):
            yy = y0 + L * k / 11
            pts.append((x + amp * math.sin(ph + yy * 0.03), yy))
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                pp = [(px + ox, py + oy) for px, py in pts]
                dl.line(pp, fill=v, width=2)
                da.line(pp, fill=int(rng.uniform(200, 255)), width=2)
    lum = lum.filter(ImageFilter.GaussianBlur(0.5))
    img = Image.merge("RGBA", (lum, lum, lum, alpha))
    img.save(path)
    return path


def updo(builder, info, g):
    style = g.get("style", "bun_low")
    co = info.co
    head = info.body & info.dom_in(("head", "neck_"))
    hco = co[info.body & info.dom_in(("head",))]
    eye_z = info.eye_z
    cx = 0.0
    cy = float(hco[:, 1].mean()) + 0.01
    top = float(hco[:, 2].max())
    cz = top - 0.09
    phi = np.arctan2(co[:, 0] - cx, -(co[:, 1] - cy))          # 0 = front, +-pi = back
    back = (1 - np.cos(phi)) / 2
    hairline = eye_z + g.get("front", 0.058) - 0.135 * back ** 1.3
    reg = head & (co[:, 2] > hairline - 0.01)
    obj = _shell_from_region(builder, info, reg, g["id"])
    _clean_islands(obj, 80)
    src = _src_index(obj)
    p = info.co[src]
    nrm = info.nrm[src]
    ph = phi[src]
    hl = hairline[src]
    above = np.clip((p[:, 2] - hl) / 0.03, 0, 1)
    vol = np.full(len(p), g.get("volume", 0.007))
    if style == "gibson":
        # Gibson-girl pompadour: a full roll swept up and back from the forehead and temples
        vol += 0.022 * np.exp(-(ph / 1.2) ** 2) * above * np.clip((top - p[:, 2]) / 0.05, 0.3, 1)
    else:
        vol += 0.008 * np.exp(-(ph / 1.0) ** 2) * above
    vol *= 0.3 + 0.7 * above
    new = p + nrm * vol[:, None]
    edges = _neighbors(obj)
    new = _laplacian(new, edges, 6, 0.4)
    inward = ((new - p) * nrm).sum(axis=1)
    new += nrm * np.clip(0.003 - inward, 0, None)[:, None]
    C.set_co(obj, new)
    # UVs: strands run up the meridians from the hairline toward the crown/bun (swept-up look)
    rel = new - np.array([cx, cy, cz])
    r = np.linalg.norm(rel, axis=1)
    el = np.arcsin(np.clip(rel[:, 2] / np.maximum(r, 1e-6), -1, 1))
    uvv = np.stack([ph * 0.09 / 0.06, el * 0.09 / 0.06], axis=1)
    me = obj.data
    lv = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", lv)
    luv = uvv[lv]
    for poly in me.polygons:   # unwrap the seam at the back (phi wraps at +-pi)
        ls = list(range(poly.loop_start, poly.loop_start + poly.loop_total))
        u = luv[ls, 0]
        if u.max() - u.min() > 3.0:
            luv[ls, 0] = np.where(u < 0, u + 2 * math.pi * 0.09 / 0.06, u)
    me.uv_layers[0].data.foreach_set("uv", luv.astype(np.float32).ravel())
    col = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    c = np.ones((len(new), 4), dtype=np.float32)
    c[:, 3] = np.clip((p[:, 2] - hl + 0.004) / 0.028, 0, 1) * 0.95 + 0.05
    c[:, :3] = (0.75 + 0.25 * above)[:, None]
    col.data.foreach_set("color", c.ravel())
    parts = [obj]
    # bun
    if style in ("bun_low", "bun_high", "gibson"):
        if style == "bun_low":
            bc = np.array([cx, cy + 0.085, eye_z - 0.03])
            rad = np.array([0.048, 0.03, 0.038])
        else:
            bc = np.array([cx, cy + 0.035, top - 0.005])
            rad = np.array([0.04, 0.035, 0.03])
        bm_ = bmesh.new()
        bmesh.ops.create_uvsphere(bm_, u_segments=16, v_segments=10, radius=1.0)
        bmesh.ops.scale(bm_, vec=Vector(rad.tolist()), verts=bm_.verts)
        bmesh.ops.translate(bm_, vec=Vector(bc.tolist()), verts=bm_.verts)
        bme = bpy.data.meshes.new(g["id"] + "_bun")
        bm_.to_mesh(bme)
        bm_.free()
        bun = bpy.data.objects.new(g["id"] + "_bun", bme)
        bpy.context.collection.objects.link(bun)
        bco = C.get_co(bun)
        # twist: strands wrap around the bun
        rel = bco - bc
        lon = np.arctan2(rel[:, 1], rel[:, 0])
        lat = np.arcsin(np.clip(rel[:, 2] / np.maximum(np.linalg.norm(rel / rad, axis=1) * rad.mean(), 1e-6), -1, 1))
        lv = np.empty(len(bme.loops), dtype=np.int32)
        bme.loops.foreach_get("vertex_index", lv)
        buv = np.stack([lat * 0.6, lon * 0.6 + lat * 0.4], axis=1)[lv]
        bme.uv_layers.new(name="UVMap")
        bme.uv_layers[0].data.foreach_set("uv", buv.astype(np.float32).ravel())
        bcol = bme.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        bc_ = np.ones((len(bco), 4), dtype=np.float32)
        bcol.data.foreach_set("color", bc_.ravel())
        for poly in bme.polygons:
            poly.use_smooth = True
        vg = bun.vertex_groups.new(name="head")
        vg.add(list(range(len(bco))), 1.0, "REPLACE")
        parts.append(bun)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if len(parts) > 1:
        bpy.ops.object.join()
    me = obj.data
    if "src_index" in me.attributes:
        me.attributes.remove(me.attributes["src_index"])
    me.uv_layers[0].name = "UVMap"
    me.color_attributes.active_color = me.color_attributes["Col"]
    mat = C.make_material("hair_updo", albedo=hair_texture(), alpha=True, size=512)
    C.assign_single_material(obj, mat)
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        m = obj.modifiers.new("Armature", "ARMATURE")
        m.object = builder.rig
    obj.parent = builder.rig
    return obj


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
    if t == "updo":
        return updo(builder, info, g)
    raise ValueError("unknown garment type " + t)
