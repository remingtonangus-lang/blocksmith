extends Node3D
## Trees, shrubs and grass for the whole map.
## Trees: deterministic scatter per 1024 m region (worker threads) from biome/moisture/slope/altitude. Every tree is
## drawn as an impostor in its region's MultiMesh (one draw per region, all species; shaders/impostor_tree.gdshader),
## baked at startup from the same meshes and materials (src/world/impostor_baker.gd, cached in user://); within
## near_end of the camera (shrub_end for shrubs; per quality preset) real meshes take over (shaders/foliage.gdshader)
## in three levels of detail from one growth pass (src/world/tree_gen.gd): LOD 0 up close, LOD 1 with half the
## leaf cards, LOD 2 with a fifth and only the trunk and boughs. Each species variant and LOD is one MultiMesh around
## the camera, re-bucketed every few metres of camera travel; every LOD -> LOD and LOD 2 -> impostor transition is a
## per-instance screen dither that is the exact complement of its neighbour's, so nothing pops.
## Grass: GPU-placed clumps in 16 m cells around the camera (shaders/grass.gdshader).

const REGION := 1024.0
const CHUNK := 256.0
const VARIANTS := 3
const GRASS_CELL := 16.0
const GRASS_LOD0 := 12.0         # cell-centre distance for the full clumps (the camera's own cells)
const GRASS_LOD1 := 28.0
const SMALL_SHRUB_FAR := 900.0
const LOD1_AT := 0.18            # LOD 1 from this fraction of near_end / shrub_end
const LOD2_AT := 0.4             # LOD 2 (no shadow casting: impostor silhouettes cast from here)
const REBUCKET := 3.0            # re-sort near trees into LODs after this much camera travel (m); every metre of
                                 # slack is a ring of trees drawn (collapsed) in two LODs

var world: WorldData
var camera: Camera3D
var tree_dist := 2500.0
var grass_dist := 80.0
var grass_density := 1.0
var species_list: Array = []
var _meshes := {}            # species -> [lod0 mesh per variant] (impostor bake, tests)
var _lod_meshes := {}        # species -> [[lod0, lod1, lod2] per variant]
var near_end := 110.0        # trees: real meshes up to here, impostors beyond (quality preset "tree_near")
var shrub_end := 60.0        # shrubs ("shrub_near")
var lod_band := 13.0         # width of every dithered cross-fade
var _lod_groups := {}        # entry index -> [MultiMeshInstance3D per LOD]
var _bucket_pos := Vector3(1e9, 0, 1e9)
var _bucket_chunks := []
var _bucket_task := -1
var _bucket_result := {}
var _entry_small := PackedInt32Array()   # entry index -> 1 for shrubs (shrub distances)
var _mats := {}              # species -> {bark, leaf}
var _bill_mat: ShaderMaterial
var _bill_mesh: ArrayMesh
var impostors: ImpostorBaker    # null when headless (bots) or the bake failed
var _leaf_tex: Texture2D
var _regions := {}           # Vector2i -> MultiMeshInstance3D (billboards)
var _region_chunks := {}     # Vector2i(chunk) -> Array of [species, variant, Transform3D]
var _near := {}              # Vector2i(chunk) -> Node3D with full-mesh MultiMeshes
var _pending := {}           # Vector2i(region) -> task id
var _results := {}           # Vector2i(region) -> Dictionary
var _mutex := Mutex.new()
var _grass_cells := {}       # Vector2i -> MultiMeshInstance3D
var _grass_mm: Array[MultiMesh] = []
var _grass_mat: ShaderMaterial
var _last_grass_center := Vector2i(999999, 999999)
var _last_missing := -1

