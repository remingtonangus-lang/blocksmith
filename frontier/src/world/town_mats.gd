class_name TownMats
extends RefCounted
## Shared settlement materials: one ShaderMaterial (shaders/building.gdshader) per packed CC0 texture set, plus
## glass, sign paint, iron, lamp glow, fire, water and the far-LOD vertex-colour material. Keys are the bucket
## keys MeshKit uses, so a whole town cell commits to one surface per material key.

const PACKED := "res://assets/ext/packed/"

# key: [texture set, tile u, tile v, boards per tile, board axis (1 = horizontal boards), tint amount, extra params]
const SETS := {
	"siding": ["build_siding", 2.5, 2.5, 14.0, 1.0, 0.3, {}],
	"paint": ["build_painted_planks_blue", 1.35, 1.35, 7.0, 1.0, 1.0, {"desaturate": 1.0, "albedo_mul": Color(1.75, 1.72, 1.66)}],
	"clap_green": ["build_painted_planks_green", 1.0, 1.0, 5.0, 1.0, 0.35, {}],
	"boards_v": ["build_painted_planks_white", 1.4, 1.4, 9.0, 0.0, 0.9, {}],
	"planks_v": ["build_planks", 1.5, 1.5, 10.0, 0.0, 0.25, {}],
	"planks_raw": ["build_planks_raw", 1.5, 1.5, 9.0, 0.0, 0.25, {}],
	"planks_brown": ["build_planks_brown", 1.8, 1.8, 12.0, 1.0, 0.25, {}],
	"dark_planks": ["build_dark_planks", 1.6, 1.6, 8.0, 1.0, 0.3, {}],
	"floor": ["build_floor", 1.1, 1.1, 6.0, 1.0, 0.65, {"dirt_amount": 0.0, "rough_add": 0.3, "spec": 0.25}],
	"log": ["build_log_wall", 1.8, 1.8, 6.0, 1.0, 0.2, {}],
	"brick": ["build_brick", 1.5, 1.5, 0.0, 1.0, 0.35, {"grime": 0.5}],
	"stone": ["build_adobe_stone", 2.4, 2.4, 0.0, 1.0, 0.3, {}],
	"adobe": ["build_adobe", 3.0, 3.0, 0.0, 1.0, 0.55, {"dirt_amount": 0.4}],
	"plaster": ["build_plaster", 3.0, 3.0, 0.0, 1.0, 1.0, {"dirt_amount": 0.5}],
	"shingles": ["build_roof_shingles", 1.2, 1.2, 8.0, 1.0, 0.3, {"dirt_amount": 0.0, "grime": 0.0}],
	"corrugated": ["build_corrugated", 2.1, 2.1, 0.0, 1.0, 0.25, {"metallic": 0.55, "spec": 0.6, "dirt_amount": 0.2}],
	"rust": ["build_rusty_metal", 1.5, 1.5, 0.0, 1.0, 0.3, {"metallic": 0.5, "dirt_amount": 0.0}],
	"roof_planks": ["build_roof_planks", 2.4, 2.4, 12.0, 0.0, 0.3, {"desaturate": 0.7, "albedo_mul": Color(0.9, 0.85, 0.8), "dirt_amount": 0.0}],
	"fine_wood": ["build_fine_wood", 1.2, 1.2, 0.0, 1.0, 0.7, {"dirt_amount": 0.0, "rough_mul": 0.7}],
	"carpet": ["build_carpet", 2.0, 2.0, 0.0, 1.0, 0.6, {"dirt_amount": 0.0, "normal_depth": 0.5}],
	"wallpaper": ["build_wallpaper", 2.2, 2.2, 0.0, 1.0, 0.8, {"dirt_amount": 0.0}],
	"timber": ["build_timber", 1.4, 1.4, 8.0, 0.0, 0.5, {}],
	"thatch": ["build_thatch", 2.0, 2.0, 0.0, 1.0, 0.7, {"dirt_amount": 0.0}],
	"canvas": ["cloth_canvas", 1.2, 1.2, 0.0, 1.0, 0.9, {"albedo_mul": Color(1.25, 1.22, 1.15), "dirt_amount": 0.8}],
}

# average colours for the far LOD shell (vertex colours)
const FAR_COL := {
	"siding": Color(0.40, 0.34, 0.28), "paint": Color(0.80, 0.78, 0.72), "clap_green": Color(0.30, 0.42, 0.36),
	"boards_v": Color(0.62, 0.60, 0.55), "planks_v": Color(0.30, 0.25, 0.20), "planks_raw": Color(0.42, 0.40, 0.36),
	"planks_brown": Color(0.40, 0.30, 0.22), "dark_planks": Color(0.36, 0.34, 0.30), "log": Color(0.50, 0.48, 0.40),
	"brick": Color(0.55, 0.28, 0.20), "stone": Color(0.62, 0.58, 0.52), "adobe": Color(0.62, 0.46, 0.30),
	"plaster": Color(0.80, 0.77, 0.70), "shingles": Color(0.32, 0.28, 0.24), "corrugated": Color(0.45, 0.45, 0.44),
	"rust": Color(0.50, 0.36, 0.24), "roof_planks": Color(0.40, 0.33, 0.26), "timber": Color(0.50, 0.45, 0.40),
	"canvas": Color(0.78, 0.72, 0.60), "thatch": Color(0.50, 0.42, 0.30),
}

