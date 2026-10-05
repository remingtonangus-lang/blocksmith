class_name Effects
extends RefCounted
## Short-lived combat effects: bullet impacts by surface (dust by terrain layer, wood splinters, stone chips and
## sparks, water splashes, snow, mud; restrained blood mist on people and animals), bullet-hole decals that fade
## out (pooled), impact sounds through the AudioDirector, and muzzle flashes whose light is stronger at night.
## CPUParticles3D + plain StandardMaterial3D so the same code runs on the Mobile renderer (Quest) and on fragile
## GPUs. Everything frees itself.
## Surface: info["surface"] if given, else AudioSurfaces.surface_at() (registered floors, water, rock, roads...).

const DECAL_LIFE := 26.0
const DECAL_FADE := 6.0
const DECAL_MAX := 48
## surface -> [dust colour, chunk colour, audio material, decal tint]
const SURF := {
	"dirt": [Color(0.60, 0.50, 0.38), Color(0.32, 0.25, 0.18), "dirt", Color(0.10, 0.08, 0.06)],
	"grass": [Color(0.55, 0.50, 0.36), Color(0.28, 0.30, 0.16), "dirt", Color(0.10, 0.09, 0.06)],
	"gravel": [Color(0.62, 0.58, 0.52), Color(0.42, 0.40, 0.37), "stone", Color(0.12, 0.11, 0.10)],
	"sand": [Color(0.78, 0.66, 0.48), Color(0.62, 0.50, 0.34), "dirt", Color(0.30, 0.24, 0.16)],
	"mud": [Color(0.36, 0.29, 0.21), Color(0.20, 0.15, 0.10), "dirt", Color(0.07, 0.05, 0.04)],
	"snow": [Color(0.93, 0.94, 0.96), Color(0.85, 0.87, 0.90), "dirt", Color(0.55, 0.57, 0.62)],
	"stone": [Color(0.66, 0.63, 0.58), Color(0.48, 0.46, 0.43), "stone", Color(0.14, 0.13, 0.12)],
	"wood": [Color(0.62, 0.50, 0.36), Color(0.78, 0.64, 0.44), "wood", Color(0.12, 0.08, 0.05)],
	"metal": [Color(0.55, 0.55, 0.56), Color(0.40, 0.40, 0.42), "metal", Color(0.15, 0.15, 0.16)],
	"water": [Color(0.86, 0.90, 0.92), Color(0.86, 0.90, 0.92), "water", Color(0, 0, 0, 0)],
}

static var _mat: StandardMaterial3D            # soft round puff (vertex colour)
static var _chip_mat: StandardMaterial3D       # hard chips/splinters (vertex colour, lit-looking flat)
static var _spark_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D
static var _hole_tex := {}
static var _decals: Array = []
static var night_override := -1.0              # >= 0 forces darkness() (tests)
static var flash_hold := 1.0                   # multiplies the flash lifetime (tests on slow renderers)
static var _tints := {}

static func _soft_tex() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, exp(-r * r * 3.5) * clampf((1.0 - r) * 5.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

static func _mats() -> void:
	if _mat != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.billboard_keep_scale = true
	_mat.albedo_texture = _soft_tex()
	_chip_mat = StandardMaterial3D.new()
	_chip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_chip_mat.vertex_color_use_as_albedo = true
	_chip_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_chip_mat.billboard_keep_scale = true
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.albedo_color = Color(1.0, 0.7, 0.35)
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.billboard_keep_scale = true
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	_flash_mat.albedo_texture = _soft_tex()
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

## Which surface a world hit landed on (people/animals are "flesh").
static func surface_of(info: Dictionary) -> String:
	if info.has("surface"):
		return str(info.surface)
	if info.has("target"):
		return "flesh"
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	var col = info.get("collider")
	if col is Object and is_instance_valid(col) and col.has_meta("surface"):
		return str(col.get_meta("surface"))
	if Game.world != null and Game.world.ok:
		var wl: float = Game.world.water_level(pos.x, pos.z)
		if wl > Game.world.height(pos.x, pos.z) + 0.05 and pos.y < wl + 0.05:
			return "water"
	var n: Vector3 = info.get("normal", Vector3.UP)
	return AudioSurfaces.surface_at(pos + n * 0.05, Game.audio)

static func _burst(root: Node, pos: Vector3, dir: Vector3, mat: Material, amount: int, life: float, speed: Vector2,
		spread: float, gravity: float, size: Vector2, c0: Color, c1: Color, damping := 2.0, quad := Vector2(1, 1)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = damping * 0.5
	p.damping_max = damping
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var q := QuadMesh.new()
	q.size = quad
	# colour by a tinted material, not per-particle vertex colours (those render wrong on some software and
	# paravirtual GPUs); fade by shrinking (chips) or by the soft texture spreading thin (puffs)
	q.material = _tinted(mat, c0)
	p.mesh = q
	var curve := Curve.new()
	curve.max_value = 2.0
	if mat == _mat:
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(0.35, 1.0))
		curve.add_point(Vector2(1, 0.0 if c1.a <= 0.01 else 1.4))
	else:
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(0.7, 0.9))
		curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)
	return p