func setup(w: WorldData, cam: Camera3D) -> void:
	world = w
	camera = cam
	tree_dist = Game.quality.tree_dist
	near_end = float(Game.quality.get("tree_near", 110.0))
	shrub_end = float(Game.quality.get("shrub_near", 60.0))
	lod_band = clampf(near_end * 0.08, 4.0, 10.0)
	grass_dist = Game.quality.grass_dist
	grass_density = Game.quality.grass_density
	_leaf_tex = TreeGen.make_leaf_atlas()
	species_list = TreeGen.SPECIES.keys()
	var gen := TreeGen.new()
	for sp in species_list:
		var vs := []
		var ls := []
		for v in VARIANTS:
			var lods: Array = gen.build_lods(sp, hash(sp) + v * 7919)
			ls.append(lods)
			vs.append(lods[0])
		_meshes[sp] = vs
		_lod_meshes[sp] = ls
		for v in VARIANTS:
			_entry_small.append(1 if TreeGen.SPECIES[sp].crown == "bush" else 0)
		_mats[sp] = _make_materials(sp)
	if not Game.headless and tree_dist > 1.0:
		var ib := ImpostorBaker.new()
		if ib.bake(self, _meshes, species_list, VARIANTS):
			impostors = ib
			ib.release_images()
	_setup_billboards()
	_setup_grass()
	world.river_at(0.0, 0.0)        # build lazy caches on the main thread before workers read them

## Build everything in range right now (screenshots, benchmarks, teleports). Blocks until done.
func settle_now() -> void:
	var cp := camera.global_position
	for k in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	var finished := _pending.keys()
	_pending.clear()
	var want := _wanted_regions(cp)
	var missing := []
	for k in want.keys():
		if not _regions.has(k) and not finished.has(k):
			missing.append(k)
	var gid := WorkerThreadPool.add_group_task(func(i: int): _generate_region(missing[i]), missing.size())
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for k in finished + missing:
		_finish_region(k, want.has(k))
	_last_missing = 0
	_update_near(cp, 1000)
	if _bucket_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bucket_task)
		_bucket_task = -1
	_rebucket(cp)
	_last_grass_center = Vector2i(999999, 999999)
	_update_grass(cp)

func is_settled() -> bool:
	return _pending.is_empty() and _last_missing == 0

func _exit_tree() -> void:
	if _bucket_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bucket_task)
	for k in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()

func _make_materials(sp: String) -> Dictionary:
	var spec: Dictionary = TreeGen.SPECIES[sp]
	var bark := ShaderMaterial.new()
	bark.shader = load("res://shaders/foliage.gdshader")
	var bark_name: String = {"pine": "bark_pine", "cottonwood": "bark_cottonwood", "aspen": "bark_cottonwood", "dead": "bark_pine"}[spec.bark]
	var ah_path := "res://assets/ext/packed/nature_%s_ah.png" % bark_name
	var nr_path := "res://assets/ext/packed/nature_%s_nr.png" % bark_name
	if ResourceLoader.exists(ah_path):
		bark.set_shader_parameter("albedo_tex", load(ah_path))
		bark.set_shader_parameter("normal_tex", load(nr_path))
	var bt := Color(1, 1, 1)
	if spec.bark == "aspen":
		bt = Color(2.2, 2.2, 2.0)
	elif spec.bark == "dead":
		bt = Color(1.3, 1.25, 1.2)
	var small: bool = spec.crown == "bush"
	bark.set_shader_parameter("tint", bt)
	bark.set_shader_parameter("tree_height", spec.height[1])
	var leaf := ShaderMaterial.new()
	leaf.shader = load("res://shaders/foliage.gdshader")
	leaf.set_shader_parameter("is_leaf", true)
	leaf.set_shader_parameter("albedo_tex", _leaf_tex)
	leaf.set_shader_parameter("tint", spec.leaf_tint)
	leaf.set_shader_parameter("tree_height", spec.height[1])
	leaf.set_shader_parameter("sway", 1.4 if small else 1.0)
	# one bark/leaf pair per LOD, differing only in the distance band they draw in
	var r := lod_ranges(small)
	var out := {"bark": [], "leaf": []}
	for l in TreeGen.LODS:
		var b: ShaderMaterial = bark if l == 0 else bark.duplicate()
		var f: ShaderMaterial = leaf if l == 0 else leaf.duplicate()
		for m in [b, f]:
			m.set_shader_parameter("lod_start", r[l].x)
			m.set_shader_parameter("lod_end", r[l].y)
			m.set_shader_parameter("lod_band", lod_band)
		out.bark.append(b)
		out.leaf.append(f)
		for v in VARIANTS:
			var mesh: ArrayMesh = _lod_meshes[sp][v][l] if _lod_meshes.has(sp) else (_meshes[sp][v] if l == 0 else null)
			if mesh == null:
				continue
			mesh.surface_set_material(0, b)
			if mesh.get_surface_count() > 1:
				mesh.surface_set_material(1, f)
	return {"bark": bark, "leaf": leaf, "lods": out}