# untextured materials merged into the single "vc" surface: key -> [base colour (sRGB), roughness, metallic]
const VC := {"iron": [Color(0.16, 0.15, 0.14), 0.5, 0.75], "brass": [Color(0.72, 0.55, 0.28), 0.35, 0.9],
	"bottle": [Color(1, 1, 1), 0.08, 0.15], "cloth": [Color(1, 1, 1), 0.95, 0.0], "water": [Color(0.05, 0.08, 0.07), 0.04, 0.1],
	"mirror": [Color(0.42, 0.42, 0.4), 0.3, 1.0]}

static var _mats := {}
static var lights_on := 0.0

static func get_all() -> Dictionary:
	if _mats.is_empty():
		_build()
	return _mats

static func mat(key: String) -> Material:
	return get_all().get(key)

static func _tex(name: String, fallback: Color, normal := false) -> Texture2D:
	var p := PACKED + name + ".png"
	if ResourceLoader.exists(p):
		return load(p)
	var img := Image.create(8, 8, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.75, 1.0) if normal else Color(fallback.r, fallback.g, fallback.b, 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _build() -> void:
	var sh: Shader = load("res://shaders/building.gdshader")
	for key in SETS:
		var s: Array = SETS[key]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tex_ah", _tex(s[0] + "_ah", FAR_COL.get(key, Color(0.5, 0.45, 0.4))))
		m.set_shader_parameter("tex_nr", _tex(s[0] + "_nr", Color.WHITE, true))
		m.set_shader_parameter("tile", Vector2(s[1], s[2]))
		m.set_shader_parameter("boards", s[3])
		m.set_shader_parameter("board_axis", s[4])
		m.set_shader_parameter("tint_amount", s[5])
		var extra: Dictionary = s[6]
		for k in extra:
			var v = extra[k]
			if v is Color:
				v = Vector3(v.r, v.g, v.b)
			m.set_shader_parameter(k, v)
		_mats[key] = m
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/window.gdshader")
	glass.render_priority = 0
	_mats["glass"] = glass
	var sign := StandardMaterial3D.new()
	sign.vertex_color_use_as_albedo = true
	sign.vertex_color_is_srgb = true
	sign.roughness = 0.62
	_mats["sign"] = sign
	var iron := StandardMaterial3D.new()
	iron.vertex_color_use_as_albedo = true
	iron.vertex_color_is_srgb = true
	iron.albedo_color = Color(0.16, 0.15, 0.14)
	iron.metallic = 0.75
	iron.roughness = 0.5
	_mats["iron"] = iron
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.28)
	brass.metallic = 0.9
	brass.roughness = 0.35
	_mats["brass"] = brass
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.95, 0.85, 0.6)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.66, 0.32)
	lamp.emission_energy_multiplier = 0.0
	lamp.roughness = 0.2
	_mats["lamp"] = lamp
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(0.2, 0.08, 0.02)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.42, 0.12)
	fire.emission_energy_multiplier = 3.0
	_mats["fire"] = fire
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.05, 0.08, 0.07)
	water.roughness = 0.04
	water.metallic = 0.1
	_mats["water"] = water
	var vc := ShaderMaterial.new()
	vc.shader = load("res://shaders/vc.gdshader")
	_mats["vc"] = vc
	var far := StandardMaterial3D.new()
	far.vertex_color_use_as_albedo = true
	far.vertex_color_is_srgb = true
	far.roughness = 0.92
	_mats["far"] = far
	var bottle := StandardMaterial3D.new()
	bottle.vertex_color_use_as_albedo = true
	bottle.vertex_color_is_srgb = true
	bottle.roughness = 0.08
	bottle.metallic = 0.15
	bottle.metallic_specular = 0.8
	_mats["bottle"] = bottle
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.vertex_color_is_srgb = true
	cloth.roughness = 0.95
	_mats["cloth"] = cloth
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color(0.42, 0.42, 0.4)
	mirror.metallic = 1.0
	mirror.roughness = 0.32
	_mats["mirror"] = mirror

## Keys whose surfaces have no normal map (skip tangent generation).
static func plain_keys() -> Array:
	return ["sign", "iron", "brass", "lamp", "fire", "water", "far", "mirror", "glass", "bottle", "cloth", "vc"]

## Night factor 0..1 drives lit windows and lamp glass emission.
static func set_lights(v: float) -> void:
	lights_on = v
	var m := get_all()
	m["glass"].set_shader_parameter("lights_on", v)
	m["lamp"].emission_energy_multiplier = lerpf(0.0, 6.0, v)