static func _tinted(base: StandardMaterial3D, c: Color) -> StandardMaterial3D:
	var key := "%d:%s" % [base.get_instance_id(), c.to_html()]
	if _tints.has(key):
		return _tints[key]
	var m: StandardMaterial3D = base.duplicate()
	m.vertex_color_use_as_albedo = false
	if base != _spark_mat:
		m.albedo_color = c
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tints[key] = m
	return m

static func impact(root: Node, info: Dictionary) -> void:
	if root == null or Game.headless:
		return
	_mats()
	var surf := surface_of(info)
	var pos: Vector3 = info.get("position", Vector3.ZERO)
	var n: Vector3 = info.get("normal", Vector3.UP)
	var d: Vector3 = info.get("direction", -n)
	if n.length() < 0.1:
		n = Vector3.UP
	if Game.audio != null and Game.audio.has_method("impact"):
		Game.audio.impact("flesh" if surf == "flesh" else str(SURF.get(surf, SURF.dirt)[2]), pos)
	match surf:
		"flesh":
			# restrained: a brief dark-red mist out of the exit side and a few drops, no gore
			var out := d.normalized() if d.length() > 0.1 else n
			_burst(root, pos, out, _mat, 7, 0.35, Vector2(0.6, 1.8), 25.0, -4.0, Vector2(0.05, 0.11),
				Color(0.30, 0.03, 0.03, 0.55), Color(0.22, 0.02, 0.02, 0.0), 4.0)
			_burst(root, pos, out, _chip_mat, 5, 0.5, Vector2(1.0, 2.6), 20.0, -9.0, Vector2(0.008, 0.016),
				Color(0.26, 0.02, 0.02, 1.0), Color(0.2, 0.01, 0.01, 1.0), 0.5)
			return
		"water":
			var wl := pos.y
			if Game.world != null and Game.world.ok:
				wl = Game.world.water_level(pos.x, pos.z)
			var wp := Vector3(pos.x, wl, pos.z)
			_burst(root, wp, Vector3.UP, _chip_mat, 26, 0.9, Vector2(2.0, 4.8), 12.0, -9.8, Vector2(0.02, 0.05),
				Color(0.9, 0.94, 0.96, 1.0), Color(0.85, 0.9, 0.92, 1.0), 0.3)
			_burst(root, wp, Vector3.UP, _mat, 8, 0.8, Vector2(0.4, 1.4), 60.0, -1.0, Vector2(0.12, 0.3),
				Color(0.9, 0.93, 0.95, 0.5), Color(0.9, 0.93, 0.95, 0.0), 3.0)
			return
	var s: Array = SURF.get(surf, SURF.dirt)
	var dust: Color = s[0]
	var chip: Color = s[1]
	match surf:
		"wood":
			# pale splinters flung out of the hole + a little sawdust
			_burst(root, pos, n, _chip_mat, 12, 0.8, Vector2(2.0, 5.0), 40.0, -9.0, Vector2(0.012, 0.03), chip,
				chip.darkened(0.3), 0.6, Vector2(0.35, 1.6))
			_burst(root, pos, n, _mat, 8, 0.9, Vector2(0.5, 1.6), 35.0, -0.6, Vector2(0.05, 0.14),
				Color(dust, 0.55), Color(dust, 0.0), 3.0)
		"stone", "gravel", "metal":
			_burst(root, pos, n, _chip_mat, 10, 0.6, Vector2(3.0, 7.0), 45.0, -9.8, Vector2(0.008, 0.02), chip,
				chip.darkened(0.2), 0.3)
			_burst(root, pos, n, _spark_mat, 5, 0.12, Vector2(4.0, 9.0), 50.0, -3.0, Vector2(0.006, 0.012),
				Color(1, 0.8, 0.45, 1), Color(1, 0.5, 0.2, 1), 0.2)
			_burst(root, pos, n, _mat, 10, 1.1, Vector2(0.6, 2.0), 35.0, -0.4, Vector2(0.06, 0.18),
				Color(dust, 0.6), Color(dust, 0.0), 3.0)
		"snow":
			_burst(root, pos, n, _mat, 16, 1.0, Vector2(0.8, 2.8), 40.0, -2.0, Vector2(0.06, 0.2),
				Color(dust, 0.85), Color(dust, 0.0), 2.5)
		"mud":
			_burst(root, pos, n, _chip_mat, 10, 0.6, Vector2(1.5, 3.5), 35.0, -9.8, Vector2(0.015, 0.035), chip, chip, 0.3)
			_burst(root, pos, n, _mat, 4, 0.7, Vector2(0.4, 1.0), 30.0, -1.0, Vector2(0.06, 0.12),
				Color(dust, 0.4), Color(dust, 0.0), 3.0)
		_:
			# dirt / grass / sand: a dust puff tinted by the ground layer, plus clods
			_burst(root, pos, n, _mat, 16, 1.5, Vector2(0.8, 2.8), 35.0, -0.8, Vector2(0.12, 0.36),
				Color(dust, 0.75), Color(dust, 0.0), 2.5)
			_burst(root, pos, n, _chip_mat, 8, 0.6, Vector2(2.0, 4.0), 30.0, -9.8, Vector2(0.01, 0.025), chip, chip, 0.3)
	_decal(root, pos, n, surf, s[3])

