"""Texture pipeline for the firearm generator.

1. All parts of a weapon share one UV atlas (smart project + average scale + pack, multi-object edit).
2. A joined copy is baked with Cycles into float images: world position, smooth normal, UV tangent, material kind id,
   edge mask (Bevel-node normal vs shading normal) + pointiness (convexity), and ambient occlusion.
3. numpy turns those per-texel facts into PBR textures: procedural blued steel, case-hardening colours, nickel,
   brass, walnut grain, hard rubber, lead; curvature-driven edge wear, cavity grime, checkering/knurling/pores as a
   tangent-space normal map. Deterministic for a given seed.
Outputs albedo (sRGB), ORM (R occlusion, G roughness, B metallic) and normal (OpenGL +Y) PNGs.
"""
import math
import os

import bpy
import numpy as np

# ------------------------------------------------------------------------------------------------- material kinds
KINDS = ["blued", "case", "nickel", "brass", "steel", "walnut", "walnut_grip", "rubber", "lead", "cart", "iron",
         "walnut_fore", "oak"]
KID = {k: i + 1 for i, k in enumerate(KINDS)}


# ------------------------------------------------------------------------------------------------- noise
def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.uint64) * np.uint64(73856093)) ^ (iy.astype(np.uint64) * np.uint64(19349663)) ^ \
        (iz.astype(np.uint64) * np.uint64(83492791)) ^ np.uint64((seed * 2654435761) & 0xFFFFFFFF)
    h = (h ^ (h >> np.uint64(13))) * np.uint64(1274126177)
    h = h ^ (h >> np.uint64(16))
    return (h & np.uint64(0xFFFFFF)).astype(np.float32) / np.float32(0xFFFFFF)


def vnoise(p, seed=0):
    """Value noise in [0,1] for (N,3) float positions (already scaled)."""
    pf = np.floor(p)
    i = pf.astype(np.int64)
    f = (p - pf).astype(np.float32)
    u = f * f * (3 - 2 * f)
    ix, iy, iz = i[:, 0], i[:, 1], i[:, 2]
    res = np.zeros(len(p), np.float32)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                res += _hash(ix + dx, iy + dy, iz + dz, seed) * wx * wy * wz
    return res


def fbm(p, octaves=4, seed=0, lac=2.03, gain=0.5):
    s = np.zeros(len(p), np.float32)
    a = 1.0
    tot = 0.0
    q = p.astype(np.float64)
    for o in range(octaves):
        s += a * vnoise(q, seed + o * 31)
        tot += a
        q = q * lac + 17.3
        a *= gain
    return s / tot


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t, np.float32)
    if a.ndim == 2 and t.ndim == 1:
        t = t[:, None]
    return a + (b - a) * t


def col(c, n):
    return np.tile(np.array(c, np.float32), (n, 1))


def ramp(t, stops):
    """Colour ramp: stops [(pos, (r,g,b))], t (N,) -> (N,3)."""
    pos = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    out = np.empty((len(t), 3), np.float32)
    for c in range(3):
        out[:, c] = np.interp(t, pos, cs[:, c])
    return out


# ------------------------------------------------------------------------------------------------- UVs
def _edit(objs):
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    vl.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")


def unwrap_pieces(objs):
    """Smart-project every piece, equalise texel density, then shrink pieces flagged with uvs < 1."""
    _edit(objs)
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.0, area_weight=0.0, correct_aspect=True,
                             scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        s = float(o.get("uvs", 1.0))
        if abs(s - 1.0) > 1e-3 and o.data.uv_layers:
            uv = o.data.uv_layers.active.data
            a = np.empty(len(uv) * 2, np.float32)
            uv.foreach_get("uv", a)
            uv.foreach_set("uv", a * s)
        o.select_set(False)


def pack(objs, margin=0.0025):
    _edit(objs)
    try:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin, shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        o.select_set(False)


# ------------------------------------------------------------------------------------------------- baking
def _float_image(name, res):
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, res, res, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    img.generated_color = (0, 0, 0, 0)
    return img


