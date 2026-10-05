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
var proxies: Array = []            # [species][variant]: ~20-triangle shadow casters for the outer ring
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
var grass_near: Node3D
var grass_mat: ShaderMaterial
var _baked := false
var extra := {}                   # Vector2i tree cell -> Array of placed trees (cities, gardens)
var exclude: Array = []           # [Vector2 centre, radius]: no wild trees inside (city podiums)
# Trunks: trees had no collision (the player, crawlers, bullets and the battle's soldiers went through them).
# Each near cell's build also returns its trunks in 8 m buckets ({Vector2i: [x, z, r, ...]}); cells near the player
# get a static physics body of shared cylinders on TRUNK_LAYER, and soldiers step around trunks via avoid().
const TRUNK_LAYER := 16
const TRUNK_R := [0.46, 0.6, 0.31, 0.0]       # base radius at scale 1: spruce, broadleaf, birch, bush (none)
const TRUNK_BUCKET := 8.0
const TRUNK_BODY_R := 60.0                     # cells whose square comes this close to the player get a body
var trunks := {}                  # Vector2i cell -> {Vector2i bucket: PackedFloat32Array}
var _tbodies := {}                # Vector2i cell -> body RID
var _tshapes := {}                # quantised radius -> cylinder shape RID
# Felled trees (a crawler drives through them): their 10 cm-rounded positions, kept so a cell rebuilt later leaves
# them out; the build tasks get a copy (worker threads never read the live dictionary).
var _felled := {}
var felled := 0
var _falling: Array = []          # [MultiMeshInstance3D, base Transform3D, axis, t, buffer]


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
	var proxy_mat := StandardMaterial3D.new()
	proxy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sp in TreeBuilder.SPECIES:
		var row := []
		for v in VARIANTS:
			row.append(_shadow_proxy(sp, (meshes_lod1[sp][v] as ArrayMesh).get_aabb(), proxy_mat))
		proxies.append(row)
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
		var gd := float(Settings.q["grass_dist"])
		# The far ring is built only out to the preset's grass distance (it was a fixed 96 m; High draws 70).
		if gd > 0.0 and absf(gd - _far_r) > 0.5:
			var old := _grass_far
			_grass_far = _grass_lattice(_far_clump, 1.0, gd + 2.0, 18.0, "GrassFar", 32.0)
			_far_r = gd
			if old:
				_grass_far.global_position = old.global_position
				old.queue_free()
		grass_near.visible = bool(Settings.q["grass"])
		if _grass_far:
			_grass_far.visible = bool(Settings.q["grass"])
		grass_mat.set_shader_parameter("radius", gd)


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


func cell_trees(c: Vector2i, far: bool = false, skip: Dictionary = {}) -> Array:
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
			# Tree line: thinning from 950 m to none at 1200 m, lone trees included (they stood on the snowfields
			# under the 1300 m snow line).
			if h > 950.0 and G.hash2(c.x * 64 + i, c.y * 64 + j, 71) > 1.0 - smoothstep(950.0, 1200.0, h):
				continue
			if not skip.is_empty() and skip.has(Vector2i(roundi(x * 10.0), roundi(z * 10.0))):
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
		var gy := snappedf(gen.height_at(p.x, p.z), 4.0)
		grass_near.global_position = Vector3(snappedf(p.x, 0.5), gy, snappedf(p.z, 0.5))
		if _grass_far:
			_grass_far.global_position = Vector3(snappedf(p.x, 1.0), gy, snappedf(p.z, 1.0))
	_t += delta
	_collect()
	_update_solo(p)
	_rebuild_supers()
	_update_trunk_bodies()
	if not _falling.is_empty():
		_update_falling(delta)
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
			trunks.erase(k)
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
		_pending[key] = WorkerThreadPool.add_task(_build_task.bind(t[0], t[1], _felled.duplicate()), false, "vegetation cell")
	if sync:
		for key in _pending.keys():
			WorkerThreadPool.wait_for_task_completion(_pending[key])
		_pending.clear()
		_collect()
		_update_solo(p)
		_rebuild_supers()


func _build_task(kind: String, k: Vector2i, skip: Dictionary = {}) -> void:
	var data: Variant
	if kind == "n":
		var list := cell_trees(k, false, skip)
		data = [_near_buffers(list), _trunk_buckets(list)]
	else:
		var trees := []
		var per := int(ICELL / CELL)
		for dz in per:
			for dx in per:
				trees.append_array(cell_trees(Vector2i(k.x * per + dx, k.y * per + dz), true, skip))
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
			near[k] = done[key][0]
			trunks[k] = done[key][1]
			_dirty[_super_of(k)] = true
		else:
			if imps.has(k):
				continue
			var mmi := _make_imp(done[key])
			imps[k] = mmi


