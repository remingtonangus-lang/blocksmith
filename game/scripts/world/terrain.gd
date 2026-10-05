class_name Terrain
extends Node3D
## CDLOD terrain: one 32x32-quad patch mesh drawn as a MultiMesh of quadtree nodes chosen around the camera
## each frame. The vertex shader reads heights from the WorldGen grid (manual bilinear, identical to
## WorldGen.height_at) and morphs each level's odd vertices onto the next coarser grid near its range limit,
## so neighbouring levels meet without cracks. Collision is a HeightMapShape3D window that follows the player
## (built on a worker thread).

const PATCH := 32
const LEAF := 32.0
const LEVELS := 11              # root = 32 * 2^10 = 32768 m
const ROOT := LEAF * 1024.0
const RANGE0 := 96.0
const COLLIDE_N := 257          # collision window: 256 m at 1 m spacing
const COLLIDE_STEP := 1.0

var gen: WorldGen
const NEAR_LEVELS := 4          # levels 0-3 (nodes up to 256 m) cast shadows, with a tight AABB
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var mm_far: MultiMesh
var mmi_far: MultiMeshInstance3D
var _buf_far := PackedFloat32Array()
var _count_far := 0
var _lo := Vector3.ZERO
var _hi := Vector3.ZERO
var material: ShaderMaterial
var ranges := PackedFloat32Array()
var minmax: Array = []          # per level: PackedFloat32Array of (min, max) pairs for nodes of that level
var _buf := PackedFloat32Array()
var _count := 0
var _focus := Vector3.ZERO
var _detail_mult := 1.0

var body: StaticBody3D
var shape: CollisionShape3D
var _col_center := Vector2(1e9, 1e9)
var _col_task := -1
var _col_pending: Dictionary = {}


func setup(g: WorldGen) -> void:
	gen = g
	ranges.resize(LEVELS)
	for l in LEVELS:
		ranges[l] = RANGE0 * pow(2.0, l)
	_build_minmax()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var tex := ImageTexture.create_from_image(gen.height_image())
	var mask_img := gen.mask_image()
	var mask_lin := mask_img.duplicate()
	mask_lin.generate_mipmaps()
	material.set_shader_parameter("maskmap_lin", ImageTexture.create_from_image(mask_lin))
	var det := gen.detail_image()
	det.generate_mipmaps()
	RenderingServer.global_shader_parameter_set("terrain_heightmap", tex)
	RenderingServer.global_shader_parameter_set("terrain_mask", ImageTexture.create_from_image(mask_img))
	RenderingServer.global_shader_parameter_set("terrain_detail", ImageTexture.create_from_image(det))
	RenderingServer.global_shader_parameter_set("terrain_normal", ImageTexture.create_from_image(gen.normal_image()))
	var mats := TerrainMaterials.build(gen.seed)
	material.set_shader_parameter("albedo_array", mats[0])
	material.set_shader_parameter("normal_array", mats[1])

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _patch_mesh()
	mm.instance_count = 2048
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.name = "TerrainPatches"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_buf.resize(2048 * 16)
	mm_far = MultiMesh.new()
	mm_far.transform_format = MultiMesh.TRANSFORM_3D
	mm_far.use_custom_data = true
	mm_far.mesh = mm.mesh
	mm_far.instance_count = 1024
	mm_far.visible_instance_count = 0
	mmi_far = MultiMeshInstance3D.new()
	mmi_far.name = "TerrainFar"
	mmi_far.multimesh = mm_far
	mmi_far.material_override = material
	mmi_far.custom_aabb = AABB(Vector3(-ROOT, -500, -ROOT), Vector3(ROOT * 2, 3500, ROOT * 2))
	mmi_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi_far)
	_buf_far.resize(1024 * 16)

	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	shape = CollisionShape3D.new()
	body.add_child(shape)
	add_child(body)
	Settings.changed.connect(_on_settings)
	_on_settings()


func _on_settings() -> void:
	_detail_mult = float(Settings.q["terrain_detail"])


func _patch_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := PATCH + 1
	for z in n:
		for x in n:
			verts.append(Vector3(float(x) / PATCH, 0.0, float(z) / PATCH))
	for z in PATCH:
		for x in PATCH:
			var i := z * n + x
			# Alternate the diagonal so morphing stays symmetric.
			if (x + z) % 2 == 0:
				idx.append_array([i, i + 1, i + n + 1, i, i + n + 1, i + n])
			else:
				idx.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-ROOT, -500, -ROOT), Vector3(ROOT * 2, 3500, ROOT * 2))
	return m


## Min/max height per quadtree node for levels >= 3 (256 m nodes and up), sampled from the height grid every
## 4 texels with a safety margin; smaller nodes use their level-3 ancestor's range (conservative).
const MM_BASE := 3


