extends Node
## Input: the action map (keyboard/mouse + gamepad, Halo Infinite-style default pad layout), the look curve
## (deadzones, response curve, acceleration) and pad discovery. A "virtual pad" fed by the macOS pad bridge
## (tools/padbridge) stands in for pads the OS has no driver for (wired PowerA GIP pads such as 20D6:2074).

signal pad_changed

const PATH := "user://controls.cfg"

# Look tuning (Halo Infinite option names). Sensitivities are 1..10, percentages 0..1.
var look_sens_h := 3.0
var look_sens_v := 3.0
var look_accel := 3.0          # 0..10: extra turn speed ramped in while the stick is held at the edge
var center_deadzone := 0.10
var axial_deadzone := 0.0
var max_threshold := 0.95
var curve_exponent := 2.2      # 1 = linear; higher = finer aim near the centre
var move_deadzone := 0.12
var zoom_sens_mult := 0.8
var invert_look := false
var vehicle_camera_relative := true   # Halo-style: push the stick toward where you look

var _accel_t := 0.0
var pad_id := -1               # SDL joypad in use, -1 when none
var pad_name := ""
var bridge_active := false     # true while the UDP pad bridge is feeding the virtual pad
var vpad := {}                 # virtual pad: axes "lx","ly","rx","ry","lt","rt" + button names -> bool
var _bridge: PacketPeerUDP
var _bridge_seen := 0.0
var _prev_buttons := {}

# action -> [keys..., mouse buttons..., pad buttons..., pad axes (axis, sign)...]
const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "crouch": [KEY_C, KEY_CTRL], "sprint": [KEY_SHIFT],
	"interact": [KEY_E, KEY_F], "reload": [KEY_R], "switch_weapon": [KEY_Q, KEY_TAB],
	"grenade": [KEY_G], "melee": [KEY_V], "equipment": [KEY_X], "flashlight": [KEY_L],
	"toggle_view": [KEY_T], "map": [KEY_M], "pause": [KEY_ESCAPE], "perf_hud": [KEY_F3],
	"quality_next": [KEY_F6], "screenshot": [KEY_F12], "time_skip": [KEY_F8], "weather_next": [KEY_F7],
	"ascend": [KEY_SPACE], "descend": [KEY_C], "boost": [KEY_SHIFT], "brake": [KEY_SPACE],
	"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4],
}
const MOUSE := {"fire": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT], "melee": [MOUSE_BUTTON_MIDDLE]}
# Halo Infinite-style default layout.
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A], "crouch": [JOY_BUTTON_B], "interact": [JOY_BUTTON_X], "reload": [JOY_BUTTON_X],
	"switch_weapon": [JOY_BUTTON_Y], "grenade": [JOY_BUTTON_LEFT_SHOULDER], "melee": [JOY_BUTTON_RIGHT_SHOULDER],
	"sprint": [JOY_BUTTON_LEFT_STICK], "equipment": [JOY_BUTTON_RIGHT_STICK], "flashlight": [JOY_BUTTON_DPAD_UP],
	"toggle_view": [JOY_BUTTON_DPAD_DOWN], "map": [JOY_BUTTON_BACK], "pause": [JOY_BUTTON_START],
	"ascend": [JOY_BUTTON_A], "descend": [JOY_BUTTON_B], "brake": [JOY_BUTTON_A], "boost": [JOY_BUTTON_LEFT_STICK],
	"weapon_next": [JOY_BUTTON_DPAD_RIGHT], "weapon_prev": [JOY_BUTTON_DPAD_LEFT],
}
const PAD_AXES := {"fire": [JOY_AXIS_TRIGGER_RIGHT], "aim": [JOY_AXIS_TRIGGER_LEFT]}


func _ready() -> void:
	_build_input_map()
	load_controls()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_pick_pad()
	_bridge = PacketPeerUDP.new()
	if _bridge.bind(47731, "127.0.0.1") != OK:
		_bridge = null


func _build_input_map() -> void:
	var names := {}
	for a in KEYS: names[a] = true
	for a in MOUSE: names[a] = true
	for a in PAD_BUTTONS: names[a] = true
	for a in PAD_AXES: names[a] = true
	for a in names:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.25)
		for k in KEYS.get(a, []):
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b in MOUSE.get(a, []):
			var m := InputEventMouseButton.new()
			m.button_index = b
			InputMap.action_add_event(a, m)
		for b in PAD_BUTTONS.get(a, []):
			var j := InputEventJoypadButton.new()
			j.button_index = b
			j.device = -1
			InputMap.action_add_event(a, j)
		for ax in PAD_AXES.get(a, []):
			var m2 := InputEventJoypadMotion.new()
			m2.axis = ax
			m2.axis_value = 1.0
			m2.device = -1
			InputMap.action_add_event(a, m2)


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_pick_pad()


func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	pad_id = pads[0] if pads.size() > 0 else -1
	pad_name = Input.get_joy_name(pad_id) if pad_id >= 0 else ""
	pad_changed.emit()


func has_pad() -> bool:
	return pad_id >= 0 or bridge_active


## Describes every pad the engine sees (for --padcheck and the controls screen).
func pad_report() -> Dictionary:
	var out := {"os": OS.get_name(), "engine": Engine.get_version_info()["string"], "pads": [], "bridge": bridge_active}
	for id in Input.get_connected_joypads():
		var info := Input.get_joy_info(id)
		out["pads"].append({"id": id, "name": Input.get_joy_name(id), "guid": Input.get_joy_guid(id),
			"known": Input.is_joy_known(id), "info": info})
	return out


