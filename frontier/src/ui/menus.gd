extends CanvasLayer
## Pause menu, settings, full-screen map and journal in Sable River's printed-paper style. Fully navigable with a
## controller (focus neighbours, D-pad / stick, A to choose, B to go back) and with mouse/keyboard. The game is
## paused while a menu is open (this layer processes always).

const SETTINGS_PATH := "user://settings.json"
const JOURNAL = preload("res://src/missions/journal.gd")

var panel: PanelContainer
var stack: Array[Control] = []
var settings := {"quality": "high", "render_scale": -1.0, "fov": 62.0, "mouse_sens": 1.0, "invert_y": false,
	"subtitles": true, "vol_master": 1.0, "vol_music": 0.8, "vol_sfx": 1.0, "vol_voice": 1.0, "snap_turn": true,
	"aim_assist": "controller", "aim_toggle": false, "colour_mode": "off", "colour_strength": 1.0, "text_scale": 1.0,
	"binds": {}}
## Rebindable actions (settings > Controls): keyboard key and gamepad button per action. Aim/fire stay on the
## mouse buttons and triggers; look and move axes stay on the sticks.
const REBIND := [["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["sprint", "Sprint / spur horse"], ["walk_toggle", "Walk toggle"], ["jump", "Jump"],
	["crouch", "Crouch"], ["interact", "Interact / talk / greet"], ["mount", "Mount / dismount"],
	["whistle", "Whistle for horse"], ["ride_auto", "Follow the road"], ["reload", "Reload"], ["nerve", "Nerve"],
	["weapon_wheel", "Weapon wheel"], ["holster", "Holster"], ["camera_side", "Swap shoulder"], ["melee", "Melee"],
	["lasso", "Lasso"], ["fish", "Fish"], ["antagonize", "Antagonize"], ["defuse", "Defuse"], ["map", "Map"],
	["journal", "Journal"], ["satchel", "Satchel"]]
const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"}
var access: Accessibility
var _default_events := {}         # action -> events before any rebinding (for Reset)
var _binds_applied := {}
var _capture := {}                # {action, kind: "key"|"pad", button} while waiting for a press
var _bind_t := 0.0
var map_view: Control
var waypoint := Vector3.INF
var route := PackedVector3Array()
var _route_t := 0.0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	access = Accessibility.new()
	access.name = "Accessibility"
	add_child(access)
	_load_settings()
	apply_settings()

func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if _capture.kind == "key" and event is InputEventKey:
		if event.physical_keycode != KEY_ESCAPE:
			_set_bind(_capture.action, "key", int(event.physical_keycode))
		_end_capture()
		get_viewport().set_input_as_handled()
	elif _capture.kind == "pad" and event is InputEventJoypadButton:
		if event.button_index != JOY_BUTTON_START:
			_set_bind(_capture.action, "pad", int(event.button_index))
		_end_capture()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _capture.is_empty():
		return
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
	v.add_child(_button("Satchel", Satchel.open))
	if Game.has_meta("news") and Game.get_meta("news").has_paper():
		v.add_child(_button("Today's Paper", func(): Game.get_meta("news").open_last()))
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
	var more := HBoxContainer.new()
	more.add_theme_constant_override("separation", 12)
	more.add_child(_button("Controls", open_controls))
	more.add_child(_button("Accessibility", open_accessibility))
	more.add_child(_button("Back", back))
	v.add_child(more)
	_push(p)

# ------------------------------------------------------------------ accessibility
func open_accessibility() -> void:
	var p := _paper_panel(Vector2(820, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UITheme.label("Accessibility", 44, "display", UITheme.INK, false))
	v.add_child(HSeparator.new())
	v.add_child(_row("Aim assist", _options(["Off", "Controller only", "Always"], ["off", "controller", "always"], "aim_assist")))
	var tg := CheckBox.new()
	tg.button_pressed = settings.aim_toggle
	tg.toggled.connect(func(b):
		settings.aim_toggle = b
		apply_settings())
	v.add_child(_row("Toggle aim (press, not hold)", tg))
	v.add_child(_row("Colour vision", _options(Accessibility.COLOUR_LABELS, Accessibility.COLOUR_MODES, "colour_mode")))
	v.add_child(_row("Colour correction strength", _slider(0.2, 1.5, 0.05, settings.colour_strength, func(x):
		settings.colour_strength = x
		apply_settings())))
	v.add_child(_row("Text and menu size", _slider(0.8, 1.5, 0.05, settings.text_scale, func(x):
		settings.text_scale = x
		apply_settings())))
	var subs := CheckBox.new()
	subs.button_pressed = settings.subtitles
	subs.toggled.connect(func(b):
		settings.subtitles = b
		apply_settings())
	v.add_child(_row("Subtitles", subs))
	v.add_child(_button("Back", back))
	_push(p)

func _options(labels: Array, values: Array, key: String) -> OptionButton:
	var o := OptionButton.new()
	for l in labels:
		o.add_item(str(l))
	o.selected = maxi(values.find(settings.get(key, values[0])), 0)
	o.item_selected.connect(func(i):
		settings[key] = values[i]
		apply_settings())
	return o

# ------------------------------------------------------------------ controls (rebinding)
func open_controls() -> void:
	_snapshot_defaults()
	var p := _paper_panel(Vector2(980, 700))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UITheme.label("Controls", 44, "display", UITheme.INK, false))
	v.add_child(UITheme.label("Choose a binding, then press the new key or button (Esc / Menu cancels).", 22, "italic", UITheme.INK_SOFT, false))
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true   # D-pad focus scrolls rows below the fold into reach
	scroll.custom_minimum_size = Vector2(920, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	v.add_child(scroll)
	for a in REBIND:
		var action: String = a[0]
		if not InputMap.has_action(action):
			continue
		var h := HBoxContainer.new()
		var l := UITheme.label(a[1], 26, "body", UITheme.INK, false)
		l.custom_minimum_size = Vector2(380, 0)
		h.add_child(l)
		for kind in ["key", "pad"]:
			var b := _button(_bind_text(action, kind), func(): pass)
			b.custom_minimum_size = Vector2(230, 0)
			b.set_meta("bind", [action, kind])
			b.pressed.connect(_begin_capture.bind(action, kind, b))
			h.add_child(b)
		list.add_child(h)
	var note := UITheme.label(_conflicts_text(), 20, "italic", UITheme.INK_SOFT, false)
	note.name = "Conflicts"
	v.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("Reset to defaults", func():
		reset_binds()
		back()
		open_controls()))
	row.add_child(_button("Back", back))
	v.add_child(row)
	_push(p)

func _begin_capture(action: String, kind: String, b: Button) -> void:
	b.text = "press a key…" if kind == "key" else "press a button…"
	# armed next frame so the press that chose this row is not taken as the new binding
	(func(): _capture = {"action": action, "kind": kind, "button": b}).call_deferred()

func _end_capture() -> void:
	var b: Button = _capture.get("button")
	if b and is_instance_valid(b):
		b.text = _bind_text(_capture.action, _capture.kind)
		var n = b.get_parent().get_parent().get_parent().get_parent().get_node_or_null("Conflicts")
		if n:
			n.text = _conflicts_text()
	_capture = {}

func _key_name(code: int) -> String:
	if code <= 0:
		return "—"
	var k := DisplayServer.keyboard_get_keycode_from_physical(code) if not Game.headless else code
	return OS.get_keycode_string(k)

func _bind_text(action: String, kind: String) -> String:
	for e in InputMap.action_get_events(action):
		if kind == "key" and e is InputEventKey:
			return _key_name(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
		if kind == "pad" and e is InputEventJoypadButton:
			return PAD_NAMES.get(e.button_index, "Button %d" % e.button_index)
	return "—"

func _conflicts_text() -> String:
	var used := {}
	var out: PackedStringArray = []
	for a in REBIND:
		if not InputMap.has_action(a[0]):
			continue
		for e in InputMap.action_get_events(a[0]):
			if e is InputEventKey:
				var k := "key %s" % _key_name(e.physical_keycode)
				if used.has(k) and a[0] not in ["mount", "melee"]:
					out.append("%s is on both %s and %s" % [_key_name(e.physical_keycode), used[k], a[1]])
				used[k] = a[1]
	return "" if out.is_empty() else "Note: " + "; ".join(out)

func _snapshot_defaults() -> void:
	InputSetup.ensure()
	for a in REBIND:
		if InputMap.has_action(a[0]) and not _default_events.has(a[0]):
			_default_events[a[0]] = InputMap.action_get_events(a[0]).duplicate()

func _set_bind(action: String, kind: String, code: int) -> void:
	_snapshot_defaults()
	var b: Dictionary = settings.binds.get(action, {})
	b[kind] = code
	settings.binds[action] = b
	_apply_bind(action)
	_save_settings()

func _apply_bind(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var b: Dictionary = settings.binds.get(action, {})
	for e in InputMap.action_get_events(action):
		if (b.has("key") and e is InputEventKey) or (b.has("pad") and e is InputEventJoypadButton):
			InputMap.action_erase_event(action, e)
	if int(b.get("key", -1)) > 0:
		var k := InputEventKey.new()
		k.physical_keycode = int(b.key)
		InputMap.action_add_event(action, k)
	if b.has("pad") and int(b.pad) >= 0:
		var j := InputEventJoypadButton.new()
		j.button_index = int(b.pad)
		InputMap.action_add_event(action, j)
	_binds_applied[action] = true

## Saved bindings onto actions that exist (systems register some actions late, so this re-runs until all landed).
func apply_binds() -> void:
	_snapshot_defaults()
	for action in settings.binds.keys():
		if not _binds_applied.has(action) and InputMap.has_action(action):
			_apply_bind(str(action))

func reset_binds() -> void:
	for action in _default_events.keys():
		InputMap.action_erase_events(action)
		for e in _default_events[action]:
			InputMap.action_add_event(action, e)
	settings.binds = {}
	_binds_applied = {}
	_save_settings()

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
	if Game.player and "base_fov" in Game.player:
		Game.player.base_fov = settings.fov
	if access:
		access.apply(settings)
	apply_binds()
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
	map_view.clip_contents = true   # the paper stays inside its frame; the margin carries the hint
	map_view.menus = self
	root.add_child(map_view)
	var hint := UITheme.label("Click / A: set waypoint     Scroll / triggers: zoom     Drag / stick: pan     Esc / B: close", 22, "italic", UITheme.PAPER)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -48
	hint.offset_bottom = -14
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
	_bind_t -= dt
	if _bind_t <= 0.0:
		_bind_t = 1.0
		if _binds_applied.size() < settings.binds.size():
			apply_binds()
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
	var p := _paper_panel(Vector2(1240, 720))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UITheme.label("Journal", 48, "display", UITheme.INK, false))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.label("Ruth Caddell — %s" % _date_text(), 24, "italic", UITheme.INK_SOFT, false))
	v.add_child(head)
	v.add_child(HSeparator.new())
	var md = Game.get("missions")
	var st = Game.get("state")
	var flags: Dictionary = st.flags if st != null else {}
	# finished missions in the order they were played (story and Strangers), newest last
	var done: Array = []
	var titles := {}
	var chapters := {}
	var regions := {}
	if md != null:
		for path in MissionDirector.MISSIONS:
			var m = load(path).new()
			titles[m.id] = m.title
			chapters[m.id] = m.chapter
			regions[m.id] = ((("The Outfit" if m.companion != "" else "A stranger") + " — " + m.region) if m.stranger else "")
		# --journal_all (evidence shots): every page written
		var ids: Array = titles.keys() if Game.args.has("journal_all") else md.completed
		for id in ids:
			if titles.has(id) and JOURNAL.ENTRIES.has(id):
				done.append(id)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 22)
	v.add_child(pages)
	# left page: where things stand, then the entries
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 560)
	pages.add_child(left)
	var status := RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.scroll_active = false
	status.custom_minimum_size = Vector2(430, 0)
	status.add_theme_font_override("normal_font", UITheme.font("body"))
	status.add_theme_font_override("italics_font", UITheme.font("italic"))
	status.add_theme_font_size_override("normal_font_size", 22)
	status.add_theme_font_size_override("italics_font_size", 22)
	status.add_theme_color_override("default_color", UITheme.INK)
	var stx := ""
	if md != null and md.active != null:
		stx += "[i]Now:[/i]  %s — %s\n" % [md.active.title, md.objective]
	if st != null:
		stx += "[i]Standing:[/i] %s (%.0f)    [i]Money:[/i] $%.2f\n" % [st.standing_label(), st.standing, st.money]
		for county in st.bounties.keys():
			if float(st.bounties[county]) > 0.0:
				stx += "[i]Bounty in %s:[/i] $%.2f\n" % [county, st.bounties[county]]
	status.text = stx
	left.add_child(status)
	left.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true   # D-pad focus scrolls rows below the fold into reach
	scroll.custom_minimum_size = Vector2(430, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# right page: the entry and its sketch
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(700, 560)
	right.add_theme_constant_override("separation", 6)
	pages.add_child(right)
	var e_title := UITheme.label("", 36, "display", UITheme.INK, false)
	right.add_child(e_title)
	var e_sub := UITheme.label("", 20, "italic", UITheme.INK_SOFT, false)
	right.add_child(e_sub)
	var e_body := RichTextLabel.new()
	e_body.bbcode_enabled = true
	e_body.custom_minimum_size = Vector2(700, 250)
	e_body.add_theme_font_override("normal_font", UITheme.font("body"))
	e_body.add_theme_font_size_override("normal_font_size", 25)
	e_body.add_theme_color_override("default_color", UITheme.INK)
	right.add_child(e_body)
	var sketch = JOURNAL.Sketch.new()
	sketch.custom_minimum_size = Vector2(520, 250)
	sketch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(sketch)
	var show_entry := func(id: String) -> void:
		var ch: int = int(chapters.get(id, 1))
		e_title.text = str(titles.get(id, id))
		var where: String = str(regions.get(id, ""))
		e_sub.text = where if where != "" else "Chapter %s" % ["One", "Two", "Three", "Four", "Five", "Six"][clampi(ch - 1, 0, 5)]
		e_body.text = JOURNAL.text_for(id, flags)
		sketch.set_kind(JOURNAL.sketch_for(id), hash(id))
	if done.is_empty():
		e_title.text = "Nothing written yet"
		e_body.text = "The pages are clean. Tom used to say a clean page is a lie waiting for a pencil."
		sketch.set_kind("hills", 7)
	var last_ch := -1
	for id in done:
		var ch: int = int(chapters.get(id, 1))
		var stranger: bool = str(regions.get(id, "")) != ""
		if not stranger and ch != last_ch:
			last_ch = ch
			list.add_child(UITheme.label("Chapter %d" % ch, 20, "caps", UITheme.OXBLOOD, false))
		var b := _button(("   · " if stranger else "   ") + str(titles[id]), func(): show_entry.call(id))
		b.add_theme_font_size_override("font_size", 24)
		b.focus_entered.connect(func(): show_entry.call(id))
		list.add_child(b)
	if not done.is_empty():
		show_entry.call(done.back())
	v.add_child(_button("Back", back))
	_push(p)
	# start on the newest entry
	if list.get_child_count() > 0:
		var lastb := list.get_child(list.get_child_count() - 1)
		if lastb is Button:
			lastb.grab_focus.call_deferred()
			(func(): scroll.ensure_control_visible(lastb)).call_deferred()
