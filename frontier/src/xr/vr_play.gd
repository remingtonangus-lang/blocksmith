class_name VRPlay
extends Node
## Physical VR play on top of the VR rig (src/xr/vr.gd): guns, reloads, Nerve, reach-to-interact, menu laser and
## reins. Everything reads the XRController3D nodes, so it runs the same with a headset or the desktop simulator.
##
## Guns (WeaponModel/WeaponHolder): grip the right hand at the hip holster (or over the shoulder / behind the hip
## for the long gun) to draw; release to holster. The gun is held on the controller's aim frame, so the real sights
## line up with the eye. Long guns: the left hand snaps to the fore-end (grip_l) when gripped near it and the gun
## then points from the right hand through the left. Trigger fires from the muzzle with a haptic pulse.
## Actions by hand (WeaponModel.manual_cycle): flick the gun down to throw a lever, grab the bolt knob with the left
## hand, or jerk the pump back. Reloads: roll a gate revolver right (gate open) or flick a break-open / top-break down
## (open), take rounds from the belt with the left hand and push them into the gate / breech / port, roll or flick back
## to close. Nerve: left Y while holding a gun slows time, the trigger marks where the muzzle points, Y again or
## releasing the gun fires the marks.
## Interact: reach a hand to a door, counter, board, campfire, horse or person and grip. Menus: the right hand is a
## laser pointer on the menu sheet (trigger clicks). Riding: grip both hands to take the reins; move the hands
## left/right to steer, push them forward to urge the horse on, pull back to stop.

const DRAW_REACH := 0.32
const SUPPORT_REACH := 0.2
const ROUND_REACH := 0.11
const BELT_REACH := 0.3
const INTERACT_REACH := 0.75

var vr: Node                      # VR
var player: Node
var left: XRController3D
var right: XRController3D
var holding := false
var two_hand := false
var _prev := {}
var _vel := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var _last_pos := {}
var _gate_open := false
var _tilt_t := 0.0
var _round: MeshInstance3D        # cartridge in the left hand while reloading
var _pump_ref := 0.0
var laser: MeshInstance3D
var laser_dot: MeshInstance3D
var _rein := false
var _rein_ref := Vector3.ZERO
var _nerve_env := {}

func setup(v: Node, p: Node, l: XRController3D, r: XRController3D) -> void:
	vr = v
	player = p
	left = l
	right = r
	name = "VRPlay"
	var holder = player.get("holder")
	if holder != null:
		holder.vr_hold = true
	_build_laser()
	# the body is still there for shadows (and mirrors); the camera sits in its head
	_body_shadow_only.call_deferred()

var _shadow_t := 0.0

func _body_shadow_only() -> void:
	var vis = player.get("visual")
	if vis is Node3D:
		for mi in (vis as Node3D).find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

# ------------------------------------------------------------------------------------------------- input helpers
func _edge(c: XRController3D, key: String, now: bool) -> bool:
	var k := str(c.tracker) + key
	var was: bool = _prev.get(k, false)
	_prev[k] = now
	return now and not was

func _gripping(c: XRController3D) -> bool:
	return c.get_is_active() and c.get_float(&"grip") > 0.55

## The hand's aim frame at the fist centre (VRHand.aim_transform): guns sit here with grip_r on the origin.
func aim_frame(c: XRController3D) -> Transform3D:
	var h = vr.hands.get("left" if c == left else "right") if vr != null else null
	if h != null:
		return h.aim_transform()
	return VRSim.grip_to_aim(c.global_transform)

func _gun() -> GunHandler:
	return player.get("gun")

func _holder() -> WeaponHolder:
	return player.get("holder")

func model() -> WeaponModel:
	var h := _holder()
	return h.model() if h != null else null

# ------------------------------------------------------------------------------------------------- per frame
func _physics_process(dt: float) -> void:
	if player == null:
		return
	_shadow_t -= dt
	if _shadow_t <= 0.0:
		_shadow_t = 1.0                    # the character model can arrive (or be swapped) after the rig
		_body_shadow_only()
	for side in ["left", "right"]:
		var c := left if side == "left" else right
		var p: Vector3 = c.global_position
		if _last_pos.has(side):
			_vel[side] = _vel[side].lerp((p - _last_pos[side]) / maxf(dt, 0.001), 0.5)
		_last_pos[side] = p
	var nv = player.get("nerve")
	_nerve_grade(nv != null and nv.active)
	var menu_open: bool = Game.get("menus") != null and not Game.menus.stack.is_empty()
	laser.visible = false
	laser_dot.visible = false
	if menu_open:
		_menu_laser()
		return
	if player.get("on_horse") != null:
		_reins(dt)
	_guns(dt)
	_interact()

