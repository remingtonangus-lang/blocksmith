class_name VR
extends Node
## OpenXR (Quest 3) support: starts the XR session when an OpenXR runtime is present, swaps the flat camera for an
## XROrigin3D rig that follows the player (seated or standing height), and maps controllers to the player's
## intent: left stick moves (head-relative), right stick snap/smooth turns, triggers aim/fire with the right hand,
## grips interact/mount. Comfort: vignette while moving or riding, snap turn by default, height calibration.

var xr: XRInterface
var origin: XROrigin3D
var cam: XRCamera3D
var left: XRController3D
var right: XRController3D
var player: Node
var snap_turn := true
var snap_deg := 30.0
var _snap_ready := true
var vignette: MeshInstance3D

static func try_start() -> VR:
	var iface := XRServer.find_interface("OpenXR")
	if iface == null:
		return null
	if not iface.is_initialized() and not iface.initialize():
		return null
	var v := VR.new()
	v.xr = iface
	return v

func attach(p: Node, root: Node) -> void:
	player = p
	var vp := root.get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = 72
	origin = XROrigin3D.new()
	origin.name = "XROrigin"
	root.add_child(origin)
	cam = XRCamera3D.new()
	cam.near = 0.05
	cam.far = 4000.0
	origin.add_child(cam)
	cam.make_current()
	left = XRController3D.new()
	left.tracker = &"left_hand"
	origin.add_child(left)
	right = XRController3D.new()
	right.tracker = &"right_hand"
	origin.add_child(right)
	for c in [left, right]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 0.14)
		m.mesh = bm
		c.add_child(m)
	Game.camera = cam
	Game.is_vr = true
	if player.get("camera") != null:
		player.camera = cam
	_build_vignette()

func _build_vignette() -> void:
	vignette = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	vignette.mesh = q
	vignette.position = Vector3(0, 0, -0.3)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/vr_vignette.gdshader")
	vignette.material_override = sm
	cam.add_child(vignette)

func _physics_process(dt: float) -> void:
	if player == null or origin == null:
		return
	# locomotion intent from the left stick relative to the head yaw
	var mv := left.get_vector2(&"primary") if left.get_is_active() else Vector2.ZERO
	var head_yaw := cam.global_rotation.y
	player.cam_yaw = head_yaw
	player.intent.move = Vector2(mv.x, mv.y)
	player.intent.sprint = left.is_button_pressed(&"primary_click")
	player.intent.aim = right.get_float(&"grip") > 0.5
	player.intent.fire = right.get_float(&"trigger") > 0.6
	player.intent.interact = right.is_button_pressed(&"ax_button")
	player.intent.jump = right.is_button_pressed(&"by_button")
	# turning: snap by default (comfort), smooth optional
	var turn := right.get_vector2(&"primary").x if right.get_is_active() else 0.0
	if snap_turn:
		if absf(turn) > 0.7 and _snap_ready:
			origin.rotate_y(deg_to_rad(-snap_deg * signf(turn)))
			_snap_ready = false
		elif absf(turn) < 0.3:
			_snap_ready = true
	else:
		origin.rotate_y(-turn * 1.6 * dt)
	# keep the origin under the player (head offset removed horizontally)
	var head_local := cam.position
	var target: Vector3 = player.global_position - origin.global_basis * Vector3(head_local.x, 0.0, head_local.z)
	var on_horse = player.get("on_horse")
	if on_horse != null:
		target.y += 0.9
	origin.global_position = target
	var moving: float = clampf(float(player.get("speed")) / 4.0, 0.0, 1.0) if player.get("speed") != null else 0.0
	(vignette.material_override as ShaderMaterial).set_shader_parameter("amount", maxf(moving, 0.6 if on_horse != null else 0.0) * 0.7)
