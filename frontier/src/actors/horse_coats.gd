class_name HorseCoats
extends RefCounted
## Coat colours, patterns and white markings for horses, chosen deterministically from a seed. Every coat is a
## set of uniforms for shaders/horse_coat.gdshader (body) and shaders/horse_hair.gdshader (mane/tail).
## Colours are hand-picked from the real range of each coat (sRGB), then jittered per horse.

const BASE := {
	# name: body, belly (soft lighter underside), points (legs/mane/tail/muzzle), points amount, mane colour, hoof
	"bay":         {"body": Color(0.40, 0.20, 0.09), "belly": Color(0.50, 0.30, 0.16), "points": Color(0.05, 0.035, 0.03), "point_amt": 1.0, "mane": Color(0.05, 0.035, 0.03), "hoof": Color(0.13, 0.11, 0.10)},
	"dark_bay":    {"body": Color(0.22, 0.11, 0.06), "belly": Color(0.32, 0.18, 0.10), "points": Color(0.04, 0.03, 0.025), "point_amt": 1.0, "mane": Color(0.04, 0.03, 0.025), "hoof": Color(0.12, 0.10, 0.09)},
	"chestnut":    {"body": Color(0.50, 0.24, 0.10), "belly": Color(0.58, 0.32, 0.16), "points": Color(0.42, 0.20, 0.09), "point_amt": 0.25, "mane": Color(0.46, 0.22, 0.09), "hoof": Color(0.22, 0.18, 0.15)},
	"sorrel":      {"body": Color(0.62, 0.32, 0.14), "belly": Color(0.70, 0.42, 0.22), "points": Color(0.55, 0.28, 0.12), "point_amt": 0.2, "mane": Color(0.80, 0.62, 0.40), "hoof": Color(0.25, 0.20, 0.16)},
	"black":       {"body": Color(0.045, 0.04, 0.04), "belly": Color(0.07, 0.06, 0.055), "points": Color(0.03, 0.028, 0.028), "point_amt": 0.5, "mane": Color(0.03, 0.028, 0.028), "hoof": Color(0.10, 0.09, 0.09)},
	"grey_dapple": {"body": Color(0.56, 0.56, 0.56), "belly": Color(0.70, 0.70, 0.69), "points": Color(0.22, 0.22, 0.23), "point_amt": 0.8, "mane": Color(0.62, 0.61, 0.60), "hoof": Color(0.16, 0.15, 0.15), "dapple": 1.0},
	"flea_grey":   {"body": Color(0.80, 0.79, 0.77), "belly": Color(0.84, 0.83, 0.81), "points": Color(0.55, 0.53, 0.52), "point_amt": 0.4, "mane": Color(0.86, 0.85, 0.83), "hoof": Color(0.20, 0.19, 0.18), "flecks": 1.0},
	"palomino":    {"body": Color(0.80, 0.60, 0.30), "belly": Color(0.86, 0.70, 0.45), "points": Color(0.70, 0.52, 0.28), "point_amt": 0.15, "mane": Color(0.93, 0.88, 0.76), "hoof": Color(0.30, 0.25, 0.20)},
	"buckskin":    {"body": Color(0.74, 0.56, 0.32), "belly": Color(0.80, 0.65, 0.42), "points": Color(0.06, 0.045, 0.035), "point_amt": 1.0, "mane": Color(0.06, 0.045, 0.035), "hoof": Color(0.12, 0.10, 0.09)},
	"dun":         {"body": Color(0.62, 0.50, 0.34), "belly": Color(0.70, 0.60, 0.44), "points": Color(0.10, 0.08, 0.06), "point_amt": 1.0, "mane": Color(0.12, 0.09, 0.07), "hoof": Color(0.12, 0.10, 0.09), "dorsal": 1.0},
	"grulla":      {"body": Color(0.40, 0.38, 0.35), "belly": Color(0.48, 0.46, 0.43), "points": Color(0.08, 0.075, 0.07), "point_amt": 1.0, "mane": Color(0.08, 0.075, 0.07), "hoof": Color(0.10, 0.09, 0.09), "dorsal": 1.0},
	"pinto":       {"body": Color(0.36, 0.18, 0.08), "belly": Color(0.46, 0.27, 0.14), "points": Color(0.05, 0.035, 0.03), "point_amt": 0.7, "mane": Color(0.10, 0.07, 0.05), "hoof": Color(0.35, 0.32, 0.28), "pinto": 1.0},
	"black_pinto": {"body": Color(0.05, 0.045, 0.045), "belly": Color(0.07, 0.06, 0.06), "points": Color(0.03, 0.03, 0.03), "point_amt": 0.3, "mane": Color(0.05, 0.045, 0.045), "hoof": Color(0.35, 0.32, 0.28), "pinto": 1.0},
	"appaloosa":   {"body": Color(0.34, 0.18, 0.09), "belly": Color(0.42, 0.26, 0.15), "points": Color(0.05, 0.035, 0.03), "point_amt": 0.8, "mane": Color(0.20, 0.13, 0.08), "hoof": Color(0.40, 0.36, 0.30), "appaloosa": 1.0},
	"leopard_appaloosa": {"body": Color(0.86, 0.84, 0.80), "belly": Color(0.88, 0.86, 0.82), "points": Color(0.30, 0.26, 0.22), "point_amt": 0.2, "mane": Color(0.55, 0.50, 0.45), "hoof": Color(0.40, 0.36, 0.30), "leopard": 1.0},
}