func _build_minmax() -> void:
	minmax.clear()
	for l in MM_BASE:
		minmax.append(PackedFloat32Array())
	var size := int(ROOT / (LEAF * 8.0))     # 128 nodes per side at level 3
	var node := LEAF * 8.0
	var base := PackedFloat32Array()
	base.resize(size * size * 2)
	for z in size:
		var wz := -ROOT * 0.5 + z * node
		for x in size:
			var wx := -ROOT * 0.5 + x * node
			var lo := 1e9
			var hi := -1e9
			if wx + node < -WorldGen.HALF or wx > WorldGen.HALF or wz + node < -WorldGen.HALF or wz > WorldGen.HALF:
				var e := gen.macro_height(clampf(wx, -WorldGen.HALF, WorldGen.HALF), clampf(wz, -WorldGen.HALF, WorldGen.HALF))
				lo = e; hi = e
			else:
				for sz in 9:
					for sx in 9:
						var h := gen.macro_height(wx + sx * node / 8.0, wz + sz * node / 8.0)
						lo = minf(lo, h); hi = maxf(hi, h)
			base[(z * size + x) * 2] = lo - 20.0
			base[(z * size + x) * 2 + 1] = hi + 20.0
	minmax.append(base)
	for l in range(MM_BASE + 1, LEVELS):
		var prev: PackedFloat32Array = minmax[l - 1]
		var ns := size / 2
		var cur := PackedFloat32Array()
		cur.resize(ns * ns * 2)
		for z in ns:
			for x in ns:
				var lo := 1e9
				var hi := -1e9
				for c in [[0, 0], [1, 0], [0, 1], [1, 1]]:
					var j: int = ((z * 2 + c[1]) * size + x * 2 + c[0]) * 2
					lo = minf(lo, prev[j]); hi = maxf(hi, prev[j + 1])
				cur[(z * ns + x) * 2] = lo
				cur[(z * ns + x) * 2 + 1] = hi
		minmax.append(cur)
		size = ns


func focus(p: Vector3) -> void:
	_focus = p


var _sel_pos := Vector3(1e9, 0, 0)
var _sel_mult := -1.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or gen == null:
		return
	var c := cam.global_position
	material.set_shader_parameter("cam_pos", c)
	# The LOD selection depends only on the camera position: skip it (and the ~128 KB buffer upload) while the
	# camera has moved under half a metre (measured 0.9 ms a frame, the largest script cost after the frigate).
	if c.distance_squared_to(_sel_pos) < 0.25 and _detail_mult == _sel_mult:
		_update_collision()
		return
	_sel_pos = c
	_sel_mult = _detail_mult
	_count = 0
	_count_far = 0
	_lo = Vector3(1e9, 1e9, 1e9)
	_hi = Vector3(-1e9, -1e9, -1e9)
	_select(0, 0, LEVELS - 1, c)
	mm.visible_instance_count = 0
	if _count > 0:
		mm.buffer = _buf
		mmi.custom_aabb = AABB(_lo, _hi - _lo)
	mm.visible_instance_count = _count
	mm_far.visible_instance_count = 0
	if _count_far > 0:
		mm_far.buffer = _buf_far
	mm_far.visible_instance_count = _count_far
	_update_collision()


func _node_box_dist(ix: int, iz: int, level: int, c: Vector3) -> float:
	var size := LEAF * pow(2.0, level)
	var x0 := -ROOT * 0.5 + ix * size
	var z0 := -ROOT * 0.5 + iz * size
	var ml := maxi(level, MM_BASE)
	var sh := ml - level
	var n := int(ROOT / (LEAF * pow(2.0, ml)))
	var mmv: PackedFloat32Array = minmax[ml]
	var j := ((iz >> sh) * n + (ix >> sh)) * 2
	var dx := maxf(maxf(x0 - c.x, 0.0), c.x - (x0 + size))
	var dz := maxf(maxf(z0 - c.z, 0.0), c.z - (z0 + size))
	var dy := maxf(maxf(mmv[j] - c.y, 0.0), c.y - mmv[j + 1])
	return sqrt(dx * dx + dy * dy + dz * dz)


func _select(ix: int, iz: int, level: int, c: Vector3) -> void:
	var r_child := ranges[level - 1] * _detail_mult if level > 0 else 0.0
	if level == 0 or _node_box_dist(ix, iz, level, c) > r_child:
		_add(ix, iz, level)
		return
	for k in 4:
		_select(ix * 2 + (k & 1), iz * 2 + (k >> 1), level - 1, c)


