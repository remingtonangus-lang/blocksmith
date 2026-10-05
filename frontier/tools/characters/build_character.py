"""Build one Frontier character (.glb) from an appearance spec (see appearance.py). Runs inside the `bpy` module.

Output glb layout (Godot import):
  <id> (root) / Rig (Skeleton3D, Godot humanoid bone names + LeftEye/RightEye)
      Body  : skinned body + garments (one surface per material), no blend shapes
      Head  : face skin + eyes + brows + lashes + teeth + tongue, face blend shapes (FACE_SHAPES)
      Hair  : hair cards (optional)        Hat : headwear (optional, weighted to Head)
Materials are named by kind ("skin", "eyes", "brows", "lashes", "teeth", "hair", "cloth:<garment>:<fabric>"),
which character_factory.gd uses to swap in the Frontier skin / cloth / hair shaders.
"""
import os
import json
import math
import numpy as np
import bpy
import bmesh
from mathutils import Vector, Matrix

import mhenv
import mhcore as C

ASSET_TYPES = {"eyes": "Eyes", "eyebrows": "Eyebrows", "eyelashes": "Eyelashes", "teeth": "Teeth",
               "tongue": "Tongue", "hair": "Hair", "clothes": "Clothes"}


def asset_mhclo(kind, name):
    d = os.path.join(mhenv.MH_ASSETS, kind, name)
    for f in os.listdir(d):
        if f.endswith(".mhclo"):
            return os.path.join(d, f)
    raise IOError("no mhclo in " + d)