const BREEDS := {
	# speed: gallop top speed m/s, accel m/s^2, handling (turn), stamina, health, scale, coat weights
	"mustang":      {"speed": 12.0, "accel": 4.2, "handling": 1.05, "stamina": 120.0, "health": 110.0, "scale": 0.95, "coats": {"bay": 3, "dun": 3, "grulla": 2, "buckskin": 2, "black": 1, "pinto": 2, "chestnut": 2, "sorrel": 1}},
	"morgan":       {"speed": 11.8, "accel": 4.4, "handling": 1.1, "stamina": 100.0, "health": 100.0, "scale": 0.97, "coats": {"bay": 3, "dark_bay": 2, "chestnut": 3, "black": 2}},
	"quarter":      {"speed": 12.6, "accel": 5.4, "handling": 1.15, "stamina": 95.0, "health": 100.0, "scale": 1.0, "coats": {"sorrel": 4, "bay": 3, "chestnut": 2, "palomino": 2, "buckskin": 2, "grey_dapple": 1, "black": 1}},
	"thoroughbred": {"speed": 14.0, "accel": 5.0, "handling": 0.95, "stamina": 90.0, "health": 85.0, "scale": 1.05, "coats": {"bay": 4, "dark_bay": 3, "chestnut": 3, "black": 1, "grey_dapple": 1}},
	"appaloosa":    {"speed": 12.2, "accel": 4.6, "handling": 1.05, "stamina": 110.0, "health": 105.0, "scale": 0.99, "coats": {"appaloosa": 5, "leopard_appaloosa": 2}},
	"paint":        {"speed": 12.4, "accel": 5.0, "handling": 1.1, "stamina": 100.0, "health": 100.0, "scale": 1.0, "coats": {"pinto": 4, "black_pinto": 2}},
	"draft":        {"speed": 9.5, "accel": 3.0, "handling": 0.8, "stamina": 140.0, "health": 150.0, "scale": 1.12, "coats": {"bay": 2, "black": 2, "grey_dapple": 2, "flea_grey": 1, "chestnut": 1}},
}

static func breed_names() -> Array:
	return BREEDS.keys()

static func breed(name: String) -> Dictionary:
	return BREEDS.get(name, BREEDS["quarter"])

