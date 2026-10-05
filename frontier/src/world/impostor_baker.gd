class_name ImpostorBaker
extends RefCounted
## Bakes the distant-tree impostors from the game's own procedural tree meshes (src/world/tree_gen.gd) with their
## real materials (shaders/foliage.gdshader compiled with IMPOSTOR_BAKE): every species x variant seen from
## TREE_VIEWS (trees) or SHRUB_VIEWS (shrubs) azimuths at ground level, into two atlases with the same layout:
##   albedo: premultiplied sRGB colour (stored at half scale) + coverage
##   normal: premultiplied view-space normal xy, blue = depth * 0.5 (+ 0.5 for leaves) + coverage
## One bake = one orthographic render of a world that holds every view twice as instances (albedo half / normal
## half of one SubViewport), supersampled 2x, then one canvas pass that resolves it with premultiplied alpha
## (shaders/impostor_post.gdshader). The atlases are cached in user://impostors keyed by a hash of the tree
## generator parameters, the foliage shader and this layout. shaders/impostor_tree.gdshader draws them.

const VERSION := 5
const SS := 2                                  # bake supersampling
const TREE_CELL := Vector2i(80, 160)           # px per view at 1x (trees: tall cells)
const SHRUB_CELL := Vector2i(80, 80)
const TREE_VIEWS := 8
const SHRUB_VIEWS := 4
const ATLAS_W := 1920                          # 24 tree views or 24 shrub views per row; cells stay 16-px aligned
const MARGIN := 0.04                           # empty border around the tree in its cell (fraction of size)
const CACHE_DIR := "user://impostors"

var albedo: Texture2D
var normal: Texture2D
var atlas_size := Vector2i.ZERO
## Per entry (species index * variants + variant), as shader arrays:
var entry_rect := PackedVector4Array()   # uv of view 0's cell (x, y) and cell size in uv (z, w)
var entry_frame := PackedVector4Array()  # x frame height S (m, at scale 1), y fraction of S below the base, z cell aspect w/h, w views
var entry_crown := PackedVector4Array()  # x crown radius, y crown bottom, z crown height, w tree height (m)
var bake_ms := 0.0
var from_cache := false
var bytes := 0

var _draw_us := 0
var _entries := []        # {mesh, views, cell, pos (px), S, base, radius, shrub}

## meshes: species -> [ArrayMesh per variant] (materials already set). Returns false if nothing could be baked.
func bake(host: Node, meshes: Dictionary, species_list: Array, variants: int) -> bool:
	var t0 := Time.get_ticks_usec()
	_layout(meshes, species_list, variants)
	var key := _cache_key(species_list, variants)
	var detail := ""
	if not _load_cache(key):
		_measure()
		var t1 := Time.get_ticks_usec()
		if not _render(host):
			return false
		var t2 := Time.get_ticks_usec()
		_save_cache(key)
		detail = " (measure %.0f, render+readback+mips %.0f [draw %.0f], cache write %.0f ms)" % [(t1 - t0) / 1000.0,
			(t2 - t1) / 1000.0, _draw_us / 1000.0, (Time.get_ticks_usec() - t2) / 1000.0]
	_fill_arrays()
	bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	bytes = _atlas_bytes()
	print("impostors: %d entries, atlas %dx%d x2 RGBA8 + mips = %.1f MB, %s in %.0f ms%s" % [_entries.size(),
		atlas_size.x, atlas_size.y, bytes / 1048576.0, "loaded from cache" if from_cache else "baked", bake_ms, detail])
	return true

## Crown shape code for the impostor's self-shadowing (shaders/impostor_tree.gdshader): 0 leafless, 1 cone, 2 rounded
## cone, 3 round/oval, 4 dome (shrubs).
static func crown_shape(spec: Dictionary) -> float:
	if spec.leaf == "":
		return 0.0
	return {"cone": 1.0, "cone_round": 2.0, "round": 3.0, "oval": 3.0, "bush": 4.0}.get(spec.crown, 3.0)

# ------------------------------------------------------------------ layout
func _layout(meshes: Dictionary, species_list: Array, variants: int) -> void:
	_entries.clear()
	for sp in species_list:
		var shrub: bool = TreeGen.SPECIES[sp].crown == "bush"
		for v in variants:
			_entries.append({"mesh": meshes[sp][v], "species": sp, "shrub": shrub, "views": SHRUB_VIEWS if shrub else TREE_VIEWS,
				"cell": SHRUB_CELL if shrub else TREE_CELL, "S": 1.0, "base": 0.0, "crown": Vector4(1, 1, 1, 1)})
	# shelf packing: all tree rows first, then shrub rows (cells of one row share a height)
	var y := 0
	for pass_shrub in [false, true]:
		var x := 0
		var row_h := 0
		for e in _entries:
			if e.shrub != pass_shrub:
				continue
			var w: int = e.views * e.cell.x
			if x + w > ATLAS_W:
				x = 0
				y += row_h
				row_h = 0
			e["pos"] = Vector2i(x, y)
			x += w
			row_h = maxi(row_h, e.cell.y)
		y += row_h
	atlas_size = Vector2i(ATLAS_W, y)