# ------------------------------------------------------------------------------------------------- guns
func _guns(dt: float) -> void:
	var g := _gun()
	var h := _holder()
	if g == null or h == null:
		return
	var rgrip := _gripping(right)
	var redge := _edge(right, "grip", rgrip)
	if not holding and redge:
		var pick := _reach_gun(right.global_position)
		if pick >= 0:
			g.select(pick)
			g.drawn = true
			g.cooldown = 0.15
			holding = true
			var m0 := model()
			if m0 != null:
				m0.manual_cycle = true
	elif holding and not rgrip:
		holding = false
		two_hand = false
		g.drawn = false
		if _gate_open:
			_close_reload()
		var n0 = player.get("nerve")
		if n0 != null and n0.active:
			n0.execute()
	player.intent.aim = holding
	if not holding and g.drawn:
		g.drawn = false                    # in VR a gun is out only while a hand holds it
	var m := model()
	if not holding or m == null:
		_drop_round()
		return
	# ---- pose the gun on the hand(s)
	var aim := aim_frame(right)
	var grip_local := m.marker_local("grip_r").origin
	var basis := aim.basis.orthonormalized()
	var pistol: bool = m.def.get("slot", "") == "sidearm"
	var lgrip := _gripping(left)
	if not pistol:
		var gl_world := (Transform3D(basis, aim.origin - basis * grip_local) * m.marker_local("grip_l")).origin
		if lgrip and _edge(left, "grip_support", true) and left.global_position.distance_to(gl_world) < SUPPORT_REACH and _round == null:
			two_hand = true
		if not lgrip:
			_edge(left, "grip_support", false)
			two_hand = false
		if two_hand:
			var dir := left.global_position - right.global_position
			if dir.length() > 0.1:
				var fwd := dir.normalized()
				var up := aim.basis.y
				basis = Basis.looking_at(fwd, up if absf(up.dot(fwd)) < 0.95 else Vector3.UP)
				# the support hand sits on grip_l: correct for the grip_r -> grip_l direction in the model
				var gl := m.marker_local("grip_l").origin - grip_local
				var model_dir := gl.normalized()
				basis = basis * Basis(Quaternion(model_dir, Vector3.FORWARD))   # so basis * model_dir == fwd
	m.global_transform = Transform3D(basis, aim.origin - basis * grip_local)
	# ---- trigger
	var trig := right.get_float(&"trigger") > 0.6
	var tedge := _edge(right, "trigger", trig)
	var nerve = player.get("nerve")
	if tedge:
		var mt := m.muzzle_transform()
		if nerve != null and nerve.active:
			nerve.mark(mt.origin, -mt.basis.z)
		elif m.needs_cycle or _gate_open:
			_haptic(right, 0.15, 0.03)
			if Game.audio != null:
				Game.audio.gun_mech("dry", mt.origin)
		elif g.can_fire():
			g.fire(mt.origin, -mt.basis.z, true, 0.5)
			if g.cooldown > 0.0:
				Effects.muzzle_flash(get_tree().current_scene, mt.origin, -mt.basis.z)
				_haptic(right, 0.9, 0.09)
				if two_hand:
					_haptic(left, 0.6, 0.07)
		elif g.clip.get(g.weapon_id(), 0) <= 0:
			if Game.audio != null:
				Game.audio.gun_mech("dry", mt.origin)
	# ---- Nerve (left Y)
	if nerve != null and _edge(left, "by", left.is_button_pressed(&"by_button")):
		if nerve.active:
			nerve.execute()
		elif nerve.can_activate():
			nerve.activate()
	# ---- working the action by hand
	if m.needs_cycle:
		match m.action:
			"lever":
				if _vel.right.dot(-basis.y) > 1.3:            # flick the gun down: lever throw
					m.cycle_action()
					_haptic(right, 0.4, 0.05)
			"bolt":
				if m.parts.has("bolt") and GunHands.BOLT_KNOB.has(m.weapon_id):
					var knob: Vector3 = (m.parts["bolt"].node as Node3D).global_transform * (GunHands.BOLT_KNOB[m.weapon_id] as Vector3)
					var hand := left if not two_hand else right
					if _edge(left, "bolt", lgrip) and left.global_position.distance_to(knob) < 0.14:
						m.cycle_action()
						_haptic(hand, 0.4, 0.05)
			"pump":
				if two_hand and _vel.left.dot(basis.z) > 0.9:  # jerk the fore-end back toward the shooter
					m.cycle_action()
					_haptic(left, 0.5, 0.06)
	# ---- reloads
	_reload(dt, m, g, basis)

