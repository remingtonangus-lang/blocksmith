"""Frontier firearm generator — Blender (bpy) headless, deterministic.

Builds the ten period firearms of src/combat/weapons.gd as detailed meshes with animated parts and markers,
bakes per-weapon PBR textures (procedural materials + curvature wear + AO), makes a merged LOD1, and exports one
.glb per weapon (+ <id>_nickel.glb finish variants for revolvers).

Usage (from the repo root or anywhere):
  python3 frontier/tools/weapons/gun_gen.py [--only lockhart_sa,merriman_lever] [--out frontier/assets/weapons_out]
      [--tex 1024] [--preview DIR] [--views q34,side,detail] [--no-bake] [--no-export] [--finish standard]
      [--variants]  (also export finish variants)
Needs: pip install bpy==5.0.1 numpy scipy pillow (Python 3.11).
"""
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import gun_lib as L  # noqa: E402
import gun_tex as T  # noqa: E402
from gun_rig import FINISHES, Gun  # noqa: E402
import models_revolvers as MR  # noqa: E402

BUILDERS = {
    "lockhart_sa": MR.build_lockhart,
}
for _mod in ("models_levers", "models_rifles", "models_shotguns"):
    try:
        _m = __import__(_mod)
        BUILDERS.update(getattr(_m, "BUILDERS", {}))
    except ImportError as _e:  # pragma: no cover - partial checkouts
        print("note: %s not available (%s)" % (_mod, _e))

ORDER = ["lockhart_sa", "sheridan_dao", "talbot_pocket", "merriman_lever", "harlan_carbine", "bowden_bolt",
         "pellman_varmint", "vance_rolling", "calder_double", "brennan_pump"]
LONG = {"merriman_lever", "harlan_carbine", "bowden_bolt", "pellman_varmint", "vance_rolling", "calder_double",
        "brennan_pump"}

PREVIEW_COL = {
    "blued": ((0.04, 0.045, 0.055), 1.0, 0.3), "case": ((0.35, 0.3, 0.32), 1.0, 0.25), "nickel": ((0.7, 0.68, 0.64), 1.0, 0.15),
    "brass": ((0.8, 0.6, 0.32), 1.0, 0.25), "cart": ((0.8, 0.6, 0.32), 1.0, 0.3), "steel": ((0.6, 0.6, 0.62), 1.0, 0.25),
    "walnut": ((0.2, 0.1, 0.05), 0.0, 0.45), "walnut_grip": ((0.2, 0.1, 0.05), 0.0, 0.45), "walnut_fore": ((0.2, 0.1, 0.05), 0.0, 0.45),
    "oak": ((0.4, 0.27, 0.14), 0.0, 0.5), "rubber": ((0.03, 0.03, 0.03), 0.0, 0.45), "lead": ((0.4, 0.4, 0.42), 0.6, 0.55),
    "iron": ((0.05, 0.05, 0.05), 1.0, 0.4),
}


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = {}
    i = 0
    while i < len(a):
        if a[i].startswith("--"):
            key = a[i][2:]
            if i + 1 < len(a) and not a[i + 1].startswith("--"):
                out[key] = a[i + 1]
                i += 2
                continue
            out[key] = True
        i += 1
    return out


def preview_materials():
    for m in bpy.data.materials:
        kind = m.get("kind")
        if not kind:
            continue
        c, met, r = PREVIEW_COL.get(kind, ((0.5, 0.5, 0.5), 0.0, 0.5))
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*c, 1)
        b.inputs["Metallic"].default_value = met
        b.inputs["Roughness"].default_value = r


def build(gid, finish="standard"):
    L.reset_scene()
    g = Gun(gid, finish)
    BUILDERS[gid](g)
    T.unwrap_pieces(g.pieces())
    g.finalize()
    return g


def bake_textures(g, out_dir, res, tag=""):
    meshes = g.meshes
    T.pack(meshes)
    t0 = time.time()
    maps = T.bake(meshes, res)
    t1 = time.time()
    A, ORM, NRM = T.synth(maps, g.spec, seed=sum(ord(c) for c in g.id))
    t2 = time.time()
    base = os.path.join(out_dir, "tex", g.id + tag)
    os.makedirs(os.path.dirname(base), exist_ok=True)
    paths = {"albedo": base + "_albedo.png", "orm": base + "_orm.png", "normal": base + "_normal.png"}
    T.save_png(paths["albedo"], A, srgb=True)
    T.save_png(paths["orm"], ORM)
    T.save_png(paths["normal"], NRM)
    print("  bake %.1fs synth %.1fs" % (t1 - t0, t2 - t1))
    return paths


