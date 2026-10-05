class_name SkySystem
extends Node
## Day-night cycle and the environment: sun/moon positions from a latitude and season, the sky shader,
## the sun light (cascaded shadows), ambient and reflections from the sky, fog with aerial perspective,
## volumetric fog, SSAO / SSIL / SDFGI / glow per quality preset, and auto exposure.

const LATITUDE := 41.0
const DECLINATION := 12.0

var hour := 9.5                 # 0..24
var day_minutes := 32.0         # real minutes per game day
var time_scale := 1.0
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var cam_attr: CameraAttributesPractical
var sun_dir := Vector3.UP
var moon_dir := Vector3.DOWN
var daylight := 1.0             # 0 night .. 1 day
var cloud_offset := Vector2.ZERO

# Weather inputs (WeatherSystem writes these).
var cloud_cover := 0.35
var cloud_dark := 0.0
var haze := 1.0
var fog_extra := 0.0
var storm_flash := 0.0


func setup() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var nt := NoiseTexture3D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.035
	fn.fractal_octaves = 4
	fn.seed = 77
	nt.noise = fn
	nt.width = 64
	nt.height = 64
	nt.depth = 64
	nt.seamless = true
	nt.seamless_blend_skirt = 0.2
	sky_mat.set_shader_parameter("cloud_noise", nt)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00005
	env.fog_aerial_perspective = 0.85
	env.fog_sky_affect = 0.0
	env.fog_height = 120.0
	env.fog_height_density = 0.0
	env.fog_sun_scatter = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.7
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 0.9
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(0.92, 0.94, 0.97)
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.5     # lit by the sky too, or it only darkens what is behind it
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = false     # exposure follows the sky instead (deterministic)
	cam_attr.auto_exposure_scale = 0.38
	cam_attr.auto_exposure_speed = 0.7
	cam_attr.auto_exposure_min_sensitivity = 50.0
	cam_attr.auto_exposure_max_sensitivity = 900.0
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.directional_shadow_pancake_size = 40.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	if Settings.has_arg("time"):
		hour = float(Settings.arg("time"))
	Settings.changed.connect(apply_quality)
	apply_quality()
	_update(0.0)


func apply_quality() -> void:
	var q := Settings.q
	sun.directional_shadow_max_distance = q["shadow_dist"]
	sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][clampi(int(q["shadow_splits"]), 0, 4)]
	env.ssao_enabled = q["ssao"]
	env.ssil_enabled = q["ssil"]
	env.sdfgi_enabled = q["sdfgi"]
	env.ssr_enabled = q["ssr"]
	env.volumetric_fog_enabled = q["vol_fog"]
	env.glow_enabled = q["glow"]
	sky_mat.set_shader_parameter("cloud_steps", float(q["clouds_steps"]))


func clock_string() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_update(0.0)


func _process(delta: float) -> void:
	if Settings.has_arg("shots") or Settings.has_arg("benchmark") or Settings.has_arg("freeze-time"):
		_update(delta)
		return
	hour = fposmod(hour + delta * time_scale * 24.0 / (day_minutes * 60.0), 24.0)
	if Input.is_action_just_pressed("time_skip"):
		hour = fposmod(hour + 1.0, 24.0)
	_update(delta)


static func sun_vector(h: float) -> Vector3:
	var H := (h / 24.0) * TAU - PI
	var phi := deg_to_rad(LATITUDE)
	var dec := deg_to_rad(DECLINATION)
	var east := -cos(dec) * sin(H)
	var north := sin(dec) * cos(phi) - cos(dec) * cos(H) * sin(phi)
	var up := sin(dec) * sin(phi) + cos(dec) * cos(H) * cos(phi)
	return Vector3(east, up, -north).normalized()


