class_name Vegetation
extends Node3D
## Forests and grass. Trees are defined per 128 m "tree cell" (deterministic jittered lattice, species from
## altitude, latitude and noise, density from the forest mask). Near cells (within NEAR_CELLS) draw full meshes
## per species; impostor cells (768 m) draw one camera-facing card per tree out to the far distance. Each tree's
## own distance picks mesh or card in the shaders (dithered cross-fade), so cell edges never pop. Cell contents
## are built on worker threads. Grass is a GPU lattice that follows the camera (grass.gdshader).

const CELL := 128.0
const ICELL := 768.0
const SPACING := 7.0
const NEAR_END := 260.0
const VARIANTS := 3

var gen: WorldGen
var meshes: Array = []            # [species][variant] -> ArrayMesh
var leaf_mat: ShaderMaterial
var bark_mat: ShaderMaterial
var birch_bark_mat: ShaderMaterial
var imp_mat: ShaderMaterial
var imp_mesh: QuadMesh
var near := {}                    # Vector2i -> per species/variant buffers of that 128 m cell
var meshes_lod1: Array = []        # [species][variant], the coarser build (2-3.5x fewer triangles)
var solo := {}                    # Vector2i -> Node3D: cells within SOLO_R, full detail, culled per cell
const SOLO_R := 140.0
var supers := {}                  # Vector2i -> Node3D: the near trees of SUPER x SUPER cells in one MultiMesh per kind
var _dirty := {}                  # super-cells to rebuild
var SUPER := int(OS.get_environment("VEG_SUPER")) if OS.get_environment("VEG_SUPER") != "" else 3   # measured: per-cell MultiMeshes were ~1100 of 1360 draws in the battle view
var imps := {}                    # Vector2i -> MultiMeshInstance3D
var _pending := {}                # key -> task id
var _results := {}                # key -> data (filled by worker tasks)
var _mutex := Mutex.new()
var _focus := Vector3.ZERO
var _t := 0.0
var grass_near: MultiMeshInstance3D
var grass_mat: ShaderMaterial
var _baked := false
var extra := {}                   # Vector2i tree cell -> Array of placed trees (cities, gardens)
var exclude: Array = []           # [Vector2 centre, radius]: no wild trees inside (city podiums)


func setup(g: WorldGen) -> void:
	gen = g
	var atlas := ImageTexture.create_from_image(TreeBuilder.leaf_atlas())
	leaf_mat = ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/foliage.gdshader")
	leaf_mat.set_shader_parameter("albedo_tex", atlas)
	leaf_mat.set_shader_parameter("near_end", NEAR_END)
	bark_mat = ShaderMaterial.new()
	bark_mat.shader = leaf_mat.shader
	bark_mat.set_shader_parameter("albedo_tex", TreeBuilder.bark_texture(false))
	bark_mat.set_shader_parameter("is_leaf", false)
	bark_mat.set_shader_parameter("near_end", NEAR_END)
	birch_bark_mat = bark_mat.duplicate()
	birch_bark_mat.set_shader_parameter("albedo_tex", TreeBuilder.bark_texture(true))
	for lod in 2:
		var rows := []
		for sp in TreeBuilder.SPECIES:
			var row := []
			for v in VARIANTS:
				var m := TreeBuilder.build(sp, 100 + v, lod)
				var surf := 0
				if sp != TreeBuilder.BUSH:
					m.surface_set_material(0, birch_bark_mat if sp == TreeBuilder.BIRCH else bark_mat)
					surf = 1
				m.surface_set_material(surf, leaf_mat)
				row.append(m)
			rows.append(row)
		if lod == 0:
			meshes = rows
		else:
			meshes_lod1 = rows
	imp_mat = ShaderMaterial.new()
	imp_mat.shader = load("res://shaders/impostor.gdshader")
	imp_mat.set_shader_parameter("species_count", float(TreeBuilder.SPECIES))
	imp_mat.set_shader_parameter("near_start", NEAR_END)
	imp_mesh = QuadMesh.new()
	imp_mesh.size = Vector2(1, 1)
	imp_mesh.center_offset = Vector3(0, 0.5, 0)
	_setup_grass()
	Settings.changed.connect(_on_settings)
	_on_settings()
	if DisplayServer.get_name() != "headless":
		_bake_impostors()


