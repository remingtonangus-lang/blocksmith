class_name SignText
extends RefCounted
## Painted sign lettering as MSDF glyph quads (2 triangles per letter, crisp at every distance): the OFL period
## fonts in assets/fonts are rasterised once into multichannel signed-distance atlases (cached in
## user://sign_atlas/), and letters are emitted into MeshKit buckets "text_<font>_<page>" whose material
## (shaders/sign_text.gdshader) reconstructs the edge and chips the paint with weathering. Signs are uppercase
## (period signage); lowercase input is upper-cased.

const SIZE := 36
const RANGE := 6
const FIRST := 32
const LAST := 95             # space .. underscore: punctuation, digits, A-Z
const CACHE := "user://sign_atlas/"
const VERSION := 2

static var _atlases := {}

static func atlas(fnt: String) -> Dictionary:
	if _atlases.has(fnt):
		return _atlases[fnt]
	var a := _load_cache(fnt)
	if a.is_empty():
		a = _generate(fnt)
		_save_cache(fnt, a)
	a.erase("imgs")              # the CPU images were only needed for the cache; the textures hold the atlas
	# materials, one per page
	var sh: Shader = load("res://shaders/sign_text.gdshader")
	var mats := TownMats.get_all()
	for i in a.pages.size():
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("atlas", a.pages[i])
		m.set_shader_parameter("px_range", float(RANGE))
		mats["text_%s_%d" % [fnt, i]] = m
	_atlases[fnt] = a
	return a

static func _generate(fnt: String) -> Dictionary:
	var path := "res://assets/fonts/%s.ttf" % fnt
	var src: FontFile = load(path) if ResourceLoader.exists(path) else null
	if src == null:
		return {"glyphs": {}, "pages": [], "imgs": []}
	var f: FontFile = src.duplicate()
	f.multichannel_signed_distance_field = true
	f.msdf_size = SIZE
	f.msdf_pixel_range = RANGE
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = f.get_rids()[0]
	var sz := Vector2i(SIZE, 0)
	ts.font_render_range(rid, sz, FIRST, LAST)
	var glyphs := {}
	var imgs := []
	var n := ts.font_get_texture_count(rid, sz)
	for i in n:
		imgs.append(ts.font_get_texture_image(rid, sz, i))
	for code in range(FIRST, LAST + 1):
		var g := ts.font_get_glyph_index(rid, SIZE, code, 0)
		var page := ts.font_get_glyph_texture_idx(rid, sz, g)
		var uv := ts.font_get_glyph_uv_rect(rid, sz, g)
		var isz: Vector2 = imgs[page].get_size() if page >= 0 and page < imgs.size() else Vector2(1, 1)
		glyphs[code] = [Rect2(uv.position / isz, uv.size / isz), ts.font_get_glyph_offset(rid, sz, g), ts.font_get_glyph_size(rid, sz, g),
			ts.font_get_glyph_advance(rid, SIZE, g).x, page]
	var pages := []
	for img in imgs:
		pages.append(_tex(img))
	return {"glyphs": glyphs, "pages": pages, "imgs": imgs}

static func _tex(img: Image) -> ImageTexture:
	var im: Image = img.duplicate()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)

static func _save_cache(fnt: String, a: Dictionary) -> void:
	if a.glyphs.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(CACHE)
	var meta := {"version": VERSION, "size": SIZE, "range": RANGE, "pages": a.imgs.size(), "glyphs": {}}
	for code in a.glyphs:
		var g: Array = a.glyphs[code]
		var r: Rect2 = g[0]
		meta.glyphs[str(code)] = [r.position.x, r.position.y, r.size.x, r.size.y, g[1].x, g[1].y, g[2].x, g[2].y, g[3], g[4]]
	for i in a.imgs.size():
		a.imgs[i].save_png(CACHE + "%s_%d.png" % [fnt, i])
	var fa := FileAccess.open(CACHE + fnt + ".json", FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(meta))