## Distance band (start, end) of each LOD for trees or shrubs; LOD 0 has no start, LOD 2 ends at the impostor.
func lod_ranges(small: bool) -> Array:
	var e := shrub_end if small else near_end
	return [Vector2(-1.0, e * LOD1_AT), Vector2(e * LOD1_AT, e * LOD2_AT), Vector2(e * LOD2_AT, e)]

## Test helper (src/tests/veg_lineup.gd): materials for one standalone mesh.
func _make_materials_for_test(sp: String, m: ArrayMesh) -> Dictionary:
	_meshes[sp] = [m, m, m]
	var mats := _make_materials(sp)
	for k in ["bark", "leaf"]:
		mats[k].set_shader_parameter("lod_end", 1e6)     # a standalone mesh shows at any distance
	return mats

func _setup_billboards() -> void:
	_bill_mat = ShaderMaterial.new()
	_bill_mat.shader = load("res://shaders/impostor_tree.gdshader")
	var info := PackedVector4Array()
	for sp in species_list:
		var spec: Dictionary = TreeGen.SPECIES[sp]
		var end := shrub_end if spec.crown == "bush" else near_end
		# knee-high brush is under a pixel past ~900 m: stop drawing it there instead of dithering specks
		var far := minf(tree_dist, SMALL_SHRUB_FAR) if float(spec.height[1]) < 2.0 else tree_dist
		for v in VARIANTS:
			info.append(Vector4(end, float(spec.height[1]), ImpostorBaker.crown_shape(spec), far))
	_bill_mat.set_shader_parameter("entry_info", info)
	_bill_mat.set_shader_parameter("lod_band", lod_band)
	_bill_mat.set_shader_parameter("tree_shadow_begin", near_end * LOD2_AT)
	_bill_mat.set_shader_parameter("shrub_shadow_begin", shrub_end * LOD2_AT)
	_bill_mat.set_shader_parameter("far_end", tree_dist)
	_bill_mat.set_shader_parameter("shadow_end", float(Game.quality.get("shadow_distance", 300.0)) + 30.0)
	if Game.args.has("impostor_tint"):
		_bill_mat.set_shader_parameter("debug_tint", Vector3(1.0, 0.3, 0.3))
	if impostors != null:
		_bill_mat.set_shader_parameter("albedo_atlas", impostors.albedo)
		_bill_mat.set_shader_parameter("normal_atlas", impostors.normal)
		_bill_mat.set_shader_parameter("atlas_px", Vector2(impostors.atlas_size))
		_bill_mat.set_shader_parameter("entry_rect", impostors.entry_rect)
		_bill_mat.set_shader_parameter("entry_frame", impostors.entry_frame)
		_bill_mat.set_shader_parameter("entry_crown", impostors.entry_crown)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uv[k])
		st.add_vertex(quad[k])
	_bill_mesh = st.commit()
	# the shader inflates the unit quad to the tree's frame: give culling a box that holds the tallest tree
	_bill_mesh.custom_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 50, 50))