## Trunks of a cell in 8 m buckets; a trunk goes in every bucket its disc (plus a soldier's radius) touches, so a
## lookup reads one bucket.
func _trunk_buckets(trees: Array) -> Dictionary:
	var out := {}
	for t in trees:
		var r: float = TRUNK_R[t[0]]
		if r <= 0.0:
			continue
		var tr: Transform3D = t[2]
		r *= tr.basis.get_scale().x
		var o := tr.origin
		var reach := r + 0.5
		for bz in range(floori((o.z - reach) / TRUNK_BUCKET), floori((o.z + reach) / TRUNK_BUCKET) + 1):
			for bx in range(floori((o.x - reach) / TRUNK_BUCKET), floori((o.x + reach) / TRUNK_BUCKET) + 1):
				var b := Vector2i(bx, bz)
				if not out.has(b):
					out[b] = PackedFloat32Array()
				var a: PackedFloat32Array = out[b]
				a.append_array([o.x, o.z, r])
				out[b] = a
	return out


## Pushes a walker at p (radius `rad`) out of any trunk and slides it round: returns the corrected position. The
## sideways nudge keeps a soldier heading straight at a trunk from stopping dead behind it.
func avoid(p: Vector3, rad: float) -> Vector3:
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var cell: Variant = trunks.get(k)
	if cell == null:
		return p
	var a: Variant = (cell as Dictionary).get(Vector2i(floori(p.x / TRUNK_BUCKET), floori(p.z / TRUNK_BUCKET)))
	if a == null:
		return p
	var arr: PackedFloat32Array = a
	for j in range(0, arr.size(), 3):
		var dx := p.x - arr[j]
		var dz := p.z - arr[j + 1]
		var rr := arr[j + 2] + rad
		var d2 := dx * dx + dz * dz
		if d2 >= rr * rr:
			continue
		var d := sqrt(d2)
		if d < 0.001:
			dx = 1.0
			dz = 0.0
			d = 1.0
		var push := rr - d
		# Out along the normal, plus as much along the tangent (always the same hand, so it does not dither).
		p.x += (dx - dz) / d * push
		p.z += (dz + dx) / d * push
	return p


## Fells every trunk within `radius` of p (a crawler's front edge): the tree leaves the cell's instances and its
## trunk body, and a copy of it tips over away from `dir` (the vehicle's travel). Returns how many fell.
func fell_near(p: Vector3, radius: float, dir: Vector3) -> int:
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not trunks.has(k):
		return 0
	var hits: Array = []
	var seen := {}
	for bz in range(floori((p.z - radius) / TRUNK_BUCKET), floori((p.z + radius) / TRUNK_BUCKET) + 1):
		for bx in range(floori((p.x - radius) / TRUNK_BUCKET), floori((p.x + radius) / TRUNK_BUCKET) + 1):
			var arr: Variant = (trunks[k] as Dictionary).get(Vector2i(bx, bz))
			if arr == null:
				continue
			var a: PackedFloat32Array = arr
			for j in range(0, a.size(), 3):
				var tk := Vector2i(roundi(a[j] * 10.0), roundi(a[j + 1] * 10.0))
				if seen.has(tk):
					continue
				if Vector2(a[j] - p.x, a[j + 1] - p.z).length() < radius + a[j + 2]:
					seen[tk] = true
					hits.append(Vector2(a[j], a[j + 1]))
	for h in hits:
		_fell(k, h, dir)
	return hits.size()


