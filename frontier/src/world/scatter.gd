extends Node3D
## Near-field ground detail from CC0 photogrammetry (Poly Haven): rocks and boulders on slopes and in the breaks,
## stumps, fallen trunks and dry branches in forests, ferns/nettles by water, desert shrubs. Deterministic per
## 128 m cell, built within RANGE of the camera, MultiMesh per model per cell; boulders and trunks get collision
## (cover in gunfights, obstacles for horses).

const CELL := 128.0
const RANGE := 260.0

## model id -> rules. weight per m² baseline, where (biome/slope/water/forest), scale range, collision radius factor.
const MODELS := {
	"rock_07": {"density": 0.0025, "slope": [0.12, 0.6], "scale": [0.6, 1.6], "coll": 0.8, "biome": [0.0, 1.0]},
	"rock_09": {"density": 0.0025, "slope": [0.12, 0.6], "scale": [0.6, 1.6], "coll": 0.8, "biome": [0.0, 1.0]},
	"boulder_01": {"density": 0.0007, "slope": [0.1, 0.55], "scale": [0.7, 1.5], "coll": 0.9, "biome": [0.3, 1.0]},
	"namaqualand_boulder_02": {"density": 0.0009, "slope": [0.05, 0.6], "scale": [0.7, 1.8], "coll": 0.9, "biome": [0.0, 0.45]},
	"namaqualand_boulder_03": {"density": 0.0009, "slope": [0.05, 0.6], "scale": [0.7, 1.8], "coll": 0.9, "biome": [0.0, 0.45]},
	"namaqualand_boulder_05": {"density": 0.0007, "slope": [0.05, 0.6], "scale": [0.7, 1.6], "coll": 0.9, "biome": [0.0, 0.5]},
	"namaqualand_rocks_01": {"density": 0.0012, "slope": [0.0, 0.5], "scale": [0.8, 1.3], "coll": 0.0, "biome": [0.0, 0.45]},
	"rock_moss_set_01": {"density": 0.0010, "slope": [0.0, 0.5], "scale": [0.8, 1.4], "coll": 0.0, "biome": [0.7, 1.0]},
	"tree_stump_01": {"density": 0.0010, "slope": [0.0, 0.35], "scale": [0.8, 1.2], "coll": 0.5, "biome": [0.72, 1.0]},
	"tree_stump_02": {"density": 0.0008, "slope": [0.0, 0.35], "scale": [0.8, 1.2], "coll": 0.5, "biome": [0.72, 1.0]},
	"dead_tree_trunk": {"density": 0.0005, "slope": [0.0, 0.3], "scale": [0.8, 1.1], "coll": 0.6, "biome": [0.7, 1.0]},
	"dead_tree_trunk_02": {"density": 0.0005, "slope": [0.0, 0.3], "scale": [0.8, 1.1], "coll": 0.6, "biome": [0.6, 1.0]},
	"dry_branches_medium_01": {"density": 0.0025, "slope": [0.0, 0.4], "scale": [0.8, 1.3], "coll": 0.0, "biome": [0.55, 1.0]},
	"fern_02": {"density": 0.006, "slope": [0.0, 0.35], "scale": [0.7, 1.3], "coll": 0.0, "biome": [0.75, 1.0], "moist": 0.55},
	"nettle_plant": {"density": 0.004, "slope": [0.0, 0.3], "scale": [0.7, 1.2], "coll": 0.0, "biome": [0.45, 1.0], "moist": 0.6},
	"celandine_01": {"density": 0.004, "slope": [0.0, 0.3], "scale": [0.8, 1.2], "coll": 0.0, "biome": [0.5, 1.0], "moist": 0.6},
	"wild_rooibos_bush": {"density": 0.003, "slope": [0.0, 0.4], "scale": [0.7, 1.3], "coll": 0.0, "biome": [0.0, 0.35]},
	"shrub_02": {"density": 0.002, "slope": [0.0, 0.4], "scale": [0.7, 1.2], "coll": 0.0, "biome": [0.4, 0.8]},
	"shrub_03": {"density": 0.002, "slope": [0.0, 0.4], "scale": [0.7, 1.2], "coll": 0.0, "biome": [0.4, 0.9]},
	"shrub_04": {"density": 0.002, "slope": [0.0, 0.4], "scale": [0.7, 1.2], "coll": 0.0, "biome": [0.4, 0.9]},
	"grass_medium_02": {"density": 0.010, "slope": [0.0, 0.35], "scale": [0.8, 1.3], "coll": 0.0, "biome": [0.3, 0.9]},
}

var world: WorldData
var camera: Camera3D
var _meshes := {}        # id -> Mesh (null if missing)
var _radius := {}        # id -> mesh bounding radius (m) at scale 1
var _cells := {}         # Vector2i -> Node3D
var _t := 0.0

