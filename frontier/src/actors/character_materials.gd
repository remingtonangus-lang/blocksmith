class_name CharacterMaterials
extends RefCounted
## Replaces the generic glTF materials of a generated character with Frontier materials, keyed by material name:
##   skin            -> skin shader (subsurface scattering, pore micro-normal, tan/weathering, wetness)
##   eyes            -> wet glossy eye (clearcoat)
##   brows/lashes    -> alpha-scissor hair strands
##   hair            -> hair shader (alpha scissor + anisotropic-ish sheen, per-character colour)
##   teeth/tongue    -> glossy
##   cloth:<garment>:<fabric>  -> cloth shader: PBR fabric texture (assets/ext/cloth/<fabric>) tiled in metres on UV2,
##                     tinted per character/seed, garment AO/normal from the glb, dirt and wear toward hems
## Per-character data (tints, weathering) comes from characters.json ("materials" per id); seed variants re-roll
## garment tints within the palette of each garment.

const CLOTH_DIR := "res://assets/ext/cloth"
var _fabric_cache: Dictionary = {}
var _shader_cache: Dictionary = {}


func apply(model: Node, info: Dictionary, rng: RandomNumberGenerator, opts := {}) -> void:
	var mats: Dictionary = info.get("materials", {})
	var done: Dictionary = {}
	for mi in _meshes(model):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m == null:
				continue
			var key := m.resource_name
			if not done.has(key):
				done[key] = _make(key, m, mats.get(key, {}), info, rng, opts)
			if done[key]:
				mi.set_surface_override_material(s, done[key])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if opts.get("no_hat", false):
		var hat := model.find_child("Hat", true, false)
		if hat:
			hat.visible = false


func _meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D and n.mesh:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out


func _tex(m: Material, which: String) -> Texture2D:
	if m is BaseMaterial3D:
		match which:
			"albedo": return m.albedo_texture
			"normal": return m.normal_texture if m.normal_enabled else null
			"ao": return m.ao_texture if m.ao_enabled else null
	return null


func _shader(name: String) -> Shader:
	if not _shader_cache.has(name):
		_shader_cache[name] = load("res://shaders/characters/%s.gdshader" % name)
	return _shader_cache[name]


func _fabric(name: String) -> Dictionary:
	if _fabric_cache.has(name):
		return _fabric_cache[name]
	var d := {}
	var base := CLOTH_DIR.path_join(name)
	for k in ["albedo", "normal", "roughness", "ao"]:
		var p := base.path_join(k + ".png")
		if ResourceLoader.exists(p):
			d[k] = load(p)
		elif FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				img.generate_mipmaps()
				d[k] = ImageTexture.create_from_image(img)
	_fabric_cache[name] = d
	return d


func _col(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(a[0], a[1], a[2])
	return fallback


func _make(key: String, src: Material, meta: Dictionary, info: Dictionary, rng: RandomNumberGenerator, opts: Dictionary) -> Material:
	var kind := key.get_slice(":", 0)
	match kind:
		"skin":
			var sm := ShaderMaterial.new()
			sm.shader = _shader("skin")
			sm.set_shader_parameter("albedo_tex", _tex(src, "albedo"))
			sm.set_shader_parameter("tint", _col(meta.get("tint"), Color(1, 1, 1)))
			sm.set_shader_parameter("weathering", float(meta.get("weathering", 0.2)))
			sm.set_shader_parameter("stubble", float(meta.get("stubble", 0.0)))
			sm.set_shader_parameter("stubble_color", _col(meta.get("stubble_color"), Color(0.12, 0.09, 0.07)))
			return sm
		"eyes":
			var em := StandardMaterial3D.new()
			em.albedo_texture = _tex(src, "albedo")
			em.roughness = 0.04
			em.metallic_specular = 0.6
			em.clearcoat_enabled = true
			em.clearcoat = 1.0
			em.clearcoat_roughness = 0.02
			return em
		"brows", "lashes", "beard":
			var hm := StandardMaterial3D.new()
			hm.albedo_texture = _tex(src, "albedo")
			hm.albedo_color = _col(meta.get("tint"), Color(1, 1, 1))
			hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			hm.alpha_scissor_threshold = 0.35
			hm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			hm.cull_mode = BaseMaterial3D.CULL_DISABLED
			hm.roughness = 0.6
			if kind == "beard":
				hm.vertex_color_use_as_albedo = true   # COLOR.a = shell layer density
				hm.alpha_scissor_threshold = 0.42
				hm.albedo_color = _col(meta.get("tint"), Color(0.3, 0.22, 0.15))
			return hm
		"hair":
			var hs := ShaderMaterial.new()
			hs.shader = _shader("hair")
			hs.set_shader_parameter("albedo_tex", _tex(src, "albedo"))
			var nt := _tex(src, "normal")
			hs.set_shader_parameter("use_normal", nt != null)
			if nt:
				hs.set_shader_parameter("normal_tex", nt)
			hs.set_shader_parameter("hair_color", _col(meta.get("tint"), Color(0.25, 0.17, 0.11)))
			return hs
		"teeth", "tongue":
			var tm := StandardMaterial3D.new()
			tm.albedo_texture = _tex(src, "albedo")
			tm.roughness = 0.25 if kind == "teeth" else 0.4
			tm.albedo_color = Color(0.92, 0.88, 0.8) if kind == "teeth" else Color(1, 1, 1)
			return tm
		"cloth", "leather", "metal":
			var cm := ShaderMaterial.new()
			cm.shader = _shader("cloth")
			var fabric_name := key.get_slice(":", 2) if key.get_slice_count(":") > 2 else str(meta.get("fabric", "none"))
			var fab := _fabric(fabric_name)
			var palette: Array = meta.get("palette", [])
			var tint := _col(meta.get("tint"), Color(1, 1, 1))
			if palette.size() > 0 and opts.has("variant_seed") and int(opts["variant_seed"]) != 0:
				tint = _col(palette[rng.randi_range(0, palette.size() - 1)], tint)
			cm.set_shader_parameter("tint", tint)
			cm.set_shader_parameter("use_fabric", fab.has("albedo"))
			if fab.has("albedo"):
				cm.set_shader_parameter("fabric_albedo", fab["albedo"])
			if fab.has("normal"):
				cm.set_shader_parameter("fabric_normal", fab["normal"])
			if fab.has("roughness"):
				cm.set_shader_parameter("fabric_roughness", fab["roughness"])
			cm.set_shader_parameter("tile", float(meta.get("tile", 2.5)))
			cm.set_shader_parameter("fabric_mix", float(meta.get("fabric_mix", 0.85)))
			var alb := _tex(src, "albedo")
			cm.set_shader_parameter("use_base", alb != null)
			if alb:
				cm.set_shader_parameter("base_albedo", alb)
			var nrm := _tex(src, "normal")
			cm.set_shader_parameter("use_base_normal", nrm != null)
			if nrm:
				cm.set_shader_parameter("base_normal", nrm)
			var ao := _tex(src, "ao")
			cm.set_shader_parameter("use_ao", ao != null)
			if ao:
				cm.set_shader_parameter("ao_tex", ao)
			cm.set_shader_parameter("dirt", float(meta.get("dirt", 0.3)))
			cm.set_shader_parameter("sheen", float(meta.get("sheen", 0.0)))
			cm.set_shader_parameter("metallic", 1.0 if kind == "metal" else 0.0)
			cm.set_shader_parameter("base_roughness", float(meta.get("roughness", 0.85)))
			return cm
	return null
