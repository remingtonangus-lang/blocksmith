extends Node3D
## Trees, shrubs and grass for the whole map.
## Trees: deterministic scatter per 1024 m region (worker threads) from biome/moisture/slope/altitude. Every tree is
## drawn as a billboard in its region's MultiMesh (one draw per region, all species; shaders/billboard_tree.gdshader);
## within NEAR_END of the camera the billboard collapses and the full mesh (per 256 m chunk, per species variant,
## shaders/foliage.gdshader) takes over, fading per instance so the swap never pops a whole chunk.
## Grass: GPU-placed clumps in 16 m cells around the camera (shaders/grass.gdshader).

const REGION := 1024.0
const CHUNK := 256.0
const VARIANTS := 3
const GRASS_CELL := 16.0
const NEAR_END := 200.0          # full meshes up to here (per instance), billboards beyond
const SHRUB_END := 110.0

var world: WorldData
var camera: Camera3D
var tree_dist := 2500.0
var grass_dist := 80.0
var grass_density := 1.0
var species_list: Array = []
var _meshes := {}            # species -> [lod0 mesh per variant]
var _sizes := {}             # species -> [Vector2(width, height) per variant]
var _mats := {}              # species -> {bark, leaf}
var _bill_mat: ShaderMaterial
var _bill_mesh: ArrayMesh
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
	grass_dist = Game.quality.grass_dist
	grass_density = Game.quality.grass_density
	_leaf_tex = TreeGen.make_leaf_atlas()
	species_list = TreeGen.SPECIES.keys()
	var gen := TreeGen.new()
	for sp in species_list:
		var vs := []
		var sz := []
		for v in VARIANTS:
			var m := gen.build(sp, hash(sp) + v * 7919, 0)
			vs.append(m)
			var a := m.get_aabb()
			sz.append(Vector2(maxf(a.size.x, a.size.z) * 0.9, a.size.y))
		_meshes[sp] = vs
		_sizes[sp] = sz
		_mats[sp] = _make_materials(sp)
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
	_last_grass_center = Vector2i(999999, 999999)
	_update_grass(cp)

func is_settled() -> bool:
	return _pending.is_empty() and _last_missing == 0

func _exit_tree() -> void:
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
	var end := SHRUB_END if small else NEAR_END
	bark.set_shader_parameter("tint", bt)
	bark.set_shader_parameter("tree_height", spec.height[1])
	bark.set_shader_parameter("lod_end", end)
	var leaf := ShaderMaterial.new()
	leaf.shader = load("res://shaders/foliage.gdshader")
	leaf.set_shader_parameter("is_leaf", true)
	leaf.set_shader_parameter("albedo_tex", _leaf_tex)
	leaf.set_shader_parameter("tint", spec.leaf_tint)
	leaf.set_shader_parameter("tree_height", spec.height[1])
	leaf.set_shader_parameter("sway", 1.4 if small else 1.0)
	leaf.set_shader_parameter("lod_end", end)
	for v in VARIANTS:
		var m: ArrayMesh = _meshes[sp][v]
		m.surface_set_material(0, bark)
		if m.get_surface_count() > 1:
			m.surface_set_material(1, leaf)
	return {"bark": bark, "leaf": leaf}

func _setup_billboards() -> void:
	_bill_mat = ShaderMaterial.new()
	_bill_mat.shader = load("res://shaders/billboard_tree.gdshader")
	_bill_mat.set_shader_parameter("leaf_tex", _leaf_tex)
	var tints := PackedVector4Array()
	var barks := PackedVector4Array()
	for sp in species_list:
		var spec: Dictionary = TreeGen.SPECIES[sp]
		var lt: Color = spec.leaf_tint
		var shape: float = {"cone": 0.0, "cone_round": 1.0, "round": 2.0, "oval": 2.0, "bush": 3.0}.get(spec.crown, 2.0)
		tints.append(Vector4(lt.r, lt.g, lt.b, 1.0 if spec.leaf != "" else 0.0))
		var bt := Vector4(0.3, 0.24, 0.19, shape)
		if spec.bark == "aspen":
			bt = Vector4(0.75, 0.74, 0.68, shape)
		elif spec.bark == "dead":
			bt = Vector4(0.42, 0.38, 0.34, shape)
		barks.append(bt)
	_bill_mat.set_shader_parameter("species_tint", tints)
	_bill_mat.set_shader_parameter("species_bark", barks)
	_bill_mat.set_shader_parameter("near_end", NEAR_END)
	_bill_mat.set_shader_parameter("shrub_end", SHRUB_END)
	_bill_mat.set_shader_parameter("far_end", tree_dist)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uv[k])
		st.add_vertex(quad[k])
	_bill_mesh = st.commit()

func _process(_dt: float) -> void:
	if world == null or camera == null:
		return
	var cp := camera.global_position
	RenderingServer.global_shader_parameter_set("player_pos", Game.player.global_position if Game.player else cp)
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
					var si := species_list.find(pick)
					var size: Vector2 = _sizes[pick][v] * s
					bill.append_array([1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, float(si), size.x, size.y, r.randf()])
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "TreeBillboards_%d_%d" % [k.x, k.y]
	add_child(mmi)
	_regions[k] = mmi
	for ck in res.chunks.keys():
		_region_chunks[ck] = res.chunks[ck]

func _update_near(cp: Vector3, max_builds: int) -> void:
	var half := world.size_m * 0.5
	var reach := NEAR_END + CHUNK * 0.75
	var built := 0
	var want := {}
	var cx := floori((cp.x + half) / CHUNK)
	var cz := floori((cp.z + half) / CHUNK)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
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

func _build_near(ck: Vector2i, list: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "TreesNear_%d_%d" % [ck.x, ck.y]
	add_child(node)
	# trunk colliders (cover for gunfights, obstacles for riders); shrubs stay passable
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	node.add_child(sb)
	var groups := {}
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
		var key := "%s:%d" % [e[0], e[1]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(e[2])
	for key in groups.keys():
		var parts: PackedStringArray = key.split(":")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[parts[0]][int(parts[1])]
		var arr: Array = groups[key]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mmi)
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
	# three densities of the same 16 m tile; instance i is identical across them so LOD changes don't reshuffle
	var counts := [int(1400 * grass_density), int(480 * grass_density), int(160 * grass_density)]
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
	var meshes := [_grass_clump(9, 4), _grass_clump(7, 3), _grass_clump(5, 2)]
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
func _grass_clump(blades: int, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = blades * 31 + segs
	for b in blades:
		var ang := r.randf() * TAU
		var off := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.0, 0.22)
		var facing := r.randf() * TAU
		var dir := Vector3(cos(facing), 0, sin(facing))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := r.randf_range(0.35, 0.75)
		var w := r.randf_range(0.025, 0.045)
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
			want[k] = 0 if d < 26.0 else (1 if d < 50.0 else 2)
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