func _on_settings() -> void:
	imp_mat.set_shader_parameter("far_end", float(Settings.q["tree_far"]))
	if grass_near:
		grass_near.visible = bool(Settings.q["grass"])
		_grass_far.visible = bool(Settings.q["grass"])
		grass_mat.set_shader_parameter("radius", float(Settings.q["grass_dist"]))


# ------------------------------------------------------------------------------------------- impostors

## Renders each species (variant 0) from the side into an atlas: albedo, then view-space normals.
func _bake_impostors() -> void:
	var w := 256
	var h := 512
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var bake: Shader = load("res://shaders/bake.gdshader")
	var albedo := Image.create(w * TreeBuilder.SPECIES, h, false, Image.FORMAT_RGBA8)
	var normal := Image.create(w * TreeBuilder.SPECIES, h, false, Image.FORMAT_RGBA8)
	for sp in TreeBuilder.SPECIES:
		var src: ArrayMesh = meshes[sp][0]
		var mi := MeshInstance3D.new()
		mi.mesh = src
		vp.add_child(mi)
		var aabb := src.get_aabb()
		var size := maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z) * 2.0)
		cam.size = size
		cam.position = Vector3(0, size * 0.5, 100.0)
		cam.near = 1.0
		cam.far = 300.0
		for mode in 2:
			var mats := []
			for s in src.get_surface_count():
				var m := ShaderMaterial.new()
				m.shader = bake
				m.set_shader_parameter("mode", mode)
				var is_leaf := s == src.get_surface_count() - 1
				m.set_shader_parameter("is_leaf", is_leaf)
				var base: ShaderMaterial = src.surface_get_material(s)
				m.set_shader_parameter("albedo_tex", base.get_shader_parameter("albedo_tex"))
				mi.set_surface_override_material(s, m)
				mats.append(m)
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			(albedo if mode == 0 else normal).blit_rect(img, Rect2i(0, 0, w, h), Vector2i(sp * w, 0))
		mi.queue_free()
		# Card height in metres for this species (the card is square in the atlas tile's aspect: 1 x 2).
		imp_scale[sp] = size
	vp.queue_free()
	_dilate(albedo)
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	imp_mat.set_shader_parameter("albedo_atlas", ImageTexture.create_from_image(albedo))
	imp_mat.set_shader_parameter("normal_atlas", ImageTexture.create_from_image(normal))
	_baked = true


var imp_scale := [24.0, 16.0, 15.0, 1.8]


