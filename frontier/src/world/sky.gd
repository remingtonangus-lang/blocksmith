class_name SkySystem
extends Node3D
## Time of day, sun/moon, sky shader, environment (tonemap, exposure, fog, GI) and weather state.
## Light colours come from a CPU port of the sky shader's scattering model so sun, ambient, fog and sky always agree.

signal hour_changed(hour: int)

const LAT := 0.62           # ~35.5 deg N in radians (territory latitude) for the sun path
const DAY_OF_YEAR := 285    # mid-October 1899

var env: Environment
var world_env: WorldEnvironment
var cam_attr: CameraAttributesPractical
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var hours: float = 9.0             # 0..24
var day: int = 0
var time_scale: float = 30.0       # game seconds per real second (48 min day)
var paused := false
var cloud_time := 0.0

# weather (targets + current, eased)
enum Weather { CLEAR, FAIR, OVERCAST, RAIN, STORM, FOG, DUST }
var weather: int = Weather.FAIR
var cover := 0.3
var cover_t := 0.3
var dark := 0.0
var dark_t := 0.0
var rain := 0.0
var rain_t := 0.0
var fog := 0.0
var fog_t := 0.0
var dust := 0.0
var dust_t := 0.0
var wet := 0.0
var lightning := 0.0
var _lightning_timer := 6.0
var wind := Vector2(1.0, 0.3)
var _last_hour := -1
var _env_timer := 0.0
var _rng := RandomNumberGenerator.new()
# cloud shadows: the deck's density rendered over deck space around the camera, sampled by ground/foliage shaders
const CLOUD_DECK := 2200.0         # deck height above the camera (matches the sky shader)
const SHADOW_RES := 256
const SHADOW_SPAN := 12000.0       # metres of deck covered by the map
var _shadow_vp: SubViewport
var _shadow_mat: ShaderMaterial

const PLANET_R := 6371e3
const ATMOS_R := 6471e3
const BETA_R := Vector3(5.5e-6, 13.0e-6, 22.4e-6)
const BETA_M := 21e-6

func setup(quality: Dictionary) -> void:
	_rng.seed = 1899
	if not Game.headless and quality.get("cloud_shadows", true) and not Game.disabled("cloudshadows"):
		_make_cloud_shadows()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = quality.get("ssao", true)
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssil_enabled = quality.get("ssil", false)
	env.ssr_enabled = quality.get("ssr", false)
	env.ssr_max_steps = 48
	env.sdfgi_enabled = quality.get("sdfgi", false)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH if false else Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.0
	env.fog_height = 220.0
	env.fog_height_density = 0.0015
	env.fog_aerial_perspective = 0.85
	env.fog_sun_scatter = 0.25
	env.volumetric_fog_enabled = quality.get("volumetric_fog", true)
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.62
	cam_attr.auto_exposure_speed = 0.8
	cam_attr.auto_exposure_min_sensitivity = 50.0
	cam_attr.auto_exposure_max_sensitivity = 1600.0
	world_env.camera_attributes = cam_attr
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = float(quality.get("shadow_distance", 300.0)) > 0.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = quality.get("shadow_distance", 300.0)
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 0.53
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = quality.get("moon_shadows", true)
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_volumetric_fog_energy = 0.5
	add_child(moon)
	set_weather(weather, true)
	_update(0.0, true)

func set_time(h: float) -> void:
	hours = fposmod(h, 24.0)
	_update(0.0, true)

func set_weather(w: int, instant := false) -> void:
	weather = w
	match w:
		Weather.CLEAR: cover_t = 0.05; dark_t = 0.0; rain_t = 0.0; fog_t = 0.0; dust_t = 0.0
		Weather.FAIR: cover_t = 0.32; dark_t = 0.0; rain_t = 0.0; fog_t = 0.0; dust_t = 0.0
		Weather.OVERCAST: cover_t = 0.8; dark_t = 0.25; rain_t = 0.0; fog_t = 0.1; dust_t = 0.0
		Weather.RAIN: cover_t = 0.92; dark_t = 0.5; rain_t = 0.7; fog_t = 0.25; dust_t = 0.0
		Weather.STORM: cover_t = 1.0; dark_t = 0.8; rain_t = 1.0; fog_t = 0.3; dust_t = 0.0
		Weather.FOG: cover_t = 0.6; dark_t = 0.15; rain_t = 0.0; fog_t = 1.0; dust_t = 0.0
		Weather.DUST: cover_t = 0.2; dark_t = 0.1; rain_t = 0.0; fog_t = 0.0; dust_t = 1.0
	if instant:
		cover = cover_t; dark = dark_t; rain = rain_t; fog = fog_t; dust = dust_t; wet = rain_t