func _fell(k: Vector2i, at: Vector2, dir: Vector3) -> void:
	var tk := Vector2i(roundi(at.x * 10.0), roundi(at.y * 10.0))
	_felled[tk] = true
	felled += 1
	# Out of the trunk buckets (it sits in every bucket its disc touched) and the cell's collision body.
	var cell: Dictionary = trunks[k]
	for b in cell.keys():
		var a: PackedFloat32Array = cell[b]
		var out := PackedFloat32Array()
		for j in range(0, a.size(), 3):
			if Vector2i(roundi(a[j] * 10.0), roundi(a[j + 1] * 10.0)) != tk:
				out.append_array([a[j], a[j + 1], a[j + 2]])
		cell[b] = out
	if _tbodies.has(k):
		PhysicsServer3D.free_rid(_tbodies[k])
		_tbodies[k] = _trunk_body(k)
	# Out of the cell's instance buffers; remember its row to drop a falling copy.
	var row := PackedFloat32Array()
	var mesh: Mesh = null
	if near.has(k):
		var bufs: Dictionary = near[k]
		for key in bufs:
			var buf: PackedFloat32Array = bufs[key]
			for i in range(0, buf.size(), 16):
				if absf(buf[i + 3] - at.x) < 0.06 and absf(buf[i + 11] - at.y) < 0.06:
					row = buf.slice(i, i + 16)
					mesh = meshes[key / VARIANTS][key % VARIANTS]
					var nb := buf.slice(0, i)
					nb.append_array(buf.slice(i + 16))
					bufs[key] = nb
					break
			if mesh:
				break
		if solo.has(k):
			(solo[k] as Node).queue_free()
			solo[k] = _make_near(near[k], meshes)
		else:
			_dirty[_super_of(k)] = true
	if mesh == null:
		return
	var base := Transform3D(Basis(Vector3(row[0], row[4], row[8]), Vector3(row[1], row[5], row[9]), Vector3(row[2], row[6], row[10])),
		Vector3(row[3], row[7], row[11]))
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		flat = Vector3.FORWARD
	var axis := Vector3.UP.cross(flat.normalized()).normalized()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.buffer = row
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-40, -40, -40) + base.origin, Vector3(80, 80, 80))
	add_child(mmi)
	_falling.append([mmi, base, axis, 0.0, row])
	if G.fx:
		var o := base.origin
		G.fx.impact(o + Vector3(0, 0.5, 0), Vector3.UP, false)
	Sfx.play_at("tree_fall", base.origin, -2.0, randf_range(0.9, 1.1))


## Felled trees tip over (accelerating, about 2 s to the ground) and lie there for 40 s.
func _update_falling(delta: float) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		var f: Array = _falling[i]
		f[3] += delta
		var mmi: MultiMeshInstance3D = f[0]
		if f[3] > 42.0 or not is_instance_valid(mmi):
			if is_instance_valid(mmi):
				mmi.queue_free()
			_falling.remove_at(i)
			continue
		var u := clampf(f[3] / 2.0, 0.0, 1.0)
		var ang := (PI * 0.47) * u * u
		var base: Transform3D = f[1]
		var b := Basis(f[2] as Vector3, ang) * base.basis
		var row: PackedFloat32Array = f[4]
		row[0] = b.x.x; row[1] = b.y.x; row[2] = b.z.x
		row[4] = b.x.y; row[5] = b.y.y; row[6] = b.z.y
		row[8] = b.x.z; row[9] = b.y.z; row[10] = b.z.z
		f[4] = row
		mmi.multimesh.buffer = row


