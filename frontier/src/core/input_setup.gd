class_name InputSetup
extends RefCounted
## Defines every input action in code (keyboard/mouse + gamepad) so project.godot stays small and the bindings
## are reviewable in one place. Gamepad layout follows the common Western-action convention:
## LT aim, RT fire, A sprint/accelerate (tap), B crouch/cancel, X jump, Y interact/mount, LB weapon wheel,
## RB Nerve (with aim), D-pad items, L3 sprint, R3 camera side.

static func ensure() -> void:
	_key("move_forward", [KEY_W], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_key("move_back", [KEY_S], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_key("move_left", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_key("move_right", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_key("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_key("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_key("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_key("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_key("sprint", [KEY_SHIFT], [JOY_BUTTON_A, JOY_BUTTON_LEFT_STICK], [])
	_key("walk_toggle", [KEY_CTRL], [], [])
	_key("jump", [KEY_SPACE], [JOY_BUTTON_X], [])
	_key("crouch", [KEY_C], [JOY_BUTTON_B], [])
	_key("interact", [KEY_E], [JOY_BUTTON_Y], [])
	_key("mount", [KEY_F], [JOY_BUTTON_Y], [])
	_key("whistle", [KEY_H], [JOY_BUTTON_DPAD_UP], [])
	_key("aim", [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	_key("fire", [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [MOUSE_BUTTON_LEFT])
	_key("reload", [KEY_R], [JOY_BUTTON_B], [])
	_key("nerve", [KEY_Q], [JOY_BUTTON_RIGHT_STICK], [])
	_key("weapon_wheel", [KEY_TAB], [JOY_BUTTON_LEFT_SHOULDER], [])
	_key("holster", [KEY_G], [], [])
	_key("camera_side", [KEY_V], [JOY_BUTTON_RIGHT_STICK], [])
	_key("map", [KEY_M], [JOY_BUTTON_BACK], [])
	_key("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_key("journal", [KEY_J], [], [])
	_key("satchel", [KEY_I], [], [])
	_key("lasso", [KEY_X], [], [])
	_key("melee", [KEY_F], [JOY_BUTTON_B], [])

static func _key(action: String, keys: Array, buttons: Array, axes: Array, mouse: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(action, e)