func _process(_dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_impl(_dt)
	Game.prof("vegetation.gd _process", _pt0)

func _process_impl(_dt: float) -> void:
	if world == null or camera == null:
		return
	var cp := camera.global_position
	RenderingServer.global_shader_parameter_set("player_pos", Game.player.global_position if Game.player else cp)
	if impostors != null and Game.sky != null and Game.sky.sun != null:
		var l: DirectionalLight3D = Game.sky.sun if Game.sky.sun.visible or Game.sky.moon == null else Game.sky.moon
		_bill_mat.set_shader_parameter("light_dir", l.global_basis.z)
	_update_regions(cp)
	_update_near(cp, 2)
	_update_grass(cp)

# ------------------------------------------------------------------ trees
func _wanted_regions(cp: Vector3) -> Dictionary:
	var half := world.size_m * 0.5
	var n := int(world.size_m / REGION)
	var want := {}
	for rz in n:
		for rx in n:
			var rect := Rect2(-half + rx * REGION, -half + rz * REGION, REGION, REGION)
			var q := Vector2(clampf(cp.x, rect.position.x, rect.end.x), clampf(cp.z, rect.position.y, rect.end.y))
			var d := q.distance_to(Vector2(cp.x, cp.z))
			if d < tree_dist:
				want[Vector2i(rx, rz)] = d
	return want

func _update_regions(cp: Vector3) -> void:
	if Engine.get_process_frames() % 15 != 0 and not _pending.is_empty():
		pass
	var want := _wanted_regions(cp)
	var missing := []
	for k in want.keys():
		if not _regions.has(k) and not _pending.has(k):
			missing.append(k)
	missing.sort_custom(func(a, b): return want[a] < want[b])
	_last_missing = missing.size()
	for i in mini(missing.size(), 2 - _pending.size()):
		var k: Vector2i = missing[i]
		_pending[k] = WorkerThreadPool.add_task(_generate_region.bind(k))
	for k in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[k]):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
			_finish_region(k, want.has(k))
			break
	for k in _regions.keys():
		if not want.has(k):
			_regions[k].queue_free()
			_regions.erase(k)
			var cpr := int(REGION / CHUNK)
			for dz in cpr:
				for dx in cpr:
					_region_chunks.erase(Vector2i(k.x * cpr + dx, k.y * cpr + dz))

## Worker thread: decide every tree in a region. Pure data, no scene access.
func _generate_region(k: Vector2i) -> void:
	var half := world.size_m * 0.5
	var cpr := int(REGION / CHUNK)
	var chunks := {}
	var bill := PackedFloat32Array()
	for cz in cpr:
		for cx in cpr:
			var ck := Vector2i(k.x * cpr + cx, k.y * cpr + cz)
			var x0 := -half + ck.x * CHUNK
			var z0 := -half + ck.y * CHUNK
			var r := RandomNumberGenerator.new()
			r.seed = hash(ck) ^ 0x5eed
			var list := []
			var step := 5.0
			var cells := int(CHUNK / step)
			for gz in cells:
				for gx in cells:
					var x := x0 + (gx + r.randf()) * step
					var z := z0 + (gz + r.randf()) * step
					var roll := r.randf()
					var pick := _choose_species(x, z, roll, r)
					if pick == "":
						continue
					var v := r.randi_range(0, VARIANTS - 1)
					var y := world.height(x, z) - 0.15
					var s := r.randf_range(0.8, 1.2)
					var rot := r.randf_range(0.0, TAU)
					var b := Basis(Vector3.UP, rot).rotated(Vector3.RIGHT, r.randf_range(-0.04, 0.04)).scaled(Vector3(s, s, s))
					list.append([pick, v, Transform3D(b, Vector3(x, y, z))])
					var entry := species_list.find(pick) * VARIANTS + v
					bill.append_array([1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, float(entry), s, rot, r.randf()])
			chunks[ck] = list
	_mutex.lock()
	_results[k] = {"chunks": chunks, "bill": bill}
	_mutex.unlock()

