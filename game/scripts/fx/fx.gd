class_name Fx
extends Node3D
## Combat effects: tracers (Capital white-blue, Cinder orange), muzzle flashes with a few pooled lights, bullet
## impacts (dust, sparks), blood mist, rockets with smoke trails, explosions (flash light, fireball, smoke
## column, debris sparks, scorch decal, camera shake, sound). Particles come from shared GPUParticles3D systems
## through emit_particle(), so any number of impacts costs one draw call per system.

const TRACERS := 700
const FLASHES := 160
const LIGHTS := 8

var tracer_mm: MultiMesh
var tracer_buf := PackedFloat32Array()
var tr_pos := PackedVector3Array()
var tr_dir := PackedVector3Array()
var tr_end := PackedFloat32Array()     # remaining distance
var tr_col := PackedFloat32Array()     # 0 capital, 1 cinder
var tr_n := 0
var flash_mm: MultiMesh
var fl_pos := PackedVector3Array()
var fl_life := PackedFloat32Array()
var fl_size := PackedFloat32Array()
var fl_n := 0
var lights: Array[OmniLight3D] = []
var light_life := PackedFloat32Array()
var dust: GPUParticles3D
var sparks: GPUParticles3D
var smoke: GPUParticles3D
var cloud: GPUParticles3D               # collapse dust: huge, pale, slow, long-lived
var fire: GPUParticles3D
var blood_p: GPUParticles3D
var debris: GPUParticles3D
var rockets: Array = []               # [pos, vel, target, faction, trail_t, exclude]
var rockets_fired := 0
var decals: Array[Decal] = []
var _decal_i := 0
var shake := 0.0
var _scorch: Texture2D
var _hole: Texture2D
var _warm := 0


func setup() -> void:
	var soft := _soft_tex()
	# Tracers.
	tracer_mm = MultiMesh.new()
	tracer_mm.transform_format = MultiMesh.TRANSFORM_3D
	tracer_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	tracer_mm.mesh = q
	tracer_mm.instance_count = TRACERS
	tracer_mm.visible_instance_count = 0
	var tm := ShaderMaterial.new()
	tm.shader = load("res://shaders/tracer.gdshader")
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tracer_mm
	tmi.material_override = tm
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tmi.custom_aabb = AABB(Vector3(-20000, -1000, -20000), Vector3(40000, 6000, 40000))
	add_child(tmi)
	tracer_buf.resize(TRACERS * 16)
	tr_pos.resize(TRACERS); tr_dir.resize(TRACERS); tr_end.resize(TRACERS); tr_col.resize(TRACERS)
	# Muzzle flashes.
	flash_mm = MultiMesh.new()
	flash_mm.transform_format = MultiMesh.TRANSFORM_3D
	flash_mm.use_custom_data = true
	flash_mm.mesh = q
	flash_mm.instance_count = FLASHES
	flash_mm.visible_instance_count = 0
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flash.gdshader")
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = flash_mm
	fmi.material_override = fm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.custom_aabb = tmi.custom_aabb
	add_child(fmi)
	fl_pos.resize(FLASHES); fl_life.resize(FLASHES); fl_size.resize(FLASHES)
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.visible = false
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
	light_life.resize(LIGHTS)
	# Particle systems.
	dust = _particles("Dust", soft, 900, 1.6, Color(0.55, 0.5, 0.42, 0.55), Vector3(0, -1.5, 0), 0.4, 1.4, 2.5, false)
	sparks = _particles("Sparks", soft, 600, 0.45, Color(3.0, 2.0, 0.9, 1.0), Vector3(0, -9.8, 0), 0.05, 0.12, 0.2, true)
	smoke = _particles("Smoke", soft, 700, 9.0, Color(0.22, 0.21, 0.2, 0.55), Vector3(0, 1.2, 0), 3.0, 9.0, 18.0, false)
	cloud = _particles("Cloud", soft, 400, 24.0, Color(0.6, 0.57, 0.52, 0.9), Vector3(0, 0.25, 0), 14.0, 38.0, 64.0, false)
	fire = _particles("Fire", soft, 500, 0.9, Color(4.0, 1.9, 0.6, 0.9), Vector3(0, 3.0, 0), 1.5, 4.0, 6.0, true)
	blood_p = _particles("Mist", soft, 200, 0.7, Color(0.35, 0.05, 0.04, 0.6), Vector3(0, -2.0, 0), 0.25, 0.6, 1.0, false)
	debris = _particles("Debris", soft, 500, 2.5, Color(0.2, 0.19, 0.18, 1.0), Vector3(0, -9.8, 0), 0.15, 0.35, 0.4, false)
	_scorch = _decal_tex(true)
	_hole = _decal_tex(false)
	for i in 160:
		var d := Decal.new()
		d.size = Vector3(1, 2, 1)
		d.texture_albedo = _hole
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.distance_fade_enabled = true
		d.distance_fade_begin = 120.0
		d.distance_fade_length = 40.0
		add_child(d)
		decals.append(d)


