"""Gun assembly: static parts joined into `body`, animated parts with pivots + animation extras, markers, finish
mapping (semantic part kinds -> material kinds), texture-region specs, and the final grip-origin shift.

Node convention in the exported glb (names exact; Godot sees -Z forward, +Y up, +X right):
  <id>            root (origin = right-hand grip point, identity orientation)
    body          all static parts (one mesh)
    hammer, hammer_l, hammer_r, trigger, trigger_2, cylinder, lever, bolt, breech, barrels, loading_gate, pump,
    ejector_rod, top_lever ... animated parts; origin = pivot. extras: anim = {type: rot|slide, axis: [x,y,z]
    (Godot local), open: degrees or metres, (optional) group}
    muzzle, grip_r, grip_l, sight_rear, sight_front, holster_attach, shell_eject   markers (empties); muzzle and
    shell_eject look along -Z (barrel direction / eject direction)
  <id>_lod1       single merged mesh, 512 textures
"""
import math

from mathutils import Matrix, Quaternion, Vector

import gun_lib as L

FINISHES = {}   # id -> {finish_name: {semantic: kind}}


def g_axis(v):
    """Blender vector -> Godot vector."""
    return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]


def look_quat(fwd, up=(0, 0, 1)):
    """Blender-space quaternion whose Godot -Z points along `fwd` (Blender) and Godot +Y along `up`.
    Godot -Z = Blender +Y, Godot +Y = Blender +Z, so the rotation maps Blender +Y -> fwd, +Z -> up."""
    f = Vector(fwd).normalized()
    u = Vector(up)
    r = f.cross(u).normalized()
    u = r.cross(f).normalized()
    m = Matrix((r, f, u)).transposed()  # columns: x->r, y->f, z->u
    return m.to_quaternion()