static func _load_cache(fnt: String) -> Dictionary:
	var jp := CACHE + fnt + ".json"
	if not FileAccess.file_exists(jp):
		return {}
	var meta = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if typeof(meta) != TYPE_DICTIONARY or int(meta.get("version", 0)) != VERSION or int(meta.get("size", 0)) != SIZE:
		return {}
	var imgs := []
	var pages := []
	for i in int(meta.pages):
		var img := Image.load_from_file(CACHE + "%s_%d.png" % [fnt, i])
		if img == null or img.is_empty():
			return {}
		imgs.append(img)
		pages.append(_tex(img))
	var glyphs := {}
	for k in meta.glyphs:
		var v: Array = meta.glyphs[k]
		glyphs[int(k)] = [Rect2(v[0], v[1], v[2], v[3]), Vector2(v[4], v[5]), Vector2(v[6], v[7]), float(v[8]), int(v[9])]
	return {"glyphs": glyphs, "pages": pages, "imgs": imgs}

## Emit `s` centred at c (kit-local frame), reading along `dir`, facing `out`; fits cap height h and width maxw.
static func add(kit: MeshKit, s: String, c: Vector3, dir: Vector3, out: Vector3, h: float, maxw: float, col: Color, fnt := "Rye") -> void:
	if Game.disabled("town_signs"):
		return
	var a := atlas(fnt)
	if a.glyphs.is_empty():
		return
	s = s.to_upper()
	# layout in font pixels: x right, y up (baseline 0)
	var pen := 0.0
	var quads := []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pad := float(RANGE) * 0.5
	for i in s.length():
		var code := s.unicode_at(i)
		if not a.glyphs.has(code):
			code = 32
		var g: Array = a.glyphs[code]
		var off: Vector2 = g[1]
		var gs: Vector2 = g[2]
		if gs.x > 0.0 and code != 32:
			var x0 := pen + off.x
			var y1 := -off.y
			var x1 := x0 + gs.x
			var y0 := y1 - gs.y
			quads.append([x0, y0, x1, y1, g[0], g[4]])
			lo = Vector2(minf(lo.x, x0 + pad), minf(lo.y, y0 + pad))
			hi = Vector2(maxf(hi.x, x1 - pad), maxf(hi.y, y1 - pad))
		pen += float(g[3])
	if quads.is_empty():
		return
	var cap := _cap_height(a)
	var sc := minf(h / cap, maxw / maxf(hi.x - lo.x, 1.0))
	var cx := (lo.x + hi.x) * 0.5
	var cy := cap * 0.5
	var up := out.cross(dir).normalized()
	if up.dot(Vector3.UP) < 0.0 and absf(dir.y) < 0.5:
		up = -up
	var lift := out * 0.004
	var tint := kit.tint
	kit.tint = Color(col.r, col.g, col.b, tint.a)
	for q in quads:
		var r: Rect2 = q[4]
		var key := "text_%s_%d" % [fnt, q[5]]
		var p00: Vector3 = c + lift + dir * ((q[0] - cx) * sc) + up * ((q[1] - cy) * sc)
		var p10: Vector3 = c + lift + dir * ((q[2] - cx) * sc) + up * ((q[1] - cy) * sc)
		var p11: Vector3 = c + lift + dir * ((q[2] - cx) * sc) + up * ((q[3] - cy) * sc)
		var p01: Vector3 = c + lift + dir * ((q[0] - cx) * sc) + up * ((q[3] - cy) * sc)
		kit.quad_uv(key, p00, p10, p11, p01, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y),
			Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y))
	kit.tint = tint

static func _cap_height(a: Dictionary) -> float:
	if a.has("cap"):
		return a.cap
	var g: Array = a.glyphs.get(72, a.glyphs[32])      # 'H'
	var capv: float = maxf(g[2].y - float(RANGE), 1.0)
	a["cap"] = capv
	return capv