## Which weapon slot the hand is reaching for: the sidearm at the hip, the long gun on the back / scabbard.
func _reach_gun(p: Vector3) -> int:
	var g := _gun()
	var h := _holder()
	var best := -1
	var bd := 1e9
	for i in g.weapons.size():
		var wm: WeaponModel = h.models.get(g.weapons[i])
		if wm == null:
			continue
		var pistol: bool = wm.def.get("slot", "") == "sidearm"
		var gp := wm.grip_transform("grip_r").origin
		var d := p.distance_to(gp)
		var reach := DRAW_REACH if pistol else DRAW_REACH * 1.5
		if not pistol:
			# over the right shoulder counts too
			var cam3 := vr.cam as Node3D
			var rel := p - cam3.global_position
			var fwd := -cam3.global_basis.z
			fwd.y = 0.0
			if rel.y > -0.12 and rel.length() < 0.45 and rel.dot(fwd.normalized()) < 0.05:
				d = minf(d, 0.2)                     # reaching back over the shoulder
		if d < reach and d < bd:
			bd = d
			best = i
	return best

func _haptic(c: XRController3D, amp: float, secs: float) -> void:
	if c.get_is_active():
		c.trigger_haptic_pulse(&"haptic", 0.0, amp, secs, 0.0)

# ------------------------------------------------------------------------------------------------- reloads
func _reload(dt: float, m: WeaponModel, g: GunHandler, basis: Basis) -> void:
	var gate_style: bool = m.parts.has("loading_gate") and m.def.get("slot", "") == "sidearm"
	var breaks := m.parts.has("barrels") or m.parts.has("breech")
	if gate_style:
		# roll the revolver onto its left side (gate up and toward the face) to open, back upright to close
		var roll := basis.x.dot(Vector3.UP)        # +X (right side) pointing up when rolled left
		if not _gate_open and roll > 0.6:
			_tilt_t += dt
			if _tilt_t > 0.15:
				_open_reload()
		elif _gate_open and roll < 0.2:
			_tilt_t += dt
			if _tilt_t > 0.25:
				_close_reload()
		else:
			_tilt_t = 0.0
	elif breaks:
		# flick the muzzle down to break it open, up to close
		var v: Vector3 = _vel.right
		if not _gate_open and v.dot(Vector3.DOWN) > 1.6 and (-basis.z).dot(Vector3.DOWN) > -0.2:
			_open_reload()
		elif _gate_open and v.dot(Vector3.UP) > 1.6:
			_close_reload()
	# rounds from the belt with the left hand
	var lgrip := _gripping(left)
	var ledge := _edge(left, "round", lgrip)
	if ledge and not two_hand and _round == null and g.ammo.get(m.def.ammo, 0) > 0:
		if left.global_position.distance_to(_belt_point()) < BELT_REACH:
			_take_round(m)
	if _round != null and not lgrip:
		_drop_round()
	if _round != null:
		var port := _port(m)
		var can_load: bool = _gate_open or not (gate_style or breaks)
		if can_load and left.global_position.distance_to(port) < ROUND_REACH and g.clip.get(g.weapon_id(), 0) < int(m.def.capacity):
			var id := g.weapon_id()
			g.clip[id] += 1
			g.ammo[m.def.ammo] = int(g.ammo[m.def.ammo]) - 1
			if not (gate_style or breaks):
				m.reload_anim(int(g.clip[id]))        # lever gate push / round into the port
			_haptic(left, 0.3, 0.04)
			if Game.audio != null:
				Game.audio.gun_mech("round" if m.def.ammo != "shotgun" else "shell", port)
			_drop_round()

func _open_reload() -> void:
	var g := _gun()
	_gate_open = true
	_tilt_t = 0.0
	g.reloading = true
	g.set("_reload_t", 1.0e9)                     # rounds come from the hand, not the timer
	_haptic(right, 0.3, 0.05)

func _close_reload() -> void:
	var g := _gun()
	_gate_open = false
	_tilt_t = 0.0
	g.reloading = false
	_haptic(right, 0.3, 0.05)

