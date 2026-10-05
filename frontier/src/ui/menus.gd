extends CanvasLayer
## Pause menu, settings, full-screen map and journal in Sable River's printed-paper style. Fully navigable with a
## controller (focus neighbours, D-pad / stick, A to choose, B to go back) and with mouse/keyboard. The game is
## paused while a menu is open (this layer processes always).

const SETTINGS_PATH := "user://settings.json"

var panel: PanelContainer
var stack: Array[Control] = []
var settings := {"quality": "high", "render_scale": -1.0, "fov": 62.0, "mouse_sens": 1.0, "invert_y": false,
	"subtitles": true, "vol_master": 1.0, "vol_music": 0.8, "vol_sfx": 1.0, "vol_voice": 1.0, "snap_turn": true}
var map_view: Control
var waypoint := Vector3.INF
var route := PackedVector3Array()
var _route_t := 0.0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	apply_settings()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if stack.is_empty():
			open_pause()
		else:
			back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and stack.is_empty():
		open_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and stack.is_empty():
		open_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("satchel") and stack.is_empty():
		Satchel.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B and not stack.is_empty():
		back()
		get_viewport().set_input_as_handled()

func _paper_panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.PAPER
	sb.border_color = UITheme.INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", UITheme.INK)
	b.add_theme_color_override("font_hover_color", UITheme.OXBLOOD)
	b.add_theme_color_override("font_focus_color", UITheme.OXBLOOD)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(UITheme.OXBLOOD, 0.08)
	focus.border_color = UITheme.OXBLOOD
	focus.border_width_left = 4
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(cb)
	return b

func _push(c: Control) -> void:
	if stack.is_empty():
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif stack.back():
		stack.back().visible = false
	stack.append(c)
	add_child(c)
	var first := _first_focusable(c)
	if first:
		first.grab_focus.call_deferred()

func back() -> void:
	if stack.is_empty():
		return
	var c: Control = stack.pop_back()
	c.queue_free()
	if stack.is_empty():
		get_tree().paused = false
		if not Game.headless:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		stack.back().visible = true
		var f := _first_focusable(stack.back())
		if f:
			f.grab_focus.call_deferred()

func close_all() -> void:
	while not stack.is_empty():
		back()

func _first_focusable(c: Node) -> Control:
	for n in c.find_children("*", "Control", true, false):
		if n.focus_mode == Control.FOCUS_ALL and n.visible:
			return n
	return null