func _finish_region(k: Vector2i, keep: bool) -> void:
	_mutex.lock()
	var res: Dictionary = _results.get(k, {})
	_results.erase(k)
	_mutex.unlock()
	if not keep or res.is_empty() or _regions.has(k):
		return
	var bill: PackedFloat32Array = res.bill
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bill_mesh
	mm.instance_count = bill.size() / 16
	if mm.instance_count > 0:
		mm.buffer = bill
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _bill_mat
	# impostors cast (turned to the sun) from the LOD 2 band out to the shadow distance, so tree shadows do not
	# end at the hand-off ring
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if impostors != null else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = impostors != null
	mmi.name = "TreeBillboards_%d_%d" % [k.x, k.y]
	add_child(mmi)
	_regions[k] = mmi
	for ck in res.chunks.keys():
		_region_chunks[ck] = res.chunks[ck]

func _update_near(cp: Vector3, max_builds: int) -> void:
	var half := world.size_m * 0.5
	var reach := maxf(near_end, shrub_end) + CHUNK * 0.75
	var built := 0
	var want := {}
	var cx := floori((cp.x + half) / CHUNK)
	var cz := floori((cp.z + half) / CHUNK)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ck := Vector2i(cx + dx, cz + dz)
			var rect := Rect2(-half + ck.x * CHUNK, -half + ck.y * CHUNK, CHUNK, CHUNK)
			var q := Vector2(clampf(cp.x, rect.position.x, rect.end.x), clampf(cp.z, rect.position.y, rect.end.y))
			if q.distance_to(Vector2(cp.x, cp.z)) < reach:
				want[ck] = true
	for ck in want.keys():
		if _near.has(ck) or not _region_chunks.has(ck) or built >= max_builds:
			continue
		_near[ck] = _build_near(ck, _region_chunks[ck])
		built += 1
	for ck in _near.keys():
		if not want.has(ck):
			_near[ck].queue_free()
			_near.erase(ck)
	var chunks := _near.keys()
	_poll_buckets()
	if cp.distance_to(_bucket_pos) > REBUCKET or chunks != _bucket_chunks:
		_rebucket_async(cp)
		_bucket_chunks = chunks

## Sort the trees around the camera into per-variant, per-LOD MultiMeshes. A tree goes into every LOD whose band
## (plus the cross-fade and some slack for camera travel until the next sort) contains it; the shaders pick per pixel
## which one shows. Sorting runs on a worker (pure data); the buffers are applied on the main thread.
func _rebucket(cp: Vector3) -> void:
	_bucket_pos = cp
	var lists := []
	for ck in _near.keys():
		lists.append(_region_chunks.get(ck, []))
	_apply_buckets(_sort_buckets(cp, lists))

func _rebucket_async(cp: Vector3) -> void:
	if _bucket_task >= 0:
		if not WorkerThreadPool.is_task_completed(_bucket_task):
			return
		WorkerThreadPool.wait_for_task_completion(_bucket_task)
		_bucket_task = -1
		_apply_buckets(_bucket_result)
	_bucket_pos = cp
	var lists := []
	for ck in _near.keys():
		lists.append(_region_chunks.get(ck, []))
	_bucket_task = WorkerThreadPool.add_task(func(): _bucket_result = _sort_buckets(cp, lists))

func _poll_buckets() -> void:
	if _bucket_task >= 0 and WorkerThreadPool.is_task_completed(_bucket_task):
		WorkerThreadPool.wait_for_task_completion(_bucket_task)
		_bucket_task = -1
		_apply_buckets(_bucket_result)