static func _hole(surf: String) -> ImageTexture:
	var key := "wood" if surf == "wood" else ("stone" if surf in ["stone", "gravel", "metal"] else "soil")
	if _hole_tex.has(key):
		return _hole_tex[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in 32:
		for x in 32:
			var v := Vector2(x - 15.5, y - 15.5)
			var r := v.length() / 15.5
			var a := atan2(v.y, v.x)
			var jag := 0.08 * sin(a * 7.0) + 0.05 * sin(a * 13.0 + 1.0)
			var c := Color(0, 0, 0, 0)
			if key == "wood":
				if r < 0.22 + jag * 0.5:
					c = Color(0.05, 0.035, 0.02, 0.95)
				elif r < 0.55 + jag:
					c = Color(0.82, 0.70, 0.52, 0.85 * (1.0 - (r - 0.22) / 0.4))     # torn pale fibres
			elif key == "stone":
				if r < 0.18:
					c = Color(0.08, 0.08, 0.08, 0.9)
				elif r < 0.62 + jag:
					c = Color(0.86, 0.84, 0.80, 0.7 * (1.0 - r))                    # fresh light chip
			else:
				c = Color(0.06, 0.05, 0.04, clampf(1.0 - r - jag, 0.0, 1.0) * 0.9)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_hole_tex[key] = t
	return t

static func _decal(root: Node, pos: Vector3, n: Vector3, surf: String, tint: Color) -> void:
	if tint.a <= 0.0:
		return
	_decals = _decals.filter(func(x): return is_instance_valid(x))
	while _decals.size() >= DECAL_MAX:
		var old: Decal = _decals.pop_front()
		old.queue_free()
	var dec := Decal.new()
	var sz := 0.09 if surf in ["wood", "stone", "metal"] else 0.16
	dec.size = Vector3(sz, 0.12, sz)
	dec.texture_albedo = _hole(surf)
	dec.cull_mask = 1
	dec.normal_fade = 0.3
	root.add_child(dec)
	dec.global_position = pos
	if absf(n.dot(Vector3.UP)) < 0.99:
		dec.look_at(pos + n.cross(Vector3.UP), n)
	dec.rotate_object_local(Vector3.UP, randf() * TAU)
	_decals.append(dec)
	var tw := dec.create_tween()
	tw.tween_interval(DECAL_LIFE - DECAL_FADE)
	tw.tween_property(dec, "modulate", Color(1, 1, 1, 0), DECAL_FADE)
	tw.tween_callback(dec.queue_free)

## 0 at midday .. 1 at night (from the sky's hour), for scaling flash lights.
static func darkness() -> float:
	if night_override >= 0.0:
		return night_override
	if Game.sky == null:
		return 0.3
	var h := float(Game.sky.get("hours")) if Game.sky.get("hours") != null else 12.0
	var sun := clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)
	return clampf(1.0 - sun * 1.6, 0.0, 1.0)

static func muzzle_flash(root: Node, pos: Vector3, dir: Vector3) -> void:
	if root == null or Game.headless:
		return
	_mats()
	var dk := darkness()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.light_energy = lerpf(3.0, 14.0, dk)              # the flash lights up the street at night
	l.omni_range = lerpf(5.0, 14.0, dk)
	l.omni_attenuation = 1.4
	l.shadow_enabled = dk > 0.6 and Game.quality_name in ["high", "ultra"]
	root.add_child(l)
	l.global_position = pos + dir * 0.3
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = _flash_mat
	m.mesh = q
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos + dir * 0.22
	# a second, longer cone-ish puff of flame along the bore
	var m2 := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.22, 0.22)
	q2.material = _flash_mat
	m2.mesh = q2
	m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m2)
	m2.global_position = pos + dir * 0.45
	var t := l.get_tree().create_timer((0.06 if dk < 0.6 else 0.08) * flash_hold, true, false, true)
	t.timeout.connect(func():
		l.queue_free()
		m.queue_free()
		m2.queue_free())