# ------------------------------------------------------------------ pause
func open_pause() -> void:
	var p := _paper_panel(Vector2(560, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var title := UITheme.label("Sable River", 54, "display", UITheme.INK, false)
	v.add_child(title)
	var st = Game.get("state")
	if st != null:
		var sub := UITheme.label("%s  —  $%.2f  —  %s" % [_date_text(), st.money, st.standing_label()], 24, "italic", UITheme.INK_SOFT, false)
		v.add_child(sub)
	v.add_child(HSeparator.new())
	v.add_child(_button("Resume", back))
	v.add_child(_button("Map", open_map))
	v.add_child(_button("Journal", open_journal))
	v.add_child(_button("Settings", open_settings))
	v.add_child(_button("Save Game", func():
		if Game.state and Game.state.save_game("manual"):
			Game.say("Game saved", 2.5)
		back()))
	v.add_child(_button("Load Game", func():
		if Game.state and Game.state.load_game("manual"):
			Game.say("Game loaded", 2.5)
		close_all()))
	v.add_child(_button("Quit to Desktop", func(): get_tree().quit()))
	_push(p)

func _date_text() -> String:
	if Game.sky == null:
		return ""
	var h: float = Game.sky.hours
	var month_day := 14 + int(Game.sky.day)
	return "October %d, 1899 — %d:%02d %s" % [month_day, (int(h) + 11) % 12 + 1, int(fmod(h, 1.0) * 60.0), "a.m." if h < 12.0 else "p.m."]

# ------------------------------------------------------------------ settings
func open_settings() -> void:
	var p := _paper_panel(Vector2(760, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.label("Settings", 44, "display", UITheme.INK, false))
	v.add_child(HSeparator.new())
	var q := OptionButton.new()
	for name in ["low", "medium", "high", "ultra"]:
		q.add_item(name.capitalize())
	q.selected = ["low", "medium", "high", "ultra"].find(settings.quality)
	q.item_selected.connect(func(i):
		settings.quality = ["low", "medium", "high", "ultra"][i]
		apply_settings())
	v.add_child(_row("Graphics quality", q))
	v.add_child(_row("Render scale (upscaled)", _slider(0.5, 1.0, 0.05, settings.render_scale if settings.render_scale > 0 else Game.quality.render_scale, func(x):
		settings.render_scale = x
		apply_settings())))
	v.add_child(_row("Field of view", _slider(50, 85, 1, settings.fov, func(x):
		settings.fov = x
		apply_settings())))
	v.add_child(_row("Look sensitivity", _slider(0.3, 2.5, 0.05, settings.mouse_sens, func(x):
		settings.mouse_sens = x
		apply_settings())))
	var inv := CheckBox.new()
	inv.button_pressed = settings.invert_y
	inv.toggled.connect(func(b):
		settings.invert_y = b
		apply_settings())
	v.add_child(_row("Invert vertical look", inv))
	var subs := CheckBox.new()
	subs.button_pressed = settings.subtitles
	subs.toggled.connect(func(b):
		settings.subtitles = b
		apply_settings())
	v.add_child(_row("Subtitles", subs))
	for key in ["vol_master", "vol_music", "vol_sfx", "vol_voice"]:
		var k: String = key
		v.add_child(_row({"vol_master": "Master volume", "vol_music": "Music", "vol_sfx": "Effects", "vol_voice": "Voices"}[k],
			_slider(0.0, 1.0, 0.05, settings[k], func(x):
				settings[k] = x
				apply_settings())))
	v.add_child(_button("Back", back))
	_push(p)

func _row(label: String, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UITheme.label(label, 28, "body", UITheme.INK, false)
	l.custom_minimum_size = Vector2(340, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.focus_mode = Control.FOCUS_ALL
	h.add_child(ctl)
	return h

func _slider(lo: float, hi: float, step: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(300, 32)
	s.value_changed.connect(cb)
	return s

func apply_settings() -> void:
	if settings.quality != Game.quality_name and Game.PRESETS.has(settings.quality) and not Game.args.has("quality") \
		and Game.quality_name != "preview" and Game.quality_name != "quest":
		Game.set_quality(settings.quality)
		if Game.main and Game.main.has_method("_apply_viewport_quality"):
			Game.main._apply_viewport_quality()
	if settings.render_scale > 0.0:
		get_viewport().scaling_3d_scale = settings.render_scale
	if Game.player:
		Game.player.set("mouse_sens", 0.0025 * settings.mouse_sens)
		Game.player.set("invert_y", settings.invert_y)
	if Game.camera and Game.player and "cam_dist" in Game.player:
		Game.camera.fov = settings.fov
	for bus in [["Master", "vol_master"], ["Music", "vol_music"], ["SFX", "vol_sfx"], ["Voice", "vol_voice"]]:
		var i := AudioServer.get_bus_index(bus[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(settings[bus[1]], 0.0001)))
	_save_settings()

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _load_settings() -> void:
	var t := FileAccess.get_file_as_string(SETTINGS_PATH)
	if t.is_empty():
		return
	var d = JSON.parse_string(t)
	if typeof(d) == TYPE_DICTIONARY:
		for k in d.keys():
			settings[k] = d[k]

# ------------------------------------------------------------------ map
func open_map() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.08, 0.06, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	map_view = load("res://src/ui/map_view.gd").new()
	map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.offset_left = 60
	map_view.offset_top = 60
	map_view.offset_right = -60
	map_view.offset_bottom = -60
	map_view.focus_mode = Control.FOCUS_ALL
	map_view.menus = self
	root.add_child(map_view)
	var hint := UITheme.label("Click / A: set waypoint     Scroll / triggers: zoom     Drag / stick: pan     Esc / B: close", 22, "italic", UITheme.PAPER)
	hint.position = Vector2(70, 18)
	root.add_child(hint)
	_push(root)

func set_waypoint(p: Vector3) -> void:
	waypoint = p
	_update_route()
	Game.say("Waypoint set", 2.0)

func clear_waypoint() -> void:
	waypoint = Vector3.INF
	route = PackedVector3Array()

func _update_route() -> void:
	if waypoint == Vector3.INF or Game.player == null or Game.roads == null:
		route = PackedVector3Array()
		return
	route = Game.roads.route(Game.player.global_position, waypoint)

func _process(dt: float) -> void:
	_route_t -= dt
	if _route_t <= 0.0 and waypoint != Vector3.INF and Game.player:
		_route_t = 3.0
		if Game.player.global_position.distance_to(waypoint) < 15.0:
			clear_waypoint()
			Game.say("You have arrived", 2.0)
		else:
			_update_route()

# ------------------------------------------------------------------ journal
func open_journal() -> void:
	var p := _paper_panel(Vector2(900, 640))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UITheme.label("Journal", 48, "display", UITheme.INK, false))
	v.add_child(UITheme.label("Ruth Caddell — %s" % _date_text(), 24, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var md = Game.get("missions")
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.custom_minimum_size = Vector2(840, 430)
	body.add_theme_font_override("normal_font", UITheme.font("body"))
	body.add_theme_font_override("italics_font", UITheme.font("italic"))
	body.add_theme_font_size_override("normal_font_size", 26)
	body.add_theme_font_size_override("italics_font_size", 26)
	body.add_theme_color_override("default_color", UITheme.INK)
	var txt := ""
	if md != null:
		if md.active != null:
			txt += "[i]Now:[/i]  %s — %s\n\n" % [md.active.title, md.objective]
		for path in MissionDirector.MISSIONS:
			var m = load(path).new()
			var done: bool = md.completed.has(m.id)
			txt += ("✓  " if done else "·  ") + m.title + "\n"
	var st = Game.get("state")
	if st != null:
		txt += "\n[i]Standing:[/i] %s (%.0f)\n[i]Money:[/i] $%.2f\n" % [st.standing_label(), st.standing, st.money]
		for county in st.bounties.keys():
			if float(st.bounties[county]) > 0.0:
				txt += "[i]Bounty in %s:[/i] $%.2f\n" % [county, st.bounties[county]]
	body.text = txt
	body.focus_mode = Control.FOCUS_ALL
	v.add_child(body)
	v.add_child(_button("Back", back))
	_push(p)