func _sort_buckets(cp: Vector3, lists: Array) -> Dictionary:
	var slack := REBUCKET + 1.5
	var bufs := {}           # entry -> [PackedFloat32Array per LOD]
	var ranges := [lod_ranges(false), lod_ranges(true)]
	for list in lists:
		for e in list:
			var t: Transform3D = e[2]
			var d := t.origin.distance_to(cp)        # the shaders fade on the 3D distance too
			var key: int = species_list.find(e[0]) * VARIANTS + e[1]
			var r: Array = ranges[_entry_small[key]]
			if d > r[2].y + slack:
				continue
			if not bufs.has(key):
				bufs[key] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
			for l in TreeGen.LODS:
				if d >= r[l].x - lod_band - slack and d <= r[l].y + slack:
					var b := t.basis
					bufs[key][l].append_array([b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y,
						b.x.z, b.y.z, b.z.z, t.origin.z])
	return bufs

func _apply_buckets(bufs: Dictionary) -> void:
	for key in _lod_groups.keys():
		if not bufs.has(key):
			for mmi in _lod_groups[key]:
				mmi.multimesh.visible_instance_count = 0
	for key in bufs.keys():
		if not _lod_groups.has(key):
			_lod_groups[key] = _make_lod_group(key)
		for l in TreeGen.LODS:
			var mm: MultiMesh = _lod_groups[key][l].multimesh
			var buf: PackedFloat32Array = bufs[key][l]
			var n := buf.size() / 12
			if n > mm.instance_count:
				mm.visible_instance_count = -1
				mm.instance_count = maxi(nearest_po2(n), 16)
			if n > 0:
				buf.resize(mm.instance_count * 12)
				mm.buffer = buf
			mm.visible_instance_count = n

func _make_lod_group(key: int) -> Array:
	var sp: String = species_list[key / VARIANTS]
	var v: int = key % VARIANTS
	var out := []
	for l in TreeGen.LODS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _lod_meshes[sp][v][l]
		mm.instance_count = 16
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# LOD 2 leaves shadow casting to the impostor silhouettes (one quad per tree)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if l < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# trees are re-bucketed around the camera: one box over the whole near field keeps culling cheap and correct
		mmi.custom_aabb = AABB(Vector3(-4096, -100, -4096), Vector3(8192, 2000, 8192))
		mmi.name = "Trees_%s_%d_lod%d" % [sp, v, l]
		add_child(mmi)
		out.append(mmi)
	return out

