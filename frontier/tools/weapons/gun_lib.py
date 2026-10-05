"""Geometry helpers for the Frontier firearm generator (Blender bpy, headless).

Conventions (Blender space; glTF/Godot conversion happens at export):
  +Y = toward the muzzle, +Z = up, +X = the gun's right side. Units are metres.
  Godot sees -Z forward, +Y up, +X right (the glTF exporter maps Blender (x, y, z) -> (x, z, -y)).
Every builder returns a bpy object with modifiers already applied, a material slot per material *kind*
(see gun_tex.KINDS), smooth shading and sharp edges split by angle.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

TAU = math.tau
DEFAULT_SHARP = math.radians(38.0)


# --------------------------------------------------------------------------------------------- scene / objects
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def link(obj, parent=None):
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def material(kind):
    """One bpy material per material kind; the texture baker recognises them by name."""
    name = "K_" + kind
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m["kind"] = kind
    return m


def set_kind(obj, kind):
    obj.data.materials.clear()
    obj.data.materials.append(material(kind))
    for p in obj.data.polygons:
        p.material_index = 0
    return obj


def obj_from_bm(name, bm, kind, parent=None):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    link(obj, parent)
    set_kind(obj, kind)
    return obj


def apply_modifiers(obj):
    if not obj.modifiers:
        return obj
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def bevel(obj, width=0.0005, segments=2, angle=30.0, apply=True):
    if width <= 0:
        return obj
    m = obj.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = True
    m.miter_outer = "MITER_ARC"
    m.profile = 0.5
    if apply:
        apply_modifiers(obj)
    return obj


def boolean(obj, cutters, op="DIFFERENCE", keep=False):
    """Boolean with one or more cutter objects (joined first). Manifold solver, exact as fallback."""
    if not isinstance(cutters, (list, tuple)):
        cutters = [cutters]
    cutters = [c for c in cutters if c is not None]
    if not cutters:
        return obj
    cut = join(cutters, "cutter") if len(cutters) > 1 else cutters[0]
    for solver in ("MANIFOLD", "EXACT"):
        m = obj.modifiers.new("bool", "BOOLEAN")
        m.operation = op
        m.solver = solver
        m.object = cut
        nverts = len(obj.data.vertices)
        try:
            apply_modifiers(obj)
        except Exception:
            obj.modifiers.clear()
            continue
        if len(obj.data.vertices) > 0 or nverts == 0:
            break
    if not keep:
        bpy.data.objects.remove(cut, do_unlink=True)
    return obj


def join(objs, name=None):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        if name:
            objs[0].name = name
        return objs[0]
    target = objs[0]
    # bake parenting transforms into data so joining keeps world placement
    ctx = bpy.context.copy()
    for o in objs:
        o.select_set(False)
    with bpy.context.temp_override(active_object=target, selected_editable_objects=objs, object=target,
                                   selected_objects=objs):
        bpy.ops.object.join()
    if name:
        target.name = name
        target.data.name = name
    return target


def finish(obj, sharp=DEFAULT_SHARP):
    """Smooth shading with sharp edges by angle."""
    me = obj.data
    me.shade_smooth()
    me.set_sharp_from_angle(angle=sharp)
    return obj


def transform(obj, mat):
    obj.data.transform(mat)
    obj.data.update()
    return obj


def move(obj, v):
    return transform(obj, Matrix.Translation(Vector(v)))


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def empty(name, loc=(0, 0, 0), parent=None, rot=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.01
    e.location = loc
    if rot is not None:
        e.rotation_mode = "QUATERNION"
        e.rotation_quaternion = rot
    return link(e, parent)


def set_origin(obj, pivot):
    """Move the object's origin to `pivot` (world space) without moving the geometry."""
    pv = Vector(pivot)
    obj.data.transform(Matrix.Translation(-pv))
    obj.location = obj.location + pv
    return obj


