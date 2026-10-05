class_name BirdLooks
extends RefCounted
## Plumage presets for the generated birds (shaders/bird_body.gdshader + bird_feather.gdshader), with a little
## per-bird jitter. Anchors come from <species>_gaits.json.

const PRESETS := {
	"turkey": {
		"body": {"back_color": Color(0.24, 0.17, 0.1), "belly_color": Color(0.16, 0.12, 0.09), "band_color": Color(0.1, 0.08, 0.06),
			"band_amount": 0.4, "head_color": Color(0.45, 0.6, 0.85), "bare_head": 1.0, "leg_color": Color(0.62, 0.42, 0.38),
			"beak_color": Color(0.55, 0.48, 0.4), "mottle": 0.25, "barring": 0.5, "sheen": 0.7, "sheen_tint": Color(0.6, 0.45, 0.2)},
		"wing": {"covert_color": Color(0.26, 0.18, 0.1), "flight_color": Color(0.28, 0.24, 0.2), "under_color": Color(0.45, 0.4, 0.34),
			"tip_color": Color(0.2, 0.16, 0.12), "bar_color": Color(0.85, 0.82, 0.76), "bars": 7.0, "tip_amount": 0.2, "fingers": 0,
			"feathers": 16.0, "sheen": 0.5, "sheen_tint": Color(0.6, 0.45, 0.2)},
		"tail": {"flight_color": Color(0.3, 0.22, 0.14), "bar_color": Color(0.12, 0.09, 0.06), "bars": 9.0,
			"tail_band": Color(0.08, 0.06, 0.05), "tail_band_amount": 1.0, "tail_tip_color": Color(0.72, 0.6, 0.42), "tail_tip_amount": 1.0}},
	"sage_grouse": {
		"body": {"back_color": Color(0.38, 0.33, 0.27), "belly_color": Color(0.12, 0.1, 0.09), "band_color": Color(0.85, 0.83, 0.78),
			"band_amount": 0.7, "head_color": Color(0.3, 0.26, 0.22), "leg_color": Color(0.5, 0.45, 0.38), "beak_color": Color(0.15, 0.13, 0.12),
			"mottle": 0.7, "barring": 0.3},
		"wing": {"covert_color": Color(0.42, 0.36, 0.28), "flight_color": Color(0.36, 0.31, 0.25), "under_color": Color(0.8, 0.78, 0.72),
			"tip_color": Color(0.25, 0.22, 0.18), "bar_color": Color(0.7, 0.66, 0.58), "bars": 5.0, "tip_amount": 0.2, "fingers": 0, "feathers": 12.0},
		"tail": {"flight_color": Color(0.32, 0.27, 0.22), "bar_color": Color(0.6, 0.55, 0.47), "bars": 6.0, "spiky": 1.0}},
	"red_tailed_hawk": {
		"body": {"back_color": Color(0.32, 0.22, 0.14), "belly_color": Color(0.88, 0.84, 0.76), "band_color": Color(0.3, 0.2, 0.12),
			"band_amount": 0.9, "head_color": Color(0.36, 0.25, 0.16), "leg_color": Color(0.85, 0.72, 0.3), "beak_color": Color(0.15, 0.14, 0.14),
			"mottle": 0.35, "barring": 0.1},
		"wing": {"covert_color": Color(0.34, 0.24, 0.15), "flight_color": Color(0.38, 0.3, 0.22), "under_color": Color(0.86, 0.83, 0.77),
			"tip_color": Color(0.1, 0.09, 0.08), "bar_color": Color(0.6, 0.52, 0.42), "bars": 8.0, "tip_amount": 0.7, "fingers": 5, "feathers": 20.0},
		"tail": {"flight_color": Color(0.7, 0.32, 0.16), "bar_color": Color(0.6, 0.28, 0.14), "bars": 0.0, "tail_band": Color(0.12, 0.08, 0.06),
			"tail_band_amount": 1.0, "tail_tip_color": Color(0.85, 0.82, 0.76), "tail_tip_amount": 0.8}},
	"crow": {
		"body": {"back_color": Color(0.035, 0.035, 0.04), "belly_color": Color(0.04, 0.04, 0.045), "head_color": Color(0.035, 0.035, 0.04),
			"leg_color": Color(0.05, 0.05, 0.05), "beak_color": Color(0.04, 0.04, 0.04), "mottle": 0.05, "sheen": 1.0,
			"sheen_tint": Color(0.35, 0.4, 0.9)},
		"wing": {"covert_color": Color(0.04, 0.04, 0.05), "flight_color": Color(0.035, 0.035, 0.04), "under_color": Color(0.06, 0.06, 0.07),
			"tip_color": Color(0.03, 0.03, 0.03), "bars": 0.0, "tip_amount": 0.0, "fingers": 5, "feathers": 18.0, "sheen": 1.0,
			"sheen_tint": Color(0.35, 0.4, 0.9)},
		"tail": {"flight_color": Color(0.035, 0.035, 0.04), "bars": 0.0, "sheen": 1.0}},
}

static func roll(species: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 7919 + species.hash())
	return {"jitter": rng.randf_range(-0.07, 0.07), "seed": Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))}

static func _set_all(mat: ShaderMaterial, d: Dictionary, jitter: float) -> void:
	for k in d:
		var v = d[k]
		if v is Color:
			v = Color(v.r * (1.0 + jitter), v.g * (1.0 + jitter), v.b * (1.0 + jitter))
		mat.set_shader_parameter(k, v)

static func apply(species: String, coat: Dictionary, body: ShaderMaterial, wing: ShaderMaterial, tail: ShaderMaterial,
		anchors: Dictionary) -> void:
	var p: Dictionary = PRESETS.get(species, PRESETS["crow"])
	var j := float(coat.get("jitter", 0.0))
	_set_all(body, p.body, j)
	_set_all(wing, p.wing, j)
	_set_all(tail, p.tail, j)
	tail.set_shader_parameter("is_tail", true)
	body.set_shader_parameter("pattern_seed", coat.get("seed", Vector3.ZERO))
	for k in ["head_c", "body_c", "body_r"]:
		var key: String = {"head_c": "head", "body_c": "body", "body_r": "body_r"}[k]
		if anchors.has(key):
			var a: Array = anchors[key]
			body.set_shader_parameter(k, Vector3(a[0], a[1], a[2]))
	if anchors.has("hip_z"):
		body.set_shader_parameter("hip_z", float(anchors.hip_z))
	if anchors.has("scale"):
		body.set_shader_parameter("body_scale", float(anchors.scale))