## Trunk colliders per 256 m chunk (cover for gunfights, obstacles for riders); shrubs stay passable.
func _build_near(ck: Vector2i, list: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "TreesNear_%d_%d" % [ck.x, ck.y]
	add_child(node)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	node.add_child(sb)
	for e in list:
		var spec: Dictionary = TreeGen.SPECIES[e[0]]
		if spec.crown != "bush":
			var t: Transform3D = e[2]
			var s := t.basis.get_scale().x
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = float(spec.trunk_r) * s * 1.1
			cyl.height = 4.0
			cs.shape = cyl
			cs.position = t.origin + Vector3(0, 2.0, 0)
			sb.add_child(cs)
	return node

## Trees within radius of a point (gameplay: cover, chopping, AI avoidance).
func trees_near(p: Vector3, radius: float) -> Array:
	var out := []
	var half := world.size_m * 0.5
	var cx := floori((p.x + half) / CHUNK)
	var cz := floori((p.z + half) / CHUNK)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for e in _region_chunks.get(Vector2i(cx + dx, cz + dz), []):
				var t: Transform3D = e[2]
				if t.origin.distance_to(p) < radius:
					out.append(e)
	return out

## Species for a candidate point, or "" for none. Density varies by biome, moisture, slope, altitude.
func _choose_species(x: float, z: float, roll: float, r: RandomNumberGenerator) -> String:
	if roll > 0.24:
		return ""                                  # above every species' density: skip the expensive checks
	var c := world.ctrl(x, z)
	if c.r > 0.05:
		return ""                                  # roads and trails stay clear
	var h := world.height(x, z)
	if h < world.lake_level + 0.6:
		return ""
	var nrm := world.normal(x, z)
	var slope := 1.0 - nrm.y
	if slope > 0.45:
		return ""
	var near := world.nearest_settlement(x, z)
	if not near.is_empty() and Vector2(near.x - x, near.z - z).length() < float(near.r) + 15.0:
		return ""
	var rv := world.river_at(x, z)
	if not rv.is_empty() and rv.dist < rv.width * 0.5 + 2.0:
		return ""
	var biome := c.b
	var moist := c.g
	# clustering noise so forests have groves and clearings
	var grove := sin(x * 0.013 + sin(z * 0.009) * 2.0) * 0.5 + sin(z * 0.017 + cos(x * 0.011) * 1.7) * 0.5
	if h > 1180.0:
		return "fir" if roll < 0.02 * (1.0 - (h - 1180.0) / 300.0) else ""
	# river bottoms: cottonwood galleries
	if not rv.is_empty() and rv.dist < rv.width * 0.5 + 45.0 and moist > 0.5:
		if roll < 0.10:
			return "cottonwood"
		if roll < 0.14:
			return "rabbitbrush"
		return ""
	if biome > 0.68:
		var dens := 0.10 + 0.12 * grove
		if roll < dens:
			if h > 900.0:
				return "fir" if r.randf() < 0.6 else "ponderosa"
			if moist > 0.7 and grove > 0.4 and h > 450.0:
				return "aspen"
			return "ponderosa"
		if roll < dens + 0.008:
			return "snag"
		return ""
	if biome > 0.5:
		# foothill woodland / prairie edge
		if roll < 0.006 + 0.02 * maxf(grove, 0.0):
			return "oak" if h < 500.0 else "juniper"
		if roll < 0.035:
			return "sagebrush"
		return ""
	if biome > 0.25:
		# dry grassland
		if roll < 0.004:
			return "juniper"
		if roll < 0.05:
			return "sagebrush" if r.randf() < 0.7 else "rabbitbrush"
		return ""
	# desert
	if roll < 0.006:
		return "mesquite"
	if roll < 0.035:
		return "sagebrush"
	return ""

# ------------------------------------------------------------------ grass
func _setup_grass() -> void:
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://shaders/grass.gdshader")
	_grass_mat.set_shader_parameter("heightmap", Game.terrain.material.get_shader_parameter("heightmap"))
	_grass_mat.set_shader_parameter("controlmap", Game.terrain.material.get_shader_parameter("controlmap"))
	_grass_mat.set_shader_parameter("map_size", world.size_m)
	_grass_mat.set_shader_parameter("h_range", world.h_range)
	_grass_mat.set_shader_parameter("lake_level", world.lake_level)
	_grass_mat.set_shader_parameter("fade_dist", grass_dist)
	# three densities of the same 16 m tile; instance i is identical across them so LOD changes don't reshuffle.
	# Geometry budget (triangles per cell): LOD 0 (camera's cells, < GRASS_LOD0 m) 900 clumps x 9 blades x 3
	# segments = 49k; LOD 1 (< GRASS_LOD1 m) 400 x 7 x 2 = 11k; LOD 2 (to grass_dist) 170 x 5 x 1 = 1.7k with wider
	# blades, over a ground already tinted like the grass it carries (terrain.gdshader), so it still reads as a field.
	var counts := [int(900 * grass_density), int(400 * grass_density), int(170 * grass_density)]
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var base := PackedFloat32Array()
	for i in counts[0]:
		var x := r.randf() * GRASS_CELL
		var z := r.randf() * GRASS_CELL
		var s := r.randf_range(0.7, 1.3)
		var rot := r.randf() * TAU
		var b := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
		base.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, 0.0, b.x.z, b.y.z, b.z.z, z, r.randf(), r.randf(), 0, 0])
	var meshes := [_grass_clump(9, 3, 1.0), _grass_clump(7, 2, 1.4), _grass_clump(5, 1, 2.2)]
	for li in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[li]
		mm.instance_count = counts[li]
		var stride := 16
		var buf := base.slice(0, counts[li] * stride)
		if li > 0:
			# thinner LODs get wider clumps to keep coverage
			for i in counts[li]:
				var k := 1.0 + li * 0.45
				buf[i * stride + 0] *= k; buf[i * stride + 2] *= k
				buf[i * stride + 8] *= k; buf[i * stride + 10] *= k
		mm.buffer = buf
		_grass_mm.append(mm)

