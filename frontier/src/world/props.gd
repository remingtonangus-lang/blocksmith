class_name TownProps
extends RefCounted
## Poly Haven CC0 props (assets/ext/props/<name>/<name>.gltf, real-world metres). Each prop is loaded once and
## reduced to a single Mesh: single-mesh props keep the imported mesh (and its generated LODs); multi-node props
## are flattened with their node transforms. Settlements place them through MultiMeshes per interior cell, so a
## room full of chairs costs one draw call per prop type.
##
## Props deliberately not used: Barrel_01 (modern hazard markings), wooden_candlestick / treasure_chest /
## spinning_wheel_01 / brass_candleholders (100k+ triangles for tiny objects).

const DIR := "res://assets/ext/props/"

# footprint (x, z) and height in metres measured from the glTF bounds, for placement and collision
const SIZE := {
	"BarberShopChair_01": Vector3(0.76, 1.49, 1.33), "CashRegister_01": Vector3(0.6, 0.62, 0.62),
	"Chandelier_02": Vector3(0.68, 0.85, 0.62), "ClassicNightstand_01": Vector3(0.57, 0.7, 0.42),
	"Lantern_01": Vector3(0.12, 0.29, 0.1), "Rockingchair_01": Vector3(0.71, 0.99, 0.83),
	"WoodenTable_01": Vector3(1.8, 0.55, 0.66), "WoodenTable_02": Vector3(0.3, 0.42, 0.3),
	"WoodenTable_03": Vector3(1.33, 0.83, 0.58), "barrel_03": Vector3(0.63, 0.93, 0.64),
	"bull_head": Vector3(0.31, 0.43, 0.28), "folding_wooden_stool": Vector3(0.53, 0.44, 0.55),
	"hanging_picture_frame_01": Vector3(0.59, 0.84, 0.02), "jug_01": Vector3(0.28, 0.21, 0.17),
	"lantern_chandelier_01": Vector3(0.58, 0.88, 0.57), "mantel_clock_01": Vector3(0.34, 0.16, 0.13),
	"old_bed_frame": Vector3(0.9, 1.2, 2.0), "painted_wooden_cabinet": Vector3(1.19, 1.18, 0.62),
	"painted_wooden_chair_01": Vector3(0.43, 0.96, 0.54), "painted_wooden_table": Vector3(2.41, 0.96, 1.14),
	"pot_enamel_01": Vector3(0.26, 0.18, 0.18), "round_wooden_table_01": Vector3(1.4, 1.01, 1.4),
	"rusted_spade_01": Vector3(0.17, 1.1, 0.05), "stone_fire_pit": Vector3(1.45, 0.39, 1.43),
	"vintage_cabinet_01": Vector3(2.02, 2.24, 0.67), "vintage_grandfather_clock_01": Vector3(0.63, 2.19, 0.43),
	"vintage_oil_lamp": Vector3(0.22, 0.8, 0.22), "vintage_suitcase": Vector3(1.61, 0.57, 0.24),
	"wicker_basket_01": Vector3(0.38, 0.12, 0.3), "wine_barrel_01": Vector3(0.74, 0.87, 0.76),
	"wooden_axe": Vector3(0.05, 0.63, 0.21), "wooden_barrels_01": Vector3(4.44, 0.96, 3.34),
	"wooden_bookshelf_worn": Vector3(1.37, 2.06, 0.58), "wooden_bowl_01": Vector3(0.31, 0.09, 0.31),
	"wooden_bucket_01": Vector3(0.37, 0.55, 0.34), "wooden_bucket_02": Vector3(0.62, 0.35, 0.62),
	"wooden_crate_01": Vector3(0.83, 0.35, 0.41), "wooden_crate_02": Vector3(0.53, 0.46, 1.17),
	"wooden_display_shelves_01": Vector3(0.37, 1.56, 1.08), "wooden_ladder": Vector3(0.96, 1.33, 0.5),
	"wooden_lantern_01": Vector3(0.22, 0.53, 0.23), "wooden_military_crate": Vector3(1.24, 0.46, 0.52),
	"wooden_picnic_table": Vector3(2.24, 0.75, 3.02), "wooden_stool_01": Vector3(0.43, 0.44, 0.44),
	"hatchet": Vector3(0.03, 0.29, 0.1), "WoodenChair_01": Vector3(0.69, 2.27, 0.66),
	"vintage_binocular": Vector3(0.19, 0.07, 0.2), "pocket_watch": Vector3(0.06, 0.08, 0.02),
	"wooden_handle_saber": Vector3(0.03, 0.94, 0.12), "wooden_stool_02": Vector3(0.27, 0.18, 0.18),
	"ladder_sectioned_01": Vector3(0.66, 2.13, 0.18), "gate_latch_01": Vector3(0.21, 0.09, 0.07),
}

static var _meshes := {}
static var load_usec := 0
static var _requested := {}

## Kick off background loading of every prop scene (call early; mesh() then picks the results up).
static func preload_all() -> void:
	for name in SIZE:
		var path: String = DIR + str(name) + "/" + str(name) + ".gltf"
		if not _meshes.has(name) and ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "", true)
			_requested[name] = path

static func has(name: String) -> bool:
	return mesh(name) != null

static func mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var path := DIR + name + "/" + name + ".gltf"
	var t0 := Time.get_ticks_usec()
	var m: Mesh = null
	if ResourceLoader.exists(path):
		var ps = ResourceLoader.load_threaded_get(path) if _requested.has(name) else load(path)
		if ps is PackedScene:
			var root: Node = ps.instantiate()
			m = _flatten(root)
			root.free()
	_meshes[name] = m
	load_usec += Time.get_ticks_usec() - t0
	return m

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, x])
	for c in n.get_children():
		_collect(c, x, out)

static func _flatten(root: Node) -> Mesh:
	var list := []
	_collect(root, Transform3D.IDENTITY, list)
	if list.is_empty():
		return null
	if list.size() == 1 and list[0][1].is_equal_approx(Transform3D.IDENTITY):
		var mi: MeshInstance3D = list[0][0]
		var src: Mesh = mi.mesh
		# bake surface override materials into a copy so MultiMesh draws them
		var has_override := false
		for s in src.get_surface_count():
			if mi.get_surface_override_material(s) != null:
				has_override = true
		if not has_override:
			return src
	var out := ArrayMesh.new()
	for e in list:
		var mi: MeshInstance3D = e[0]
		var src: Mesh = mi.mesh
		for s in src.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(src, s, e[1])
			st.commit(out)
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = src.surface_get_material(s)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
