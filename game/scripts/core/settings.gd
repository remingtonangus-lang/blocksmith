extends Node
## Quality presets (Low / Medium / High / Ultra), user options and their persistence (user://settings.cfg).
## Systems read `Settings.q` (the active quality table) and listen to `changed`.

signal changed

const PATH := "user://settings.cfg"
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]

# One row per preset. render_scale is the 3D resolution relative to the window (upscaled by MetalFX / FSR2).
const PRESETS := {
	"Low": {
		"render_scale": 0.5, "upscaler": "fsr1", "msaa": 0, "taa": false, "fxaa": true,
		"shadow_size": 2048, "shadow_dist": 260.0, "shadow_splits": 2, "soft_shadows": 0,
		"ssao": false, "ssil": false, "sdfgi": false, "ssr": false, "vol_fog": false, "glow": true,
		"clouds_steps": 0, "view_dist": 9000.0, "veg_density": 0.45, "veg_dist": 260.0, "grass": false,
		"grass_dist": 0.0, "tree_far": 1800.0, "lod_bias": 0.6, "terrain_detail": 0.6, "city_detail": 0.5,
		"particles": 0.5, "decals": 64, "debris": 24, "lights": 8, "water_quality": 0,
	},
	"Medium": {
		"render_scale": 0.62, "upscaler": "metalfx_spatial", "msaa": 0, "taa": false, "fxaa": true,
		"shadow_size": 4096, "shadow_dist": 420.0, "shadow_splits": 3, "soft_shadows": 1,
		"ssao": true, "ssil": false, "sdfgi": false, "ssr": false, "vol_fog": true, "glow": true,
		"clouds_steps": 16, "view_dist": 14000.0, "veg_density": 0.7, "veg_dist": 420.0, "grass": true,
		"grass_dist": 45.0, "tree_far": 3200.0, "lod_bias": 0.85, "terrain_detail": 0.8, "city_detail": 0.75,
		"particles": 0.75, "decals": 128, "debris": 48, "lights": 16, "water_quality": 1,
	},
	"High": {
		"render_scale": 0.67, "upscaler": "metalfx_temporal", "msaa": 0, "taa": false, "fxaa": false,
		"shadow_size": 4096, "shadow_dist": 700.0, "shadow_splits": 4, "soft_shadows": 2,
		"ssao": true, "ssil": false, "sdfgi": false, "ssr": false, "vol_fog": true, "glow": true,
		"clouds_steps": 28, "view_dist": 20000.0, "veg_density": 1.0, "veg_dist": 650.0, "grass": true,
		"grass_dist": 70.0, "tree_far": 5000.0, "lod_bias": 1.0, "terrain_detail": 1.0, "city_detail": 1.0,
		"particles": 1.0, "decals": 192, "debris": 80, "lights": 24, "water_quality": 2,
	},
	"Ultra": {
		"render_scale": 0.85, "upscaler": "metalfx_temporal", "msaa": 0, "taa": false, "fxaa": false,
		"shadow_size": 8192, "shadow_dist": 1100.0, "shadow_splits": 4, "soft_shadows": 3,
		"ssao": true, "ssil": true, "sdfgi": true, "ssr": true, "vol_fog": true, "glow": true,
		"clouds_steps": 44, "view_dist": 26000.0, "veg_density": 1.35, "veg_dist": 900.0, "grass": true,
		"grass_dist": 95.0, "tree_far": 7000.0, "lod_bias": 1.4, "terrain_detail": 1.25, "city_detail": 1.0,
		"particles": 1.25, "decals": 256, "debris": 120, "lights": 32, "water_quality": 2,
	},
}

var preset := "High"
var q: Dictionary = PRESETS["High"].duplicate()

# User options (not part of a preset).
var fullscreen := true
var vsync := true
var fov := 78.0
var master_volume := 0.9
var music_volume := 0.5
var sfx_volume := 1.0
var show_perf := false
var adaptive_resolution := true
var target_fps := 60.0
var mouse_sensitivity := 0.12
var invert_y := false

## Command-line options: Godot passes unknown options through, user options come after `--`.
var args := {}


func _ready() -> void:
	_parse_args()
	_limit_to_gpu()
	load_settings()
	if args.has("preset"):
		set_preset(String(args["preset"]).capitalize())
	if args.has("windowed") or args.has("benchmark") or args.has("shots") or args.has("smoke") or args.has("scenario"):
		fullscreen = false
	if args.has("benchmark") and not args.has("vsync"):
		vsync = false          # measure the headroom, not the display refresh


var raw_cmdline := ""