## Static trunk colliders for the cells around the player (or the camera when there is none).
func _update_trunk_bodies() -> void:
	if (G.frame % 10) != 0:
		return
	var anchor: Vector3
	if G.player and is_instance_valid(G.player):
		anchor = (G.player as Node3D).global_position
		var v: Variant = G.player.get("vehicle")
		if v is Node3D and is_instance_valid(v):
			anchor = (v as Node3D).global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		anchor = cam.global_position
	var want := {}
	var cc := Vector2i(floori(anchor.x / CELL), floori(anchor.z / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := cc + Vector2i(dx, dz)
			var qx := clampf(anchor.x, k.x * CELL, (k.x + 1) * CELL)
			var qz := clampf(anchor.z, k.y * CELL, (k.y + 1) * CELL)
			if Vector2(qx - anchor.x, qz - anchor.z).length() < TRUNK_BODY_R and trunks.has(k):
				want[k] = true
	for k in _tbodies.keys():
		if not want.has(k):
			PhysicsServer3D.free_rid(_tbodies[k])
			_tbodies.erase(k)
	# One new body per update (up to ~300 shapes each), the player's own cell first.
	if want.has(cc) and not _tbodies.has(cc):
		_tbodies[cc] = _trunk_body(cc)
		return
	for k in want:
		if not _tbodies.has(k):
			_tbodies[k] = _trunk_body(k)
			return


func _trunk_body(k: Vector2i) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	PhysicsServer3D.body_set_collision_layer(body, TRUNK_LAYER)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var seen := {}
	for b in trunks[k]:
		var arr: PackedFloat32Array = trunks[k][b]
		for j in range(0, arr.size(), 3):
			var x := arr[j]
			var z := arr[j + 1]
			var tk := Vector2(x, z)
			if seen.has(tk):
				continue
			seen[tk] = true
			var q := clampi(roundi(arr[j + 2] * 20.0), 3, 30)
			if not _tshapes.has(q):
				var sh := PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(sh, {"radius": q / 20.0, "height": 9.0})
				_tshapes[q] = sh
			var y := gen.height_at(x, z)
			PhysicsServer3D.body_add_shape(body, _tshapes[q], Transform3D(Basis.IDENTITY, Vector3(x, y + 3.5, z)))
	return body


func _exit_tree() -> void:
	for k in _tbodies:
		PhysicsServer3D.free_rid(_tbodies[k])
	_tbodies.clear()
	for q in _tshapes:
		PhysicsServer3D.free_rid(_tshapes[q])
	_tshapes.clear()


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
			supers[sk] = _make_near(merged, meshes_lod1, proxies)
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


## One MultiMesh per species/variant. With `shadow_set`, the trees themselves cast no shadow and a second
## MultiMesh of low-poly proxies (shadows only) does: measured, tree shadows were 6.5 of 11 M primitives in the
## forest view.
func _make_near(bufs: Dictionary, mset: Array, shadow_set: Array = []) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	for key in bufs:
		var buf: PackedFloat32Array = bufs[key]
		for pass_i in (2 if not shadow_set.is_empty() else 1):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			var src: Array = mset if pass_i == 0 else shadow_set
			mm.mesh = src[key / VARIANTS][key % VARIANTS]
			mm.instance_count = buf.size() / 16
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if shadow_set.is_empty():
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif pass_i == 0:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			root.add_child(mmi)
	return root


## A shadow caster fitted to a tree's bounds: a six-sided cone for spruce, a double cone (crown) for the rest,
## and a thin three-sided trunk.
func _shadow_proxy(sp: int, b: AABB, m: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := b.size.y
	var y0 := b.position.y
	var top := Vector3(0, b.end.y, 0)
	var r := maxf(b.size.x, b.size.z) * 0.5 * 0.85
	var ring_y := y0 + h * (0.14 if sp == TreeBuilder.SPRUCE else 0.6)
	var low := Vector3(0, y0 + h * (0.14 if sp == TreeBuilder.SPRUCE else 0.3), 0)
	if sp == TreeBuilder.BUSH:
		ring_y = y0 + h * 0.45
		low = Vector3(0, y0, 0)
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(Vector3(cos(a) * r, ring_y, sin(a) * r))
	for i in 6:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 6]
		st.add_vertex(top); st.add_vertex(p1); st.add_vertex(p0)
		st.add_vertex(low); st.add_vertex(p0); st.add_vertex(p1)
	if sp != TreeBuilder.BUSH:
		var tr := h * 0.03
		for i in 3:
			var a0 := TAU * i / 3.0
			var a1 := TAU * (i + 1) / 3.0
			var q0 := Vector3(cos(a0) * tr, y0, sin(a0) * tr)
			var q1 := Vector3(cos(a1) * tr, y0, sin(a1) * tr)
			var u0 := Vector3(q0.x, low.y, q0.z)
			var u1 := Vector3(q1.x, low.y, q1.z)
			st.add_vertex(q0); st.add_vertex(u1); st.add_vertex(q1)
			st.add_vertex(q0); st.add_vertex(u0); st.add_vertex(u1)
	st.generate_normals()
	st.set_material(m)
	return st.commit()


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
	grass_near = _grass_lattice(_grass_clump(16, 0.55, 7), 0.5, 20.0, 0.0, "GrassNear", 20.0)
	_far_clump = _grass_clump(9, 0.9, 8)


var _grass_far: Node3D
var _far_clump: ArrayMesh
var _far_r := -1.0


## A ring of clumps around the camera, cut into square tiles so frustum culling drops the tiles behind and beside
## the view (one MultiMesh for the whole ring had one bounding box: every clump of the full circle was drawn; the
## CI Mac's ablation measured grass at 9.2 of 23.9 ms in the battle view).
func _grass_lattice(clump: ArrayMesh, step: float, r_out: float, r_in: float, nm: String, tile: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	var tiles := {}
	var n := int(r_out / step)
	for z in range(-n, n + 1):
		for x in range(-n, n + 1):
			var d := Vector2(x, z).length() * step
			if d > r_out or d < r_in:
				continue
			var k := Vector2i(floori(x * step / tile), floori(z * step / tile))
			if not tiles.has(k):
				tiles[k] = PackedFloat32Array()
			var buf: PackedFloat32Array = tiles[k]
			buf.append_array([1, 0, 0, x * step, 0, 1, 0, 0, 0, 0, 1, z * step, G.hash2(x, z, 5) * 100.0, step, 0, 0])
			tiles[k] = buf
	for k in tiles:
		var buf: PackedFloat32Array = tiles[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = clump
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = grass_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The clumps find their own ground height in the shader; the holder rides at the ground height under the
		# camera, so the box only spans the relief within the ring (a box over every terrain height defeated the
		# frustum's side planes).
		mmi.custom_aabb = AABB(Vector3(k.x * tile - 2.0, -200.0, k.y * tile - 2.0), Vector3(tile + 4.0, 400.0, tile + 4.0))
		holder.add_child(mmi)
	add_child(holder)
	return holder


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