## Spreads leaf colour into transparent texels so mipmaps do not darken the card edges.
func _dilate(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for pass_i in 4:
		var out := data.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var o := (y * w + x) * 4
				if data[o + 3] > 0:
					continue
				for d in [4, -4, w * 4, -w * 4]:
					var q: int = o + d
					if data[q + 3] > 0 or (pass_i > 0 and (data[q] + data[q + 1] + data[q + 2]) > 0):
						out[o] = data[q]; out[o + 1] = data[q + 1]; out[o + 2] = data[q + 2]
						break
		data = out
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


# ----------------------------------------------------------------------------------------- tree lists

## Trees in one 128 m cell: Array of [species, variant, Transform3D, tint, phase].
func add_trees(list: Array) -> void:
	for t in list:
		var p: Vector3 = (t[2] as Transform3D).origin
		var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not extra.has(k):
			extra[k] = []
		extra[k].append(t)


func _excluded(x: float, z: float) -> bool:
	for e in exclude:
		var c: Vector2 = e[0]
		if absf(x - c.x) < e[1] and absf(z - c.y) < e[1]:
			return true
	return false


func cell_trees(c: Vector2i, far: bool = false) -> Array:
	var out := []
	if extra.has(c):
		out.append_array(extra[c])
	if _excluded((c.x + 0.5) * CELL, (c.y + 0.5) * CELL):
		return out
	var n := int(CELL / SPACING)
	var x0 := c.x * CELL
	var z0 := c.y * CELL
	for j in n:
		for i in n:
			var hx := G.hash2(c.x * 64 + i, c.y * 64 + j, 11)
			var hz := G.hash2(c.x * 64 + i, c.y * 64 + j, 23)
			var x := x0 + (i + 0.15 + hx * 0.7) * SPACING
			var z := z0 + (j + 0.15 + hz * 0.7) * SPACING
			if not gen.in_world(x, z):
				continue
			var f := gen.forest_at(x, z)
			var r := G.hash2(c.x * 64 + i, c.y * 64 + j, 37)
			var lone := 0.012
			if r > smoothstep(0.05, 0.55, f) * 0.95 + lone:
				continue
			var h := gen.macro_height(x, z) if far else gen.height_at(x, z)
			if h < 2.0 or gen.water_at(x, z) > -100.0 or gen.urban_at(x, z) > 0.2:
				continue
			if gen.slope_at(x, z) > 0.65:
				continue
			var sp := _species(x, z, h, r)
			var v := int(G.hash2(c.x * 64 + i, c.y * 64 + j, 41) * VARIANTS) % VARIANTS
			var s := lerpf(0.75, 1.2, G.hash2(c.x * 64 + i, c.y * 64 + j, 53))
			var yaw := G.hash2(c.x * 64 + i, c.y * 64 + j, 61) * TAU
			var tilt := Basis(Vector3(1, 0, 0), (r - 0.5) * 0.05)
			var b := Basis(Vector3.UP, yaw) * tilt
			b = b.scaled(Vector3(s, s, s))
			out.append([sp, v, Transform3D(b, Vector3(x, h - 0.15, z)), G.hash2(i, j, c.x * 7 + c.y), r])
			# Undergrowth: bushes at forest edges and in clearings.
			if not far and f > 0.15 and f < 0.6 and G.hash2(i, j, 99 + c.x) < 0.35:
				var bx := x + (hx - 0.5) * 4.0
				var bz := z + (hz - 0.5) * 4.0
				var bh := gen.height_at(bx, bz)
				var bb := Basis(Vector3.UP, yaw * 3.0).scaled(Vector3.ONE * lerpf(0.8, 1.4, hz))
				out.append([TreeBuilder.BUSH, v, Transform3D(bb, Vector3(bx, bh - 0.1, bz)), hx, hz])
	return out


func _species(x: float, z: float, h: float, r: float) -> int:
	var north := clampf((-z - 1500.0) / 2500.0, 0.0, 1.0)
	var alt := clampf((h - 250.0) / 450.0, 0.0, 1.0)
	var spruce_p := maxf(north, alt) * 0.85 + 0.08
	var k := fposmod(r * 13.37, 1.0)
	if k < spruce_p:
		return TreeBuilder.SPRUCE
	return TreeBuilder.BIRCH if fposmod(r * 71.3, 1.0) < 0.33 else TreeBuilder.BROADLEAF


# ------------------------------------------------------------------------------------------- streaming

func is_settled() -> bool:
	return (_baked or DisplayServer.get_name() == "headless") and _pending.is_empty() and _results.is_empty()


func focus(p: Vector3) -> void:
	_focus = p
	_stream(p, true)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	if grass_near:
		grass_near.global_position = Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))
		_grass_far.global_position = Vector3(snappedf(p.x, 1.0), 0.0, snappedf(p.z, 1.0))
	_t += delta
	_collect()
	_update_solo(p)
	_rebuild_supers()
	if _t > 0.2:
		_t = 0.0
		_stream(p, false)