func _add(ix: int, iz: int, level: int) -> void:
	var size := LEAF * pow(2.0, level)
	var x0 := -ROOT * 0.5 + ix * size
	var z0 := -ROOT * 0.5 + iz * size
	var far := level >= NEAR_LEVELS
	var o := 0
	if not far:
		if _count >= 2048:
			return
		o = _count * 16
		_count += 1
		var ml := MM_BASE
		var sh := ml - level
		var n := int(ROOT / (LEAF * pow(2.0, ml)))
		var mmv: PackedFloat32Array = minmax[ml]
		var j := ((iz >> sh) * n + (ix >> sh)) * 2
		_lo = Vector3(minf(_lo.x, x0), minf(_lo.y, mmv[j] - 2.0), minf(_lo.z, z0))
		_hi = Vector3(maxf(_hi.x, x0 + size), maxf(_hi.y, mmv[j + 1] + 2.0), maxf(_hi.z, z0 + size))
	else:
		if _count_far >= 1024:
			return
		o = _count_far * 16
		_count_far += 1
	var r := ranges[level] * _detail_mult
	# Basis (row-major 3x4) scales the unit patch to the node; custom = morph start, morph end, level, step.
	var v := [size, 0.0, 0.0, x0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, size, z0, r * 0.78, r * 0.98, float(level), size / PATCH]
	if far:
		for k in 16:
			_buf_far[o + k] = v[k]
	else:
		for k in 16:
			_buf[o + k] = v[k]


# -------------------------------------------------------------------------------------------- collision

func _update_collision() -> void:
	var anchor := _focus
	if G.player and is_instance_valid(G.player):
		anchor = G.player.global_position
		# In a vehicle the player node stays where they got in; the window follows the vehicle.
		var v: Variant = G.player.vehicle
		if v != null and is_instance_valid(v) and v is Node3D:
			anchor = (v as Node3D).global_position
	var cen := Vector2(roundf(anchor.x / 32.0) * 32.0, roundf(anchor.z / 32.0) * 32.0)
	if _col_task >= 0:
		if WorkerThreadPool.is_task_completed(_col_task):
			WorkerThreadPool.wait_for_task_completion(_col_task)
			_col_task = -1
			var hs := HeightMapShape3D.new()
			hs.map_width = COLLIDE_N
			hs.map_depth = COLLIDE_N
			hs.map_data = _col_pending["data"]
			shape.shape = hs
			var cc: Vector2 = _col_pending["center"]
			body.global_position = Vector3(cc.x, 0.0, cc.y)
		return
	if cen.distance_to(_col_center) < 48.0:
		return
	_col_center = cen
	_col_pending = {"center": cen}
	_col_task = WorkerThreadPool.add_task(_build_collision.bind(cen), true, "terrain collision")


func _build_collision(cen: Vector2) -> void:
	var data := PackedFloat32Array()
	data.resize(COLLIDE_N * COLLIDE_N)
	var half := (COLLIDE_N - 1) * 0.5 * COLLIDE_STEP
	for z in COLLIDE_N:
		var wz := cen.y - half + z * COLLIDE_STEP
		for x in COLLIDE_N:
			data[z * COLLIDE_N + x] = gen.height_at(cen.x - half + x * COLLIDE_STEP, wz)
	_col_pending["data"] = data


## True when the ground under `p` has physics collision (inside the live window, `margin` metres from its edge).
func has_collision_at(p: Vector3, margin: float = 16.0) -> bool:
	if shape == null or shape.shape == null:
		return false
	var half := (COLLIDE_N - 1) * 0.5 * COLLIDE_STEP - margin
	var c := body.global_position
	return absf(p.x - c.x) < half and absf(p.z - c.z) < half


## Rigid bodies beyond the collision window would fall through the world: they are frozen (and put back on the
## analytic ground if they already sank) until the window reaches them again. Returns true if `rb` is frozen.
func guard_body(rb: RigidBody3D, lift: float = 0.5) -> bool:
	var p := rb.global_position
	if has_collision_at(p):
		if rb.freeze and rb.has_meta("terrain_frozen"):
			rb.remove_meta("terrain_frozen")
			rb.freeze = false
		return false
	# City podiums, base platforms and decks still hold things up: only freeze when no static collision lies
	# under the body (a ray down to the analytic ground).
	var g := gen.height_at(p.x, p.z)
	if not rb.freeze:
		var q := PhysicsRayQueryParameters3D.create(p, Vector3(p.x, g - 1.0, p.z))
		q.collision_mask = 1
		q.exclude = [rb.get_rid(), body.get_rid()]
		if not rb.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return false
		if p.y > g + 30.0:
			return false
	if not rb.freeze:
		rb.set_meta("terrain_frozen", true)
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true
	if p.y < g - lift:
		rb.global_position = Vector3(p.x, g + lift, p.z)
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	return true


## Forces the collision window to be built around a point now (spawning, teleports).
func collision_now(p: Vector3) -> void:
	if _col_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_col_task)
		_col_task = -1
	var cen := Vector2(roundf(p.x / 32.0) * 32.0, roundf(p.z / 32.0) * 32.0)
	_col_center = cen
	_col_pending = {"center": cen}
	_build_collision(cen)
	var hs := HeightMapShape3D.new()
	hs.map_width = COLLIDE_N
	hs.map_depth = COLLIDE_N
	hs.map_data = _col_pending["data"]
	shape.shape = hs
	body.global_position = Vector3(cen.x, 0.0, cen.y)