func _belt_point() -> Vector3:
	var vis = player.get("visual")
	var b: Basis = (vis as Node3D).global_basis if vis is Node3D else Basis.IDENTITY
	return player.global_position + Vector3(0, 0.98, 0) + b * Vector3(-0.12, 0, -0.1)

func _port(m: WeaponModel) -> Vector3:
	if m.parts.has("loading_gate"):
		return (m.parts["loading_gate"].node as Node3D).global_position
	var se := m.marker("shell_eject")
	return se.global_position if se != null else m.global_position

func _take_round(m: WeaponModel) -> void:
	_round = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var shot: bool = m.def.ammo == "shotgun"
	cm.top_radius = 0.0105 if shot else 0.0055
	cm.bottom_radius = cm.top_radius
	cm.height = 0.065 if shot else 0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.08, 0.06) if shot else Color(0.8, 0.6, 0.32)
	mat.metallic = 0.0 if shot else 1.0
	mat.roughness = 0.4
	cm.material = mat
	_round.mesh = cm
	left.add_child(_round)
	_round.position = Vector3(0.0, 0.0, -0.06)
	_round.rotation.x = PI / 2
	_haptic(left, 0.2, 0.03)

func _drop_round() -> void:
	if _round != null:
		_round.queue_free()
		_round = null

# ------------------------------------------------------------------------------------------------- Nerve look
func _nerve_grade(on: bool) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var env: Environment = cam.environment if cam.environment != null else cam.get_world_3d().environment
	if env == null:
		return
	if on and _nerve_env.is_empty():
		_nerve_env = {"on": env.adjustment_enabled, "sat": env.adjustment_saturation, "b": env.adjustment_brightness}
		env.adjustment_enabled = true
		env.adjustment_saturation = 0.18           # the overlay shader is screen-space; in VR grade the world
		env.adjustment_brightness = 0.92
	elif not on and not _nerve_env.is_empty():
		env.adjustment_enabled = _nerve_env.on
		env.adjustment_saturation = _nerve_env.sat
		env.adjustment_brightness = _nerve_env.b
		_nerve_env.clear()

# ------------------------------------------------------------------------------------------------- interaction
func _interact() -> void:
	var hud = Game.get("hud")
	for c in [left, right]:
		if c == right and holding:
			continue
		if c == left and (two_hand or _round != null):
			continue
		var p: Vector3 = c.global_position
		var best: Node = null
		var bd := INTERACT_REACH
		for n in get_tree().get_nodes_in_group("interactable"):
			if not (n is Node3D) or not n.has_method("interact_prompt") or n == player:
				continue
			var q := (n as Node3D).global_position
			var d := Vector2(q.x - p.x, q.z - p.z).length() + maxf(absf(q.y + 1.0 - p.y) - 1.0, 0.0)
			if d < bd and str(n.interact_prompt()) != "":
				bd = d
				best = n
		var door = null
		var main = Game.get("main")
		if best == null and main != null and main.get("settlements") != null and main.settlements.has_method("nearest_door"):
			door = main.settlements.nearest_door(p, 0.6)
		if best == null and door == null:
			for dn in get_tree().get_nodes_in_group("door"):   # loose doors (test sets)
				var dd: TownDoor = dn
				if (dd.global_transform * Vector3(dd.width * 0.5 * dd.hinge_sign, 1.0, 0.0)).distance_to(p) < 0.6:
					door = dd
		if c == right and _reach_gun(p) >= 0:
			continue                                   # the right hand at the holster draws instead
		var g := _gripping(c)
		var e := _edge(c, "interact", g)
		if best != null:
			if hud and hud.has_method("prompt"):
				hud.prompt("[Grip]  " + str(best.interact_prompt()))
			if e:
				best.interact(player)
				_haptic(c, 0.3, 0.05)
			return
		if door != null:
			if hud and hud.has_method("prompt"):
				hud.prompt("[Grip]  " + ("Close door" if door.is_open() else "Open door"))
			if e:
				door.interact(player)
				_haptic(c, 0.3, 0.05)
			return

# ------------------------------------------------------------------------------------------------- menu laser
func _build_laser() -> void:
	laser = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.002
	cm.bottom_radius = 0.002
	cm.height = 1.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.55)
	cm.material = m
	laser.mesh = cm
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.visible = false
	add_child(laser)
	laser.top_level = true
	laser_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	sm.material = m
	laser_dot.mesh = sm
	laser_dot.top_level = true
	laser_dot.visible = false
	add_child(laser_dot)

