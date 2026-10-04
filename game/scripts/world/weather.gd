class_name WeatherSystem
extends Node3D
## Weather states (clear, cloudy, overcast, fog, rain, storm, snow) blended over a minute, changing every few
## minutes. Drives the sky (cloud cover, darkness, haze), fog, wind, sea state, ground wetness and fresh snow,
## rain / snow particles around the camera (snow instead of rain above the snow line) and storm lightning.

const STATES := {
	"clear":    {"cover": 0.22, "dark": 0.0, "haze": 0.8, "fog": 0.0, "wet": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.25, "sea": 0.3, "freshsnow": 0.0},
	"cloudy":   {"cover": 0.52, "dark": 0.05, "haze": 1.0, "fog": 0.0, "wet": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.45, "sea": 0.45, "freshsnow": 0.0},
	"overcast": {"cover": 0.82, "dark": 0.25, "haze": 1.6, "fog": 0.00004, "wet": 0.1, "rain": 0.0, "snow": 0.0, "wind": 0.5, "sea": 0.5, "freshsnow": 0.0},
	"fog":      {"cover": 0.7, "dark": 0.1, "haze": 4.0, "fog": 0.0011, "wet": 0.25, "rain": 0.0, "snow": 0.0, "wind": 0.08, "sea": 0.2, "freshsnow": 0.0},
	"rain":     {"cover": 0.9, "dark": 0.45, "haze": 2.2, "fog": 0.00025, "wet": 1.0, "rain": 0.75, "snow": 0.0, "wind": 0.6, "sea": 0.65, "freshsnow": 0.0},
	"storm":    {"cover": 1.0, "dark": 0.8, "haze": 2.8, "fog": 0.00045, "wet": 1.0, "rain": 1.0, "snow": 0.0, "wind": 1.0, "sea": 1.0, "freshsnow": 0.0},
	"snow":     {"cover": 0.9, "dark": 0.3, "haze": 2.4, "fog": 0.0003, "wet": 0.2, "rain": 0.0, "snow": 1.0, "wind": 0.45, "sea": 0.55, "freshsnow": 1.0},
}
const CYCLE := ["clear", "clear", "cloudy", "overcast", "rain", "cloudy", "clear", "fog", "cloudy", "storm", "overcast", "clear"]

var state := "clear"
var cur := {}
var target := {}
var blend_speed := 1.0 / 60.0
var next_change := 420.0
var rain: GPUParticles3D
var snow: GPUParticles3D
var collider: GPUParticlesCollisionHeightField3D
var wetness := 0.0
var fresh_snow := 0.0
var wind_dir := Vector2(1.0, 0.35).normalized()
var _flash := 0.0
var _flash_t := 4.0
var _cycle_i := 0
var forced := false


func setup(_gen: WorldGen) -> void:
	cur = STATES["clear"].duplicate()
	target = cur.duplicate()
	rain = _make_particles(false)
	snow = _make_particles(true)
	collider = GPUParticlesCollisionHeightField3D.new()
	collider.size = Vector3(80, 120, 80)
	collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	collider.follow_camera_enabled = true
	add_child(collider)
	var w := String(Settings.arg("weather", ""))
	if w != "":
		set_weather(w, true)
		forced = true


func _make_particles(is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Snow" if is_snow else "Rain"
	p.amount = 9000 if not is_snow else 6000
	p.lifetime = 1.3 if not is_snow else 7.0
	p.preprocess = 1.0
	p.visibility_aabb = AABB(Vector3(-40, -60, -40), Vector3(80, 120, 80))
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.collision_base_size = 0.05
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(32, 2, 32)
	m.direction = Vector3(0, -1, 0)
	m.spread = 3.0 if not is_snow else 25.0
	m.initial_velocity_min = 22.0 if not is_snow else 0.6
	m.initial_velocity_max = 28.0 if not is_snow else 1.4
	m.gravity = Vector3(0, -9.8, 0) if not is_snow else Vector3(0, -1.1, 0)
	if is_snow:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 1.4
		m.turbulence_noise_scale = 4.0
		m.damping_min = 0.6
		m.damping_max = 1.2
	m.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55) if not is_snow else Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if not is_snow else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.75, 0.8, 0.88, 0.32) if not is_snow else Color(0.97, 0.98, 1.0, 0.9)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if not is_snow else BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sm.disable_receive_shadows = true
	q.material = sm
	p.draw_pass_1 = q
	add_child(p)
	return p