func _soft_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _decal_tex(scorch: bool) -> Texture2D:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.seed = 3 if scorch else 9
	nz.frequency = 0.08
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5)
			var n := nz.get_noise_2d(x, y) * 0.3
			var a := clampf(1.0 - (d + n) * (1.1 if scorch else 2.4), 0.0, 1.0)
			var c := Color(0.04, 0.035, 0.03) if scorch else Color(0.05, 0.05, 0.05)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * (0.9 if scorch else 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _particles(nm: String, tex: Texture2D, amount: int, life: float, col: Color, grav: Vector3, s0: float, s1: float, s2: float, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.emitting = false        # emission comes only from emit_particle()
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20000, -1000, -20000), Vector3(40000, 6000, 40000))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount_ratio = 1.0
	var m := ParticleProcessMaterial.new()
	m.gravity = grav
	m.damping_min = 0.6
	m.damping_max = 1.6
	m.scale_min = s0
	m.scale_max = s0 * 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, s0 / s2 if s2 > 0 else 1.0))
	curve.add_point(Vector2(0.3, s1 / s2 if s2 > 0 else 1.0))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.scale_min = s2
	m.scale_max = s2 * 1.4
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.vertex_color_use_as_albedo = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = tex
	sm.disable_receive_shadows = true
	sm.proximity_fade_enabled = not additive
	sm.proximity_fade_distance = 1.5
	q.material = sm
	p.draw_pass_1 = q
	add_child(p)
	# Measured (tools/particle check, 2026-10-05): emit_particle() particles are dropped when amount_ratio is 0;
	# they render with amount_ratio 1 and emitting false, which also keeps the system's own emitter silent.
	p.amount_ratio = 1.0
	return p


func _emit(p: GPUParticles3D, at: Vector3, vel: Vector3, col: Color = Color(1, 1, 1, 1)) -> void:
	p.emit_particle(Transform3D(Basis.IDENTITY, at), vel, col, Color(), GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR)


func _near_cam(p: Vector3, d: float) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_squared_to(p) < d * d


# ------------------------------------------------------------------------------------------------- API

## A rifle shot from `from` toward `to`: muzzle flash, a tracer (not every round), impact effects.
func shot(from: Vector3, to: Vector3, faction: int, hit_body: bool) -> void:
	if not _near_cam(from, 2500.0) and not _near_cam(to, 2500.0):
		return
	flash(from, 0.5)
	if randf() < 0.45 or _near_cam(from, 60.0):
		tracer(from, to, faction)
	if Sfx.has_method("gunshot"):
		Sfx.gunshot(from, faction)
	if not hit_body:
		impact(to, Vector3.UP, false)


func tracer(from: Vector3, to: Vector3, faction: int) -> void:
	var i := tr_n % TRACERS
	tr_n += 1
	var d := to - from
	tr_pos[i] = from
	tr_dir[i] = d.normalized()
	tr_end[i] = d.length()
	tr_col[i] = float(faction)