func _process(dt: float) -> void:
	if not paused:
		hours += dt * time_scale / 3600.0
		if hours >= 24.0:
			hours -= 24.0
			day += 1
	cloud_time += dt * (1.0 + rain * 2.0)
	_update(dt, false)

func sun_direction() -> Vector3:
	# solar position from hour angle, declination and latitude; +X east, -Z north
	var decl := deg_to_rad(-23.44 * cos(TAU / 365.0 * (DAY_OF_YEAR + 10)))
	var ha := (hours - 12.0) / 24.0 * TAU
	var alt := asin(sin(LAT) * sin(decl) + cos(LAT) * cos(decl) * cos(ha))
	var az := atan2(-sin(ha), tan(decl) * cos(LAT) - sin(LAT) * cos(ha))   # from north, clockwise (east positive)
	return Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt)).normalized()

func moon_direction() -> Vector3:
	# simple: opposite-ish to the sun with a lag that drifts with the phase
	var ph := moon_phase()
	var lag := ph * TAU
	var d := sun_direction()
	var b := Basis(Vector3(0.25, 1.0, 0.1).normalized(), lag)
	return (b * d).normalized()

func moon_phase() -> float:
	return fposmod((day + 11.0) / 29.53, 1.0)

func is_night() -> bool:
	return sun_direction().y < -0.05

func _update(dt: float, force: bool) -> void:
	var k := 1.0 - exp(-dt * 0.02) if not force else 1.0
	cover = lerpf(cover, cover_t, k)
	dark = lerpf(dark, dark_t, k)
	rain = lerpf(rain, rain_t, k * 2.0)
	fog = lerpf(fog, fog_t, k)
	dust = lerpf(dust, dust_t, k)
	wet = clampf(wet + (rain * 0.05 - (1.0 - rain) * 0.004 * maxf(sun_direction().y, 0.0)) * dt, 0.0, 1.0) if not force else rain
	RenderingServer.global_shader_parameter_set("wetness", wet)
	RenderingServer.global_shader_parameter_set("rain_amount", rain)
	RenderingServer.global_shader_parameter_set("wind_dir", wind)
	RenderingServer.global_shader_parameter_set("wind_strength", 0.35 + cover * 0.4 + rain * 0.5 + dust * 0.8)
	# lightning flashes in storms
	lightning = maxf(lightning - dt * 6.0, 0.0)
	if rain > 0.85 and dark > 0.6:
		_lightning_timer -= dt
		if _lightning_timer < 0.0:
			lightning = 1.0
			_lightning_timer = _rng.randf_range(4.0, 16.0)
	var sd := sun_direction()
	var md := moon_direction()
	sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	moon.look_at_from_position(Vector3.ZERO, -md, Vector3.UP if absf(md.y) < 0.99 else Vector3.FORWARD)
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("moon_phase", moon_phase())
	sky_mat.set_shader_parameter("cloud_cover", cover)
	sky_mat.set_shader_parameter("cloud_dark", dark)
	sky_mat.set_shader_parameter("cloud_time", cloud_time)
	sky_mat.set_shader_parameter("wind_dir", wind)
	sky_mat.set_shader_parameter("haze", dust * 0.8 + fog * 0.4)
	sky_mat.set_shader_parameter("lightning", lightning)
	sky_mat.set_shader_parameter("star_rot", (day * 24.0 + hours) / 23.934 * TAU)
	_update_cloud_shadows(sd)
	_env_timer -= dt
	if _env_timer <= 0.0 or force:
		_env_timer = 0.25
		_update_lighting(sd, md)
	var hi := int(hours)
	if hi != _last_hour:
		_last_hour = hi
		hour_changed.emit(hi)

func _make_cloud_shadows() -> void:
	_shadow_vp = SubViewport.new()
	_shadow_vp.size = Vector2i(SHADOW_RES, SHADOW_RES)
	_shadow_vp.disable_3d = true
	_shadow_vp.transparent_bg = false
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(SHADOW_RES, SHADOW_RES)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = load("res://shaders/cloud_shadow_map.gdshader")
	rect.material = _shadow_mat
	_shadow_vp.add_child(rect)
	add_child(_shadow_vp)
	RenderingServer.global_shader_parameter_set("cloud_shadow_map", _shadow_vp.get_texture())

