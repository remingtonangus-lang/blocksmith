extends RefCounted
## UI dead-end oracle (QUALITY_BAR 11): drives the menus with gamepad events only (Menu/Start, D-pad, A, B).
## For every screen reachable from the pause menu it explores the focus graph with real D-pad presses and fails
## when a focusable control cannot be reached, when a screen opens without focus, or when B does not return to the
## screen before it. Also rebinds a key and a pad button through the Controls screen and resets them, and checks the
## game unpauses once every menu is closed.

const OPEN := ["Map", "Journal", "Satchel", "Settings", "Controls", "Accessibility", "Today's Paper"]
const DIRS := [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT]

static var tree: SceneTree
static var menus: Node

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "ui", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	tree = runner.get_tree()
	menus = Game.get("menus")
	if menus == null:   # headless runs have no menus: make the real one
		menus = load("res://src/ui/menus.gd").new()
		menus.name = "Menus"
		Game.main.add_child(menus)
		Game.set("menus", menus)
	await _frames(3)
	var saved: Dictionary = menus.settings.duplicate(true)
	var visited: Array = []
	await _press(JOY_BUTTON_START)
	if menus.stack.size() != 1:
		_fail(res, "Menu/Start did not open the pause menu")
		return res
	await _screen(res, "Pause", 0, visited)
	await _rebind_check(res)
	await _press(JOY_BUTTON_B)
	if not menus.stack.is_empty():
		_fail(res, "B on the pause menu left %d screens open" % menus.stack.size())
		menus.close_all()
	await _frames(2)
	if tree.paused:
		_fail(res, "game still paused with every menu closed")
	menus.settings = saved
	menus.apply_settings()
	res.checks["screens"] = visited
	print("  ui: screens visited %s" % str(visited))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  ui FAIL: " + why)

static func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

static func _press(button: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventJoypadButton.new()
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(2)

static func _focus() -> Control:
	return menus.get_viewport().gui_get_focus_owner()

static func _focusables(top: Control) -> Array:
	var out: Array = []
	for n in top.find_children("*", "Control", true, false):
		if n.focus_mode == Control.FOCUS_ALL and n.is_visible_in_tree():
			out.append(n)
	return out

static func _label(c: Control) -> String:
	if c is Button:
		return (c as Button).text
	return c.get_class()

## Explore one screen: every focusable control reachable by D-pad; each sub-screen opens with A and closes with B.
static func _screen(res: Dictionary, title: String, depth: int, visited: Array) -> void:
	visited.append(title)
	var top: Control = menus.stack.back()
	var start := _focus()
	if start == null or not top.is_ancestor_of(start):
		_fail(res, "%s opened without focus on one of its controls" % title)
		return
	# breadth-first over the focus graph using real presses (focus is put back on a node to try its four sides)
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for d in (DIRS.slice(0, 2) if c is Slider else DIRS):   # left/right on a slider change its value
			if not is_instance_valid(c):
				break
			c.grab_focus()
			await _frames(1)
			await _press(d)
			var f := _focus()
			if f != null and top.is_ancestor_of(f) and not seen.has(f):
				seen[f] = true
				queue.append(f)
	var missing: Array = []
	for c in _focusables(top):
		if not seen.has(c):
			missing.append(_label(c))
	if not missing.is_empty():
		_fail(res, "%s: unreachable by D-pad: %s" % [title, ", ".join(missing)])
	if depth >= 3:
		return
	for c in _focusables(top):
		if not (c is Button) or not seen.has(c) or not (c.text in OPEN) or c.text in visited:
			continue
		var name: String = c.text
		var before: int = menus.stack.size()
		c.grab_focus()
		await _frames(1)
		await _press(JOY_BUTTON_A)
		if Game.args.has("ui_debug"):
			print("  ui dbg: after A on %s focus=%s stack=%d accept=%s" % [name, _focus(), menus.stack.size(), InputMap.action_get_events("ui_accept")])
		if menus.stack.size() != before + 1:
			_fail(res, "A on '%s' did not open a screen" % name)
			continue
		await _screen(res, name, depth + 1, visited)
		await _press(JOY_BUTTON_B)
		if menus.stack.size() != before:
			_fail(res, "B did not leave '%s' (stack %d, expected %d)" % [name, menus.stack.size(), before])
			while menus.stack.size() > before:
				menus.back()
				await _frames(1)
		var f := _focus()
		if f == null or not menus.stack.back().is_ancestor_of(f):
			_fail(res, "focus lost after closing '%s'" % name)

## Controls screen: rebind Jump to pad Y and key K by "pressing" them, then reset to defaults.
static func _rebind_check(res: Dictionary) -> void:
	menus.open_controls()
	await _frames(2)
	var top: Control = menus.stack.back()
	var pad_btn: Button = null
	var key_btn: Button = null
	for c in _focusables(top):
		if c.has_meta("bind") and c.get_meta("bind")[0] == "jump":
			if c.get_meta("bind")[1] == "pad":
				pad_btn = c
			else:
				key_btn = c
	if pad_btn == null or key_btn == null:
		_fail(res, "Controls screen has no Jump row")
		menus.back()
		return
	pad_btn.grab_focus()
	await _frames(1)
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_Y)
	var has_y := false
	for e in InputMap.action_get_events("jump"):
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y:
			has_y = true
	if not has_y:
		_fail(res, "rebinding Jump to Y through the Controls screen did not take")
	key_btn.grab_focus()
	await _frames(1)
	await _press(JOY_BUTTON_A)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	Input.parse_input_event(k)
	await _frames(3)
	var has_k := false
	for e in InputMap.action_get_events("jump"):
		if e is InputEventKey and e.physical_keycode == KEY_K:
			has_k = true
	if not has_k:
		_fail(res, "rebinding Jump to K through the Controls screen did not take")
	menus.reset_binds()
	var back_x := false
	for e in InputMap.action_get_events("jump"):
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X:
			back_x = true
	if not back_x:
		_fail(res, "Reset to defaults did not restore Jump on X")
	res.checks["rebind"] = "ok" if has_y and has_k and back_x else "fail"
	await _press(JOY_BUTTON_B)
