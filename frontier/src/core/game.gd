extends Node
## Global game state (autoload "Game"): command-line options, quality presets, references to the live world,
## simple event bus. Gameplay systems register themselves here; tests and bots read it.

signal world_ready
signal message(text: String, seconds: float)
signal noise(pos: Vector3, radius: float, source: Node)   # gunshots, shouts, breaking glass: AI hearing

const PRESETS := {
	"low": {"tree_near": 65.0, "shrub_near": 40.0, "render_scale": 0.6, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false,
		"shadow_distance": 120.0, "shadow_size": 2048, "terrain_range": 1.8, "grass_density": 0.35, "grass_dist": 40.0,
		"tree_dist": 900.0, "moon_shadows": false, "upscale": "fsr", "msaa": 0, "taa": false, "lod_bias": 0.5},
	"medium": {"tree_near": 85.0, "shrub_near": 50.0, "render_scale": 0.75, "ssao": true, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": true,
		"shadow_distance": 200.0, "shadow_size": 4096, "terrain_range": 2.2, "grass_density": 0.6, "grass_dist": 60.0,
		"tree_dist": 1500.0, "moon_shadows": false, "upscale": "metalfx_spatial", "msaa": 0, "taa": true, "lod_bias": 0.8},
	"high": {"tree_near": 100.0, "shrub_near": 60.0, "render_scale": 0.77, "ssao": true, "ssil": false, "ssr": true, "sdfgi": false, "volumetric_fog": true,
		"shadow_distance": 300.0, "shadow_size": 4096, "terrain_range": 2.6, "grass_density": 1.0, "grass_dist": 80.0,
		"tree_dist": 2500.0, "moon_shadows": true, "upscale": "metalfx_temporal", "msaa": 0, "taa": false, "lod_bias": 1.0},
	"ultra": {"tree_near": 150.0, "shrub_near": 80.0, "render_scale": 1.0, "ssao": true, "ssil": true, "ssr": true, "sdfgi": true, "volumetric_fog": true,
		"shadow_distance": 450.0, "shadow_size": 8192, "terrain_range": 3.2, "grass_density": 1.4, "grass_dist": 110.0,
		"tree_dist": 4000.0, "moon_shadows": true, "upscale": "metalfx_temporal", "msaa": 0, "taa": false, "lod_bias": 1.5},
	"preview": {"tree_near": 100.0, "shrub_near": 60.0, "render_scale": 1.0, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false,
		"shadow_distance": 250.0, "shadow_size": 4096, "terrain_range": 2.2, "grass_density": 0.6, "grass_dist": 60.0,
		"tree_dist": 1200.0, "moon_shadows": false, "upscale": "none", "msaa": 0, "taa": false, "lod_bias": 1.0},
	"quest": {"tree_near": 45.0, "shrub_near": 30.0, "render_scale": 1.0, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "volumetric_fog": false,
		"shadow_distance": 60.0, "shadow_size": 2048, "terrain_range": 1.5, "grass_density": 0.25, "grass_dist": 30.0,
		"tree_dist": 700.0, "moon_shadows": false, "cloud_shadows": false, "upscale": "none", "msaa": 2, "taa": false, "lod_bias": 0.4,
		"shadow_splits": 2, "glow": false, "water_refraction": false, "mounted_horse_lod1": true},     # see design/VR.md (Mobile renderer, stereo)
}

var args := {}                 # --key value / --flag from the command line (after "--" too)
var quality_name := "high"
var quality: Dictionary = PRESETS["high"]
var world: WorldData
var terrain: Node
var sky: Node
var player: Node3D
var camera: Camera3D
var main: Node
var audio: Node               # AudioDirector (src/audio/audio_director.gd)
var hud: Node
var missions: Node            # MissionDirector
var state: Node               # WorldState (standing, money, law, saves)
var menus: Node
var wildlife: Node
var camp: Node
var roads: RoadGraph
var encounters: Node
var robbery: Node              # hold-ups and store robberies (src/systems/robbery.gd)
var fishing: Node              # src/systems/fishing.gd
var population: Node           # town life: residents, schedules, spot claims (src/ai/population.gd)
var is_vr := false
var headless := false
var rng := RandomNumberGenerator.new()
var log_lines: PackedStringArray = []
var error_logger: ErrorLogger

