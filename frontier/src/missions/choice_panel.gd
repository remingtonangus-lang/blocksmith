extends PanelContainer
## A dialogue choice on paper (MissionDirector.choose): the prompt in italic ink and up to nine numbered answers.
## Mouse, keyboard (number keys 1-9, arrows + Enter) and controller (D-pad + A) all work; a choice can't be backed
## out of with Esc / B. Emits `chosen(index)` once, or `chosen(-1)` if something closes it before a choice.

signal chosen(index: int)

var count := 0
var done := false

func build(menus: Node, prompt: String, options: Array) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.PAPER
	sb.border_color = UITheme.INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(860, 0)
	# sit in the lower third so the speaker's face stays in frame
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -430
	offset_right = 430
	offset_bottom = -150
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	if prompt != "":
		var l := UITheme.label(prompt, 28, "italic", UITheme.INK_SOFT, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(800, 0)
		v.add_child(l)
		v.add_child(HSeparator.new())
	count = options.size()
	for i in count:
		var idx := i
		var b: Button = menus._button("%d.  %s" % [i + 1, str(options[i])], func(): pick(idx))
		b.add_theme_font_override("font", UITheme.font("body"))
		b.add_theme_font_size_override("font_size", 30)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(800, 0)
		v.add_child(b)
	tree_exiting.connect(func():
		if not done:
			done = true
			chosen.emit(-1))

func pick(i: int) -> void:
	if done or i < 0 or i >= count:
		return
	done = true
	chosen.emit(i)

func _unhandled_input(e: InputEvent) -> void:
	if done:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode
		if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < count:
			get_viewport().set_input_as_handled()
			pick(k - KEY_1)
			return
		if k >= KEY_KP_1 and k <= KEY_KP_9 and k - KEY_KP_1 < count:
			get_viewport().set_input_as_handled()
			pick(k - KEY_KP_1)
			return
	if e.is_action_pressed("pause") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