def _bake_material(kind, img):
    m = bpy.data.materials.new("BAKE_" + kind)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    # sources
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.name = "matid"
    rgb.outputs[0].default_value = (KID.get(kind, 0) / 64.0, 0, 0, 1)
    tan = nt.nodes.new("ShaderNodeTangent")
    tan.direction_type = "UV_MAP"
    tan.uv_map = "UVMap"
    tan.name = "tangent"
    vm = nt.nodes.new("ShaderNodeVectorMath")
    vm.operation = "MULTIPLY_ADD"
    vm.inputs[1].default_value = (0.5, 0.5, 0.5)
    vm.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(tan.outputs[0], vm.inputs[0])
    vm.name = "tangent_enc"
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.0007
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs[0], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    comb.name = "edge"
    nt.links.new(dot.outputs["Value"], comb.inputs[0])
    nt.links.new(geo.outputs["Pointiness"], comb.inputs[1])
    return m


def _route(mats, which):
    for m in mats:
        nt = m.node_tree
        em = [n for n in nt.nodes if n.type == "EMISSION"][0]
        src = {"matid": nt.nodes["matid"].outputs[0], "tangent": nt.nodes["tangent_enc"].outputs[0],
               "edge": nt.nodes["edge"].outputs[0]}[which]
        nt.links.new(src, em.inputs["Color"])