func flash(at: Vector3, size: float) -> void:
	var i := fl_n % FLASHES
	fl_n += 1
	fl_pos[i] = at
	fl_life[i] = 0.06
	fl_size[i] = size
	if _near_cam(at, 80.0):
		for k in LIGHTS:
			if light_life[k] <= 0.0:
				lights[k].global_position = at
				lights[k].visible = true
				lights[k].light_energy = 2.5 * size
				light_life[k] = 0.05
				break


func impact(at: Vector3, normal: Vector3, metal: bool) -> void:
	if not _near_cam(at, 900.0):
		return
	for k in 3:
		_emit(dust, at, (normal + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6))) * randf_range(0.6, 2.0))
	if metal or randf() < 0.3:
		for k in 5:
			_emit(sparks, at, (normal * 2.0 + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1))) * randf_range(3.0, 8.0))
	if _near_cam(at, 120.0):
		decal(at, normal, 0.18, false)


func blood(at: Vector3, dir: Vector3) -> void:
	if not _near_cam(at, 300.0):
		return
	for k in 4:
		_emit(blood_p, at, dir * randf_range(0.5, 2.0) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.5), randf_range(-0.4, 0.4)))


func decal(at: Vector3, normal: Vector3, size: float, scorch: bool) -> void:
	var d := decals[_decal_i % decals.size()]
	_decal_i += 1
	d.texture_albedo = _scorch if scorch else _hole
	d.size = Vector3(size, maxf(size, 1.0), size)
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := up.cross(ref).normalized()
	var z := x.cross(up)
	d.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), at)
	d.visible = true


## A large blast: light flash, fireball, smoke column, debris, scorch, camera shake and sound.
## Visuals and sound only; damage goes through Combat.explode.
func explosion(at: Vector3, power: float = 1.0) -> void:
	if Sfx.has_method("explosion"):
		Sfx.explosion(at, power)
	if not _near_cam(at, 4000.0):
		return
	flash(at + Vector3(0, 1, 0), 3.0 * power)
	for k in LIGHTS:
		if light_life[k] <= 0.0:
			lights[k].global_position = at + Vector3(0, 3, 0)
			lights[k].visible = true
			lights[k].omni_range = 40.0 * power
			lights[k].light_energy = 14.0 * power
			light_life[k] = 0.25
			break
	var n := int(14 * power)
	for k in n:
		var v := Vector3(randf_range(-1, 1), randf_range(0.4, 1.6), randf_range(-1, 1)) * randf_range(4.0, 14.0) * sqrt(power)
		_emit(fire, at + Vector3(0, 0.5, 0), v)
	for k in int(10 * power):
		var v := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)) * randf_range(1.0, 5.0) * sqrt(power)
		_emit(smoke, at + Vector3(randf_range(-2, 2), 1.0, randf_range(-2, 2)) * power, v)
	for k in int(24 * power):
		_emit(debris, at + Vector3(0, 0.5, 0), Vector3(randf_range(-1, 1), randf_range(0.8, 2.0), randf_range(-1, 1)) * randf_range(6.0, 22.0) * sqrt(power))
	for k in int(16 * power):
		_emit(sparks, at + Vector3(0, 0.5, 0), Vector3(randf_range(-1, 1), randf_range(0.2, 1.5), randf_range(-1, 1)) * randf_range(10.0, 30.0))
	decal(at, Vector3.UP, 4.0 * power, true)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(at)
		shake = maxf(shake, clampf(power * 2.5 / maxf(d / 25.0, 1.0), 0.0, 1.5))
		if Controls.has_pad():
			Controls.rumble(clampf(shake, 0.0, 1.0), clampf(shake * 0.7, 0.0, 1.0), 0.35)


func rocket(from: Vector3, to: Vector3, faction: int, exclude: Array = []) -> void:
	var dir := (to - from).normalized()
	rockets.append([from, dir * 120.0, to, faction, 0.0, exclude])
	rockets_fired += 1
	flash(from, 1.2)
	if Sfx.has_method("rocket"):
		Sfx.rocket(from)