func _update_cloud_shadows(sd: Vector3) -> void:
	var cam: Camera3D = Game.camera
	var origin := Vector2.ZERO
	var cam_y := 0.0
	if cam:
		origin = Vector2(cam.global_position.x, cam.global_position.z)
		cam_y = cam.global_position.y
	sky_mat.set_shader_parameter("cloud_origin", origin)
	if _shadow_vp == null:
		return
	# low sun: shadows stretch and fade; overcast: light is diffuse, no distinct shadows
	var strength := 0.62 * smoothstep(0.03, 0.18, sd.y) * (1.0 - smoothstep(0.7, 0.95, cover))
	if strength <= 0.001:
		RenderingServer.global_shader_parameter_set("cloud_shadow_rect", Vector4(0, 0, 1, 0))
		_shadow_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var deck_alt := cam_y + CLOUD_DECK
	# centre the map on where the camera's own shadow ray meets the deck, snapped to texels against shimmer
	var c := origin + Vector2(sd.x, sd.z) / maxf(sd.y, 0.12) * CLOUD_DECK
	var texel := SHADOW_SPAN / SHADOW_RES
	c = (c / texel).round() * texel
	var r := Vector4(c.x - SHADOW_SPAN * 0.5, c.y - SHADOW_SPAN * 0.5, SHADOW_SPAN, strength)
	_shadow_mat.set_shader_parameter("rect", r)
	_shadow_mat.set_shader_parameter("cover", cover)
	_shadow_mat.set_shader_parameter("cloud_time", cloud_time)
	_shadow_mat.set_shader_parameter("wind_dir", wind)
	RenderingServer.global_shader_parameter_set("cloud_shadow_rect", r)
	RenderingServer.global_shader_parameter_set("cloud_sun", Vector4(sd.x, sd.y, sd.z, deck_alt))

func _update_lighting(sd: Vector3, md: Vector3) -> void:
	var trans := _transmittance(sd)
	var zen := _scatter(Vector3.UP, sd)
	var hor := _scatter(Vector3(-sd.x, 0.02, -sd.z).normalized() if Vector2(sd.x, sd.z).length() > 0.01 else Vector3(1, 0.02, 0), sd)
	var hor_sun := _scatter(Vector3(sd.x, 0.05, sd.z).normalized() if Vector2(sd.x, sd.z).length() > 0.01 else Vector3(1, 0.05, 0), sd)
	sky_mat.set_shader_parameter("zenith_col", zen)
	sky_mat.set_shader_parameter("horizon_col", (hor + hor_sun) * 0.5)
	sky_mat.set_shader_parameter("sun_trans", trans)
	# broken cloud is handled by the cloud-shadow map; the global dimming only takes over as the deck closes up
	var cloud_block := 1.0 - cover * 0.35 - smoothstep(0.55, 1.0, cover) * 0.45 - dark * 0.2
	var sun_up := smoothstep(-0.06, 0.04, sd.y)
	var c := Color(trans.x, trans.y, trans.z)
	var mx := maxf(c.r, maxf(c.g, c.b))
	if mx > 0.0:
		c = Color(c.r / mx, c.g / mx, c.b / mx)
	sun.light_color = c.lerp(Color(0.85, 0.88, 0.95), cover * 0.6)
	sun.light_energy = 3.6 * sun_up * clampf(cloud_block, 0.08, 1.0) * clampf(mx * 1.6, 0.0, 1.0) + lightning * 4.0
	sun.visible = sun.light_energy > 0.001
	var phase_lit := 1.0 - absf(moon_phase() * 2.0 - 1.0)
	var moon_up := smoothstep(-0.02, 0.1, md.y) * (1.0 - sun_up)
	moon.light_energy = 0.07 * phase_lit * moon_up * clampf(1.0 - cover * 0.8, 0.1, 1.0)
	moon.visible = moon.light_energy > 0.002
	var night := 1.0 - sun_up
	env.ambient_light_energy = lerpf(0.72, 0.6, night) * (1.0 - dark * 0.35) * (1.0 + cover * 0.4)
	env.ambient_light_sky_contribution = 1.0
	# fog colour = horizon colour (aerial perspective), heavier in fog/rain/dust
	var fogc := Color((hor.x + hor_sun.x) * 0.5, (hor.y + hor_sun.y) * 0.5, (hor.z + hor_sun.z) * 0.5)
	fogc = fogc.lerp(Color(0.72, 0.56, 0.38) * fogc.get_luminance() * 2.2, dust)
	env.fog_light_color = fogc
	env.fog_light_energy = 1.0
	env.fog_density = 0.00008 + cover * 0.00006 + fog * 0.004 + rain * 0.0012 + dust * 0.003
	# valley mist lives in the height fog (pools low, leaves the ridges clear); volumetric fog carries weather
	env.fog_height_density = 0.0008 + fog * 0.02 + _valley_mist() * 0.008
	env.volumetric_fog_density = 0.0015 + fog * 0.03 + rain * 0.006 + dust * 0.02 + _valley_mist() * 0.003
	env.volumetric_fog_length = 220.0 + fog * 380.0
	# storms read dark: hold exposure down instead of letting auto exposure lift the gloom back to daylight
	cam_attr.auto_exposure_scale = 0.62 * (1.0 - dark * 0.5) * (1.0 - fog * 0.15)
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.92).lerp(Color(0.85, 0.7, 0.5), dust)
	env.glow_intensity = 0.3 + night * 0.25