func _menu_laser() -> void:
	var quad: MeshInstance3D = vr.get("menu_quad")
	var vp: SubViewport = vr.get("menu_vp")
	if quad == null or vp == null or not quad.visible or not right.get_is_active():
		return
	var aim := aim_frame(right)
	var o := aim.origin
	var d := -aim.basis.z.normalized()
	var n := quad.global_basis.z.normalized()
	var denom := n.dot(d)
	if absf(denom) < 1e-4:
		return
	var t := n.dot(quad.global_position - o) / denom
	if t <= 0.0 or t > 6.0:
		return
	var hit := o + d * t
	var local := quad.global_transform.affine_inverse() * hit
	var size: Vector2 = (quad.mesh as QuadMesh).size
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	laser.visible = true
	laser.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(1, t, 1)), o + d * t * 0.5)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	laser_dot.visible = true
	laser_dot.global_position = hit
	var px := uv * Vector2(vp.size)
	var mm := InputEventMouseMotion.new()
	mm.position = px
	mm.global_position = px
	vp.push_input(mm)
	var trig := right.get_float(&"trigger") > 0.6
	var e := _edge(right, "laser", trig)
	var released: bool = not trig and _prev.get(str(right.tracker) + "laser_down", false)
	if e or released:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = e
		mb.position = px
		mb.global_position = px
		vp.push_input(mb)
		if e:
			_haptic(right, 0.15, 0.02)
	_prev[str(right.tracker) + "laser_down"] = trig

# ------------------------------------------------------------------------------------------------- reins
func _reins(_dt: float) -> void:
	var horse: Node3D = player.on_horse
	var both := _gripping(left) and _gripping(right) and not holding
	_rein_lines(horse, both)
	if not both:
		_rein = false
		return
	var hb := Basis(Vector3.UP, float(horse.get("yaw")) if horse.get("yaw") != null else horse.global_rotation.y)
	var mid := (left.global_position + right.global_position) * 0.5
	var head := (vr.cam as Node3D).global_position
	var rel := hb.inverse() * (mid - head)              # x right, z back
	if not _rein:
		_rein = true
		_rein_ref = rel
	var steer := clampf((rel.x - _rein_ref.x) / 0.14, -1.0, 1.0)
	var push := clampf((_rein_ref.z - rel.z) / 0.12, -1.0, 1.0)  # hands forward = positive
	player.cam_yaw = hb.get_euler().y
	var mv := Vector2(steer * 0.8, 1.0 if push > -0.5 else -1.0)
	player.intent.move = mv
	player.intent.sprint = push > 0.6
	if push < -0.5:
		player.intent.move = Vector2(0, -1)            # pull back: whoa

## Reins as two leather straps from the fists to the bit while they are held (the tack's own reins hang otherwise).
var _rein_mesh: Array = []
func _rein_lines(horse: Node3D, on: bool) -> void:
	if _rein_mesh.is_empty():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.13, 0.07)
		mat.roughness = 0.8
		for i in 2:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.016, 1.0, 0.004)
			bm.material = mat
			mi.mesh = bm
			mi.top_level = true
			add_child(mi)
			_rein_mesh.append(mi)
	var bit := Vector3.INF
	var side := Vector3.RIGHT
	var vis = horse.get("visual")
	var sk: Skeleton3D = vis.get("skeleton") if vis != null else null
	if on and sk != null:
		var b := sk.find_bone("head")
		if b >= 0:
			var bt := sk.global_transform * sk.get_bone_global_pose(b)
			bit = bt.origin + bt.basis.y.normalized() * 0.42 - bt.basis.z.normalized() * 0.04
			side = bt.basis.x.normalized()
	for i in 2:
		var mi: MeshInstance3D = _rein_mesh[i]
		mi.visible = on and bit != Vector3.INF
		if not mi.visible:
			continue
		var c := left if i == 0 else right
		var a := aim_frame(c).origin
		var e := bit + side * (-0.07 if i == 0 else 0.07)
		var d := e - a
		var l := d.length()
		if l < 0.05:
			mi.visible = false
			continue
		var y := d / l
		var x := y.cross(Vector3.UP).normalized() if absf(y.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var z := x.cross(y)
		mi.global_transform = Transform3D(Basis(x, y * l, z), (a + e) * 0.5)
