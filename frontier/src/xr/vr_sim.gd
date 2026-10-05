class_name VRSim
extends Node
## Desktop VR simulator (`--vr_sim`): stands in for an OpenXR runtime by registering the head / left_hand /
## right_hand trackers with XRServer and driving their poses and inputs, so XRCamera3D, XRController3D and every
## VR code path run unchanged (only `viewport.use_xr` stays off: the head camera renders to the window).
## Interactive: mouse looks (head), the hands ride in front of the body; LMB right trigger, RMB right grip,
## Q left grip, F left trigger, E A, R B, Tab menu, WASD left stick, arrows right stick, X left Y-button,
## 1/2 roll the right hand (gate tilt), V flick the right hand down. Scripted: set_pose()/set_input() (feature shots,
## tests). `--vr_stereo` shows a side-by-side stereo pair.

const IPD := 0.064
## Grip pose -Z points this many degrees below the aim (pointing) direction on the Quest controllers; the sim
## generates grip poses the same way, so code that aims along the aim ray works for both.
const GRIP_TO_AIM := 35.0

var head: XRPositionalTracker
var lt: XRControllerTracker
var rt: XRControllerTracker
var scripted := false
var head_local := Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))
var left_local := Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.2, -0.3))
var right_local := Transform3D(Basis.IDENTITY, Vector3(0.2, 1.2, -0.3))
var _yaw := 0.0
var _pitch := 0.0
var _roll_r := 0.0
var _flick := 0.0
var _stereo: CanvasLayer
var _eyes: Array = []

func _init() -> void:
	name = "VRSim"
	head = _tracker(XRPositionalTracker.new(), &"head", XRServer.TRACKER_HEAD)
	lt = _tracker(XRControllerTracker.new(), &"left_hand", XRServer.TRACKER_CONTROLLER)
	rt = _tracker(XRControllerTracker.new(), &"right_hand", XRServer.TRACKER_CONTROLLER)

func _tracker(t: XRPositionalTracker, n: StringName, type: int) -> XRPositionalTracker:
	t.name = n
	t.type = type
	if t is XRControllerTracker:
		t.hand = XRPositionalTracker.TRACKER_HAND_LEFT if n == &"left_hand" else XRPositionalTracker.TRACKER_HAND_RIGHT
	var old := XRServer.get_tracker(n)
	if old != null:
		XRServer.remove_tracker(old)
	XRServer.add_tracker(t)
	return t

func _exit_tree() -> void:
	for t in [head, lt, rt]:
		if t != null and XRServer.get_tracker(t.name) == t:
			XRServer.remove_tracker(t)

## Scripted poses (relative to the XROrigin). Hands are given as AIM frames (-Z = where the hand points); the
## grip pose sent to the tracker is tilted like a real controller's.
func set_pose(h: Transform3D, l_aim: Transform3D, r_aim: Transform3D) -> void:
	scripted = true
	head_local = h
	left_local = aim_to_grip(l_aim)
	right_local = aim_to_grip(r_aim)
	_push()

static func aim_to_grip(aim: Transform3D) -> Transform3D:
	return aim * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-GRIP_TO_AIM)), Vector3.ZERO)

static func grip_to_aim(grip: Transform3D) -> Transform3D:
	return grip * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(GRIP_TO_AIM)), Vector3.ZERO)

func set_input(side: String, input: StringName, value) -> void:
	(lt if side == "left" else rt).set_input(input, value)

func clear_inputs() -> void:
	for t in [lt, rt]:
		for k in [&"trigger", &"grip"]:
			t.set_input(k, 0.0)
		for k in [&"ax_button", &"by_button", &"menu_button", &"primary_click", &"trigger_click", &"grip_click"]:
			t.set_input(k, false)
		t.set_input(&"primary", Vector2.ZERO)

## A look-at transform for scripted heads/hands.
static func look(from: Vector3, to: Vector3) -> Transform3D:
	var d := to - from
	if d.length() < 0.001:
		return Transform3D(Basis.IDENTITY, from)
	return Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), from)