## A clump of curved, tapered blades (geometry, no alpha test: cheap on tile-based GPUs).
func _grass_clump(blades: int, segs: int, width: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = blades * 31 + segs
	for b in blades:
		var ang := r.randf() * TAU
		var off := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.0, 0.32)
		var facing := r.randf() * TAU
		var dir := Vector3(cos(facing), 0, sin(facing))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := r.randf_range(0.16, 0.48)
		var w := r.randf_range(0.014, 0.03) * width
		var lean := r.randf_range(0.1, 0.45)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in segs + 1:
			var t := float(s) / segs
			var y := t * h
			var bend := dir * lean * t * t * h
			var c := off + Vector3(0, y, 0) + bend
			var ww := w * (1.0 - t * 0.92)
			var l := c - side * ww
			var rr := c + side * ww
			if s > 0:
				var n := (dir * -0.3 + Vector3.UP).normalized()
				var col0 := Color(float(s - 1) / segs, b / float(blades), 0, 1)
				var col1 := Color(t, b / float(blades), 0, 1)
				st.set_normal(n); st.set_color(col0); st.set_uv(Vector2(0, 1.0 - float(s - 1) / segs)); st.add_vertex(prev_l)
				st.set_normal(n); st.set_color(col0); st.set_uv(Vector2(1, 1.0 - float(s - 1) / segs)); st.add_vertex(prev_r)
				st.set_normal(n); st.set_color(col1); st.set_uv(Vector2(1, 1.0 - t)); st.add_vertex(rr)
				st.set_normal(n); st.set_color(col0); st.set_uv(Vector2(0, 1.0 - float(s - 1) / segs)); st.add_vertex(prev_l)
				st.set_normal(n); st.set_color(col1); st.set_uv(Vector2(1, 1.0 - t)); st.add_vertex(rr)
				st.set_normal(n); st.set_color(col1); st.set_uv(Vector2(0, 1.0 - t)); st.add_vertex(l)
			prev_l = l
			prev_r = rr
	st.index()
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-1, -2, -1), Vector3(GRASS_CELL + 2, 2000, GRASS_CELL + 2))
	return m

func _update_grass(cp: Vector3) -> void:
	var half := world.size_m * 0.5
	var center := Vector2i(floori((cp.x + half) / GRASS_CELL), floori((cp.z + half) / GRASS_CELL))
	if center == _last_grass_center and Engine.get_process_frames() % 10 != 0:
		return
	_last_grass_center = center
	var r := int(ceil(grass_dist / GRASS_CELL))
	var want := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := center + Vector2i(dx, dz)
			var cc := Vector2(-half + (k.x + 0.5) * GRASS_CELL, -half + (k.y + 0.5) * GRASS_CELL)
			var d := cc.distance_to(Vector2(cp.x, cp.z))
			if d > grass_dist + GRASS_CELL * 0.7:
				continue
			want[k] = 0 if d < GRASS_LOD0 else (1 if d < GRASS_LOD1 else 2)
	for k in _grass_cells.keys():
		if not want.has(k):
			_grass_cells[k].queue_free()
			_grass_cells.erase(k)
	for k in want.keys():
		var lod: int = want[k]
		var mmi: MultiMeshInstance3D = _grass_cells.get(k)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.material_override = _grass_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.position = Vector3(-half + k.x * GRASS_CELL, 0.0, -half + k.y * GRASS_CELL)
			add_child(mmi)
			_grass_cells[k] = mmi
		if mmi.multimesh != _grass_mm[lod]:
			mmi.multimesh = _grass_mm[lod]