## Morning valley mist: denser just after sunrise in calm weather.
func _valley_mist() -> float:
	var morning := smoothstep(4.5, 6.0, hours) * smoothstep(9.5, 7.0, hours)
	return morning * (1.0 - dust) * (1.0 - cover * 0.5)

func _ray_sphere_far(ro: Vector3, rd: Vector3, r: float) -> float:
	var b := ro.dot(rd)
	var c := ro.dot(ro) - r * r
	var d := b * b - c
	if d < 0.0:
		return -1.0
	return -b + sqrt(d)

func _transmittance(sd: Vector3) -> Vector3:
	var ro := Vector3(0, PLANET_R + 400.0, 0)
	var L := _ray_sphere_far(ro, sd, ATMOS_R)
	var ds := L / 8.0
	var odr := 0.0
	var odm := 0.0
	for j in 8:
		var p := ro + sd * (j + 0.5) * ds
		var h := maxf(p.length() - PLANET_R, 0.0)
		odr += exp(-h / 8000.0) * ds
		odm += exp(-h / 1200.0) * ds
	var bm := BETA_M * (1.0 + (dust * 0.8 + fog * 0.4) * 6.0) * 1.1
	return Vector3(exp(-(BETA_R.x * odr + bm * odm)), exp(-(BETA_R.y * odr + bm * odm)), exp(-(BETA_R.z * odr + bm * odm)))

func _scatter(rd: Vector3, sd: Vector3) -> Vector3:
	var ro := Vector3(0, PLANET_R + 400.0, 0)
	var tmax := _ray_sphere_far(ro, rd, ATMOS_R)
	var steps := 10
	var ds := tmax / steps
	var sr := Vector3.ZERO
	var sm := Vector3.ZERO
	var odr := 0.0
	var odm := 0.0
	var mu := rd.dot(sd)
	var pr := 3.0 / (16.0 * PI) * (1.0 + mu * mu)
	var g := 0.76
	var pm := 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5))
	var bm := BETA_M * (1.0 + (dust * 0.8 + fog * 0.4) * 6.0)
	for i in steps:
		var p := ro + rd * (i + 0.5) * ds
		var h := p.length() - PLANET_R
		var hr := exp(-h / 8000.0) * ds
		var hm := exp(-h / 1200.0) * ds
		odr += hr
		odm += hm
		var L := _ray_sphere_far(p, sd, ATMOS_R)
		var lds := L / 4.0
		var lodr := 0.0
		var lodm := 0.0
		var lit := true
		for j in 4:
			var lp := p + sd * (j + 0.5) * lds
			var lh := lp.length() - PLANET_R
			if lh < 0.0:
				lit = false
				break
			lodr += exp(-lh / 8000.0) * lds
			lodm += exp(-lh / 1200.0) * lds
		if lit:
			var tr := odr + lodr
			var tm := (odm + lodm) * bm * 1.1
			var att := Vector3(exp(-(BETA_R.x * tr + tm)), exp(-(BETA_R.y * tr + tm)), exp(-(BETA_R.z * tr + tm)))
			sr += att * hr
			sm += att * hm
	return 22.0 * (sr * BETA_R * pr + sm * bm * pm)