func _init() -> void:
	_parse_args()
	rng.seed = int(args.get("seed", 1899))
	headless = DisplayServer.get_name() == "headless"
	if args.has("quality"):
		set_quality(str(args["quality"]))
	elif RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe"):
		set_quality("preview")       # software rendering in the cloud session: keep shots fast
	elif OS.has_feature("android"):
		set_quality("quest")
	if args.has("disable"):
		quality = quality.duplicate()
		if disabled("vfog"): quality["volumetric_fog"] = false
		if disabled("ssr"): quality["ssr"] = false
		if disabled("ssao"): quality["ssao"] = false
		if disabled("ssil"): quality["ssil"] = false
		if disabled("grass"): quality["grass_density"] = 0.0
		if disabled("trees"): quality["tree_dist"] = 1.0
		if disabled("shadows"): quality["shadow_distance"] = 0.0

func _enter_tree() -> void:
	error_logger = ErrorLogger.new()
	OS.add_logger(error_logger)

func _parse_args() -> void:
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var i := 0
	while i < all.size():
		var a: String = all[i]
		if a.begins_with("--") and a.length() > 2:
			var key := a.substr(2)
			if key.contains("="):
				var kv := key.split("=", true, 1)
				args[kv[0]] = kv[1]
			elif i + 1 < all.size() and not all[i + 1].begins_with("--"):
				args[key] = all[i + 1]
				i += 1
			else:
				args[key] = true
		i += 1

func arg(key: String, default = null):
	return args.get(key, default)

func arg_f(key: String, default: float) -> float:
	return float(args.get(key, default))

## Feature kill-switches for perf attribution: --disable vfog,ssr,ssao,ssil,grass,trees,shadows,scatter,water,clouds
## --prof: report any single operation slower than 15 ms (spawns, builds) with a label.
func prof(label: String, t0_usec: int) -> void:
	if args.has("prof"):
		var ms := (Time.get_ticks_usec() - t0_usec) / 1000.0
		if ms > 15.0:
			print("PROF %s %.1f ms" % [label, ms])

var prof_acc := {}                # label -> usec accumulated this frame (--prof)
func acc(label: String, t0_usec: int) -> void:
	prof_acc[label] = int(prof_acc.get(label, 0)) + Time.get_ticks_usec() - t0_usec

func disabled(feature: String) -> bool:
	return str(args.get("disable", "")).split(",").has(feature)

func set_quality(name: String) -> void:
	if not PRESETS.has(name):
		push_warning("unknown quality preset " + name)
		return
	quality_name = name
	quality = PRESETS[name]

func log_event(kind: String, data: Dictionary = {}) -> void:
	var line := "%.2f %s %s" % [Time.get_ticks_msec() / 1000.0, kind, JSON.stringify(data)]
	log_lines.append(line)
	if args.has("verbose"):
		print(line)

func say(text: String, seconds := 4.0) -> void:
	message.emit(text, seconds)

## Automated modes must never hang: quit with an error after a hard time limit.
func arm_watchdog(seconds: float) -> void:
	var t := Timer.new()
	t.wait_time = seconds
	t.one_shot = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		push_error("WATCHDOG: no completion after %d s" % int(seconds))
		print("WATCHDOG: no completion after %d s" % int(seconds))
		get_tree().quit(3))
	t.start()

func _ready() -> void:
	if args.has("shot") or args.has("tour") or args.has("bot") or args.has("benchmark") or args.has("smoke"):
		arm_watchdog(float(args.get("watchdog", 1800)))
	# Mobile renderer (Quest): with the project's soft shadow filter quality 3 (and Soft Low, 2), every StandardMaterial3D
	# surface lost all direct sunlight whenever the sun cast shadows (props, guns, ground read dark grey); custom
	# shaders were unaffected. Soft Very Low (1) renders correctly and is the right cost for a Quest anyway. See design/VR.md.
	if not headless and RenderingServer.get_current_rendering_method() == "mobile":
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