func set_weather(name: String, instant: bool = false) -> void:
	if not STATES.has(name):
		return
	state = name
	target = STATES[name].duplicate()
	if instant:
		cur = target.duplicate()
		wetness = cur["wet"]
		fresh_snow = cur["freshsnow"]
	_apply(0.0)


func _process(delta: float) -> void:
	if not forced and not Settings.has_arg("shots") and not Settings.has_arg("benchmark"):
		next_change -= delta
		if next_change <= 0.0:
			_cycle_i = (_cycle_i + 1) % CYCLE.size()
			set_weather(CYCLE[_cycle_i])
			next_change = randf_range(300.0, 720.0)
		if Input.is_action_just_pressed("weather_next"):
			_cycle_i = (_cycle_i + 1) % CYCLE.size()
			set_weather(CYCLE[_cycle_i], true)
	var k := clampf(delta * blend_speed * 3.0, 0.0, 1.0)
	for key in target:
		cur[key] = lerpf(cur[key], target[key], k)
	_apply(delta)


func _apply(delta: float) -> void:
	var sky: SkySystem = G.sky
	if sky == null:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	# Precipitation: snow instead of rain above the snow line.
	var alt_snow := smoothstep(WorldGen.SNOW_LINE - 350.0, WorldGen.SNOW_LINE - 100.0, cam_pos.y)
	var rain_amt: float = cur["rain"] * (1.0 - alt_snow)
	var snow_amt: float = maxf(cur["snow"], cur["rain"] * alt_snow)
	rain.emitting = rain_amt > 0.05
	snow.emitting = snow_amt > 0.05
	rain.amount_ratio = clampf(rain_amt, 0.0, 1.0)
	snow.amount_ratio = clampf(snow_amt, 0.0, 1.0)
	var lead := Vector3(wind_dir.x, 0.0, wind_dir.y) * -6.0 * float(cur["wind"])
	rain.global_position = cam_pos + Vector3(0, 22, 0) + lead
	snow.global_position = cam_pos + Vector3(0, 16, 0) + lead
	var pm: ParticleProcessMaterial = rain.process_material
	pm.gravity = Vector3(wind_dir.x * 6.0 * float(cur["wind"]), -9.8, wind_dir.y * 6.0 * float(cur["wind"]))
	# Ground: wet while it rains, dries slowly; fresh snow builds in snow storms.
	if delta > 0.0:
		var wet_target: float = cur["wet"]
		wetness = move_toward(wetness, wet_target, delta * (0.05 if wet_target > wetness else 0.008))
		fresh_snow = move_toward(fresh_snow, float(cur["freshsnow"]), delta * 0.01)
	RenderingServer.global_shader_parameter_set("weather_wetness", wetness)
	RenderingServer.global_shader_parameter_set("weather_snow", fresh_snow)
	var t := Time.get_ticks_msec() / 1000.0
	var gust := 0.75 + 0.25 * sin(t * 0.37) * sin(t * 1.13)
	RenderingServer.global_shader_parameter_set("wind", Vector4(wind_dir.x, float(cur["wind"]) * gust, wind_dir.y, t))
	sky.cloud_cover = cur["cover"]
	sky.cloud_dark = cur["dark"]
	sky.haze = cur["haze"]
	sky.fog_extra = cur["fog"]
	if G.world and G.world.water:
		G.world.water.sea_state = cur["sea"]
	# Storm lightning.
	if cur["dark"] > 0.6 and delta > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash = 1.0
			_flash_t = randf_range(4.0, 14.0)
			if Sfx.has_method("thunder"):
				Sfx.thunder(cam_pos + Vector3(randf_range(-3000, 3000), 400, randf_range(-3000, 3000)))
	_flash = maxf(0.0, _flash - delta * 5.0)
	var flicker := _flash * (0.6 + 0.4 * sin(t * 90.0))
	sky.storm_flash = flicker