class Gun:
    def __init__(self, gid, finish="standard", detail=1.0):
        self.id = gid
        self.finish = finish
        fm = FINISHES.get(gid, {})
        self.fmap = dict(fm.get("standard", {}))
        self.fmap.update(fm.get(finish, {}))
        self.detail = detail
        self.root = L.empty(gid)
        self.static = []
        self.parts = {}        # name -> dict(objs, pivot, anim)
        self.markers = {}      # name -> (loc, quat)
        self.spec = {"checker": [], "grooves": [], "lines": [], "grain": {}, "grain_center": {}, "handling": []}
        self.shift = Vector((0, 0, 0))

    def k(self, semantic):
        return self.fmap.get(semantic, semantic)

    def add(self, obj, part=None, uvs=None):
        """uvs: relative texel density (hidden or tiny pieces get less of the atlas)."""
        if obj is None:
            return obj
        if uvs is not None:
            obj["uvs"] = uvs
        elif "uvs" not in obj:
            obj["uvs"] = 1.0
        if part is None:
            self.static.append(obj)
        else:
            self.parts[part]["objs"].append(obj)
        return obj

    def part(self, name, pivot, anim=None, parent=None):
        """anim in Blender terms: {'type': 'rot', 'axis': (1,0,0), 'open': deg} or {'type': 'slide',
        'axis': (0,-1,0), 'open': metres} or {'type': 'bolt', 'axis', 'open', 'rot_axis', 'rot'}. Converted to
        Godot axes on export. `parent` nests the part under another part (moves with it)."""
        self.parts[name] = {"objs": [], "pivot": Vector(pivot), "anim": anim or {}, "parent": parent}
        return name

    def marker(self, name, loc, fwd=(0, 1, 0), up=(0, 0, 1)):
        self.markers[name] = (Vector(loc), look_quat(fwd, up))

    def pieces(self):
        out = list(self.static)
        for p in self.parts.values():
            out += p["objs"]
        return out

    def finalize(self):
        """Join statics into body, join part pieces, set pivots, create markers. Returns list of mesh objects."""
        meshes = []
        if self.static:
            body = L.join(self.static, "body")
            body.parent = self.root
            meshes.append(body)
        for name, p in self.parts.items():
            if not p["objs"]:
                continue
            o = L.join(p["objs"], name)
            L.set_origin(o, p["pivot"])
            o.parent = self.root
            a = p["anim"]
            if a:
                ex = {"type": a["type"], "axis": g_axis(a["axis"]), "open": a["open"]}
                if "rot_axis" in a:
                    ex["rot_axis"] = g_axis(a["rot_axis"])
                for key in ("group", "half", "steps", "rot"):
                    if key in a:
                        ex[key] = a[key]
                o["anim"] = ex
            meshes.append(o)
        objs = {o.name: o for o in meshes}
        for name, p in self.parts.items():
            par = p.get("parent")
            if par and name in objs and par in objs:
                o = objs[name]
                o.parent = objs[par]
                o.location = p["pivot"] - self.parts[par]["pivot"]
        for name, (loc, q) in self.markers.items():
            L.empty(name, loc, self.root, q)
        for o in meshes:
            L.triangulate(o)
            o.data.name = o.name
        self.meshes = meshes
        return meshes

    def scale_all(self, s):
        """Uniformly scale everything built so far (geometry, pivots, markers, texture-region specs)."""
        M = Matrix.Scale(s, 4)
        for o in self.pieces():
            o.data.transform(M)
        for p in self.parts.values():
            p["pivot"] = p["pivot"] * s
        for n, (loc, q) in list(self.markers.items()):
            self.markers[n] = (loc * s, q)
        sc = lambda v: tuple(x * s for x in v)
        for r in self.spec["checker"]:
            r["center"], r["radii"], r["pitch"] = sc(r["center"]), sc(r["radii"]), r.get("pitch", 0.0016) * s
        for r in self.spec["grooves"]:
            r["range"], r["pitch"] = sc(r["range"]), r["pitch"] * s
            if r.get("box"):
                r["box"] = (sc(r["box"][0]), sc(r["box"][1]))
        for r in self.spec["lines"]:
            r["pts"] = [sc(p) for p in r["pts"]]
        self.spec["handling"] = [(sc(a), sc(b), amt) for (a, b, amt) in self.spec["handling"]]
        for k2, v in self.spec["grain_center"].items():
            self.spec["grain_center"][k2] = sc(v)
        if hasattr(self, "detail_target"):
            self.detail_target = sc(self.detail_target)

    def shift_to_grip(self):
        g = self.markers["grip_r"][0]
        self.shift = g.copy()
        for o in self.root.children:
            if o.type == "MESH" and o.name == "body":
                o.data.transform(Matrix.Translation(-g))
            else:
                o.location = o.location - g


# ------------------------------------------------------------------------------------------------- shared builders
def cartridge_rim(name, kind_cart, center, r_rim, depth=0.0012, primer_r=None):
    """Case head visible at the rear of a chamber: rim disc + primer, facing -Y."""
    cx, cy, cz = center
    st = [(cy - 0.0002, r_rim * 0.96), (cy, r_rim), (cy + depth, r_rim), (cy + depth, r_rim * 0.8), (cy + 0.02, r_rim * 0.8)]
    o = L.loft(name, st, kind_cart, 24, cx, cz)
    if primer_r:
        pr = L.loft(name + "_pr", [(cy - 0.00035, primer_r * 0.9), (cy - 0.0003, primer_r), (cy + 0.001, primer_r)], kind_cart, 16, cx, cz)
        o = L.join([o, pr])
    return o


def bullet_nose(name, kind, center, r, length, y_front):
    """Round-nose lead bullet whose tip is at y_front, pointing +Y."""
    cx, cz = center[0], center[2]
    st = [(y_front - length, r)]
    for i in range(1, 7):
        a = i / 6 * math.pi / 2
        st.append((y_front - length * 0.55 + length * 0.55 * math.sin(a), r * math.cos(a) * 0.98 + 0.0001))
    return L.loft(name, st, kind, 20, cx, cz, cap0=True, cap1=True)