def deform(obj, fn):
    """fn(co: np.ndarray (N,3)) -> new coords."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = fn(co.reshape(-1, 3))
    me.vertices.foreach_set("co", co.reshape(-1).astype(np.float32))
    me.update()
    return obj


# --------------------------------------------------------------------------------------------- 2D profiles
def fillet(pts, r_default=0.0, segs=None):
    """Closed polygon of (y, z) or (y, z, r); corners with r > 0 become circular arcs."""
    n = len(pts)
    out = []
    for i in range(n):
        p = pts[i]
        r = p[2] if len(p) > 2 else r_default
        b = Vector((p[0], p[1]))
        if r <= 0:
            out.append((b.x, b.y))
            continue
        a = Vector(pts[i - 1][:2])
        c = Vector(pts[(i + 1) % n][:2])
        d1 = a - b
        d2 = c - b
        if d1.length < 1e-9 or d2.length < 1e-9:
            out.append((b.x, b.y))
            continue
        d1.normalize()
        d2.normalize()
        cosang = max(-1.0, min(1.0, d1.dot(d2)))
        ang = math.acos(cosang)
        if ang < 1e-3 or ang > math.pi - 1e-3:
            out.append((b.x, b.y))
            continue
        t = r / math.tan(ang / 2)
        t = min(t, (Vector(pts[i - 1][:2]) - b).length * 0.5, (Vector(pts[(i + 1) % n][:2]) - b).length * 0.5)
        reff = t * math.tan(ang / 2)
        p1 = b + d1 * t
        p2 = b + d2 * t
        bis = (d1 + d2).normalized()
        cen = b + bis * (reff / math.sin(ang / 2))
        a1 = math.atan2(p1.y - cen.y, p1.x - cen.x)
        a2 = math.atan2(p2.y - cen.y, p2.x - cen.x)
        da = a2 - a1
        while da > math.pi:
            da -= TAU
        while da < -math.pi:
            da += TAU
        k = segs or max(2, int(abs(da) / math.radians(12)) + 1)
        for j in range(k + 1):
            aa = a1 + da * j / k
            out.append((cen.x + reff * math.cos(aa), cen.y + reff * math.sin(aa)))
    return dedupe(out)


def dedupe(pts, eps=1e-6):
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps:
            out.append(p)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    return out


def arc(cy, cz, r, a0, a1, n=8):
    """Points on an arc (degrees), inclusive."""
    return [(cy + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def catmull(pts, n=6, closed=False):
    """Centripetal-ish Catmull-Rom through points (open or closed); returns dense polyline."""
    P = [Vector(p[:2]) for p in pts]
    if closed:
        P = [P[-1]] + P + [P[0], P[1]]
    else:
        P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            v = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((v.x, v.y))
    if not closed:
        out.append((P[-2].x, P[-2].y))
    return out


def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        y0, z0 = pts[i - 1]
        y1, z1 = pts[i]
        a += y0 * z1 - y1 * z0
    return a * 0.5


# --------------------------------------------------------------------------------------------- solids
def extrude(name, pts, x0, x1, kind, bev=0.0005, bseg=2, parent=None, r_default=0.0, bangle=30.0):
    """Side profile (y, z[, r]) extruded along X from x0 to x1."""
    P = fillet(pts, r_default) if any(len(p) > 2 for p in pts) or r_default > 0 else dedupe([tuple(p[:2]) for p in pts])
    if poly_area(P) < 0:
        P = P[::-1]
    bm = bmesh.new()
    vs = [bm.verts.new((x0, y, z)) for (y, z) in P]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(x1 - x0, 0, 0), verts=nv)
    o = obj_from_bm(name, bm, kind, parent)
    bevel(o, bev, bseg, bangle)
    return finish(o)


def extrude_xz(name, pts, y0, y1, kind, bev=0.0005, bseg=2, r_default=0.0):
    """Cross-section (x, z[, r]) extruded along Y from y0 to y1."""
    P = fillet(pts, r_default) if any(len(p) > 2 for p in pts) or r_default > 0 else dedupe([tuple(p[:2]) for p in pts])
    if poly_area(P) < 0:
        P = P[::-1]
    bm = bmesh.new()
    vs = [bm.verts.new((x, y0, z)) for (x, z) in P]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=nv)
    o = obj_from_bm(name, bm, kind)
    bevel(o, bev, bseg)
    return finish(o)


def extrude_xy(name, pts, z0, z1, kind, bev=0.0005, bseg=2, r_default=0.0):
    """Plan-view outline (x, y[, r]) extruded along Z from z0 to z1."""
    P = fillet(pts, r_default) if any(len(p) > 2 for p in pts) or r_default > 0 else dedupe([tuple(p[:2]) for p in pts])
    if poly_area(P) < 0:
        P = P[::-1]
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z0)) for (x, y) in P]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, z1 - z0), verts=nv)
    o = obj_from_bm(name, bm, kind)
    bevel(o, bev, bseg)
    return finish(o)


def box(name, x0, x1, y0, y1, z0, z1, kind, bev=0.0005, bseg=2):
    return extrude(name, [(y0, z0), (y1, z0), (y1, z1), (y0, z1)], x0, x1, kind, bev, bseg)


def _ring(shape, r, n, phase=0.0):
    """Ring of n (x, z) points; shape 'c' circle, 'o' octagon (r = across-flats/2), 'h' hexagon."""
    out = []
    for i in range(n):
        a = TAU * i / n + phase
        if shape == "c":
            rr = r
        else:
            k = 8 if shape == "o" else 6
            seg = TAU / k
            # flats centred on top (a = pi/2): measure angle from nearest flat centre
            rel = (a - math.pi / 2) % seg - seg / 2
            rr = r / math.cos(rel)
        out.append((rr * math.cos(a), rr * math.sin(a)))
    return out


def loft(name, stations, kind, n=32, x0=0.0, z0=0.0, cap0=True, cap1=True, parent=None, phase=None, sharp=DEFAULT_SHARP,
         scale_x=1.0):
    """Surface of revolution-ish along +Y. stations: [(y, r) or (y, r, shape)] traversed in order (y may go
    back, e.g. into a bore). Consecutive rings are joined with quads; first/last rings are capped with fans."""
    bm = bmesh.new()
    rings = []
    for st in stations:
        y, r = st[0], st[1]
        shape = st[2] if len(st) > 2 else "c"
        ph = phase if phase is not None else (math.pi / n if shape == "c" else 0.0)
        pts = _ring(shape, max(r, 1e-5), n, ph)
        rings.append([bm.verts.new((x0 + px * scale_x, y, z0 + pz)) for (px, pz) in pts])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    for ring, use in ((rings[0], cap0), (rings[-1], cap1)):
        if use:
            c = Vector((0, 0, 0))
            for v in ring:
                c += v.co
            cv = bm.verts.new(c / len(ring))
            for i in range(n):
                bm.faces.new((ring[i], ring[(i + 1) % n], cv))
    o = obj_from_bm(name, bm, kind, parent)
    return finish(o, sharp)


def cyl(name, r, y0, y1, kind, n=24, x0=0.0, z0=0.0, chamfer=0.0003, axis="Y", center=(0, 0, 0)):
    """Cylinder along an axis with small chamfers. For axis X/Z the cylinder is built along Y around the origin,
    rotated, then moved to `center` (y0/y1 are then offsets along the axis)."""
    c = min(chamfer, r * 0.3, abs(y1 - y0) * 0.3)
    st = [(y0, r - c), (y0 + c, r), (y1 - c, r), (y1, r - c)] if c > 0 else [(y0, r), (y1, r)]
    if axis == "Y":
        return loft(name, st, kind, n, x0, z0)
    o = loft(name, st, kind, n)
    if axis == "X":
        transform(o, rot_z(-90))
    elif axis == "Z":
        transform(o, rot_x(90))
    return move(o, center)


def sphere(name, r, center, kind, n=16, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=n, v_segments=max(6, n // 2), radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)
    o = obj_from_bm(name, bm, kind)
    return finish(o, math.radians(80))


def sweep(name, path, section, kind, closed_path=False, cap=True, twist_up=(1, 0, 0), sharp=DEFAULT_SHARP):
    """Sweep a closed 2D section [(u, v)] along a 3D polyline. For planar YZ paths the section u axis is X
    (the gun's side) and v the in-plane normal. Ends are capped."""
    P = [Vector(p) for p in path]
    m = len(P)
    U = Vector(twist_up)
    rings = []
    bm = bmesh.new()
    for i in range(m):
        if closed_path:
            t = (P[(i + 1) % m] - P[i - 1]).normalized()
        else:
            t = (P[min(i + 1, m - 1)] - P[max(i - 1, 0)]).normalized()
        v = U.cross(t).normalized()
        u = t.cross(v).normalized()
        rings.append([bm.verts.new(P[i] + u * su + v * sv) for (su, sv) in section])
    n = len(section)
    pairs = list(zip(rings[:-1], rings[1:]))
    if closed_path:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    if cap and not closed_path:
        for ring in (rings[0], rings[-1]):
            try:
                bm.faces.new(ring)
            except ValueError:
                pass
    o = obj_from_bm(name, bm, kind)
    return finish(o, sharp)


def section_rect(w, h, r=0.0, n=3):
    """Rounded rectangle section centred on 0: w along u (X), h along v."""
    pts = [(-w / 2, -h / 2, r), (w / 2, -h / 2, r), (w / 2, h / 2, r), (-w / 2, h / 2, r)]
    return fillet(pts, segs=n) if r > 0 else [(p[0], p[1]) for p in pts]


def section_ellipse(w, h, n=12):
    return [(w / 2 * math.cos(TAU * i / n), h / 2 * math.sin(TAU * i / n)) for i in range(n)]


def path_yz(pts2d, x=0.0):
    return [(x, y, z) for (y, z) in pts2d]


# --------------------------------------------------------------------------------------------- pillow (organic slabs)
def _resample(poly, step):
    out = []
    n = len(poly)
    for i in range(n):
        a = np.array(poly[i])
        b = np.array(poly[(i + 1) % n])
        L = np.linalg.norm(b - a)
        k = max(1, int(math.ceil(L / step)))
        for j in range(k):
            out.append(a + (b - a) * j / k)
    return np.array(out)


def _inside(pts, poly):
    """Even-odd point-in-polygon, vectorised. pts (N,2), poly (M,2)."""
    x, y = pts[:, 0][:, None], pts[:, 1][:, None]
    x0, y0 = poly[:, 0][None, :], poly[:, 1][None, :]
    x1, y1 = np.roll(poly[:, 0], -1)[None, :], np.roll(poly[:, 1], -1)[None, :]
    cond = (y0 > y) != (y1 > y)
    with np.errstate(divide="ignore", invalid="ignore"):
        xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
    hit = cond & (x < xi)
    return (hit.sum(axis=1) % 2) == 1


def _dist_to_poly(pts, poly):
    a = poly[None, :, :]
    b = np.roll(poly, -1, axis=0)[None, :, :]
    p = pts[:, None, :]
    ab = b - a
    t = np.clip(((p - a) * ab).sum(-1) / np.maximum((ab * ab).sum(-1), 1e-12), 0, 1)
    d = np.linalg.norm(p - (a + ab * t[..., None]), axis=-1)
    return d.min(axis=1)


def pillow(name, outline, half_width, kind, round_r=None, step=0.003, x_center=0.0, rings=5, flat_bottom=None):
    """Organic slab: a closed side outline (y, z) given thickness along X by half_width(y, z) (callable or float),
    with rounded edges of radius round_r (2D inset distance at which the full width is reached; default = the
    local half width). Both faces share the outline vertices, giving a closed, smooth, wood-like solid
    (gun stocks, grips, fore-ends)."""
    from scipy.spatial import Delaunay
    P = np.array(outline, dtype=np.float64)
    if poly_area([tuple(p) for p in P]) < 0:
        P = P[::-1]
    B = _resample(P, step * 0.6)
    hw = half_width if callable(half_width) else (lambda y, z, _w=half_width: np.full_like(y, _w))
    pts = [B]
    # offset rings for a smooth rounded edge
    nb = np.zeros_like(B)
    prev = np.roll(B, 1, axis=0)
    nxt = np.roll(B, -1, axis=0)
    tang = nxt - prev
    tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-12)
    nb[:, 0], nb[:, 1] = -tang[:, 1], tang[:, 0]  # inward for CCW polygon
    rr = round_r if round_r is not None else float(np.max(hw(B[:, 0], B[:, 1])))
    for k in range(1, rings + 1):
        d = rr * (1 - math.cos(k / rings * math.pi / 2))
        R = B + nb * d
        R = _resample_open_dense(R, step * 0.6 * (1 + 0.5 * k / rings))
        keep = _inside(R, P) & (_dist_to_poly(R, P) > d * 0.8)
        pts.append(R[keep])
    gx, gy = np.meshgrid(np.arange(P[:, 0].min(), P[:, 0].max(), step), np.arange(P[:, 1].min(), P[:, 1].max(), step))
    G = np.stack([gx.ravel(), gy.ravel()], 1)
    G = G[_inside(G, P)]
    G = G[_dist_to_poly(G, P) > rr * 1.02]
    pts.append(G)
    V2 = np.concatenate(pts, 0)
    nB = len(B)
    tri = Delaunay(V2)
    T = tri.simplices
    cen = V2[T].mean(1)
    T = T[_inside(cen, P)]
    # drop sliver triangles that bridge across concave notches (all three verts on the boundary, centroid far out)
    d = _dist_to_poly(V2, P)
    d[:nB] = 0.0
    w = hw(V2[:, 0], V2[:, 1])
    rloc = np.minimum(rr, np.maximum(w, 1e-4)) if round_r is None else np.full_like(w, rr)
    s = np.clip(d / np.maximum(rloc, 1e-6), 0, 1)
    prof = np.sqrt(np.clip(1 - (1 - s) ** 2, 0, 1))
    X = w * prof
    bm = bmesh.new()
    top = [bm.verts.new((x_center + X[i], V2[i, 0], V2[i, 1])) for i in range(len(V2))]
    bot = [top[i] if i < nB else bm.verts.new((x_center - X[i], V2[i, 0], V2[i, 1])) for i in range(len(V2))]
    for a, b, c in T:
        try:
            bm.faces.new((top[a], top[b], top[c]))
        except ValueError:
            pass
        try:
            bm.faces.new((bot[a], bot[c], bot[b]))
        except ValueError:
            pass
    if flat_bottom is not None:
        pass
    o = obj_from_bm(name, bm, kind)
    return finish(o, math.radians(70))