func _parse_args() -> void:
	var all: PackedStringArray = OS.get_cmdline_args()
	all.append_array(OS.get_cmdline_user_args())
	# Godot consumes some of its own options before the game sees them (--benchmark, --windowed, ...). On macOS
	# and Linux, read this process's real command line so `Alabaster --benchmark` works without `--`.
	if OS.get_name() in ["macOS", "Linux"] and not OS.has_feature("web"):
		var out := []
		if OS.execute("ps", ["-o", "args=", "-p", str(OS.get_process_id())], out) == 0 and out.size() > 0:
			raw_cmdline = String(out[0]).strip_edges()
			for tok in raw_cmdline.split(" ", false):
				if tok in ["--benchmark", "--windowed"] and not all.has(tok):
					all.append(tok)
	var env := OS.get_environment("CAPITAL_ARGS")
	if env != "":
		all.append_array(env.split(" ", false))
	var i := 0
	while i < all.size():
		var a: String = all[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val: Variant = true
			if key.contains("="):
				val = key.get_slice("=", 1)
				key = key.get_slice("=", 0)
			elif i + 1 < all.size() and not all[i + 1].begins_with("--") and _takes_value(key):
				val = all[i + 1]
				i += 1
			args[key] = val
		i += 1
	if args.has("bench"):
		args["benchmark"] = true


func _takes_value(key: String) -> bool:
	return key in ["preset", "seed", "time", "weather", "shots", "smoke", "spawn", "scene", "benchmark-out",
		"only", "yaw", "pitch", "scale", "res", "shard", "scenario"]


func arg(key: String, default: Variant = null) -> Variant:
	return args.get(key, default)


func has_arg(key: String) -> bool:
	return args.has(key)


func set_preset(name: String) -> void:
	if not PRESETS.has(name):
		push_warning("unknown preset %s" % name)
		return
	preset = name
	q = PRESETS[name].duplicate()
	_limit_to_gpu()
	changed.emit()


## Virtual / low-feature GPUs (the CI runner's "Apple Paravirtual device", software rasterisers) lack the atomic
## storage images that volumetric fog, SDFGI and SSIL need: switch those off there.
func _limit_to_gpu() -> void:
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.contains("Paravirtual") or has_arg("safe-gpu"):
		q["vol_fog"] = false
		q["sdfgi"] = false
		q["ssil"] = false


func set_q(key: String, value: Variant) -> void:
	q[key] = value
	changed.emit()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var p: String = cf.get_value("quality", "preset", "High")
	if PRESETS.has(p):
		preset = p
		q = PRESETS[p].duplicate()
	var overrides: Dictionary = cf.get_value("quality", "overrides", {})
	for k in overrides:
		q[k] = overrides[k]
	_limit_to_gpu()
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	vsync = cf.get_value("display", "vsync", vsync)
	fov = cf.get_value("display", "fov", fov)
	adaptive_resolution = cf.get_value("display", "adaptive_resolution", adaptive_resolution)
	show_perf = cf.get_value("display", "show_perf", show_perf)
	master_volume = cf.get_value("audio", "master", master_volume)
	music_volume = cf.get_value("audio", "music", music_volume)
	sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
	mouse_sensitivity = cf.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cf.get_value("controls", "invert_y", invert_y)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("quality", "preset", preset)
	var overrides := {}
	var base: Dictionary = PRESETS[preset]
	for k in q:
		if base.get(k) != q[k]:
			overrides[k] = q[k]
	cf.set_value("quality", "overrides", overrides)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "fov", fov)
	cf.set_value("display", "adaptive_resolution", adaptive_resolution)
	cf.set_value("display", "show_perf", show_perf)
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.save(PATH)


func is_mac() -> bool:
	return OS.get_name() == "macOS"


## Applies the display side of the active preset to a viewport (3D scaling, AA, shadows).
func apply_viewport(vp: Viewport) -> void:
	var scale: float = q["render_scale"]
	if has_arg("scale"):
		scale = float(arg("scale"))
	vp.scaling_3d_scale = clampf(scale, 0.25, 2.0)
	var up: String = q["upscaler"]
	var mode := Viewport.SCALING_3D_MODE_FSR2
	if up == "fsr1":
		mode = Viewport.SCALING_3D_MODE_FSR
	elif up == "metalfx_spatial":
		mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL if _metal() else Viewport.SCALING_3D_MODE_FSR
	elif up == "metalfx_temporal":
		mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if _metal() else Viewport.SCALING_3D_MODE_FSR2
	if scale >= 0.999 and not q["taa"]:
		mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_mode = mode
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(q["msaa"]) / 2, 0, 2)]
	vp.use_taa = bool(q["taa"]) and mode != Viewport.SCALING_3D_MODE_FSR2 and mode != Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 1.5 / float(q["lod_bias"])
	vp.use_occlusion_culling = true
	vp.positional_shadow_atlas_size = 2048
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow_size"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(q["soft_shadows"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(maxi(0, int(q["soft_shadows"]) - 1))


func _metal() -> bool:
	return RenderingServer.get_current_rendering_driver_name() == "metal"


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
