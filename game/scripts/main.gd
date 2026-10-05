extends Node3D
## Boot: settings and window, the loading screen while the world generates on a thread, then the world,
## the player and the HUD. Command-line modes: --benchmark, --shots DIR, --smoke SECONDS, --padcheck.

var load_seconds := 0.0
var _t0 := 0
var _gen: WorldGen
var _thread: Thread
var _loading: CanvasLayer
var _load_label: Label
var _load_bar: ColorRect
var _ready_to_build := false
var _built := false
var _smoke_t := 0.0
var _smoke_frames := 0
var _last_stage := ""


func _ready() -> void:
	G.main = self
	_t0 = Time.get_ticks_msec()
	G.seed = int(Settings.arg("seed", 1337))
	Settings.apply_window()
	if Settings.has_arg("res") and DisplayServer.get_name() != "headless":
		var r := String(Settings.arg("res")).split("x")
		if r.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(r[0]), int(r[1])))
	Settings.apply_viewport(get_viewport())
	Settings.changed.connect(func(): Settings.apply_viewport(get_viewport()))
	G.log_line("Alabaster %s on %s, %s / %s, preset %s, args %s" % [ProjectSettings.get_setting("application/config/version"),
		OS.get_name(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(),
		Settings.preset, str(Settings.args)])
	if Settings.raw_cmdline != "":
		G.log_line("command line: %s" % Settings.raw_cmdline)
	if Settings.has_arg("padcheck"):
		_padcheck()
		return
	_make_loading()
	_gen = WorldGen.new(G.seed)
	G.gen = _gen
	_thread = Thread.new()
	_thread.start(_generate)


func _generate() -> void:
	_gen.generate(not Settings.has_arg("regen"))
	call_deferred("_on_generated")


func _on_generated() -> void:
	_thread.wait_to_finish()
	_ready_to_build = true


func _make_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.94, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var title := Label.new()
	title.text = "A L A B A S T E R"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.18, 0.2, 0.23))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-280, -90)
	title.size = Vector2(560, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(title)
	_load_label = Label.new()
	_load_label.add_theme_color_override("font_color", Color(0.35, 0.38, 0.42))
	_load_label.set_anchors_preset(Control.PRESET_CENTER)
	_load_label.position = Vector2(-280, 0)
	_load_label.size = Vector2(560, 30)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(_load_label)
	var track := ColorRect.new()
	track.color = Color(0.8, 0.82, 0.85)
	track.set_anchors_preset(Control.PRESET_CENTER)
	track.position = Vector2(-200, 40)
	track.size = Vector2(400, 3)
	_loading.add_child(track)
	_load_bar = ColorRect.new()
	_load_bar.color = Color(0.25, 0.28, 0.32)
	_load_bar.set_anchors_preset(Control.PRESET_CENTER)
	_load_bar.position = Vector2(-200, 40)
	_load_bar.size = Vector2(0, 3)
	_loading.add_child(_load_bar)
	add_child(_loading)


func _process(delta: float) -> void:
	G.frame += 1
	if not _built:
		if _gen and _gen.stage != _last_stage:
			_last_stage = _gen.stage
			G.log_line("loading: %s (%.1f s)" % [_last_stage, (Time.get_ticks_msec() - _t0) / 1000.0])
		if (Settings.has_arg("benchmark") or Settings.has_arg("smoke")) and Time.get_ticks_msec() - _t0 > 300000:
			G.log_line("loading: TIMEOUT, the world did not finish in 300 s (stage '%s')" % (_gen.stage if _gen else "?"))
			get_tree().quit(3)
			return
		if _load_label and _gen:
			_load_label.text = "The Capital is waking: %s" % _gen.stage
			_load_bar.size.x = 400.0 * _gen.progress
		if _ready_to_build:
			_build()
		return
	if Settings.has_arg("smoke"):
		_smoke_t += delta
		_smoke_frames += 1
		if _smoke_t >= float(Settings.arg("smoke", 30)):
			G.log_line("smoke: ok, %d frames in %.1f s (%.1f fps), mem %.0f MB" % [_smoke_frames, _smoke_t,
				_smoke_frames / _smoke_t, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
			get_tree().quit(0)


func _build() -> void:
	_built = true
	var world := preload("res://scripts/world/world.gd").new()
	world.name = "World"
	add_child(world)
	world.setup(_gen)
	load_seconds = (Time.get_ticks_msec() - _t0) / 1000.0
	G.log_line("world ready in %.2f s" % load_seconds)
	var hud := preload("res://scripts/core/perf_hud.gd").new()
	add_child(hud)
	add_child(preload("res://scripts/core/adaptive_res.gd").new())
	if Settings.has_arg("benchmark"):
		G.log_line("benchmark: mode on, starting the flythrough")
		var b := preload("res://scripts/core/benchmark.gd").new()
		add_child(b)
		b.start(world.benchmark_segments())
	elif Settings.has_arg("drawreport"):
		var want := String(Settings.arg("drawreport"))
		for sg in world.benchmark_segments():
			if sg["name"] == want:
				var d := preload("res://scripts/core/draw_report.gd").new()
				add_child(d)
				d.start(sg)
	elif Settings.has_arg("shots"):
		var s := preload("res://scripts/core/shots.gd").new()
		s.process_mode = Node.PROCESS_MODE_ALWAYS          # the pause_menu shot pauses the game
		add_child(s)
		s.start(world.shot_list(), String(Settings.arg("shots")))
	else:
		world.spawn_player()
		var menu := PauseMenu.new()
		menu.name = "PauseMenu"
		add_child(menu)
		if Settings.has_arg("scenario"):
			var sc := preload("res://scripts/core/scenarios.gd").new()
			sc.process_mode = Node.PROCESS_MODE_ALWAYS      # keeps testing while the pause menu has the game paused
			add_child(sc)
			var names := String(Settings.arg("scenario")).split(",")
			if names[0] == "all":
				names = PackedStringArray(["ride", "drive", "fly", "dropship", "battle", "weapons", "destroy", "parked", "trees", "stand", "menu"])
			sc.start(Array(names))
	_loading.queue_free()


func _padcheck() -> void:
	# SDL enumerates pads a moment after start; wait, then write what the engine sees.
	await get_tree().create_timer(3.0).timeout
	var rep := Controls.pad_report()
	var path := G.log_dir() + "/padcheck.json"
	G.write_json(path, rep)
	G.log_line("padcheck: %s" % JSON.stringify(rep))
	get_tree().quit(0)