def _resample_open_dense(R, step):
    return R


# --------------------------------------------------------------------------------------------- misc parts
def screw(name, center, normal_axis, r, kind="blued", head_h=0.0007, slot_angle=0.0, n=20):
    """Domed slotted screw head sitting on a surface; normal_axis 'x+','x-','z+','z-','y+'."""
    st = [(0.0, r * 0.98), (head_h * 0.35, r), (head_h * 0.8, r * 0.82), (head_h, r * 0.45), (head_h * 1.05, 0.0001)]
    o = loft(name, st, kind, n, cap0=True, cap1=True)
    # slot
    sl = box(name + "_slot", -r * 1.3, r * 1.3, head_h * 0.3, head_h * 2, -r * 0.13, r * 0.13, kind, bev=0)
    transform(sl, rot_y(slot_angle))
    boolean(o, sl)
    finish(o, math.radians(50))
    o["uvs"] = 0.6
    ax = {"y+": Matrix.Identity(4), "y-": rot_z(180), "x+": rot_z(-90), "x-": rot_z(90), "z+": rot_x(90), "z-": rot_x(-90)}[normal_axis]
    transform(o, ax)
    return move(o, center)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def pin(name, center, axis, r, length, kind="blued", n=16):
    return cyl(name, r, -length / 2, length / 2, kind, n=n, axis=axis, center=center, chamfer=r * 0.25)
