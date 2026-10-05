class_name PauseMenu
extends CanvasLayer
## Esc / the pad's Menu button: pauses the game and shows the options. Everything the brief asks to be adjustable
## is here and works with the pad on a TV (D-pad or left stick to move, left/right to change, B to go back):
## quality preset, field of view, look sensitivity (both axes), look acceleration, centre and axial deadzones,
## response curve, zoom sensitivity, invert look, Halo-style vehicle steering, mouse sensitivity, volumes.
## Changes apply at once and are saved when the menu closes (user://controls.cfg, user://settings.cfg).

var root: Control
var first: Control
var open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_build()
	root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif open and event.is_action_pressed("ui_cancel"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	open = not open
	root.visible = open
	get_tree().paused = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		first.grab_focus()
	else:
		Controls.save_controls()
		Settings.save_settings()
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.94, 0.95, 0.96, 0.96)
	sb.border_color = Color(0.55, 0.58, 0.62)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ALABASTER  -  PAUSED"
	title.add_theme_color_override("font_color", Color(0.25, 0.28, 0.32))
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_toggle)
	box.add_child(resume)
	first = resume
	var presets := OptionButton.new()
	for p in ["Low", "Medium", "High", "Ultra"]:
		presets.add_item(p)
	presets.select(["Low", "Medium", "High", "Ultra"].find(Settings.preset))
	presets.item_selected.connect(func(i: int): Settings.set_preset(presets.get_item_text(i)))
	_row(box, "Quality preset", presets)
	_slider(box, "Field of view", 60.0, 100.0, 1.0, Settings.fov, func(v: float): Settings.fov = v)
	_slider(box, "Look sensitivity (horizontal)", 1.0, 10.0, 0.5, Controls.look_sens_h, func(v: float): Controls.look_sens_h = v)
	_slider(box, "Look sensitivity (vertical)", 1.0, 10.0, 0.5, Controls.look_sens_v, func(v: float): Controls.look_sens_v = v)
	_slider(box, "Look acceleration", 0.0, 10.0, 0.5, Controls.look_accel, func(v: float): Controls.look_accel = v)
	_slider(box, "Centre deadzone", 0.0, 0.3, 0.01, Controls.center_deadzone, func(v: float): Controls.center_deadzone = v)
	_slider(box, "Axial deadzone", 0.0, 0.3, 0.01, Controls.axial_deadzone, func(v: float): Controls.axial_deadzone = v)
	_slider(box, "Response curve (1 = linear)", 1.0, 4.0, 0.1, Controls.curve_exponent, func(v: float): Controls.curve_exponent = v)
	_slider(box, "Zoom sensitivity", 0.3, 1.5, 0.05, Controls.zoom_sens_mult, func(v: float): Controls.zoom_sens_mult = v)
	_slider(box, "Mouse sensitivity", 0.03, 0.4, 0.01, Settings.mouse_sensitivity, func(v: float): Settings.mouse_sensitivity = v)
	_check(box, "Invert look (pad)", Controls.invert_look, func(on: bool): Controls.invert_look = on)
	_check(box, "Invert look (mouse)", Settings.invert_y, func(on: bool): Settings.invert_y = on)
	_check(box, "Vehicles steer toward the camera (Halo-style)", Controls.vehicle_camera_relative, func(on: bool): Controls.vehicle_camera_relative = on)
	_slider(box, "Master volume", 0.0, 1.0, 0.05, Settings.master_volume, func(v: float): Settings.master_volume = v; _volumes())
	_slider(box, "Effects volume", 0.0, 1.0, 0.05, Settings.sfx_volume, func(v: float): Settings.sfx_volume = v; _volumes())
	_slider(box, "Music volume", 0.0, 1.0, 0.05, Settings.music_volume, func(v: float): Settings.music_volume = v; _volumes())
	var quit := Button.new()
	quit.text = "Quit to desktop"
	quit.pressed.connect(func():
		Controls.save_controls()
		Settings.save_settings()
		get_tree().quit(0))
	box.add_child(quit)
	# Centre the panel once its size is known.
	panel.resized.connect(func(): panel.position = (root.size - panel.size) * 0.5)
	root.resized.connect(func(): panel.position = (root.size - panel.size) * 0.5)


func _volumes() -> void:
	if Sfx.has_method("_volumes"):
		Sfx._volumes()


func _row(box: VBoxContainer, label: String, ctl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(330, 0)
	l.add_theme_color_override("font_color", Color(0.2, 0.22, 0.25))
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	box.add_child(h)


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, value: float, apply: Callable) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.text = str(snappedf(value, step))
	v.add_theme_color_override("font_color", Color(0.2, 0.22, 0.25))
	s.value_changed.connect(func(x: float):
		apply.call(x)
		v.text = str(snappedf(x, step)))
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(330, 0)
	l.add_theme_color_override("font_color", Color(0.2, 0.22, 0.25))
	h.add_child(l)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	h.add_child(v)
	box.add_child(h)


func _check(box: VBoxContainer, label: String, on: bool, apply: Callable) -> void:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(func(x: bool): apply.call(x))
	_row(box, label, c)