def bake(objs, res, ao_samples=32, ao_dist=0.012, margin=8):
    """Bake geometry facts for the given (unwrapped) objects. Returns dict of (res,res,4) float arrays."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.seed = 7
    sc.render.bake.margin = margin
    sc.render.bake.margin_type = "EXTEND"
    sc.render.bake.use_clear = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    sc.world.light_settings.distance = ao_dist
    # joined copy with transforms applied
    dups = []
    for o in objs:
        d = o.copy()
        d.data = o.data.copy()
        sc.collection.objects.link(d)
        d.parent = None
        d.matrix_world = o.matrix_world.copy()
        dups.append(d)
    from gun_lib import join
    j = join(dups, "BAKE_JOINED")
    j.data.transform(j.matrix_world)
    j.matrix_world.identity()
    hidden = []
    for o in sc.objects:
        if o is not j and o.type == "MESH" and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    img = _float_image("bake_tmp", res)
    bmats = []
    for i, slot in enumerate(j.material_slots):
        kind = slot.material.get("kind", "blued") if slot.material else "blued"
        bm = _bake_material(kind, img)
        bmats.append(bm)
        j.material_slots[i].material = bm
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    j.select_set(True)
    vl.objects.active = j
    out = {}

    def grab(im):
        r = im.size[0]
        a = np.empty(r * r * 4, np.float32)
        im.pixels.foreach_get(a)
        return a.reshape(r, r, 4).copy()

    import time as _t

    def run(kind, samples, key, im=img, **kw):
        t0 = _t.time()
        sc.cycles.samples = samples
        for m in bmats:
            [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"][0].image = im
        im.generated_color = (0, 0, 0, 0)
        im.source = "GENERATED"
        bpy.ops.object.bake(type=kind, margin=margin if im is img else max(2, margin // 2), use_clear=True, **kw)
        out[key] = grab(im)
        times.append("%s %.1fs" % (key, _t.time() - t0))

    times = []
    run("POSITION", 1, "pos")
    run("NORMAL", 1, "nrm", normal_space="OBJECT")
    _route(bmats, "tangent")
    run("EMIT", 1, "tan")
    _route(bmats, "matid")
    run("EMIT", 1, "mat")
    _route(bmats, "edge")
    # edge mask and AO are smooth enough to bake at half resolution and upsample
    img2 = _float_image("bake_half", res // 2)
    run("EMIT", 6, "edge", im=img2)
    run("AO", ao_samples, "ao", im=img2)
    from scipy import ndimage
    out["edge"] = ndimage.zoom(out["edge"], (2, 2, 1), order=1)
    out["ao"] = ndimage.zoom(out["ao"], (2, 2, 1), order=1)
    print("  bake passes: " + ", ".join(times))
    bpy.data.objects.remove(j, do_unlink=True)
    for m in bmats:
        bpy.data.materials.remove(m)
    for o in hidden:
        o.hide_render = False
    bpy.data.images.remove(img)
    bpy.data.images.remove(img2)
    return out


# ------------------------------------------------------------------------------------------------- synthesis
class Ctx:
    """Per-texel inputs (only for covered texels)."""

    def __init__(self, maps, spec):
        pos = maps["pos"]
        self.res = pos.shape[0]
        self.valid = pos[..., 3] > 0.5
        idx = np.nonzero(self.valid.ravel())[0]
        self.idx = idx
        f = lambda k: maps[k].reshape(-1, 4)[idx]
        self.P = f("pos")[:, :3].astype(np.float64)
        self.N = f("nrm")[:, :3] * 2 - 1
        self.N /= np.maximum(np.linalg.norm(self.N, axis=1, keepdims=True), 1e-6)
        T = f("tan")[:, :3] * 2 - 1
        T = T - self.N * (T * self.N).sum(1, keepdims=True)
        self.T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-6)
        self.B = np.cross(self.N, self.T)
        self.kind = np.rint(f("mat")[:, 0] * 64).astype(np.int32)
        e = f("edge")
        self.edge = np.clip((1 - e[:, 0]) * 6.0, 0, 1)
        self.convex = np.clip((e[:, 1] - 0.5) * 8 + 0.5, 0, 1)
        self.ao = np.clip(f("ao")[:, 0], 0, 1)
        self.spec = spec
        self.n = len(idx)


def _wood_rings(P, axis, seed, ring_scale=110.0, center_off=(0.02, 0.0, 0.25)):
    """Annual-ring field for wood with grain along `axis` (unit vector)."""
    a = np.array(axis, np.float64)
    a /= np.linalg.norm(a)
    s = P @ a
    q = P - s[:, None] * a[None, :]
    c = np.array(center_off, np.float64)
    c = c - (c @ a) * a
    w = fbm(np.stack([P[:, 0] * 25, P[:, 1] * 25, P[:, 2] * 25], 1) + seed, 3, seed) - 0.5
    r = np.linalg.norm(q - c[None, :], axis=1) + w * 0.006 + np.sin(s * 9.0 + seed) * 0.002
    t = (r * ring_scale) % 1.0
    return s, q, t


def synth(maps, spec, seed=1):
    """Returns (albedo_lin (res,res,3), orm (res,res,3), normal (res,res,3)) float arrays in 0..1."""
    C = Ctx(maps, spec)
    n = C.n
    P = C.P
    alb = np.zeros((n, 3), np.float32)
    rough = np.full(n, 0.5, np.float32)
    metal = np.zeros(n, np.float32)
    wear_edge = smooth(0.18, 0.75, C.edge * (0.35 + 0.65 * C.convex))
    cav = smooth(0.25, 0.95, 1 - C.ao)
    grain_noise = fbm(P * 900.0, 2, seed + 5)
    wearn = fbm(P * 260.0, 3, seed + 9)
    wear = np.clip(wear_edge * (0.55 + 0.9 * wearn) - 0.18, 0, 1)
    # broad handling wear region (hand contact) from spec boxes
    for box in spec.get("handling", []):
        (y0, y1), (z0, z1), amt = box
        m = smooth(0, 0.01, P[:, 1] - y0) * smooth(0, 0.01, y1 - P[:, 1]) * smooth(0, 0.01, P[:, 2] - z0) * smooth(0, 0.01, z1 - P[:, 2])
        wear = np.clip(wear + m * amt * smooth(0.4, 0.8, fbm(P * 45.0, 3, seed + 13)) * (0.25 + 0.75 * C.convex), 0, 1)
    height_fns = []

    def sel(kind):
        return C.kind == KID[kind]

    # -------- blued steel (also iron)
    for kname in ("blued", "iron"):
        m = sel(kname)
        if m.any():
            p = P[m]
            k = m.sum()
            mott = fbm(p * 70.0, 4, seed + 11)
            base = mix(col((0.030, 0.034, 0.044), k), col((0.055, 0.045, 0.050), k), smooth(0.45, 0.8, mott))
            if kname == "iron":
                base = mix(col((0.045, 0.043, 0.042), k), col((0.07, 0.055, 0.045), k), smooth(0.4, 0.8, mott))
            base *= (0.85 + 0.3 * fbm(p * 400, 2, seed + 3))[:, None]
            bare = col((0.56, 0.56, 0.57), k) * (0.85 + 0.15 * grain_noise[m])[:, None]
            w = wear[m]
            a = mix(base, bare, w)
            r = 0.26 + 0.08 * mott + w * 0.08
            # dull brown patina where not worn and in recesses
            pat = smooth(0.55, 0.85, fbm(p * 30.0, 3, seed + 21)) * (1 - w) * 0.5
            a = mix(a, col((0.10, 0.065, 0.045), k), pat * 0.5)
            r = r + pat * 0.15
            alb[m], rough[m], metal[m] = a, r, 1.0
    # -------- case hardened
    m = sel("case")
    if m.any():
        p = P[m]
        k = m.sum()
        warp = np.stack([fbm(p * 40 + 3.1, 3, seed + 41), fbm(p * 40 + 7.7, 3, seed + 42), fbm(p * 40 + 1.3, 3, seed + 43)], 1)
        t1 = fbm(p * 45.0 + warp * 1.8, 4, seed + 44)
        t2 = fbm(p * 90.0 + warp * 2.5, 3, seed + 45)
        cc = ramp(np.clip((t1 - 0.25) * 2.0, 0, 1), [
            (0.00, (0.32, 0.33, 0.35)), (0.18, (0.22, 0.28, 0.42)), (0.30, (0.09, 0.12, 0.30)),
            (0.42, (0.24, 0.12, 0.24)), (0.55, (0.36, 0.22, 0.13)), (0.66, (0.56, 0.44, 0.24)),
            (0.78, (0.40, 0.40, 0.40)), (0.90, (0.20, 0.30, 0.46)), (1.00, (0.42, 0.42, 0.44))])
        grey = col((0.36, 0.36, 0.37), k)
        cc = mix(cc, grey, 0.25 + 0.3 * smooth(0.3, 0.8, t2))
        bare = col((0.62, 0.62, 0.62), k)
        w = wear[m]
        a = mix(cc, bare, w * 0.85)
        alb[m], rough[m], metal[m] = a, 0.2 + 0.08 * t2 + 0.08 * w, 1.0
    # -------- nickel
    m = sel("nickel")
    if m.any():
        p = P[m]
        k = m.sum()
        v = fbm(p * 120.0, 3, seed + 51)
        a = col((0.70, 0.68, 0.64), k) * (0.94 + 0.08 * v)[:, None]
        w = wear[m]
        flake = smooth(0.62, 0.7, fbm(p * 180.0, 3, seed + 52)) * smooth(0.2, 0.6, w)
        a = mix(a, col((0.46, 0.43, 0.40), k), flake)
        alb[m], rough[m], metal[m] = a, 0.13 + 0.06 * v + 0.12 * flake, 1.0
    # -------- brass / cartridge brass
    for kname in ("brass", "cart"):
        m = sel(kname)
        if m.any():
            p = P[m]
            k = m.sum()
            tar = fbm(p * 50.0, 4, seed + 61)
            bright = col((0.86, 0.66, 0.36), k)
            dull = col((0.52, 0.38, 0.19), k)
            w = wear[m]
            tt = smooth(0.35, 0.75, tar) * (1 - w) * (0.75 if kname == "brass" else 0.35)
            a = mix(bright, dull, tt)
            a = mix(a, col((0.25, 0.22, 0.12), k), cav[m] * 0.7)
            alb[m], rough[m], metal[m] = a, 0.2 + 0.25 * tt + 0.15 * cav[m] - 0.08 * w, 1.0
    # -------- bright steel
    m = sel("steel")
    if m.any():
        p = P[m]
        k = m.sum()
        lines = vnoise(np.stack([p[:, 0] * 2500, p[:, 1] * 40, p[:, 2] * 2500], 1), seed + 71)
        a = col((0.58, 0.58, 0.60), k) * (0.88 + 0.12 * lines)[:, None]
        a = mix(a, col((0.18, 0.16, 0.15), k), cav[m] * 0.6)
        alb[m], rough[m], metal[m] = a, 0.24 + 0.12 * lines, 1.0
    # -------- lead
    m = sel("lead")
    if m.any():
        p = P[m]
        k = m.sum()
        ox = fbm(p * 300.0, 3, seed + 81)
        a = mix(col((0.38, 0.38, 0.40), k), col((0.55, 0.55, 0.56), k), smooth(0.5, 0.8, ox))
        alb[m], rough[m], metal[m] = a, 0.55 + 0.2 * ox, 0.6
    # -------- hard rubber
    m = sel("rubber")
    if m.any():
        p = P[m]
        k = m.sum()
        v = fbm(p * 200.0, 3, seed + 91)
        a = col((0.034, 0.030, 0.027), k) * (0.85 + 0.3 * v)[:, None]
        a = mix(a, col((0.09, 0.075, 0.06), k), wear[m] * 0.7)
        alb[m], rough[m], metal[m] = a, 0.42 + 0.1 * v + 0.15 * wear[m], 0.0
    # -------- woods
    wood_axes = spec.get("grain", {})
    for kname in ("walnut", "walnut_grip", "walnut_fore", "oak"):
        m = sel(kname)
        if not m.any():
            continue
        p = P[m]
        k = m.sum()
        ax = wood_axes.get(kname, (0, 1, 0))
        s, q, t = _wood_rings(p, ax, seed + KID[kname] * 7, ring_scale=38.0 if kname != "oak" else 50.0,
                              center_off=spec.get("grain_center", {}).get(kname, (0.03, 0.0, 0.35)))
        late = smooth(0.55, 0.85, t) * (1 - smooth(0.9, 1.0, t))
        fig = fbm(np.stack([p[:, 0] * 60, s * 8, p[:, 2] * 60], 1) if abs(ax[1]) > 0.5 else p * 40, 4, seed + 101)
        if kname == "oak":
            light, dark = (0.42, 0.28, 0.15), (0.24, 0.14, 0.07)
        else:
            light, dark = (0.135, 0.062, 0.030), (0.042, 0.020, 0.010)
        broad = fbm(np.stack([p[:, 0] * 18, s * 3.0, p[:, 2] * 18], 1), 3, seed + 107)
        a = mix(col(light, k), col(dark, k), np.clip(late * 0.22 + smooth(0.25, 0.8, fig) * 0.45 + smooth(0.3, 0.8, broad) * 0.45, 0, 1))
        # streaky pores along the grain
        a_ = np.array(ax, np.float64) / np.linalg.norm(ax)
        qn = np.linalg.norm(q, axis=1)
        pore = vnoise(np.stack([s * 60.0, q[:, 0] * 2200.0 + q[:, 2] * 700, q[:, 2] * 2200.0 - q[:, 0] * 500], 1), seed + 111)
        pores = smooth(0.72, 0.9, pore)
        a = a * (1 - 0.35 * pores)[:, None]
        w = wear[m]
        a = mix(a, col((0.40, 0.25, 0.13) if kname != "oak" else (0.55, 0.40, 0.24), k), w * 0.6)
        a = mix(a, col((0.05, 0.035, 0.025), k), cav[m] * 0.6)
        r = 0.36 + 0.12 * fig + 0.25 * w + 0.15 * pores
        alb[m], rough[m], metal[m] = a, r, 0.0
    # -------- AO into albedo (cavities) and grime
    alb *= (0.62 + 0.38 * C.ao)[:, None]
    rough = np.clip(rough + cav * 0.18, 0.05, 1.0)

    # -------- detail height (normal map)
    def height(Pq):
        h = np.zeros(len(Pq), np.float32)
        kd = C.kind
        # wood pores
        wm = np.isin(kd, [KID["walnut"], KID["walnut_grip"], KID["walnut_fore"], KID["oak"]])
        if wm.any():
            for kname in ("walnut", "walnut_grip", "walnut_fore", "oak"):
                mm = kd == KID[kname]
                if not mm.any():
                    continue
                ax = np.array(wood_axes.get(kname, (0, 1, 0)), np.float64)
                ax /= np.linalg.norm(ax)
                pq = Pq[mm]
                s = pq @ ax
                qq = pq - s[:, None] * ax[None, :]
                pore = vnoise(np.stack([s * 60.0, qq[:, 0] * 2200.0 + qq[:, 2] * 700, qq[:, 2] * 2200.0 - qq[:, 0] * 500], 1), seed + 111)
                h[mm] -= smooth(0.72, 0.9, pore) * 0.00003
        # checkering / knurl regions
        for reg in spec.get("checker", []):
            kinds = [KID[k] for k in reg["kinds"]]
            mm = np.isin(kd, kinds)
            nd = np.array(reg.get("normal", (1, 0, 0)), np.float64)
            mm &= np.abs(C.N @ nd) > reg.get("min_dot", 0.35)
            if not mm.any():
                continue
            pq = Pq[mm]
            cy, cz = reg["center"]
            ang = math.radians(reg.get("angle", 0.0))
            ca, sa = math.cos(ang), math.sin(ang)
            dy, dz = pq[:, 1] - cy, pq[:, 2] - cz
            u = dy * ca + dz * sa
            v = -dy * sa + dz * ca
            ry, rz = reg["radii"]
            if reg.get("shape", "ellipse") == "ellipse":
                rr = np.sqrt((u / ry) ** 2 + (v / rz) ** 2)
            else:
                rr = np.maximum(np.abs(u) / ry, np.abs(v) / rz)
            inside = smooth(1.0, 0.97, rr)
            pitch = reg.get("pitch", 0.0016)
            la = math.radians(reg.get("line_angle", 32.0))
            # diamonds: two families of V grooves at +-la to the region axis
            g1 = ((u * math.cos(la) + v * math.sin(la)) / pitch) % 1.0
            g2 = ((u * math.cos(la) - v * math.sin(la)) / pitch) % 1.0
            tri1 = 1 - 2 * np.abs(g1 - 0.5)
            tri2 = 1 - 2 * np.abs(g2 - 0.5)
            depth = reg.get("depth", 0.00035)
            pat = np.minimum(tri1, tri2)
            hh = (pat - 1.0) * depth * inside
            if reg.get("border", True):
                bd = np.abs(rr - 1.03) * min(ry, rz)
                hh -= smooth(0.0007, 0.0002, bd) * depth * 0.8
            h[mm] += hh.astype(np.float32)
        for reg in spec.get("lines", []):
            # engraved seam lines: polyline (y, z) on faces whose normal matches reg normal
            kinds = [KID[k] for k in reg["kinds"]]
            mm = np.isin(kd, kinds)
            nd = np.array(reg.get("normal", (1, 0, 0)), np.float64)
            mm &= np.abs(C.N @ nd) > reg.get("min_dot", 0.6)
            if not mm.any():
                continue
            pq = Pq[mm]
            pts = np.array(reg["pts"], np.float64)
            dmin = np.full(len(pq), 1e9)
            for i in range(len(pts) - 1):
                a0, b0 = pts[i], pts[i + 1]
                ab = b0 - a0
                q2 = pq[:, 1:3] - a0
                t = np.clip((q2 @ ab) / max(ab @ ab, 1e-12), 0, 1)
                dmin = np.minimum(dmin, np.linalg.norm(q2 - t[:, None] * ab[None, :], axis=1))
            w = reg.get("width", 0.00025)
            h[mm] -= (smooth(w, 0.0, dmin) * reg.get("depth", 0.0002)).astype(np.float32)
        for reg in spec.get("grooves", []):
            # parallel grooves (pump fore-end, trigger serrations, hammer spur lines)
            kinds = [KID[k] for k in reg["kinds"]]
            mm = np.isin(kd, kinds)
            pq = Pq[mm]
            if not mm.any():
                continue
            ax = np.array(reg["axis"], np.float64)
            ax /= np.linalg.norm(ax)
            s = pq @ ax
            lo, hi = reg["range"]
            inside = smooth(lo, lo + 0.0005, s) * smooth(hi, hi - 0.0005, s)
            box = reg.get("box")
            if box is not None:
                (y0, y1), (z0, z1) = box
                inside = inside * ((pq[:, 1] > y0) & (pq[:, 1] < y1) & (pq[:, 2] > z0) & (pq[:, 2] < z1))
            g = (s / reg["pitch"]) % 1.0
            h[mm] += ((1 - 2 * np.abs(g - 0.5)) - 1.0) * reg.get("depth", 0.0003) * inside
        return h

    e = 0.00012
    h0 = height(P)
    ht = height(P + C.T * e)
    hb = height(P + C.B * e)
    k = 1.0 / e
    nx = -(ht - h0) * k
    ny = -(hb - h0) * k
    nz = np.ones(n, np.float32)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    nts = np.stack([nx / L, ny / L, nz / L], 1) * 0.5 + 0.5
    # checkering darkens cavities slightly and roughens
    groove = np.clip(-h0 / 0.00035, 0, 1)
    alb *= (1 - 0.35 * groove)[:, None]
    rough = np.clip(rough + groove * 0.15, 0, 1)

    res = C.res

    def scatter(vals, ch, fill):
        img = np.empty((res * res, ch), np.float32)
        img[:] = fill
        img[C.idx] = vals.reshape(len(C.idx), ch)
        return img.reshape(res, res, ch)

    A = scatter(alb, 3, 0.2)
    ORM = scatter(np.stack([C.ao, rough, metal], 1), 3, (1.0, 0.5, 0.0))
    NRM = scatter(nts, 3, (0.5, 0.5, 1.0))
    # dilate into the empty background (mip-friendly)
    from scipy import ndimage
    inv = ~C.valid
    if inv.any():
        _, (iy, ix) = ndimage.distance_transform_edt(inv, return_indices=True)
        A = A[iy, ix]
        ORM = ORM[iy, ix]
        NRM = NRM[iy, ix]
    return A, ORM, NRM


def lin2srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def save_png(path, arr, srgb=False):
    from PIL import Image
    a = lin2srgb(arr) if srgb else np.clip(arr, 0, 1)
    # Blender bakes are bottom-up; PNG rows are top-down
    a = (a[::-1] * 255 + 0.5).astype(np.uint8)
    Image.fromarray(a).save(path, optimize=True)


def downscale(src, dst, size):
    from PIL import Image
    im = Image.open(src)
    im.resize((size, size), Image.LANCZOS).save(dst, optimize=True)


# ------------------------------------------------------------------------------------------------- export material
def _gltf_output_group():
    g = bpy.data.node_groups.get("glTF Material Output")
    if g is None:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        g.nodes.new("NodeGroupInput")
    return g


def export_material(name, albedo, orm, normal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    ia = nt.nodes.new("ShaderNodeTexImage")
    ia.image = bpy.data.images.load(albedo)
    ia.image.colorspace_settings.name = "sRGB"
    io = nt.nodes.new("ShaderNodeTexImage")
    io.image = bpy.data.images.load(orm)
    io.image.colorspace_settings.name = "Non-Color"
    inn = nt.nodes.new("ShaderNodeTexImage")
    inn.image = bpy.data.images.load(normal)
    inn.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ia.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(io.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    nt.links.new(inn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = _gltf_output_group()
    nt.links.new(sep.outputs[0], grp.inputs[0])
    return m