## Full appearance for a horse: base coat + jitter + white markings, all from the seed.
static func roll(seed: int, breed_name: String, coat_name: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 7919 + 17)
	var b := breed(breed_name)
	if coat_name == "" or not BASE.has(coat_name):
		coat_name = _weighted(rng, b.coats)
	var c: Dictionary = BASE[coat_name].duplicate()
	var j := rng.randf_range(-0.06, 0.06)
	var sat := rng.randf_range(0.9, 1.1)
	for k in ["body", "belly", "points", "mane"]:
		var col: Color = c[k]
		col = Color.from_hsv(col.h + rng.randf_range(-0.012, 0.012), clampf(col.s * sat, 0.0, 1.0), clampf(col.v * (1.0 + j), 0.0, 1.0))
		c[k] = col
	c["name"] = coat_name
	c["breed"] = breed_name
	c["pattern_seed"] = Vector3(rng.randf_range(-50, 50), rng.randf_range(-50, 50), rng.randf_range(-50, 50))
	# white markings: socks/stockings per leg (height in metres), face (0 none, 1 star, 2 strip, 3 blaze, 4 bald)
	var socks := [0.0, 0.0, 0.0, 0.0]          # LF, RF, LH, RH
	var white_chance := 0.55 if coat_name in ["chestnut", "sorrel", "bay", "pinto", "black_pinto", "palomino"] else 0.3
	for i in 4:
		if rng.randf() < white_chance * (1.15 if i >= 2 else 0.85):
			socks[i] = [0.07, 0.11, 0.2, 0.3, 0.45][rng.randi_range(0, 4)]
	c["socks"] = socks
	var face := 0
	if rng.randf() < white_chance + 0.1:
		face = rng.randi_range(1, 4) if coat_name != "black" else rng.randi_range(1, 2)
	c["face"] = face
	c["snip"] = 1.0 if rng.randf() < 0.2 else 0.0
	c["pinto"] = c.get("pinto", 0.0) * rng.randf_range(0.8, 1.2)
	c["appaloosa"] = c.get("appaloosa", 0.0)
	c["leopard"] = c.get("leopard", 0.0)
	c["dapple"] = c.get("dapple", 0.0)
	c["flecks"] = c.get("flecks", 0.0)
	c["dorsal"] = c.get("dorsal", 0.0)
	return c

static func _weighted(rng: RandomNumberGenerator, w: Dictionary) -> String:
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	var r := rng.randf() * tot
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]

## Apply a coat to the body and hair materials.
static func apply(coat: Dictionary, body: ShaderMaterial, hair: ShaderMaterial) -> void:
	if body:
		body.set_shader_parameter("base_color", coat.body)
		body.set_shader_parameter("belly_color", coat.belly)
		body.set_shader_parameter("point_color", coat.points)
		body.set_shader_parameter("point_amount", coat.point_amt)
		body.set_shader_parameter("hoof_color", coat.hoof)
		body.set_shader_parameter("mane_color", coat.mane)
		body.set_shader_parameter("dapple", coat.dapple)
		body.set_shader_parameter("flecks", coat.flecks)
		body.set_shader_parameter("dorsal_stripe", coat.dorsal)
		body.set_shader_parameter("pinto", coat.pinto)
		body.set_shader_parameter("appaloosa", coat.appaloosa)
		body.set_shader_parameter("leopard", coat.leopard)
		body.set_shader_parameter("pattern_seed", coat.pattern_seed)
		body.set_shader_parameter("socks", Vector4(coat.socks[0], coat.socks[1], coat.socks[2], coat.socks[3]))
		body.set_shader_parameter("face_white", float(coat.face))
		body.set_shader_parameter("snip", coat.snip)
	if hair:
		hair.set_shader_parameter("hair_color", coat.mane)
		var tip: Color = coat.mane.lerp(coat.body, 0.25) if coat.name in ["bay", "dark_bay", "buckskin", "dun"] else coat.mane.lightened(0.12)
		hair.set_shader_parameter("tip_color", tip)
		hair.set_shader_parameter("pinto", coat.pinto)
		hair.set_shader_parameter("pattern_seed", coat.pattern_seed)
