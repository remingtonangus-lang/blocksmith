extends Node3D
## Precipitation and airborne particles around the camera, driven by the sky's weather state: rain streaks (wind-
## slanted, motion-stretched), ground splashes, snowflakes above the snow line, blowing dust in dust storms.
## GPUParticles3D on Forward+, CPUParticles3D on Mobile (Quest), amounts scaled by intensity and quality.

var rain: GPUParticles3D
var splash: GPUParticles3D
var snow: GPUParticles3D
var dust: GPUParticles3D

func _ready() -> void:
	if Game.headless:
		set_process(false)
		return
	rain = _make_rain()
	splash = _make_splash()
	snow = _make_snow()
	dust = _make_dust()
	for p in [rain, splash, snow, dust]:
		add_child(p)

func _box_mat(extents: Vector3, vel: Vector3, spread: float, scale_min: float, scale_max: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = vel.normalized()
	m.spread = spread
	m.initial_velocity_min = vel.length() * 0.85
	m.initial_velocity_max = vel.length() * 1.15
	m.gravity = Vector3.ZERO
	m.scale_min = scale_min
	m.scale_max = scale_max
	return m

func _unshaded(color: Color, add := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 9000
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	p.local_coords = false
	p.process_material = _box_mat(Vector3(22, 2, 22), Vector3(0.0, -16.0, 0.0), 2.0, 1.0, 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var mat := _unshaded(Color(0.75, 0.8, 0.9, 0.32))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 1600
	p.lifetime = 0.25
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	var m := _box_mat(Vector3(14, 0.05, 14), Vector3(0, 1.2, 0), 60.0, 0.6, 1.2)
	m.gravity = Vector3(0, -9.0, 0)
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var mat := _unshaded(Color(0.85, 0.88, 0.95, 0.35))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

func _make_snow() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 5000
	p.lifetime = 6.0
	p.preprocess = 4.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var m := _box_mat(Vector3(25, 6, 25), Vector3(0, -1.4, 0), 25.0, 0.6, 1.4)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.2
	m.turbulence_noise_scale = 4.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var mat := _unshaded(Color(1, 1, 1, 0.85))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 700
	p.lifetime = 4.0
	p.preprocess = 2.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var m := _box_mat(Vector3(30, 4, 30), Vector3(7.0, 0.3, 2.0), 15.0, 2.0, 6.0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mat := _unshaded(Color(0.72, 0.56, 0.38, 0.07))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

func _process(_dt: float) -> void:
	var sky = Game.sky
	var cam: Camera3D = Game.camera
	if sky == null or cam == null:
		return
	var cp := cam.global_position
	var ground := Game.world.height(cp.x, cp.z)
	var snow_line := 1150.0
	var cold := smoothstep(snow_line - 100.0, snow_line, cp.y)
	var r: float = sky.rain
	var wind: Vector2 = sky.wind
	rain.global_position = cp + Vector3(wind.x * 3.0, 9.0, wind.y * 3.0)
	snow.global_position = cp + Vector3(0, 7.0, 0)
	splash.global_position = Vector3(cp.x, ground + 0.05, cp.z)
	dust.global_position = cp + Vector3(-wind.x * 10.0, 1.5, -wind.y * 10.0)
	var rain_amt := r * (1.0 - cold)
	rain.emitting = rain_amt > 0.05
	rain.amount_ratio = clampf(rain_amt, 0.0, 1.0)
	(rain.process_material as ParticleProcessMaterial).direction = Vector3(wind.x * 0.25, -1.0, wind.y * 0.25).normalized()
	splash.emitting = rain_amt > 0.2 and cp.y - ground < 6.0
	splash.amount_ratio = clampf(rain_amt, 0.0, 1.0)
	snow.emitting = r * cold > 0.05
	snow.amount_ratio = clampf(r * cold, 0.0, 1.0)
	dust.emitting = sky.dust > 0.1
	dust.amount_ratio = clampf(sky.dust, 0.0, 1.0)
