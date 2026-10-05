class_name VR
extends Node
## OpenXR (Quest 3) support: starts the XR session when an OpenXR runtime is present, swaps the flat camera for an
## XROrigin3D rig that follows the player (seated or standing height), and maps controllers to the player's
## intent: left stick moves (head-relative), right stick snap/smooth turns, triggers aim/fire with the right hand,
## grips interact/mount. Comfort: vignette while moving or riding, snap turn by default, height calibration.
## Physical play (guns, reloads, reach-to-interact, menu laser, reins) lives in VRPlay (vr_play.gd). The player's own
## character is the body (VRBody, vr_body.gd: head follow, arm IK to the controllers, finger curl, head shadow-only);
## VRHand gloves stand in when there is no character skeleton.
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
var smooth_speed := 100.0          # deg/s (smooth turning)
var vignette_strength := 1.0       # 0 = off (Settings > Accessibility)
var height_mode := "standing"      # "standing" (real height, 1:1 or calibrated) | "seated" (raised to the character)
var stand_eye := 0.0               # calibrated standing eye height (0 = not calibrated: 1:1)
var seated_eye := 1.2              # seated eye height (calibrate to measure)
var body: VRBody
var _body_t := 0.0
var _lean_rest := Vector2.ZERO     # where the head "belongs" in the room; leaning away from it moves the view
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
	if Game.get("menus") != null and Game.menus.get("settings") is Dictionary:
		apply_settings(Game.menus.settings)
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
		origin.rotate_y(-deg_to_rad(smooth_speed) * turn * dt)
	# put the camera at the character's eyes: real head height relative to the calibrated eye height; leaning in the
	# room moves the view (up to 35 cm) while the body catches up over a couple of seconds
	_body_t -= dt
	if _body_t <= 0.0:
		_body_t = 1.0
		_ensure_body()
	var head_local := cam.position
	if _auto_eye <= 0.5 and cam.position.y > 0.5:
		_auto_t += dt
		if _auto_t > 1.0:
			_auto_eye = cam.position.y          # standing uncalibrated: your eyes become the character's eyes
	var hl := Vector2(head_local.x, head_local.z)
	_lean_rest = _lean_rest.lerp(hl, 1.0 - exp(-0.6 * dt))
	if (hl - _lean_rest).length() > 0.35:
		_lean_rest = hl - (hl - _lean_rest).normalized() * 0.35
	var eye := eye_anchor()
	var on_horse = player.get("on_horse")
	origin.global_position = Vector3(eye.x, eye.y - user_eye(), eye.z) - origin.global_basis * Vector3(_lean_rest.x, 0.0, _lean_rest.y)
	_update_body()
	_horse_lod(on_horse)
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
	(vignette.material_override as ShaderMaterial).set_shader_parameter("amount", clampf(moving * 0.7 * vignette_strength, 0.0, 1.0))

# ------------------------------------------------------------------------------------------------- body + comfort
## The character model can arrive after the rig: keep trying to put VRBody on its skeleton.
func _ensure_body() -> void:
	if body != null and is_instance_valid(body):
		return
	var vis = player.get("visual")
	if not (vis is Node3D):
		return
	var sk: Skeleton3D = null
	var holder = player.get("holder")
	if holder != null and holder.get("skel") != null:
		sk = holder.skel
	if sk == null:
		var found := (vis as Node3D).find_children("*", "Skeleton3D", true, false)
		sk = found[0] if not found.is_empty() else null
	if sk == null:
		return
	var b := VRBody.new()
	b.name = "VRBody"
	sk.add_child(b)                       # last modifier: after the animation, GunHands and the look-at
	if not b.setup_vr(sk, self, str(vis.get("character_id")) if vis.get("character_id") != null else "default"):
		b.queue_free()
		return
	body = b
	body.driving = true
	VRBody.hide_head(vis)
	for h in hands.values():
		h.visible = false                 # the character's own hands now
	if play != null:
		play.body_mode = true

func _update_body() -> void:
	if body == null or not is_instance_valid(body):
		return
	body.body = Basis(Vector3.UP, float(player.facing))
	body.held_model = play.model() if play.holding else null
	body.head_xf = cam.global_transform
	for side in ["Right", "Left"]:
		var c := right if side == "Right" else left
		var h: VRHand = hands["right" if side == "Right" else "left"]
		body.hand_on[side] = c.get_is_active()
		body.hand_xf[side] = h.aim_transform()
		body.inputs[side] = {"grip": c.get_float(&"grip"), "trigger": c.get_float(&"trigger"), "thumb": h.thumb,
			"holding": play.holding if side == "Right" else play.two_hand}