func _update(delta: float) -> void:
	sun_dir = sun_vector(hour)
	moon_dir = sun_vector(fposmod(hour + 11.2, 24.0))
	moon_dir = (moon_dir + Vector3(0.0, 0.08, 0.0)).normalized()
	var sun_up := sun_dir.y
	daylight = smoothstep(-0.1, 0.12, sun_up)
	var moon_lit := moon_dir.y > 0.02 and sun_up < 0.0
	var ldir := sun_dir if (sun_up > -0.06 or not moon_lit) else moon_dir
	var up := Vector3.UP if absf(ldir.y) < 0.98 else Vector3.FORWARD
	sun.look_at_from_position(Vector3.ZERO, -ldir, up)
	# Sun colour from a cheap transmittance estimate; warmer near the horizon.
	var air := 1.0 / maxf(0.06, sun_up + 0.04)
	var tr := Vector3(exp(-0.012 * air), exp(-0.028 * air), exp(-0.068 * air))
	var overcast := 1.0 - cloud_cover * 0.72
	if sun_up > -0.06:
		var e := smoothstep(-0.06, 0.1, sun_up)
		sun.light_color = Color(tr.x, tr.y, tr.z).lerp(Color(1, 1, 1), 0.15)
		sun.light_energy = 3.2 * e * overcast
		sun.shadow_opacity = clampf(1.0 - cloud_cover * 0.7, 0.25, 1.0)
	else:
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.12 * smoothstep(0.02, 0.2, moon_dir.y) * overcast
		sun.shadow_opacity = 0.7
	sun.light_energy += storm_flash * 6.0
	sun.light_specular = 1.0
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("cloud_cover", cloud_cover)
	sky_mat.set_shader_parameter("cloud_dark", cloud_dark)
	sky_mat.set_shader_parameter("haze", haze)
	cloud_offset += Vector2(14.0, 5.0) * delta * (1.0 + cloud_dark * 2.0)
	sky_mat.set_shader_parameter("cloud_offset", cloud_offset)
	sky_mat.set_shader_parameter("star_rot", hour / 24.0 * TAU)
	env.background_energy_multiplier = 1.0 + storm_flash * 4.0
	var night := 1.0 - daylight
	RenderingServer.global_shader_parameter_set("night", night)
	# Fog: thin blue-grey haze in clear weather, thick in rain and storms, bluer at night.
	env.fog_density = 0.000045 * haze + fog_extra
	# Heavy haze: fog, terrain haze and water haze take the pale tone the sky shader gives a foggy horizon.
	var fogk := smoothstep(1.0, 4.0, haze)
	var pale := Color(0.78, 0.8, 0.81) * lerpf(0.06, 1.0, clampf(daylight * 2.5, 0.0, 1.0))
	env.fog_light_color = Color(0.62, 0.70, 0.82).lerp(Color(0.05, 0.07, 0.12), night).lerp(pale, fogk * 0.85)
	env.fog_light_energy = lerpf(1.0, 0.25, night)
	env.fog_height_density = 0.00025 * haze + fog_extra * 3.0
	env.volumetric_fog_density = 0.0008 + fog_extra * 2.0
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.ambient_light_energy = lerpf(0.25, 1.0, daylight)
	var hz := Color(0.58, 0.66, 0.78).lerp(Color(0.5, 0.52, 0.55), cloud_cover * 0.7) * lerpf(0.02, 1.0, daylight) * (1.0 - cloud_dark * 0.55)
	if sun_up > -0.1 and sun_up < 0.2:
		hz = hz.lerp(Color(0.9, 0.6, 0.4) * hz.get_luminance() * 1.6, (1.0 - absf(sun_up - 0.05) / 0.15) * 0.5)
	hz = hz.lerp(pale, fogk * 0.85)
	# The water fogs itself: match the terrain's exponential + height fog (3x fog_extra) so rivers and the sea do not
	# stand out bright and clear in fog weather.
	RenderingServer.global_shader_parameter_set("horizon_fog", Vector4(hz.r, hz.g, hz.b, 0.000045 * haze + fog_extra * 3.5))
	if Settings.has_arg("noambient"):
		env.ambient_light_energy = 0.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = lerpf(0.88, 2.4, night) * lerpf(1.0, 1.25, cloud_cover)