## Frame per entry: tallest extent and widest radius around the trunk axis, fitted to the cell aspect, base at the
## bottom margin. Exact over every vertex so no leaf card pokes into the neighbouring cell.
func _measure() -> void:
	for e in _entries:
		var m: ArrayMesh = e.mesh
		var ymin := 0.0
		var ymax := 0.5
		var r2 := 0.01
		for s in m.get_surface_count():
			var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in verts:
				r2 = maxf(r2, p.x * p.x + p.z * p.z)
				ymin = minf(ymin, p.y)
				ymax = maxf(ymax, p.y)
		var h := ymax - ymin
		var start: float = 0.0 if e.shrub else float(TreeGen.SPECIES[e.species].start)
		e["crown"] = Vector4(sqrt(r2), ymax * start, maxf(ymax * (1.0 - start), 0.3), ymax)
		var asp: float = float(e.cell.x) / e.cell.y
		var S := maxf(h * (1.0 + 2.0 * MARGIN), 2.0 * sqrt(r2) * (1.0 + 2.0 * MARGIN) / asp)
		e.S = S
		e.base = (-ymin + h * MARGIN) / S

func _fill_arrays() -> void:
	entry_rect = PackedVector4Array()
	entry_frame = PackedVector4Array()
	entry_crown = PackedVector4Array()
	var inv := Vector2(1.0 / atlas_size.x, 1.0 / atlas_size.y)
	for e in _entries:
		entry_rect.append(Vector4(e.pos.x * inv.x, e.pos.y * inv.y, e.cell.x * inv.x, e.cell.y * inv.y))
		entry_frame.append(Vector4(e.S, e.base, float(e.cell.x) / e.cell.y, e.views))
		entry_crown.append(e.crown)

func _atlas_bytes() -> int:
	return int(atlas_size.x * atlas_size.y * 4 * 2 * 4.0 / 3.0)

# ------------------------------------------------------------------ render
func _render(host: Node) -> bool:
	# one world, one orthographic camera, one viewport: albedo views in the top half, the same views again for the
	# normal pass in the bottom half (INSTANCE_CUSTOM.x picks the output in the bake shader)
	var size := Vector2i(atlas_size.x, atlas_size.y * 2) * SS
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.scaling_3d_scale = 1.0
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = atlas_size.y * 2
	cam.near = 1.0
	cam.far = 20000.0
	cam.position = Vector3(atlas_size.x * 0.5, -atlas_size.y, 10000.0)
	vp.add_child(cam)
	cam.current = true
	# node transform changes reach the renderer only when the scene tree flushes them (end of frame); the bake draws
	# right now, so hand the camera transform to the RenderingServer directly (the instances sit at the origin)
	RenderingServer.camera_set_transform(cam.get_camera_rid(), cam.global_transform)
	# bake variant of the real materials: same parameters, foliage shader compiled with IMPOSTOR_BAKE; swapped onto
	# the mesh surfaces for the bake and restored afterwards
	var sh := Shader.new()
	sh.code = (load("res://shaders/foliage.gdshader") as Shader).code.replace("shader_type spatial;", "shader_type spatial;\n#define IMPOSTOR_BAKE")
	var bake_mats := {}
	var restore := []
	for e in _entries:
		var m: ArrayMesh = e.mesh
		for si in m.get_surface_count():
			var base_mat: Material = m.surface_get_material(si)
			restore.append([m, si, base_mat])
			if not bake_mats.has(base_mat):
				var bm: ShaderMaterial = base_mat.duplicate()
				bm.shader = sh
				bake_mats[base_mat] = bm
			m.surface_set_material(si, bake_mats[base_mat])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = e.views * 2
		var s: float = e.cell.y / e.S                       # px per metre
		for pass_i in 2:
			for k in e.views:
				var cx: float = e.pos.x + (k + 0.5) * e.cell.x
				var by: float = -(e.pos.y + e.cell.y + pass_i * atlas_size.y) + e.base * e.cell.y
				# view k looks at the tree from azimuth k*TAU/views (tree-local): turn the tree the other way
				var b := Basis(Vector3.UP, -TAU * k / e.views).scaled(Vector3(s, s, s))
				var idx: int = pass_i * e.views + k
				mm.set_instance_transform(idx, Transform3D(b, Vector3(cx, by, 0.0)))
				mm.set_instance_custom_data(idx, Color(pass_i, e.crown.x, e.crown.y, e.crown.z))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(mmi)
	# resolve: one canvas pass, albedo on top (sRGB), normal below (raw)
	var post := SubViewport.new()
	post.size = Vector2i(atlas_size.x, atlas_size.y * 2)
	post.transparent_bg = true
	post.disable_3d = true
	post.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(post)
	# a raw canvas item: Control drawing is deferred to the end of the frame, the bake draws right now
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/impostor_post.gdshader")
	pm.set_shader_parameter("src", vp.get_texture())
	var ci := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ci, post.world_2d.canvas)
	RenderingServer.canvas_item_set_material(ci, pm.get_rid())
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2.ZERO, Vector2(post.size)), Color.WHITE)
	# draw these viewports now (sub-viewports only draw with their parent, so the game view stays active with its 3D
	# off for the two bake frames)
	var root_vp := host.get_viewport().get_viewport_rid()
	var root_3d_off: bool = host.get_viewport().disable_3d
	RenderingServer.viewport_set_disable_3d(root_vp, true)
	var td := Time.get_ticks_usec()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	post.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	var img := post.get_texture().get_image()
	_draw_us = Time.get_ticks_usec() - td
	RenderingServer.viewport_set_disable_3d(root_vp, root_3d_off)
	for r in restore:
		r[0].surface_set_material(r[1], r[2])
	RenderingServer.free_rid(ci)
	vp.queue_free()
	post.queue_free()
	if img == null or img.is_empty():
		push_warning("impostors: bake readback failed")
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var a := img.get_region(Rect2i(0, 0, atlas_size.x, atlas_size.y))
	var n := img.get_region(Rect2i(0, atlas_size.y, atlas_size.x, atlas_size.y))
	a.generate_mipmaps()
	n.generate_mipmaps()
	_set_images(a, n)
	return true