func _process(delta: float) -> void:
	_poll_bridge()
	if bridge_active and Time.get_ticks_msec() / 1000.0 - _bridge_seen > 2.0:
		bridge_active = false
		vpad.clear()
		pad_changed.emit()


## Reads pad-bridge packets: "AXES lx ly rx ry lt rt|BTN a b x y lb rb back start ls rs up down left right".
func _poll_bridge() -> void:
	if _bridge == null:
		return
	while _bridge.get_available_packet_count() > 0:
		var s := _bridge.get_packet().get_string_from_utf8()
		var parts := s.split(" ")
		if parts.size() < 8 or parts[0] != "PAD":
			continue
		var was := bridge_active
		bridge_active = true
		_bridge_seen = Time.get_ticks_msec() / 1000.0
		vpad["lx"] = float(parts[1]); vpad["ly"] = float(parts[2])
		vpad["rx"] = float(parts[3]); vpad["ry"] = float(parts[4])
		vpad["lt"] = float(parts[5]); vpad["rt"] = float(parts[6])
		var bits := int(parts[7])
		var map := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_LEFT_STICK,
			JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_GUIDE]
		for i in map.size():
			var down := (bits >> i) & 1 == 1
			var btn: int = map[i]
			if _prev_buttons.get(btn, false) != down:
				var ev := InputEventJoypadButton.new()
				ev.button_index = btn
				ev.pressed = down
				ev.device = 7
				Input.parse_input_event(ev)
				_prev_buttons[btn] = down
		for pair in [[JOY_AXIS_TRIGGER_LEFT, vpad["lt"]], [JOY_AXIS_TRIGGER_RIGHT, vpad["rt"]]]:
			var m := InputEventJoypadMotion.new()
			m.axis = pair[0]
			m.axis_value = pair[1]
			m.device = 7
			Input.parse_input_event(m)
		if not was:
			pad_changed.emit()


func _axis(axis: int) -> float:
	if bridge_active:
		match axis:
			JOY_AXIS_LEFT_X: return vpad.get("lx", 0.0)
			JOY_AXIS_LEFT_Y: return vpad.get("ly", 0.0)
			JOY_AXIS_RIGHT_X: return vpad.get("rx", 0.0)
			JOY_AXIS_RIGHT_Y: return vpad.get("ry", 0.0)
			JOY_AXIS_TRIGGER_LEFT: return vpad.get("lt", 0.0)
			JOY_AXIS_TRIGGER_RIGHT: return vpad.get("rt", 0.0)
	if pad_id < 0:
		return 0.0
	return Input.get_joy_axis(pad_id, axis)


func trigger(right: bool) -> float:
	return _axis(JOY_AXIS_TRIGGER_RIGHT if right else JOY_AXIS_TRIGGER_LEFT)


## Movement vector in the player's local frame (x = right, y = forward), keyboard and left stick.
func move_vector() -> Vector2:
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	var s := Vector2(_axis(JOY_AXIS_LEFT_X), -_axis(JOY_AXIS_LEFT_Y))
	var m := s.length()
	if m > move_deadzone:
		s = s / m * clampf((m - move_deadzone) / (max_threshold - move_deadzone), 0.0, 1.0)
		v += s
	else:
		v = v
	return v.limit_length(1.0)


## Stick look rate in radians this frame (x = yaw, y = pitch), with deadzones, curve and acceleration.
func look_delta(delta: float, zoomed: bool) -> Vector2:
	var raw := Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y))
	return shape_look(raw, delta, zoomed)


func shape_look(raw: Vector2, delta: float, zoomed: bool) -> Vector2:
	if absf(raw.x) < axial_deadzone: raw.x = 0.0
	if absf(raw.y) < axial_deadzone: raw.y = 0.0
	var m := raw.length()
	if m <= center_deadzone:
		_accel_t = 0.0
		return Vector2.ZERO
	var scaled := clampf((m - center_deadzone) / maxf(0.01, max_threshold - center_deadzone), 0.0, 1.0)
	var shaped := pow(scaled, curve_exponent) * 0.75 + scaled * 0.25
	var dir := raw / m
	var yaw_rate := deg_to_rad(55.0 + 42.0 * look_sens_h)
	var pitch_rate := deg_to_rad(40.0 + 30.0 * look_sens_v)
	if scaled >= 0.98:
		_accel_t += delta
	else:
		_accel_t = maxf(0.0, _accel_t - delta * 3.0)
	var boost := clampf((_accel_t - 0.12) / 0.45, 0.0, 1.0) * look_accel * deg_to_rad(16.0)
	var mult := zoom_sens_mult if zoomed else 1.0
	var out := Vector2(dir.x * shaped * (yaw_rate + boost), dir.y * shaped * (pitch_rate + boost * 0.4))
	if invert_look:
		out.y = -out.y
	return out * mult * delta


func load_controls() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in ["look_sens_h", "look_sens_v", "look_accel", "center_deadzone", "axial_deadzone", "max_threshold",
			"curve_exponent", "move_deadzone", "zoom_sens_mult", "invert_look", "vehicle_camera_relative"]:
		set(k, cf.get_value("pad", k, get(k)))


func save_controls() -> void:
	var cf := ConfigFile.new()
	for k in ["look_sens_h", "look_sens_v", "look_accel", "center_deadzone", "axial_deadzone", "max_threshold",
			"curve_exponent", "move_deadzone", "zoom_sens_mult", "invert_look", "vehicle_camera_relative"]:
		cf.set_value("pad", k, get(k))
	cf.save(PATH)


func rumble(weak: float, strong: float, secs: float) -> void:
	if pad_id >= 0:
		Input.start_joy_vibration(pad_id, weak, strong, secs)
