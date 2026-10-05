class_name Terrain
extends Node3D
## CDLOD terrain: one 64x64-quad patch mesh drawn through a MultiMesh at quadtree nodes chosen around the camera,
## vertex-morphed between levels (shaders/terrain.gdshader). Collision: HeightMapShape3D tiles around each focus.

const PATCH := 64                  # quads per patch side
const LEAF := 128.0                # leaf node size (m) -> 2 m vertex spacing
const LEVELS := 7                  # leaf .. root (128 * 2^6 = 8192)
const COLL_TILE := 64.0            # collision tile size (m)
const COLL_RING := 2               # tiles each side of the focus tile (5x5 = 320 m square)

var world: WorldData
var camera: Camera3D
var lod_range_scale := 2.6         # ranges[l] = LEAF * scale * 2^l ; quality presets tune this
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var material: ShaderMaterial
var _minmax: PackedFloat32Array    # [64*64*2] leaf min/max
var _pyr: Array = []               # per level: PackedFloat32Array min/max grid
var _ranges: PackedFloat32Array
var _sel: PackedFloat32Array = PackedFloat32Array()
var _count := 0
var _last_cam := Vector3(INF, 0, 0)
var _planes: Array[Plane] = []
var foci: Array[Node3D] = []       # bodies needing collision (player, horse, nearby NPCs)
var _coll_tiles := {}              # Vector2i -> StaticBody3D
var _coll_body: StaticBody3D

func setup(w: WorldData, cam: Camera3D) -> void:
	world = w
	camera = cam
	_load_minmax()
	_build_ranges()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var htex := ImageTexture.create_from_image(world.height_image)
	var ctex := ImageTexture.create_from_image(world.control_image)
	material.set_shader_parameter("heightmap", htex)
	material.set_shader_parameter("controlmap", ctex)
	material.set_shader_parameter("map_size", world.size_m)
	material.set_shader_parameter("h_range", world.h_range)
	material.set_shader_parameter("hm_res", float(world.res))
	material.set_shader_parameter("lake_level", world.lake_level)
	material.set_shader_parameter("grass_fade", float(Game.quality.get("grass_dist", 80.0)) if not Game.disabled("grass") else 0.0)
	_bind_textures()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _build_patch()
	mm.instance_count = 2048
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.custom_aabb = AABB(Vector3(-world.size_m, -100, -world.size_m), Vector3(world.size_m * 2, world.h_range + 200, world.size_m * 2))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_coll_body = StaticBody3D.new()
	_coll_body.name = "TerrainCollision"
	_coll_body.collision_layer = 1
	add_child(_coll_body)

func _bind_textures() -> void:
	var ah = load("res://assets/ext/packed/terrain_ah.png") if ResourceLoader.exists("res://assets/ext/packed/terrain_ah.png") else null
	var nr = load("res://assets/ext/packed/terrain_nr.png") if ResourceLoader.exists("res://assets/ext/packed/terrain_nr.png") else null
	if ah == null or nr == null:
		push_warning("terrain: packed CC0 textures missing, using procedural stand-ins")
		var arr := _fallback_arrays()
		ah = arr[0]
		nr = arr[1]
	material.set_shader_parameter("tex_ah", ah)
	material.set_shader_parameter("tex_nr", nr)

func _fallback_arrays() -> Array:
	var cols := [Color8(78, 92, 44), Color8(150, 132, 84), Color8(120, 110, 70), Color8(110, 86, 62), Color8(140, 118, 92),
		Color8(70, 56, 44), Color8(84, 66, 46), Color8(176, 146, 110), Color8(170, 102, 66), Color8(118, 112, 104),
		Color8(150, 84, 56), Color8(236, 238, 242), Color8(128, 120, 110)]
	var ahs: Array[Image] = []
	var nrs: Array[Image] = []
	for c in cols:
		var a := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		a.fill(Color(c.r, c.g, c.b, 0.5))
		a.generate_mipmaps()
		ahs.append(a)
		var n := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		n.fill(Color(0.5, 0.5, 0.85, 1.0))
		n.generate_mipmaps()
		nrs.append(n)
	var ta := Texture2DArray.new()
	ta.create_from_images(ahs)
	var tn := Texture2DArray.new()
	tn.create_from_images(nrs)
	return [ta, tn]

