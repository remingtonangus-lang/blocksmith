class_name AnimalCoats
extends RefCounted
## Coat presets for the generated wildlife (shaders/animal_coat.gdshader): colours and pattern amounts per species,
## jittered per animal from its seed. Anchor points come from the model's <species>_gaits.json.

const PRESETS := {
	"mule_deer": {"base": Color(0.50, 0.40, 0.31), "belly": Color(0.86, 0.82, 0.74), "dorsal": Color(0.36, 0.30, 0.25),
		"point": Color(0.42, 0.34, 0.27), "face": Color(0.45, 0.38, 0.32), "muzzle": Color(0.88, 0.86, 0.82),
		"rump": Color(0.93, 0.91, 0.87), "tail_tip": Color(0.05, 0.045, 0.04), "belly_amt": 0.7, "dorsal_amt": 0.45,
		"point_amt": 0.2, "rump_amt": 1.0, "tail_amt": 1.0, "fur": 0.35},
	"elk": {"base": Color(0.55, 0.42, 0.30), "belly": Color(0.30, 0.22, 0.16), "dorsal": Color(0.62, 0.50, 0.37),
		"point": Color(0.20, 0.14, 0.10), "face": Color(0.26, 0.18, 0.12), "muzzle": Color(0.30, 0.22, 0.16),
		"rump": Color(0.86, 0.76, 0.58), "tail_tip": Color(0.80, 0.70, 0.52), "belly_amt": 0.6, "dorsal_amt": 0.3,
		"point_amt": 0.7, "rump_amt": 1.0, "tail_amt": 0.0, "cape": 0.85, "cape_col": Color(0.22, 0.15, 0.10), "fur": 0.45},
	"pronghorn": {"base": Color(0.74, 0.52, 0.30), "belly": Color(0.95, 0.93, 0.89), "dorsal": Color(0.66, 0.46, 0.27),
		"point": Color(0.70, 0.50, 0.30), "face": Color(0.30, 0.22, 0.16), "muzzle": Color(0.12, 0.09, 0.07),
		"rump": Color(0.96, 0.95, 0.92), "tail_tip": Color(0.96, 0.95, 0.92), "belly_amt": 1.0, "dorsal_amt": 0.2,
		"point_amt": 0.1, "rump_amt": 1.0, "tail_amt": 0.0, "bands": 1.0, "fur": 0.25},
	"bison": {"base": Color(0.36, 0.25, 0.16), "belly": Color(0.20, 0.14, 0.10), "dorsal": Color(0.42, 0.30, 0.20),
		"point": Color(0.12, 0.09, 0.07), "face": Color(0.10, 0.07, 0.05), "muzzle": Color(0.12, 0.10, 0.09),
		"belly_amt": 0.5, "dorsal_amt": 0.3, "point_amt": 0.8, "cape": 1.0, "cape_col": Color(0.13, 0.09, 0.06), "fur": 0.9},
	"rabbit": {"base": Color(0.55, 0.47, 0.37), "belly": Color(0.90, 0.88, 0.84), "dorsal": Color(0.40, 0.34, 0.27),
		"point": Color(0.58, 0.50, 0.40), "face": Color(0.55, 0.46, 0.36), "muzzle": Color(0.75, 0.70, 0.62),
		"rump": Color(0.92, 0.90, 0.86), "tail_tip": Color(0.1, 0.09, 0.08), "belly_amt": 0.9, "dorsal_amt": 0.4,
		"point_amt": 0.1, "rump_amt": 0.6, "tail_amt": 0.0, "grizzle": 0.6, "fur": 0.55},
	"coyote": {"base": Color(0.60, 0.50, 0.38), "belly": Color(0.88, 0.84, 0.76), "dorsal": Color(0.36, 0.31, 0.26),
		"point": Color(0.62, 0.45, 0.30), "face": Color(0.62, 0.48, 0.34), "muzzle": Color(0.86, 0.82, 0.74),
		"tail_tip": Color(0.08, 0.07, 0.06), "belly_amt": 0.85, "dorsal_amt": 0.55, "point_amt": 0.35, "tail_amt": 1.0,
		"grizzle": 0.8, "fur": 0.6},
	"wolf": {"base": Color(0.55, 0.53, 0.50), "belly": Color(0.86, 0.84, 0.80), "dorsal": Color(0.25, 0.24, 0.23),
		"point": Color(0.70, 0.66, 0.60), "face": Color(0.60, 0.57, 0.52), "muzzle": Color(0.88, 0.86, 0.82),
		"tail_tip": Color(0.07, 0.065, 0.06), "belly_amt": 0.85, "dorsal_amt": 0.6, "point_amt": 0.3, "tail_amt": 0.9,
		"grizzle": 0.9, "fur": 0.8},
	"cougar": {"base": Color(0.68, 0.52, 0.36), "belly": Color(0.90, 0.86, 0.78), "dorsal": Color(0.58, 0.43, 0.29),
		"point": Color(0.62, 0.47, 0.32), "face": Color(0.66, 0.50, 0.35), "muzzle": Color(0.95, 0.93, 0.89),
		"tail_tip": Color(0.10, 0.08, 0.07), "belly_amt": 0.9, "dorsal_amt": 0.35, "point_amt": 0.15, "tail_amt": 1.0,
		"fur": 0.3},
	"black_bear": {"base": Color(0.07, 0.06, 0.055), "belly": Color(0.09, 0.08, 0.07), "dorsal": Color(0.06, 0.05, 0.05),
		"point": Color(0.05, 0.045, 0.04), "face": Color(0.08, 0.07, 0.06), "muzzle": Color(0.55, 0.42, 0.30),
		"belly_amt": 0.3, "dorsal_amt": 0.3, "point_amt": 0.5, "fur": 0.85},
	"raccoon": {"base": Color(0.45, 0.43, 0.40), "belly": Color(0.62, 0.60, 0.56), "dorsal": Color(0.25, 0.24, 0.22),
		"point": Color(0.20, 0.18, 0.16), "face": Color(0.80, 0.78, 0.74), "muzzle": Color(0.90, 0.88, 0.84),
		"tail_tip": Color(0.08, 0.07, 0.06), "belly_amt": 0.6, "dorsal_amt": 0.5, "point_amt": 0.6, "tail_amt": 1.0,
		"mask": 1.0, "rings": 1.0, "grizzle": 0.7, "fur": 0.75},
	"fox": {"base": Color(0.72, 0.36, 0.14), "belly": Color(0.94, 0.92, 0.88), "dorsal": Color(0.66, 0.30, 0.11),
		"point": Color(0.08, 0.06, 0.05), "face": Color(0.74, 0.38, 0.16), "muzzle": Color(0.95, 0.93, 0.9),
		"tail_tip": Color(0.95, 0.94, 0.92), "belly_amt": 0.95, "dorsal_amt": 0.3, "point_amt": 1.0, "tail_amt": 1.0,
		"grizzle": 0.25, "fur": 0.6},
}