func setup(w: WorldData, cam: Camera3D) -> void:
	world = w
	camera = cam
	for id in MODELS.keys():
		var path := "res://assets/ext/nature/%s/%s.gltf" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var ps: PackedScene = load(path)
		if ps == null:
			continue
		var inst := ps.instantiate()
		var mi: MeshInstance3D = _first_mesh(inst)
		if mi != null and mi.mesh != null:
			var mesh: Mesh = mi.mesh
			if id.contains("boulder") or id.contains("rock"):
				# pale photogrammetry granite reads as white balls on the plains: weather it down a little
				mesh = mesh.duplicate()
				for si in mesh.get_surface_count():
					var m = mesh.surface_get_material(si)
					if m is StandardMaterial3D:
						var d: StandardMaterial3D = m.duplicate()
						d.albedo_color = d.albedo_color * Color(0.74, 0.71, 0.66)
						mesh.surface_set_material(si, d)
			_meshes[id] = mesh
			var a: AABB = mi.mesh.get_aabb()
			_radius[id] = maxf(a.size.x, a.size.z) * 0.5
		inst.free()
	print("scatter: %d CC0 models" % _meshes.size())

func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null

var _pending := {}       # Vector2i -> task id
var _results := {}
var _mutex := Mutex.new()

func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_impl(dt)
	Game.prof("scatter.gd _process", _pt0)

func _process_impl(dt: float) -> void:
	if world == null or _meshes.is_empty():
		return
	# finish completed worker jobs (cheap: buffers + shapes)
	for k in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[k]):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
			_mutex.lock()
			var res = _results.get(k)
			_results.erase(k)
			_mutex.unlock()
			if res != null and not _cells.has(k):
				_cells[k] = _instantiate(res)
			break
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	var want := _wanted()
	for k in want.keys():
		if not _cells.has(k) and not _pending.has(k) and _pending.size() < 3:
			_pending[k] = WorkerThreadPool.add_task(_generate.bind(k))
	for k in _cells.keys():
		if not want.has(k):
			_cells[k].queue_free()
			_cells.erase(k)

func _wanted() -> Dictionary:
	var cp := camera.global_position
	var half := world.size_m * 0.5
	var cx := floori((cp.x + half) / CELL)
	var cz := floori((cp.z + half) / CELL)
	var r := int(ceil(RANGE / CELL))
	var want := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(cx + dx, cz + dz)
			var rect := Rect2(-half + k.x * CELL, -half + k.y * CELL, CELL, CELL)
			var q := Vector2(clampf(cp.x, rect.position.x, rect.end.x), clampf(cp.z, rect.position.y, rect.end.y))
			if q.distance_to(Vector2(cp.x, cp.z)) <= RANGE:
				want[k] = true
	return want

func settle_now() -> void:
	for k in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()
	var want := _wanted()
	var missing := want.keys().filter(func(k): return not _cells.has(k))
	var gid := WorkerThreadPool.add_group_task(func(i: int): _generate(missing[i]), missing.size())
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for k in _results.keys():
		if not _cells.has(k) and want.has(k):
			_cells[k] = _instantiate(_results[k])
	_results.clear()

func _exit_tree() -> void:
	for k in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[k])

## Worker thread: placements for one cell (pure data).
func _generate(k: Vector2i) -> void:
	var half := world.size_m * 0.5
	var x0 := -half + k.x * CELL
	var z0 := -half + k.y * CELL
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) ^ 0x51ab
	var out := {"models": {}, "colliders": []}
	for id in _meshes.keys():
		var rule: Dictionary = MODELS[id]
		var n := int(rule.density * CELL * CELL * rng.randf_range(0.6, 1.4))
		var xf: Array[Transform3D] = []
		for i in n:
			var x := x0 + rng.randf() * CELL
			var z := z0 + rng.randf() * CELL
			var c := world.ctrl(x, z)
			if c.r > 0.05 or c.b < rule.biome[0] or c.b > rule.biome[1]:
				continue
			if rule.has("moist") and c.g < rule.moist:
				continue
			if world.is_water(x, z):
				continue
			var nrm := world.normal(x, z)
			var slope := 1.0 - nrm.y
			if slope < rule.slope[0] or slope > rule.slope[1]:
				continue
			var near := world.nearest_settlement(x, z)
			if not near.is_empty() and Vector2(near.x - x, near.z - z).length() < float(near.r) + 8.0:
				continue
			var s := rng.randf_range(rule.scale[0], rule.scale[1])
			var y := world.height(x, z) - 0.08 * s
			if id.contains("boulder") or id.begins_with("rock"):
				y -= rng.randf_range(0.15, 0.4) * float(_radius.get(id, 0.5)) * s     # bedded in, not sitting on top
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			if float(rule.coll) > 0.7 or id.begins_with("rock"):
				var tilt := Vector3.UP.cross(nrm)
				if tilt.length() > 0.01:
					b = Basis(tilt.normalized(), Vector3.UP.angle_to(nrm) * 0.7) * b
			xf.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, y, z)))
			if float(rule.coll) > 0.0:
				var rad: float = _radius[id] * s * float(rule.coll)
				out.colliders.append([Vector3(x, y + rad * 0.4, z), rad])
		if not xf.is_empty():
			out.models[id] = xf
	_mutex.lock()
	_results[k] = out
	_mutex.unlock()

func _instantiate(res: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	if not res.colliders.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		node.add_child(body)
		for c in res.colliders:
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = c[1]
			cs.shape = sh
			cs.position = c[0]
			body.add_child(cs)
	for id in res.models.keys():
		var rule: Dictionary = MODELS[id]
		var xf: Array = res.models[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[id]
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var small: bool = float(rule.coll) == 0.0
		mmi.visibility_range_end = 90.0 if small else RANGE
		mmi.visibility_range_end_margin = 10.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mmi)
	return node