func _stream(p: Vector3, sync: bool) -> void:
	var near_cells := int(ceil((NEAR_END + 40.0) / CELL))
	var far := float(Settings.q["tree_far"])
	var cc := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var want_near := {}
	for dz in range(-near_cells, near_cells + 1):
		for dx in range(-near_cells, near_cells + 1):
			var k := cc + Vector2i(dx, dz)
			var center := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
			if center.distance_to(Vector2(p.x, p.z)) < NEAR_END + CELL:
				want_near[k] = true
	var ic := Vector2i(floori(p.x / ICELL), floori(p.z / ICELL))
	var ir := int(ceil(far / ICELL))
	var want_imp := {}
	if _baked:
		for dz in range(-ir, ir + 1):
			for dx in range(-ir, ir + 1):
				var k := ic + Vector2i(dx, dz)
				var center := Vector2((k.x + 0.5) * ICELL, (k.y + 0.5) * ICELL)
				if center.distance_to(Vector2(p.x, p.z)) < far + ICELL * 0.71 and absf(center.x) < WorldGen.HALF + ICELL and absf(center.y) < WorldGen.HALF + ICELL:
					want_imp[k] = true
	for k in near.keys():
		if not want_near.has(k):
			near.erase(k)
			_dirty[_super_of(k)] = true
	for k in imps.keys():
		if not want_imp.has(k):
			imps[k].queue_free()
			imps.erase(k)
	# Nearest first.
	var todo := []
	for k in want_near:
		if not near.has(k) and not _pending.has(["n", k]):
			todo.append(["n", k, Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL).distance_to(Vector2(p.x, p.z))])
	for k in want_imp:
		if not imps.has(k) and not _pending.has(["i", k]):
			todo.append(["i", k, Vector2((k.x + 0.5) * ICELL, (k.y + 0.5) * ICELL).distance_to(Vector2(p.x, p.z)) + 300.0])
	todo.sort_custom(func(a, b): return a[2] < b[2])
	var budget := 1000 if sync else 6
	for t in todo:
		if _pending.size() >= 8 and not sync:
			break
		if budget <= 0:
			break
		budget -= 1
		var key := [t[0], t[1]]
		_pending[key] = WorkerThreadPool.add_task(_build_task.bind(t[0], t[1]), false, "vegetation cell")
	if sync:
		for key in _pending.keys():
			WorkerThreadPool.wait_for_task_completion(_pending[key])
		_pending.clear()
		_collect()
		_update_solo(p)
		_rebuild_supers()


func _build_task(kind: String, k: Vector2i) -> void:
	var data: Variant
	if kind == "n":
		data = _near_buffers(cell_trees(k))
	else:
		var trees := []
		var per := int(ICELL / CELL)
		for dz in per:
			for dx in per:
				trees.append_array(cell_trees(Vector2i(k.x * per + dx, k.y * per + dz), true))
		data = _imp_buffer(trees)
	_mutex.lock()
	_results[[kind, k]] = data
	_mutex.unlock()


func _collect() -> void:
	_mutex.lock()
	var done := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for key in done:
		if _pending.has(key):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			_pending.erase(key)
		var kind: String = key[0]
		var k: Vector2i = key[1]
		if kind == "n":
			if near.has(k):
				continue
			near[k] = done[key]
			_dirty[_super_of(k)] = true
		else:
			if imps.has(k):
				continue
			var mmi := _make_imp(done[key])
			imps[k] = mmi


## Per species/variant transform buffers (12 floats + 4 custom per instance).
func _near_buffers(trees: Array) -> Dictionary:
	var out := {}
	for t in trees:
		var key: int = t[0] * VARIANTS + t[1]
		if not out.has(key):
			out[key] = PackedFloat32Array()
		var buf: PackedFloat32Array = out[key]
		_push(buf, t[2], t[3], t[4], t[0])
		out[key] = buf
	return out