static func roll(species: String, seed: int) -> Dictionary:
	var c: Dictionary = PRESETS.get(species, PRESETS["mule_deer"]).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 131 + species.hash())
	var j := rng.randf_range(-0.08, 0.08)
	for k in ["base", "dorsal", "face"]:
		var col: Color = c[k]
		c[k] = Color.from_hsv(col.h + rng.randf_range(-0.01, 0.01), clampf(col.s * rng.randf_range(0.9, 1.1), 0.0, 1.0), clampf(col.v * (1.0 + j), 0.0, 1.0))
	c["seed"] = Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))
	return c

static func apply(c: Dictionary, mat: ShaderMaterial, anchors: Dictionary) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("base_color", c.base)
	mat.set_shader_parameter("belly_color", c.belly)
	mat.set_shader_parameter("dorsal_color", c.dorsal)
	mat.set_shader_parameter("point_color", c.point)
	mat.set_shader_parameter("face_color", c.face)
	mat.set_shader_parameter("muzzle_color", c.muzzle)
	mat.set_shader_parameter("rump_color", c.get("rump", c.belly))
	mat.set_shader_parameter("tail_tip_color", c.get("tail_tip", c.dorsal))
	mat.set_shader_parameter("belly_amount", c.get("belly_amt", 0.7))
	mat.set_shader_parameter("dorsal_amount", c.get("dorsal_amt", 0.4))
	mat.set_shader_parameter("point_amount", c.get("point_amt", 0.3))
	mat.set_shader_parameter("rump_amount", c.get("rump_amt", 0.0))
	mat.set_shader_parameter("tail_tip_amount", c.get("tail_amt", 0.0))
	mat.set_shader_parameter("band_amount", c.get("bands", 0.0))
	mat.set_shader_parameter("mask_amount", c.get("mask", 0.0))
	mat.set_shader_parameter("ring_amount", c.get("rings", 0.0))
	mat.set_shader_parameter("grizzle", c.get("grizzle", 0.0))
	mat.set_shader_parameter("cape_amount", c.get("cape", 0.0))
	mat.set_shader_parameter("cape_color", c.get("cape_col", c.dorsal))
	mat.set_shader_parameter("fur_length", c.get("fur", 0.4))
	mat.set_shader_parameter("pattern_seed", c.get("seed", Vector3.ZERO))
	for k in ["y_rear", "y_front", "z_back", "z_belly", "z_knee", "z_hock"]:
		if anchors.has(k):
			mat.set_shader_parameter(k, float(anchors[k]))
	for k in ["poll", "nose", "tail_base", "tail_tip", "eye"]:
		if anchors.has(k):
			var a: Array = anchors[k]
			mat.set_shader_parameter(k, Vector3(a[0], a[1], a[2]))
	if anchors.has("scale"):
		mat.set_shader_parameter("body_scale", float(anchors.scale))
