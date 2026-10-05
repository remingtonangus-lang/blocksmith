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


var _look_cache: Dictionary = {}   # character id -> {material key -> [Material, tint slot or -1]}

const TINT_SLOTS := 8


func apply(model: Node, info: Dictionary, rng: RandomNumberGenerator, opts := {}) -> void:
	## Materials are built once per look and shared by every instance of it (same uniform sets, better batching);
	## a seed variant's garment colours go into per-instance shader uniforms (cloth.gdshader tint_0..7) instead of
	## new materials.
	var mats: Dictionary = info.get("materials", {})
	var id := str(info.get("id", ""))
	var cache: Dictionary = _look_cache.get(id, {})
	var fresh := cache.is_empty()
	var variant := opts.has("variant_seed") and int(opts["variant_seed"]) != 0
	var tints := {}                       # slot -> Color for this instance
	var tinted := {}                      # MeshInstance3D -> true when one of its surfaces reads a tint slot
	var meshes := _meshes(model)
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m == null:
				continue
			var key := m.resource_name
			if not cache.has(key):
				var slot := -1
				var meta: Dictionary = mats.get(key, {})
				var kind := key.get_slice(":", 0)
				if kind in ["cloth", "leather", "metal"] and (meta.get("palette", []) as Array).size() > 0:
					var used := 0
					for k in cache:
						if cache[k][1] >= 0:
							used += 1
					if used < TINT_SLOTS:
						slot = used
				var made := _make(key, m, meta, info, rng, {})
				if made is ShaderMaterial and slot >= 0:
					made.set_shader_parameter("tint_slot", slot)
				cache[key] = [made, slot]
			var entry: Array = cache[key]
			if entry[0]:
				mi.set_surface_override_material(s, entry[0])
			if entry[1] >= 0:
				tinted[mi] = true
			if variant and entry[1] >= 0 and not tints.has(entry[1]):
				var palette: Array = mats.get(key, {}).get("palette", [])
				tints[entry[1]] = _col(palette[rng.randi_range(0, palette.size() - 1)], Color(1, 1, 1))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_lod_ranges(mi)
	if fresh and id != "":
		_look_cache[id] = cache
	for mi in tinted:
		for slot in tints:
			var c: Color = tints[slot]
			mi.set_instance_shader_parameter("tint_%d" % slot, Color(c.r, c.g, c.b, 1.0))
	if opts.get("no_hat", false):
		var hat := model.find_child("Hat", true, false)
		if hat:
			hat.visible = false


static func sss_available() -> bool:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return false
	if Game.disabled("sss"):
		return false
	return int(ProjectSettings.get_setting("rendering/environment/subsurface_scattering/subsurface_scattering_quality", 1)) > 0


func forget(id: String) -> void:
	## Drop a look's shared materials (CharacterFactory calls this when it evicts the look).
	_look_cache.erase(id)


const LOD0_END := 16.0
const LOD1_END := 42.0

func _lod_ranges(mi: MeshInstance3D) -> void:
	## Generator LODs: Body/Head/Hair/Hat (full detail, blend shapes) near, LOD1 (~8 k tris) mid, LOD2 (~2.5 k) far.
	match String(mi.name):
		"LOD1":
			mi.visibility_range_begin = LOD0_END
			mi.visibility_range_end = LOD1_END
		"LOD2":
			mi.visibility_range_begin = LOD1_END
		_:
			if mi.get_parent() and mi.get_parent().find_child("LOD1", false, false) != null:
				mi.visibility_range_end = LOD0_END
	if mi.name == "LOD1" or mi.name == "LOD2":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end_margin = 1.5 if mi.visibility_range_end > 0.0 else 0.0
	mi.visibility_range_begin_margin = 1.5 if mi.visibility_range_begin > 0.0 else 0.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


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
	for k in d:
		d[k].resource_name = "fabric/%s/%s" % [name, k]
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
			sm.set_shader_parameter("skin_age", clampf((float(info.get("age", 30)) - 20.0) / 50.0, 0.0, 1.0))
			# wrap-light scatter: light where Forward+ screen-space SSS runs, stronger where it doesn't (Mobile/Quest,
			# --disable sss on CI's paravirtual GPU)
			var sss_on := sss_available()
			sm.set_shader_parameter("wrap", 0.22 if sss_on else 0.5)
			sm.set_shader_parameter("sss", 0.45 if sss_on else 0.0)
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
		"beard":
			var bs := ShaderMaterial.new()
			bs.shader = _shader("strands")
			bs.set_shader_parameter("albedo_tex", _tex(src, "albedo"))
			bs.set_shader_parameter("use_normal", false)
			bs.set_shader_parameter("use_vertex_color", true)
			var bc := _col(meta.get("tint"), Color(0.3, 0.22, 0.15))
			bs.set_shader_parameter("hair_color", Color(maxf(bc.r, 0.07), maxf(bc.g, 0.055), maxf(bc.b, 0.045)))
			bs.set_shader_parameter("alpha_cut", 0.4)
			return bs
		"brows", "lashes":
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
				var bc := _col(meta.get("tint"), Color(0.3, 0.22, 0.15))
				hm.albedo_color = Color(maxf(bc.r, 0.07), maxf(bc.g, 0.055), maxf(bc.b, 0.045))
				hm.metallic_specular = 0.25
				hm.roughness = 0.75
			return hm
		"hair", "hair_updo":
			var hs := ShaderMaterial.new()
			hs.shader = _shader("strands" if kind == "hair_updo" else "hair")
			hs.set_shader_parameter("albedo_tex", _tex(src, "albedo"))
			var nt := _tex(src, "normal")
			hs.set_shader_parameter("use_normal", nt != null)
			if nt:
				hs.set_shader_parameter("normal_tex", nt)
			hs.set_shader_parameter("hair_color", _col(meta.get("tint"), Color(0.25, 0.17, 0.11)))
			hs.set_shader_parameter("use_vertex_color", kind == "hair_updo")
			return hs
		"cornea":
			# additive clear dome: only the specular highlight and reflections land on the iris (wet eyes)
			var cm2 := StandardMaterial3D.new()
			cm2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			cm2.albedo_color = Color(0, 0, 0)
			cm2.roughness = 0.04
			cm2.metallic_specular = 1.0
			cm2.cull_mode = BaseMaterial3D.CULL_BACK
			return cm2
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