func _unhandled_input(e: InputEvent) -> void:
	if scripted:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= e.relative.x * 0.0025
		_pitch = clampf(_pitch - e.relative.y * 0.0025, -1.3, 1.3)

func _process(dt: float) -> void:
	if not scripted:
		_interactive(dt)
	_push()
	if _stereo == null and Game.args.has("vr_stereo"):
		_build_stereo()
	_update_stereo()

func _interactive(dt: float) -> void:
	var hb := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	head_local = Transform3D(hb, Vector3(0, 1.62, 0))
	if Input.is_key_pressed(KEY_1):
		_roll_r = move_toward(_roll_r, 1.4, dt * 4.0)
	elif Input.is_key_pressed(KEY_2):
		_roll_r = move_toward(_roll_r, 0.0, dt * 4.0)
	_flick = 0.35 if Input.is_key_pressed(KEY_V) else move_toward(_flick, 0.0, dt * 2.0)
	var body := Basis(Vector3.UP, _yaw)
	var aim_r := Transform3D(hb * Basis(Vector3.FORWARD, -_roll_r), head_local.origin + body * Vector3(0.16, -0.22 - _flick, -0.45))
	var aim_l := Transform3D(hb, head_local.origin + body * Vector3(-0.08, -0.26, -0.62))
	left_local = aim_to_grip(aim_l)
	right_local = aim_to_grip(aim_r)
	rt.set_input(&"trigger", 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0)
	rt.set_input(&"grip", 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else 0.0)
	lt.set_input(&"grip", 1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
	lt.set_input(&"trigger", 1.0 if Input.is_key_pressed(KEY_F) else 0.0)
	rt.set_input(&"ax_button", Input.is_key_pressed(KEY_E))
	rt.set_input(&"by_button", Input.is_key_pressed(KEY_R))
	lt.set_input(&"by_button", Input.is_key_pressed(KEY_X))
	lt.set_input(&"menu_button", Input.is_key_pressed(KEY_TAB))
	var mv := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
	lt.set_input(&"primary", mv)
	rt.set_input(&"primary", Vector2(float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))))

func _push() -> void:
	var c := XRPose.XR_TRACKING_CONFIDENCE_HIGH
	head.set_pose(&"default", head_local, Vector3.ZERO, Vector3.ZERO, c)
	for pair in [[lt, left_local], [rt, right_local]]:
		var t: XRControllerTracker = pair[0]
		var g: Transform3D = pair[1]
		t.set_pose(&"default", g, Vector3.ZERO, Vector3.ZERO, c)
		t.set_pose(&"grip", g, Vector3.ZERO, Vector3.ZERO, c)
		t.set_pose(&"aim", grip_to_aim(g), Vector3.ZERO, Vector3.ZERO, c)

# ---------------------------------------------------------------------------------------- side-by-side stereo
func _build_stereo() -> void:
	_stereo = CanvasLayer.new()
	_stereo.layer = 50
	add_child(_stereo)
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	_stereo.add_child(box)
	var win: Vector2i = get_viewport().size
	for i in 2:
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(cont)
		var vp := SubViewport.new()
		vp.size = Vector2i(win.x / 2, win.y)
		vp.world_3d = get_viewport().world_3d
		cont.add_child(vp)
		var c := Camera3D.new()
		c.current = true
		vp.add_child(c)
		_eyes.append(c)

func _update_stereo() -> void:
	if _eyes.is_empty():
		return
	var main := get_viewport().get_camera_3d()
	if main == null:
		return
	for i in 2:
		var c: Camera3D = _eyes[i]
		c.keep_aspect = Camera3D.KEEP_WIDTH
		c.fov = 100.0
		c.near = main.near
		c.far = main.far
		c.global_transform = main.global_transform.translated_local(Vector3((-0.5 + i) * IPD, 0, 0))
		c.environment = main.environment
		c.attributes = main.attributes