def apply_material(meshes, mat):
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.material_index = 0


def make_lod1(g, paths, out_dir, tag=""):
    dups = []
    sc = bpy.context.scene
    for o in g.meshes:
        d = o.copy()
        d.data = o.data.copy()
        sc.collection.objects.link(d)
        d.parent = None
        d.matrix_world = o.matrix_world.copy()
        dups.append(d)
    j = L.join(dups, g.id + "_lod1")
    j.data.transform(j.matrix_world)
    j.matrix_world.identity()
    m = j.modifiers.new("dec", "DECIMATE")
    m.ratio = 0.22
    m.use_collapse_triangulate = True
    L.apply_modifiers(j)
    lp = {}
    for k, p in paths.items():
        lp[k] = p.replace(".png", "_512.png")
        T.downscale(p, lp[k], 512)
    mat = T.export_material(g.id + tag + "_lod1", lp["albedo"], lp["orm"], lp["normal"])
    apply_material([j], mat)
    # LOD1 sits at the root origin (same grip-origin space as LOD0)
    for p in j.data.polygons:
        p.use_smooth = True
    return j


def export_glb(g, lod1, path):
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    objs = [g.root] + list(g.root.children_recursive) + ([lod1] if lod1 else [])
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_extras=True,
                              export_yup=True, export_apply=False, export_tangents=True, export_image_format="AUTO",
                              export_animations=False, export_cameras=False, export_lights=False)