# ---------------------------------------------------------------------------------------------- update

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	# Warm-up: a transparent particle per system in view, so the pipelines compile at start instead of
	# swallowing the first explosion (and hitching it).
	if _warm < 30 and cam:
		_warm += 1
		if _warm % 10 == 1:
			var at := cam.global_position - cam.global_transform.basis.z * 6.0
			# Microscopic as well as transparent: the colour ramp can override the emitted alpha, and a warm-up
			# cloud particle showed as a grey column in shots.
			var tiny := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0005), at)
			for ps in [dust, sparks, smoke, cloud, fire, blood_p, debris]:
				(ps as GPUParticles3D).emit_particle(tiny, Vector3.ZERO, Color(1, 1, 1, 0), Color(),
					GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR)
	# Tracers fly at 850 m/s and draw as 9 m streaks.
	var k := 0
	for i in TRACERS:
		if tr_end[i] <= 0.0:
			continue
		var step := 850.0 * delta
		tr_pos[i] += tr_dir[i] * step
		tr_end[i] -= step
		if tr_end[i] <= 0.0:
			continue
		var o := k * 16
		var p := tr_pos[i]
		var d := tr_dir[i]
		tracer_buf[o] = 1; tracer_buf[o + 1] = 0; tracer_buf[o + 2] = 0; tracer_buf[o + 3] = p.x
		tracer_buf[o + 4] = 0; tracer_buf[o + 5] = 1; tracer_buf[o + 6] = 0; tracer_buf[o + 7] = p.y
		tracer_buf[o + 8] = 0; tracer_buf[o + 9] = 0; tracer_buf[o + 10] = 1; tracer_buf[o + 11] = p.z
		tracer_buf[o + 12] = d.x; tracer_buf[o + 13] = d.y; tracer_buf[o + 14] = d.z; tracer_buf[o + 15] = tr_col[i]
		k += 1
	tracer_mm.visible_instance_count = 0
	if k > 0:
		tracer_mm.buffer = tracer_buf
	tracer_mm.visible_instance_count = k
	# Flashes.
	var fk := 0
	var fbuf := PackedFloat32Array()
	for i in FLASHES:
		if fl_life[i] <= 0.0:
			continue
		fl_life[i] -= delta
		var p := fl_pos[i]
		var s := fl_size[i]
		fbuf.append_array([s, 0, 0, p.x, 0, s, 0, p.y, 0, 0, s, p.z, fl_life[i] / 0.06, randf(), 0, 0])
		fk += 1
	flash_mm.visible_instance_count = 0
	if fk > 0:
		fbuf.resize(FLASHES * 16)
		flash_mm.buffer = fbuf
	flash_mm.visible_instance_count = fk
	for i in LIGHTS:
		if light_life[i] > 0.0:
			light_life[i] -= delta
			if light_life[i] <= 0.0:
				lights[i].visible = false
				lights[i].omni_range = 9.0
	# Rockets: straight flight with a smoke trail, explode on arrival or when they hit the ground.
	var keep := []
	for r in rockets:
		var p: Vector3 = r[0]
		var v: Vector3 = r[1]
		var tgt: Vector3 = r[2]
		p += v * delta
		r[4] += delta
		if r[4] > 0.02:
			r[4] = 0.0
			_emit(smoke, p, Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)), Color(1, 1, 1, 0.5))
			_emit(fire, p, -v * 0.02)
		var hit: Dictionary = G.combat._trace(get_world_3d().direct_space_state, r[0], p, r[5]) if G.combat else {}
		if not hit.is_empty() or p.distance_to(tgt) < v.length() * delta * 1.5:
			var at: Vector3 = hit["position"] if not hit.is_empty() else p
			if G.combat:
				G.combat.explode(at, 0.7, hit, r[3])
			else:
				explosion(at, 0.7)
			continue
		r[0] = p
		keep.append(r)
	rockets = keep
	# Camera shake decays; the player's camera reads `shake`.
	shake = maxf(0.0, shake - delta * 1.8)