## Where the camera belongs: the character's eyes (rest pose, so walk bob never moves the view). At the eyes the
## collar opening stays behind and below the view when looking down at yourself.
const EYE_PUSH := 0.05
func eye_anchor() -> Vector3:
	if body != null and is_instance_valid(body) and body.get_skeleton() != null:
		var horse = player.get("on_horse")
		if horse != null:
			# seated: straight up from the saddle seat by the character's hips->eyes height (the rider's readable
			# pose is not where the seated body is drawn: see WeaponHolder.mount_offset)
			var hv = horse.get("visual")
			if hv != null and hv.has_method("seat_transform"):
				var st: Transform3D = hv.seat_transform()
				var fwd: Vector3 = horse.forward() if horse.has_method("forward") else -st.basis.z
				return st.origin + st.basis.y.normalized() * (body.eye_height - body.hips_height + 0.06) + fwd * 0.04
			# on foot: the animated eyes (the gameplay clips stand ~10 cm taller than the rest pose, so a rest-pose
		# camera sat inside the neck), low-passed in the player's frame so walk bob never moves the view
		var pg := (player as Node3D).global_transform
		var local: Vector3 = pg.affine_inverse() * body.posed_eye(EYE_PUSH)
		if _eye_local == Vector3.ZERO:
			_eye_local = local
		_eye_local = _eye_local.lerp(local, 1.0 - exp(-1.5 * get_physics_process_delta_time()))
		return pg * _eye_local
	return player.global_position + Vector3(0, 1.62, 0)

var _eye_local := Vector3.ZERO
var _auto_t := 0.0
var _auto_eye := 0.0                # standing, not calibrated: the head height measured after the first second

func character_eye_height() -> float:
	if body != null and is_instance_valid(body):
		return _eye_local.y if _eye_local != Vector3.ZERO else body.eye_height
	return 1.62

## The user's own eye height for the current play position (standing uncalibrated = 1:1 with the character).
func user_eye() -> float:
	if height_mode == "seated":
		return seated_eye
	if stand_eye > 0.5:
		return stand_eye
	return _auto_eye if _auto_eye > 0.5 else character_eye_height()

## Measure the user's eye height now (stand or sit naturally) for the current play position, and save it.
func calibrate() -> float:
	var h := cam.position.y
	if height_mode == "seated":
		seated_eye = h
	else:
		stand_eye = h
	if Game.get("menus") != null and Game.menus.get("settings") is Dictionary:
		Game.menus.settings["vr_seated_eye" if height_mode == "seated" else "vr_stand_eye"] = h
		if Game.menus.has_method("_save_settings"):
			Game.menus._save_settings()
	return h

func apply_settings(st: Dictionary) -> void:
	var t := str(st.get("vr_turn", "snap30" if st.get("snap_turn", true) else "smooth"))
	snap_turn = t != "smooth"
	snap_deg = 45.0 if t == "snap45" else 30.0
	smooth_speed = float(st.get("vr_turn_speed", 100.0))
	vignette_strength = float(st.get("vr_vignette", 1.0))
	height_mode = str(st.get("vr_height_mode", "standing"))
	stand_eye = float(st.get("vr_stand_eye", 0.0))
	seated_eye = float(st.get("vr_seated_eye", 1.2))

## Quest preset: the horse you sit on keeps its 26k hero body for the eyes (LOD1 looked faceted a metre away) but
## casts its shadows with the 8k LOD1 body, so the shadow cascades skip the hero mesh.
var _lod_horse: Node = null
func _horse_lod(on_horse) -> void:
	var want: Node = on_horse if (on_horse != null and Game.quality.get("mounted_horse_lod1", false)) else null
	if want == _lod_horse:
		return
	if _lod_horse != null and is_instance_valid(_lod_horse):
		_set_horse_lod(_lod_horse, false)
	_lod_horse = want
	if want != null:
		_set_horse_lod(want, true)

static func _set_horse_lod(h: Node, on: bool) -> void:
	for n in h.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		match String(mi.name):
			"Body":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			"Body_LOD1":
				if not mi.has_meta("vr_begin"):
					mi.set_meta("vr_begin", mi.visibility_range_begin)
				mi.visibility_range_begin = 0.0 if on else float(mi.get_meta("vr_begin"))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