# --------------------------------------------------------------------------------------------- preview renders
def setup_studio():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("GUN_SAMPLES", "40"))
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    w = sc.world
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    sky = w.node_tree.nodes.new("ShaderNodeTexGradient")
    mp = w.node_tree.nodes.new("ShaderNodeMapping")
    tc = w.node_tree.nodes.new("ShaderNodeTexCoord")
    rp = w.node_tree.nodes.new("ShaderNodeValToRGB")
    mp.inputs["Rotation"].default_value = (0, -math.pi / 2, 0)
    w.node_tree.links.new(tc.outputs["Generated"], mp.inputs[0])
    w.node_tree.links.new(mp.outputs[0], sky.inputs[0])
    w.node_tree.links.new(sky.outputs[0], rp.inputs[0])
    rp.color_ramp.elements[0].color = (0.05, 0.05, 0.055, 1)
    rp.color_ramp.elements[1].color = (0.6, 0.6, 0.62, 1)
    w.node_tree.links.new(rp.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 0.35
    # backdrop
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.35))
    pl = bpy.context.active_object
    pl.name = "PREVIEW_floor"
    pm = bpy.data.materials.new("floor")
    pm.use_nodes = True
    pm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.10, 0.097, 0.094, 1)
    pm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    pl.data.materials.append(pm)
    pl.hide_render = False
    for name, loc, energy, size, col in (("key", (1.2, -0.9, 1.4), 80, 1.2, (1, 0.95, 0.88)),
                                         ("fill", (-1.3, -0.6, 0.6), 22, 1.6, (0.85, 0.9, 1.0)),
                                         ("rim", (-0.4, 1.6, 1.0), 70, 0.8, (1, 1, 1))):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        ld.color = col
        lo = bpy.data.objects.new("PREVIEW_" + name, ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        d = Vector((0, 0, 0)) - Vector(loc)
        lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("cam")
    co = bpy.data.objects.new("PREVIEW_cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


def bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx


def render_views(g, out_dir, views, res=(960, 540), tag=""):
    co = setup_studio()
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    meshes = [o for o in g.root.children_recursive if o.type == "MESH"]
    mn, mx = bounds(meshes)
    floor = bpy.data.objects["PREVIEW_floor"]
    floor.location.z = mn.z - 0.02
    c = (mn + mx) * 0.5
    size = (mx - mn).length
    os.makedirs(out_dir, exist_ok=True)
    for v in views:
        cam = co.data
        cam.lens = 85
        target = c.copy()
        if v == "q34":
            d = Vector((0.85, -0.42, 0.32))
            dist = size * 2.6
        elif v == "side":
            d = Vector((1.0, 0.0, 0.05))
            dist = size * 2.45
        elif v == "left":
            d = Vector((-1.0, 0.0, 0.05))
            dist = size * 2.45
        elif v == "front":
            d = Vector((0.18, 1.0, 0.1))
            dist = size * 1.2
            target = Vector(g.markers["muzzle"][0]) - g.shift
        elif v == "detail":
            d = Vector((0.75, -0.55, 0.4))
            dist = 0.30 if g.id in LONG else 0.22
            target = Vector(g.detail_target) - g.shift if hasattr(g, "detail_target") else Vector((0, 0, 0.03))
        else:
            continue
        co.location = target + d.normalized() * dist
        co.rotation_euler = (target - co.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out_dir, "%s%s_%s.png" % (g.id, tag, v))
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        print("  preview %s %.1fs" % (sc.render.filepath, time.time() - t0))


def pose(g, opened):
    """Pose animated parts at their open extreme (for detail previews)."""
    for o in g.root.children:
        a = o.get("anim")
        if not a:
            continue
        a = a.to_dict() if hasattr(a, "to_dict") else dict(a)
        ax = Vector((a["axis"][0], -a["axis"][2], a["axis"][1]))  # Godot -> Blender
        amt = float(a["open"]) * (opened.get(o.name, 0.0))
        if a["type"] == "rot":
            o.rotation_mode = "AXIS_ANGLE"
            o.rotation_axis_angle = (math.radians(amt), ax.x, ax.y, ax.z)
        else:
            o.location = o.location + ax * amt


def main():
    a = args()
    ids = a.get("only", ",".join(i for i in ORDER if i in BUILDERS)).split(",")
    out = a.get("out", os.path.join(HERE, "..", "..", "assets", "weapons_out"))
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    finishes = ["standard"]
    if a.get("finish"):
        finishes = [a["finish"]]
    if a.get("variants"):
        finishes = ["standard"] + [f for f in ("nickel",) if True]
    manifest = {}
    for gid in ids:
        if gid not in BUILDERS:
            print("skip %s (no builder yet)" % gid)
            continue
        for fin in finishes:
            if fin != "standard" and fin not in FINISHES.get(gid, {}):
                continue
            tag = "" if fin == "standard" else "_" + fin
            t0 = time.time()
            g = build(gid, fin)
            nv = sum(len(o.data.vertices) for o in g.meshes)
            nt = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in g.meshes)
            print("%s%s: %d parts, %d verts, %d tris, build %.1fs" % (gid, tag, len(g.meshes), nv, nt, time.time() - t0))
            lod1 = None
            if not a.get("no-bake"):
                res = int(a.get("tex", 2048 if gid in LONG else 1024))
                paths = bake_textures(g, out, res, tag)
                mat = T.export_material(gid + tag, paths["albedo"], paths["orm"], paths["normal"])
                apply_material(g.meshes, mat)
            else:
                preview_materials()
            g.shift_to_grip()
            if not a.get("no-bake"):
                lod1 = make_lod1(g, paths, out, tag)
            if a.get("preview"):
                views = a.get("views", "q34,side,detail").split(",")
                if lod1:
                    lod1.hide_render = True
                if "open" in a:
                    pose(g, {n: 1.0 for n in a["open"].split(",")} if isinstance(a["open"], str) else {})
                pres = tuple(int(v) for v in a.get("pres", "960x540").split("x"))
                render_views(g, a["preview"], views, res=pres, tag=tag)
            if not a.get("no-export") and not a.get("no-bake"):
                path = os.path.join(out, gid + tag + ".glb")
                export_glb(g, lod1, path)
                print("  exported %s (%.1f MB) in %.1fs" % (path, os.path.getsize(path) / 1e6, time.time() - t0))
                manifest[gid + tag] = {"file": os.path.basename(path), "verts": nv, "tris": nt,
                                       "lod1_tris": sum(len(p.vertices) - 2 for p in lod1.data.polygons) if lod1 else 0}
    if manifest:
        mp = os.path.join(out, "manifest.json")
        old = {}
        if os.path.exists(mp):
            with open(mp) as f:
                old = json.load(f)
        old.update(manifest)
        with open(mp, "w") as f:
            json.dump(old, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