func _load_minmax() -> void:
	var bytes := FileAccess.get_file_as_bytes(WorldData.DIR + "minmax.bin")
	_minmax = bytes.to_float32_array()
	if _minmax.size() != 64 * 64 * 2:
		_minmax = PackedFloat32Array()
		_minmax.resize(64 * 64 * 2)
		for i in 64 * 64:
			_minmax[i * 2] = 0.0
			_minmax[i * 2 + 1] = world.h_range
	_pyr.clear()
	_pyr.append(_minmax)
	var n := 64
	for l in range(1, LEVELS):
		var prev: PackedFloat32Array = _pyr[l - 1]
		var m := n / 2
		var cur := PackedFloat32Array()
		cur.resize(m * m * 2)
		for z in m:
			for x in m:
				var lo := INF
				var hi := -INF
				for dz in 2:
					for dx in 2:
						var o := ((z * 2 + dz) * n + (x * 2 + dx)) * 2
						lo = minf(lo, prev[o])
						hi = maxf(hi, prev[o + 1])
				cur[(z * m + x) * 2] = lo
				cur[(z * m + x) * 2 + 1] = hi
		_pyr.append(cur)
		n = m

func _build_ranges() -> void:
	_ranges = PackedFloat32Array()
	for l in LEVELS:
		_ranges.append(LEAF * lod_range_scale * pow(2.0, l))

func set_quality(range_scale: float) -> void:
	lod_range_scale = range_scale
	_build_ranges()
	_last_cam = Vector3(INF, 0, 0)

func _build_patch() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := PATCH + 1
	for z in n:
		for x in n:
			verts.append(Vector3(float(x) / PATCH, 0.0, float(z) / PATCH))
			uv2.append(Vector2(0, 0))
	for z in PATCH:
		for x in PATCH:
			var a := z * n + x
			var b := a + 1
			var c := a + n
			var d := c + 1
			if (x + z) % 2 == 0:
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	# skirts: duplicate the border ring, flagged in UV2.x so the shader drops them
	var border: Array[int] = []
	for x in n: border.append(x)
	for z in range(1, n): border.append(z * n + PATCH)
	for x in range(PATCH - 1, -1, -1): border.append(PATCH * n + x)
	for z in range(PATCH - 1, 0, -1): border.append(z * n)
	var base := verts.size()
	for i in border.size():
		verts.append(verts[border[i]])
		uv2.append(Vector2(1, 0))
	for i in border.size():
		var j := (i + 1) % border.size()
		var t0 := border[i]
		var t1 := border[j]
		var s0 := base + i
		var s1 := base + j
		idx.append_array([t0, s0, t1, t1, s0, s1])
		idx.append_array([t0, t1, s0, t1, s1, s0])   # both windings: skirts visible from either side
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(0, -100, 0), Vector3(1, world.h_range + 200, 1))
	return m

func _process(_dt: float) -> void:
	if camera == null or world == null:
		return
	var cp := camera.global_position
	material.set_shader_parameter("cam_pos", cp)
	# reselect when the camera moved or turned noticeably
	if cp.distance_squared_to(_last_cam) > 4.0 or Engine.get_process_frames() % 6 == 0:
		_last_cam = cp
		_select(cp)
	_update_collision()

func _select(cp: Vector3) -> void:
	_planes = camera.get_frustum()
	_count = 0
	if _sel.size() != mm.instance_count * 16:
		_sel.resize(mm.instance_count * 16)
	var root_size := LEAF * pow(2.0, LEVELS - 1)
	_visit(LEVELS - 1, 0, 0, root_size, cp)
	mm.buffer = _sel
	mm.visible_instance_count = _count

func _node_aabb(level: int, nx: int, nz: int, size: float) -> AABB:
	var grid: PackedFloat32Array = _pyr[level]
	var n := 64 >> level
	var o := (nz * n + nx) * 2
	var x0 := -world.size_m * 0.5 + nx * size
	var z0 := -world.size_m * 0.5 + nz * size
	return AABB(Vector3(x0, grid[o] - 2.0, z0), Vector3(size, grid[o + 1] - grid[o] + 4.0, size))

func _visible(box: AABB, cp: Vector3) -> bool:
	# never cull nodes near the camera (they may cast shadows into view)
	if _dist_to_box(cp, box) < 400.0:
		return true
	var c := box.get_center()
	var e := box.size * 0.5
	for p in _planes:
		var r := e.x * absf(p.normal.x) + e.y * absf(p.normal.y) + e.z * absf(p.normal.z)
		if p.distance_to(c) > r:
			return false
	return true