class CharacterBuilder:
    def __init__(self, spec, out_dir):
        self.spec = spec
        self.out_dir = out_dir
        self.hero = spec.get("lod", "npc") == "hero"
        self.tex = 2048 if self.hero else 1024
        self.HS = C.mhenv.svc("humanservice").HumanService
        self.TS = C.mhenv.svc("targetservice").TargetService
        self.Mhclo = C.mhenv.mpfb_module("entities.clothes.mhclo").Mhclo
        self.parts = []  # (kind, obj, mhclo, extra)
        self.report = {"id": spec["id"]}
        self.extra_body_delete = None
        self.hat_info = None
        self.beard_mask = None

    # ------------------------------------------------------------------------------------------------------------
    def build(self):
        C.reset_scene()
        sp = self.spec
        self.basemesh = bm = self.HS.create_human(mask_helpers=False, macro_detail_dict=sp["macro"])
        for name, w in sorted(sp.get("details", {}).items()):
            p = C.target_path(name)
            if p and abs(w) > 1e-4:
                self.TS.load_target(bm, p, weight=float(w))
        self.TS.bake_targets(bm)
        self.joint_centers = self._joint_centers(("joint-l-eye", "joint-r-eye", "joint-head", "joint-head-2",
                                                  "joint-neck"))
        self.HS.add_builtin_rig(bm, "game_engine")
        self.rig = bm.parent
        self._add_bodyparts()
        self._add_clothes()
        self._face_shapes()
        self._skin_masks()
        self._garments_procedural()
        self._remove_helpers_and_covered()
        self._rig_eyes()
        self._rename_bones()
        self._materials()
        self._assemble()
        return self.export()

    def _joint_centers(self, names):
        co = C.get_co(self.basemesh)
        out = {}
        for n in names:
            m = C.group_vertex_mask(self.basemesh, n)
            if m.any():
                out[n] = Vector(co[m].mean(axis=0).tolist())
        return out

    def _add_mhclo(self, kind, name, asset_type=None):
        path = asset_mhclo(kind, name)
        obj = self.HS.add_mhclo_asset(path, self.basemesh, asset_type=asset_type or ASSET_TYPES[kind],
                                      subdiv_levels=0, material_type="GAMEENGINE")
        for m in list(obj.modifiers):
            if m.type == "SUBSURF":
                obj.modifiers.remove(m)
        mh = self.Mhclo()
        mh.load(path)
        self.parts.append((kind, obj, mh, {"name": name}))
        return obj

    def _add_bodyparts(self):
        sp = self.spec
        # low-poly eyes for everyone (the high-poly set needs a separate transparent cornea); heroes get them
        # subdivided once for round silhouettes in close-ups
        eyes = self._add_mhclo("eyes", "low-poly")
        if self.hero:
            m = eyes.modifiers.new("Sub", "SUBSURF")
            m.levels = 1
            m.render_levels = 1
            C.apply_modifier(eyes, m)
        self._add_mhclo("eyebrows", sp.get("eyebrows", "eyebrow001"))
        self._add_mhclo("eyelashes", sp.get("eyelashes", "eyelashes01"))
        self._add_mhclo("teeth", "teeth_base")
        self._add_mhclo("tongue", "tongue01")
        if sp.get("hair"):
            self._add_mhclo("hair", sp["hair"])

    def _add_clothes(self):
        for g in self.spec.get("clothes", []):
            if g.get("kind") == "mh":
                obj = self._add_mhclo("clothes", g["asset"])
                self.parts[-1][3].update(g)

    # ------------------------------------------------------------------------------------------------------------
    def _face_shapes(self):
        bm = self.basemesh
        co0 = C.get_co(bm)
        n = co0.shape[0]
        self.face_delta_any = np.zeros(n, dtype=bool)
        C.ensure_basis(bm)
        heads = [(k, o, mh) for (k, o, mh, _) in self.parts if k in ("eyebrows", "eyelashes", "teeth", "tongue")]
        arrs = {}
        for k, o, mh in heads:
            arrs[o.name] = C.mhclo_arrays(mh, len(o.data.vertices))
            C.ensure_basis(o)
        for sname, parts in C.FACE_SHAPES.items():
            try:
                d = C.combined_delta(n, parts)
            except IOError as e:
                print("WARN face shape", sname, e)
                continue
            moving = np.abs(d).max(axis=1) > 1e-6
            if not moving.any():
                continue  # e.g. vis_sil: the rest pose is the basis
            self.face_delta_any |= moving
            C.add_shape(bm, sname, co0 + d)
            for k, o, mh in heads:
                vi, vw = arrs[o.name]
                C.add_shape(o, sname, C.get_co(o, o.data.shape_keys.key_blocks["Basis"]) + C.transfer_delta(vi, vw, d))
        self.report["face_shapes"] = len(C.FACE_SHAPES)

    def _garments_procedural(self):
        procs = [g for g in self.spec.get("clothes", []) if g.get("kind") == "proc"]
        if not procs:
            return
        import garments
        # order: hats first (hair squash), beards, then body layers inner -> outer
        procs.sort(key=lambda g: {"hat": 0, "beard": 1}.get(g["type"], 2))
        for g in procs:
            obj = garments.build(self, g)
            if obj is None:
                continue
            if g["type"] == "beard":
                self.parts.append(("beard", obj, None, g))
            else:
                gg = dict(g)
                if g["type"] == "hat":
                    gg["slot"] = "hat"
                self.parts.append(("garment", obj, None, gg))
        if self.hat_info is not None:
            for kind, obj, mh, extra in self.parts:
                if kind == "hair":
                    garments.squash_hair_under_hat(self, obj)

    def _remove_helpers_and_covered(self):
        bm = self.basemesh
        body = C.group_vertex_mask(bm, "body")
        dele = ~body
        for vg in bm.vertex_groups:
            if vg.name.startswith("Delete."):
                dele |= C.group_vertex_mask(bm, vg.name, 0.5)
        extra = getattr(self, "extra_body_delete", None)
        if extra is not None:
            dele |= extra
        # keep an original-index attribute for later normal fix-ups and the head split
        oi = bm.data.attributes.new("orig_index", "INT", "POINT")
        oi.data.foreach_set("value", np.arange(len(bm.data.vertices), dtype=np.int32))
        self._full_normals = self._vertex_normals(bm)
        C.delete_vertices(bm, dele)
        for vg in list(bm.vertex_groups):
            if vg.name.startswith(("joint-", "helper-", "Delete.", "HelperGeometry", "JointCubes")):
                bm.vertex_groups.remove(vg)
        for m in list(bm.modifiers):
            if m.type == "MASK":
                bm.modifiers.remove(m)

    def _vertex_normals(self, obj):
        n = len(obj.data.vertices)
        a = np.empty(n * 3, dtype=np.float32)
        obj.data.vertices.foreach_get("normal", a)
        return a.reshape(n, 3)

    # ------------------------------------------------------------------------------------------------------------
    def _rig_eyes(self):
        rig = self.rig
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = rig
        rig.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = rig.data.edit_bones
        head = eb["head"]
        for jn, bn in (("joint-l-eye", "LeftEye"), ("joint-r-eye", "RightEye")):
            c = self.joint_centers[jn]
            b = eb.new(bn)
            b.head = c
            b.tail = c + Vector((0.0, -0.025, 0.0))  # points forward (-Y), roll 0: Z up
            b.roll = 0.0
            b.parent = head
            b.use_deform = True
        bpy.ops.object.mode_set(mode="OBJECT")
        for kind, obj, mh, extra in self.parts:
            if kind != "eyes":
                continue
            for vg in list(obj.vertex_groups):
                obj.vertex_groups.remove(vg)
            co = C.get_co(obj)
            gl = obj.vertex_groups.new(name="LeftEye")
            gr = obj.vertex_groups.new(name="RightEye")
            # MakeHuman faces -Y; the character's left is +X.
            left = [int(i) for i in np.nonzero(co[:, 0] > 0)[0]]
            right = [int(i) for i in np.nonzero(co[:, 0] <= 0)[0]]
            gl.add(left, 1.0, "REPLACE")
            gr.add(right, 1.0, "REPLACE")

    def _rename_bones(self):
        rig = self.rig
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        # Upper arm "_l" is on +X (character's left) in MPFB's game_engine rig.
        assert rig.data.bones["upperarm_l"].head_local.x > 0
        for old, new in C.GODOT_BONES.items():
            b = rig.data.bones.get(old)
            if b is None:
                continue
            b.name = new
            for o in meshes:
                vg = o.vertex_groups.get(old)
                if vg is not None and o.vertex_groups.get(new) is None:
                    vg.name = new
        rig.name = "Rig"
        rig.data.name = "Rig"

    # ------------------------------------------------------------------------------------------------------------
    def _materials(self):
        sp = self.spec
        S = self.tex
        skin = C.parse_mhmat(os.path.join(mhenv.MH_ASSETS, sp["skin"]))
        self.mat_skin = C.make_material("skin", albedo=skin.get("diffuseTexture"), roughness=0.55, size=S)
        C.assign_single_material(self.basemesh, self.mat_skin)
        for kind, obj, mh, extra in self.parts:
            if kind == "eyes":
                mm = C.parse_mhmat(self._eye_mat(sp.get("eye_color", "brownlight")))
                C.assign_single_material(obj, C.make_material("eyes", albedo=mm.get("diffuseTexture"),
                                                              roughness=0.08, size=512 if not self.hero else 1024))
            elif kind in ("eyebrows", "eyelashes", "hair"):
                mm = C.parse_mhmat(mh.material) if mh.material else {}
                name = {"eyebrows": "brows", "eyelashes": "lashes", "hair": "hair"}[kind]
                C.assign_single_material(obj, C.make_material(
                    name, albedo=mm.get("diffuseTexture"), normal=mm.get("normalmapTexture") if kind == "hair" else None,
                    roughness=0.45, alpha=True, size=1024 if kind == "hair" else 512))
            elif kind in ("teeth", "tongue"):
                mm = C.parse_mhmat(mh.material) if mh.material else {}
                C.assign_single_material(obj, C.make_material("teeth" if kind == "teeth" else "tongue",
                                                              albedo=mm.get("diffuseTexture"), roughness=0.3, size=512))
            elif kind == "clothes":
                mm = C.parse_mhmat(mh.material) if mh.material else {}
                fabric = extra.get("fabric", "none")
                C.assign_single_material(obj, C.make_material(
                    "%s:%s:%s" % (extra.get("material", "cloth"), extra.get("id", extra["asset"]), fabric),
                    albedo=mm.get("diffuseTexture"),
                    normal=mm.get("normalmapTexture"), ao=mm.get("aomapTexture"), roughness=0.8, size=S))

    def _eye_mat(self, color):
        p = os.path.join(mhenv.MH_ASSETS, "eyes", "materials", color + ".mhmat")
        if not os.path.exists(p):
            p = os.path.join(mhenv.MH_ASSETS, "eyes", "materials", "brownlight.mhmat")
        return p

    # ------------------------------------------------------------------------------------------------------------
    def _prepare_attributes(self):
        """Every mesh gets UVMap + UV2 (metres) and a Col attribute (r occlusion, g wear, b beard/stubble mask)."""
        import garments
        bm = self.basemesh
        oi = np.empty(len(bm.data.vertices), dtype=np.int32)
        bm.data.attributes["orig_index"].data.foreach_get("value", oi)
        mask = np.zeros(len(oi), dtype=np.float32)
        if self.stubble_full is not None:
            mask = self.stubble_full[oi].astype(np.float32)
        objs = [bm] + [o for (k, o, mh, e) in self.parts]
        for o in objs:
            me = o.data
            if len(me.uv_layers) == 0:
                me.uv_layers.new(name="UVMap")
            me.uv_layers[0].name = "UVMap"
            if me.uv_layers.get("UV2") is None:
                lay = me.uv_layers.new(name="UV2")
                src = me.uv_layers[0].data
                a = np.empty(len(src) * 2, dtype=np.float32)
                src.foreach_get("uv", a)
                lay.data.foreach_set("uv", a * 1.6)   # MakeHuman atlases: ~1.6 m per UV unit
            if me.color_attributes.get("Col") is None:
                col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
                c = np.zeros((len(me.vertices), 4), dtype=np.float32)
                c[:, 0] = 1.0
                c[:, 3] = 1.0
                if o is bm:
                    c[:, 2] = mask
                col.data.foreach_set("color", c.ravel())
            me.color_attributes.active_color = me.color_attributes["Col"]

    def _skin_masks(self):
        """Stubble mask on the original basemesh indices (before helpers/covered vertices are deleted)."""
        self.stubble_full = None
        if self.spec.get("sex", "male") == "male":
            import garments
            if getattr(self, "_body_info", None) is None:
                self._body_info = garments.BodyInfo(self)
                self._body_info.eye_z = (self.joint_centers["joint-l-eye"].z + self.joint_centers["joint-r-eye"].z) / 2
            info = self._body_info
            m = garments.beard_region(info, "full") | garments.beard_region(info, "moustache")
            # soften the edge: 1 inside, 0.5 on the first ring outside
            soft = m.astype(np.float32)
            e = info.edges
            ring = np.zeros_like(m)
            ring[e[m[e[:, 0]], 1]] = True
            ring[e[m[e[:, 1]], 0]] = True
            soft[ring & ~m] = 0.45
            self.stubble_full = soft

    def _assemble(self):
        """Split the body into Head (blend shapes) and Body, then join parts into Body/Head/Hair/Hat objects."""
        self._prepare_attributes()
        for kind, obj, mh, extra in self.parts:
            if kind == "teeth":
                C.decimate(obj, 0.5 if self.hero else 0.22)
            elif kind == "beard" and not self.hero:
                C.decimate(obj, 0.5)
        bm = self.basemesh
        oi = np.empty(len(bm.data.vertices), dtype=np.int32)
        bm.data.attributes["orig_index"].data.foreach_get("value", oi)
        head_vert = self._head_vertex_mask(bm, oi)
        # Duplicate: head copy keeps faces touching the head set, body copy keeps the rest.
        head = bm.copy()
        head.data = bm.data.copy()
        bpy.context.collection.objects.link(head)
        self._keep_faces(head, head_vert, keep=True)
        self._keep_faces(bm, head_vert, keep=False)
        bm.shape_key_clear()
        for o in (head, bm):
            ia = np.empty(len(o.data.vertices), dtype=np.int32)
            o.data.attributes["orig_index"].data.foreach_get("value", ia)
            o.data.normals_split_custom_set_from_vertices([tuple(v) for v in self._full_normals[ia]])
            o.data.attributes.remove(o.data.attributes["orig_index"])
        head.name = "Head"
        bm.name = "Body"
        groups = {"Head": [head], "Body": [bm], "Hair": [], "Hat": []}
        for kind, obj, mh, extra in self.parts:
            if kind in C.HEAD_PARTS:
                groups["Head"].append(obj)
            elif kind == "hair":
                groups["Hair"].append(obj)
            elif extra.get("slot") == "hat":
                groups["Hat"].append(obj)
            else:
                groups["Body"].append(obj)
        self.objects = {}
        for name, objs in groups.items():
            if not objs:
                continue
            for o in objs:
                o.shape_key_clear() if (name != "Head" and o.data.shape_keys) else None
            target = objs[0]
            if len(objs) > 1:
                bpy.ops.object.select_all(action="DESELECT")
                for o in objs:
                    o.select_set(True)
                bpy.context.view_layer.objects.active = target
                bpy.ops.object.join()
            target.name = name
            target.data.name = name
            target.parent = self.rig
            target.matrix_parent_inverse = Matrix.Identity(4)
            for m in list(target.modifiers):
                if m.type != "ARMATURE":
                    target.modifiers.remove(m)
            if not any(m.type == "ARMATURE" for m in target.modifiers):
                mod = target.modifiers.new("Armature", "ARMATURE")
                mod.object = self.rig
            if not self.hero and name in ("Body", "Hat"):
                C.decimate(target, self.spec.get("body_decimate", 0.5 if name == "Body" else 0.6), keep_shapes=False)
            self._limit_weights(target)
            self.objects[name] = target

    def _head_vertex_mask(self, bm, oi):
        """Vertices that move under any face shape (dilated), plus everything weighted mostly to the head bone."""
        moving = self.face_delta_any[oi]
        hw = np.zeros(len(oi), dtype=np.float32)
        vg = bm.vertex_groups.get("Head")
        if vg is not None:
            gi = vg.index
            for v in bm.data.vertices:
                for g in v.groups:
                    if g.group == gi:
                        hw[v.index] = g.weight
        mask = moving | (hw > 0.5)
        me = bm.data
        edges = np.empty(len(me.edges) * 2, dtype=np.int32)
        me.edges.foreach_get("vertices", edges)
        edges = edges.reshape(-1, 2)
        for _ in range(2):
            grow = mask.copy()
            grow[edges[mask[edges[:, 0]], 1]] = True
            grow[edges[mask[edges[:, 1]], 0]] = True
            mask = grow
        return mask

    def _keep_faces(self, obj, vmask, keep):
        me = obj.data
        bmsh = bmesh.new()
        bmsh.from_mesh(me)
        dead = []
        for f in bmsh.faces:
            touches = any(vmask[v.index] for v in f.verts)
            if touches != keep:
                dead.append(f)
        bmesh.ops.delete(bmsh, geom=dead, context="FACES")
        loose = [v for v in bmsh.verts if not v.link_faces]
        bmesh.ops.delete(bmsh, geom=loose, context="VERTS")
        bmsh.to_mesh(me)
        bmsh.free()
        me.update()

    def _limit_weights(self, obj):
        """Godot skins use 4 influences per vertex: keep the top 4 and normalise; drop non-bone groups."""
        bones = set(b.name for b in self.rig.data.bones)
        for vg in list(obj.vertex_groups):
            if vg.name not in bones:
                obj.vertex_groups.remove(vg)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

    # ------------------------------------------------------------------------------------------------------------
    def export(self):
        os.makedirs(self.out_dir, exist_ok=True)
        path = os.path.join(self.out_dir, self.spec["id"] + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        self.rig.select_set(True)
        for o in self.objects.values():
            o.select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=True, export_apply=False,
            export_skins=True, export_morph=True, export_morph_normal=True, export_morph_tangent=False,
            export_animations=False, export_yup=True, export_texcoords=True, export_normals=True,
            export_tangents=False, export_materials="EXPORT", export_image_format="AUTO",
            export_def_bones=False, export_extras=False, export_attributes=False,
            export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True)
        tris = {}
        for name, o in self.objects.items():
            o.data.calc_loop_triangles()
            tris[name] = len(o.data.loop_triangles)
        self.report.update({"glb": os.path.basename(path), "tris": tris, "tris_total": sum(tris.values()),
                            "bytes": os.path.getsize(path),
                            "height_m": round(max(v.co.z for v in self.objects["Head"].data.vertices), 3)})
        return self.report