func _set_images(a: Image, n: Image) -> void:
	albedo = ImageTexture.create_from_image(a)
	normal = ImageTexture.create_from_image(n)
	_last_images = [a, n]

var _last_images := []

## Debug/test: the atlases as images (only valid right after a bake or cache load).
func images() -> Array:
	return _last_images

func release_images() -> void:
	_last_images = []

# ------------------------------------------------------------------ cache
func _cache_key(species_list: Array, variants: int) -> String:
	var parts := [VERSION, SS, TREE_CELL, SHRUB_CELL, TREE_VIEWS, SHRUB_VIEWS, ATLAS_W, MARGIN, variants, species_list,
		var_to_str(TreeGen.SPECIES), load("res://shaders/foliage.gdshader").code.md5_text(),
		load("res://shaders/impostor_post.gdshader").code.md5_text()]
	var gen := FileAccess.get_file_as_string("res://src/world/tree_gen.gd")    # empty in exported builds: fine
	parts.append(gen.md5_text())
	return var_to_str(parts).md5_text().substr(0, 16)

func _cache_path(key: String) -> String:
	return CACHE_DIR.path_join("trees_%s.bin" % key)

func _load_cache(key: String) -> bool:
	if Game.args.has("rebake"):
		return false
	var f := FileAccess.open_compressed(_cache_path(key), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var meta = f.get_var()
	if typeof(meta) != TYPE_DICTIONARY or meta.get("count", -1) != _entries.size() or meta.get("size") != atlas_size \
			or not meta.has("crown"):
		return false
	for i in _entries.size():
		_entries[i].S = meta.S[i]
		_entries[i].base = meta.base[i]
		_entries[i].crown = meta.crown[i]
	var imgs := []
	for k in 2:
		var len := f.get_32()
		var data := f.get_buffer(len)
		if data.size() != len:
			return false
		var img := Image.create_from_data(atlas_size.x, atlas_size.y, true, Image.FORMAT_RGBA8, data)
		if img == null or img.is_empty():
			return false
		imgs.append(img)
	_set_images(imgs[0], imgs[1])
	from_cache = true
	return true

func _save_cache(key: String) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	# drop stale atlases from older generator parameters
	for fn in DirAccess.get_files_at(CACHE_DIR):
		if fn.begins_with("trees_") and fn.ends_with(".bin") and fn != _cache_path(key).get_file():
			DirAccess.remove_absolute(CACHE_DIR.path_join(fn))
	# write aside and rename, so a second game instance never reads a half-written atlas
	var tmp := _cache_path(key) + ".%d.tmp" % OS.get_process_id()
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	var S := []
	var base := []
	var crown := []
	for e in _entries:
		S.append(e.S)
		base.append(e.base)
		crown.append(e.crown)
	f.store_var({"count": _entries.size(), "size": atlas_size, "S": S, "base": base, "crown": crown})
	for img in _last_images:
		var data: PackedByteArray = img.get_data()
		f.store_32(data.size())
		f.store_buffer(data)
	f.close()
	DirAccess.rename_absolute(tmp, _cache_path(key))
