class_name VR
extends Node
## OpenXR (Quest 3) support: starts the XR session when an OpenXR runtime is present, swaps the flat camera for an
## XROrigin3D rig that follows the player (seated or standing height), and maps controllers to the player's
## intent: left stick moves (head-relative), right stick snap/smooth turns, triggers aim/fire with the right hand,
## grips interact/mount. Comfort: vignette while moving or riding, snap turn by default, height calibration.
## Physical play (guns, reloads, reach-to-interact, menu laser, reins) lives in VRPlay (vr_play.gd); hands are VRHand.
## `--vr_sim` runs all of it without a headset: VRSim (vr_sim.gd) drives the XR trackers and the head camera
## renders to the window instead of an HMD.

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
# HUD and menus are CanvasLayers, which XR doesn't draw: in VR they render into SubViewports shown on panels
var hud_vp: SubViewport
var hud_quad: MeshInstance3D
var menu_vp: SubViewport
var menu_quad: MeshInstance3D
var _menu_was_open := false
var _btn_prev := {}
var sim: VRSim                    # desktop simulator (--vr_sim), null with a real runtime
var play: VRPlay
var hands := {}                   # "left"/"right" -> VRHand
var _body_turn := false
const SIM_FOV := 100.0

static func try_start() -> VR:
	if Game.args.has("vr_sim"):
		var s := VR.new()
		s.name = "VR"
		s.sim = VRSim.new()
		return s
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
	if sim != null:
		add_child(sim)                            # trackers first, so the rig's nodes find them
	else:
		vp.use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.physics_ticks_per_second = 72
	origin = XROrigin3D.new()
	origin.name = "XROrigin"
	origin.process_mode = Node.PROCESS_MODE_ALWAYS   # controllers keep tracking while a menu pauses the tree
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
		var h := VRHand.new()
		h.setup("left" if c == left else "right")
		c.add_child(h)
		hands[h.side] = h
	Game.camera = cam
	Game.is_vr = true
	if player.get("camera") != null:
		player.camera = cam
	if sim != null:
		cam.keep_aspect = Camera3D.KEEP_WIDTH     # a Quest 3 eye sees ~104 deg across; the window shows about that
		cam.fov = SIM_FOV
	_build_vignette()
	play = VRPlay.new()
	add_child(play)
	play.setup(self, player, left, right)
	process_mode = Node.PROCESS_MODE_ALWAYS       # menus pause the tree; panels and menu input keep working
	_build_panels.call_deferred()

func _panel_viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.gui_embed_subwindows = true
	add_child(vp)
	return vp

func _panel_quad(vp: SubViewport, width_m: float, on_top: bool) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(width_m, width_m * float(vp.size.y) / float(vp.size.x))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = vp.get_texture()
	m.no_depth_test = on_top
	m.render_priority = 10 if on_top else 0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_panels() -> void:
	# HUD: head-locked, slightly low, comfortable reading distance
	if Game.get("hud") and Game.hud is CanvasLayer:
		hud_vp = _panel_viewport(Vector2i(1600, 900))
		Game.hud.get_parent().remove_child(Game.hud)
		hud_vp.add_child(Game.hud)
		hud_quad = _panel_quad(hud_vp, 1.3, true)
		hud_quad.position = Vector3(0.0, -0.12, -1.5)
		cam.add_child(hud_quad)
	# menus: a world-locked sheet placed in front of the head when a menu opens
	if Game.get("menus") and Game.menus is CanvasLayer:
		menu_vp = _panel_viewport(Vector2i(1920, 1080))
		Game.menus.get_parent().remove_child(Game.menus)
		menu_vp.add_child(Game.menus)
		menu_quad = _panel_quad(menu_vp, 1.6, false)
		menu_quad.visible = false
		get_tree().current_scene.add_child(menu_quad)

func _edge(c: XRController3D, button: StringName) -> bool:
	var key := str(c.tracker) + str(button)
	var now := c.is_button_pressed(button)
	var was: bool = _btn_prev.get(key, false)
	_btn_prev[key] = now
	return now and not was

func _ui(action: String) -> void:
	if menu_vp == null:
		return
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		menu_vp.push_input(e)

func _process(_dt: float) -> void:
	if sim != null and cam != null:
		cam.fov = SIM_FOV                         # the flat-screen settings (menus.gd) write Game.camera.fov
	if menu_quad == null or cam == null:
		return
	var open: bool = not Game.menus.stack.is_empty()
	if open and not _menu_was_open:
		var yaw := cam.global_rotation.y
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		menu_quad.global_position = cam.global_position + fwd * 1.4 + Vector3(0, -0.1, 0)
		menu_quad.look_at(cam.global_position + Vector3(0, -0.1, 0), Vector3.UP)
		menu_quad.rotate_object_local(Vector3.UP, PI)
	menu_quad.visible = open
	menu_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if hud_quad:
		hud_quad.visible = not open
		hud_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if open else SubViewport.UPDATE_ALWAYS
	_menu_was_open = open
	# menu (left hand) opens pause; while a menu is open the right stick / A / B drive focus navigation
	if left.get_is_active() and _edge(left, &"menu_button"):
		if open:
			Game.menus.back()
		else:
			Game.menus.open_pause()
	if open and right.get_is_active():
		var v := right.get_vector2(&"primary")
		var key := "nav"
		var dir := ""
		if v.y > 0.7: dir = "ui_up"
		elif v.y < -0.7: dir = "ui_down"
		elif v.x > 0.7: dir = "ui_right"
		elif v.x < -0.7: dir = "ui_left"
		if dir != "" and _btn_prev.get(key, "") != dir:
			_ui(dir)
		_btn_prev[key] = dir
		if _edge(right, &"ax_button"):
			_ui("ui_accept")
		if _edge(right, &"by_button"):
			Game.menus.back()

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
	# the (shadow-only) body turns after the head once it has looked well away, like a person shifting their feet
	var off := absf(wrapf(head_yaw - float(player.facing), -PI, PI))
	_body_turn = player.get("on_horse") == null and (off > 0.6 or (_body_turn and off > 0.05))
	if _body_turn:
		player.facing = lerp_angle(player.facing, head_yaw, 1.0 - exp(-5.0 * dt))
	player.intent.move = Vector2(mv.x, mv.y)
	player.intent.sprint = left.is_button_pressed(&"primary_click")
	# aim/fire come from the hands (VRPlay: draw by gripping at the holster, fire from the real muzzle); A is a
	# fallback interact with whatever the HUD prompts
	player.intent.fire = false
	player.intent.interact = right.is_button_pressed(&"ax_button") and not play.holding
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
	origin.global_position = target           # mounted: the rider's origin sits below the seat, so the head lands right
	if hands.has("right"):
		hands.right.holding = play.holding
	if hands.has("left"):
		hands.left.holding = play.two_hand
	var moving: float = clampf(float(player.get("speed")) / 4.0, 0.0, 1.0) if player.get("speed") != null else 0.0
	if on_horse != null:
		# riding: always some vignette, more with pace and turning (the horse moves you, not your legs)
		var hs: float = absf(float(on_horse.get("speed"))) if on_horse.get("speed") != null else 0.0
		var yr: float = absf(float(on_horse.get("yaw_rate"))) if on_horse.get("yaw_rate") != null else 0.0
		moving = clampf((0.35 if hs > 0.5 else 0.0) + hs / 12.0 + yr * 0.25, 0.0, 1.0)
	(vignette.material_override as ShaderMaterial).set_shader_parameter("amount", moving * 0.7)