func _dist_to_box(p: Vector3, b: AABB) -> float:
	var q := p.clamp(b.position, b.end)
	return p.distance_to(q)

func _visit(level: int, nx: int, nz: int, size: float, cp: Vector3) -> void:
	var box := _node_aabb(level, nx, nz, size)
	if not _visible(box, cp):
		return
	if level > 0 and _dist_to_box(cp, box) < _ranges[level - 1]:
		var half := size * 0.5
		for c in 4:
			_visit(level - 1, nx * 2 + (c & 1), nz * 2 + (c >> 1), half, cp)
		return
	_emit(level, box.position.x, box.position.z, size)

func _emit(level: int, x0: float, z0: float, size: float) -> void:
	if _count >= mm.instance_count:
		return
	var o := _count * 16
	# Transform3D (basis rows + origin) in MultiMesh buffer layout: row-major 3x4
	_sel[o + 0] = size; _sel[o + 1] = 0.0; _sel[o + 2] = 0.0; _sel[o + 3] = x0
	_sel[o + 4] = 0.0; _sel[o + 5] = 1.0; _sel[o + 6] = 0.0; _sel[o + 7] = 0.0
	_sel[o + 8] = 0.0; _sel[o + 9] = 0.0; _sel[o + 10] = size; _sel[o + 11] = z0
	var r := _ranges[level]
	_sel[o + 12] = r * 0.72        # morph start
	_sel[o + 13] = r * 0.98        # morph end
	_sel[o + 14] = size / PATCH    # vertex spacing
	_sel[o + 15] = float(level)
	_count += 1

# ---------------------------------------------------------------- collision
func _update_collision() -> void:
	var want := {}
	for f in foci:
		if not is_instance_valid(f):
			continue
		var p := f.global_position
		var tx := floori((p.x + world.size_m * 0.5) / COLL_TILE)
		var tz := floori((p.z + world.size_m * 0.5) / COLL_TILE)
		var ring := COLL_RING if f == Game.player else 1
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				want[Vector2i(tx + dx, tz + dz)] = true
	var built := 0
	for k in want.keys():
		if not _coll_tiles.has(k) and built < 2:     # spread tile builds across frames
			_coll_tiles[k] = _build_coll_tile(k)
			built += 1
	for k in _coll_tiles.keys():
		if not want.has(k):
			_coll_tiles[k].queue_free()
			_coll_tiles.erase(k)

## Ensure collision exists right now around a point (spawns, teleports, tests).
func ensure_collision_at(p: Vector3) -> void:
	var tx := floori((p.x + world.size_m * 0.5) / COLL_TILE)
	var tz := floori((p.z + world.size_m * 0.5) / COLL_TILE)
	for dz in range(-COLL_RING, COLL_RING + 1):
		for dx in range(-COLL_RING, COLL_RING + 1):
			var k := Vector2i(tx + dx, tz + dz)
			if not _coll_tiles.has(k):
				_coll_tiles[k] = _build_coll_tile(k)

## Cheap variant for spawns: only the single tile under p (the focus ring fills in the rest over frames).
func ensure_tile(p: Vector3) -> void:
	var k := Vector2i(floori((p.x + world.size_m * 0.5) / COLL_TILE), floori((p.z + world.size_m * 0.5) / COLL_TILE))
	if not _coll_tiles.has(k):
		_coll_tiles[k] = _build_coll_tile(k)

func _build_coll_tile(k: Vector2i) -> CollisionShape3D:
	# 33x33 samples at 2 m (64 m tile); one shared sample row/column with neighbours
	var samples := int(COLL_TILE / world.cell) + 1
	var ix0 := k.x * (samples - 1)
	var iz0 := k.y * (samples - 1)
	var data := PackedFloat32Array()
	data.resize(samples * samples)
	for z in samples:
		for x in samples:
			data[z * samples + x] = world.sample(ix0 + x, iz0 + z)
	var shape := HeightMapShape3D.new()
	shape.map_width = samples
	shape.map_depth = samples
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# HeightMapShape3D is centred on its node; sample i sits at texel centre (i + 0.5) * cell
	var cx := -world.size_m * 0.5 + (ix0 + 0.5) * world.cell + COLL_TILE * 0.5
	var cz := -world.size_m * 0.5 + (iz0 + 0.5) * world.cell + COLL_TILE * 0.5
	cs.position = Vector3(cx, 0.0, cz)
	cs.scale = Vector3(world.cell, 1.0, world.cell)
	_coll_body.add_child(cs)
	return cs