func _imp_buffer(trees: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	for t in trees:
		var sp: int = t[0]
		if sp == TreeBuilder.BUSH:
			continue
		var tr: Transform3D = t[2]
		var s := tr.basis.get_scale().x * float(imp_scale[sp])
		_push(buf, Transform3D(Basis.IDENTITY.scaled(Vector3(s * 0.5, s, s * 0.5)), tr.origin), t[3], t[4], sp)
	return buf


func _push(buf: PackedFloat32Array, tr: Transform3D, tint: float, phase: float, sp: int) -> void:
	var b := tr.basis
	buf.append_array([b.x.x, b.y.x, b.z.x, tr.origin.x, b.x.y, b.y.y, b.z.y, tr.origin.y, b.x.z, b.y.z, b.z.z, tr.origin.z,
		float(sp), tint, phase, 0.0])


func _super_of(k: Vector2i) -> Vector2i:
	return Vector2i(floori(float(k.x) / SUPER), floori(float(k.y) / SUPER))


## Concatenates the member cells' buffers of each dirty super-cell into one MultiMesh per species/variant.
func _rebuild_supers() -> void:
	if _dirty.is_empty():
		return
	for sk in _dirty:
		if supers.has(sk):
			(supers[sk] as Node).queue_free()
			supers.erase(sk)
		var merged := {}
		for dz in SUPER:
			for dx in SUPER:
				var k := Vector2i(sk.x * SUPER + dx, sk.y * SUPER + dz)
				if not near.has(k) or solo.has(k):
					continue
				var bufs: Dictionary = near[k]
				for key in bufs:
					if not merged.has(key):
						merged[key] = PackedFloat32Array()
					var m: PackedFloat32Array = merged[key]
					m.append_array(bufs[key])
					merged[key] = m
		if not merged.is_empty():
			supers[sk] = _make_near(merged, meshes_lod1)
	_dirty.clear()


## Cells near the camera get their own full-detail MultiMeshes (they leave their super-cell, which is rebuilt).
func _update_solo(p: Vector3) -> void:
	for k in solo.keys():
		var c := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
		if not near.has(k) or c.distance_to(Vector2(p.x, p.z)) > SOLO_R + 20.0:
			(solo[k] as Node).queue_free()
			solo.erase(k)
			_dirty[_super_of(k)] = true
	for k in near:
		if solo.has(k):
			continue
		var c := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
		if c.distance_to(Vector2(p.x, p.z)) < SOLO_R:
			solo[k] = _make_near(near[k], meshes)
			_dirty[_super_of(k)] = true


func _make_near(bufs: Dictionary, mset: Array) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	for key in bufs:
		var buf: PackedFloat32Array = bufs[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mset[key / VARIANTS][key % VARIANTS]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)
	return root


func _make_imp(buf: PackedFloat32Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = imp_mesh
	mm.instance_count = buf.size() / 16
	if mm.instance_count > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = imp_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ----------------------------------------------------------------------------------------------- grass

func _setup_grass() -> void:
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	# Two lattices: dense fine clumps near the camera, sparser wider clumps further out.
	grass_near = _grass_lattice(_grass_clump(16, 0.55, 7), 0.5, 20.0, 0.0, "GrassNear")
	_grass_far = _grass_lattice(_grass_clump(9, 0.9, 8), 1.0, 96.0, 18.0, "GrassFar")


var _grass_far: MultiMeshInstance3D


func _grass_lattice(clump: ArrayMesh, step: float, r_out: float, r_in: float, nm: String) -> MultiMeshInstance3D:
	var buf := PackedFloat32Array()
	var n := int(r_out / step)
	for z in range(-n, n + 1):
		for x in range(-n, n + 1):
			var d := Vector2(x, z).length() * step
			if d > r_out or d < r_in:
				continue
			buf.append_array([1, 0, 0, x * step, 0, 1, 0, 0, 0, 0, 1, z * step, G.hash2(x, z, 5) * 100.0, step, 0, 0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = clump
	mm.instance_count = buf.size() / 16
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-r_out - 10, -100, -r_out - 10), Vector3(r_out * 2 + 20, 3000, r_out * 2 + 20))
	add_child(mmi)
	return mmi


## One clump: thin bent blades (three segments each) spread over `spread` metres.
func _grass_clump(blades: int, spread: float, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for b in blades:
		var a := rng.randf() * TAU
		var base := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread)) * 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := rng.randf_range(0.28, 0.62)
		var w := rng.randf_range(0.012, 0.022)
		var lean := rng.randf_range(0.08, 0.3)
		var pts := []
		for s in 4:
			var t := s / 3.0
			var c := base + dir * lean * t * t + Vector3(0, h * t, 0)
			var ww := w * (1.0 - t * 0.85)
			pts.append([c - side * ww, c + side * ww, t])
		for s in 3:
			var p0: Array = pts[s]
			var p1: Array = pts[s + 1]
			for v in [[p0[0], p0[2]], [p0[1], p0[2]], [p1[1], p1[2]], [p0[0], p0[2]], [p1[1], p1[2]], [p1[0], p1[2]]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0, 1.0 - v[1]))
				st.add_vertex(v[0])
	return st.commit()
