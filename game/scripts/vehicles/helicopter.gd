class_name Helicopter
extends RigidBody3D
## Attack helicopter (the Capital's "Heron" gunship; the Cinder Pact flies a rust-and-olive copy). Arcade-sim
## flight on Jolt: the stick asks for a velocity in the heading frame, A/Space and B/C climb and sink, the
## heading follows the camera (Halo-style), the body tilts into its acceleration, a hover assist holds height.
## Chin gun follows the crosshair (RT / LMB), rocket pods fire salvos (LB / G). AI flies waypoint orbits and
## attacks enemy groups.

const MASS := 6500.0
const MAX_SPEED := 72.0
const CLIMB := 14.0

var faction := 0
var pilot: Player = null
var cam: VehicleCam
var rotor: Node3D
var tail: Node3D
var rotor_speed := 0.0
var gun_t := 0.0
var rocket_t := 0.0
var rockets := 16
var hp := 900.0
var ai := false
var ai_orbit := Vector3.ZERO
var ai_radius := 350.0
var ai_alt := 110.0
var ai_angle := 0.0
var _target_vel := Vector3.ZERO
var _heading := 0.0
var engine_on := false
var _gun_side := 0
var rotor_snd: AudioStreamPlayer3D


func build(f: int, mat: Material) -> void:
	faction = f
	mass = MASS
	gravity_scale = 1.0
	linear_damp = 0.2
	angular_damp = 3.0
	collision_layer = 4
	collision_mask = 1 | 4
	can_sleep = false
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 1.4, 0)
	var main := Kit.STONE if f == 0 else Kit.OLIVE
	var trim := Kit.TRIM if f == 0 else Kit.RUST
	var k := Kit.new()
	# Fuselage: a slim chamfered body, tandem canopy, tail boom, fin, stub wings with pods, skids.
	var side := PackedVector2Array([Vector2(-6.2, 1.5), Vector2(-5.6, 2.5), Vector2(-4.0, 3.1), Vector2(-1.6, 3.4),
		Vector2(1.6, 3.3), Vector2(3.4, 2.8), Vector2(10.5, 2.75), Vector2(10.5, 2.35), Vector2(3.2, 1.9),
		Vector2(1.5, 1.1), Vector2(-3.5, 1.0), Vector2(-5.6, 1.15)])
	var xf := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(-0.8, 0, 0))
	k.prism(xf, side, 0.0, 1.6, k.col(main, 0.5, 2.0, false), true, true, k.col(main, 0.5, 2.0, false))
	k.box(Transform3D.IDENTITY, Vector3(0, 3.0, -3.4), Vector3(1.3, 0.85, 3.6), k.col(Kit.DARKGLASS, 0.5, 1.0, false))
	k.box(Transform3D.IDENTITY, Vector3(0, 3.4, 9.6), Vector3(0.18, 2.6, 1.6), k.col(main, 0.5))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.6, 9.9), Vector3(3.2, 0.12, 1.0), k.col(trim, 0.5))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.15, -0.6), Vector3(4.8, 0.18, 1.3), k.col(trim, 0.5))
	for s in [-1.0, 1.0]:
		k.tube(Vector3(s * 2.1, 1.8, -1.8), Vector3(s * 2.1, 1.8, 0.8), 0.32, 8, k.col(Kit.METAL, 0.5), true)
		k.tube(Vector3(s * 1.0, 0.15, -2.6), Vector3(s * 1.0, 0.15, 2.6), 0.08, 6, k.col(Kit.METAL, 0.5), true)
		k.tube(Vector3(s * 1.0, 0.15, -1.6), Vector3(s * 0.7, 1.1, -1.6), 0.07, 6, k.col(Kit.METAL, 0.5), true)
		k.tube(Vector3(s * 1.0, 0.15, 1.6), Vector3(s * 0.7, 1.1, 1.6), 0.07, 6, k.col(Kit.METAL, 0.5), true)
	k.tube(Vector3(0, 0.95, -5.0), Vector3(0, 0.95, -6.5), 0.09, 6, k.col(Kit.METAL, 0.5), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 3.4, 0.4)), Kit.ngon(0.6, 8), 0.0, 0.7, k.col(trim, 0.5), true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	add_child(mi)
	rotor = _rotor(mat, 6.4, 4, Vector3(0, 4.15, 0.4), false)
	tail = _rotor(mat, 0.9, 6, Vector3(0.3, 3.4, 10.2), true)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.4, 9.0)
	cs.shape = box
	cs.position = Vector3(0, 2.0, -1.0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var skid := BoxShape3D.new()
	skid.size = Vector3(2.4, 0.3, 5.0)
	cs2.shape = skid
	cs2.position = Vector3(0, 0.15, 0)
	add_child(cs2)
	G.add_interactable(self, Vector3(-1.2, 2.0, -3.0), 4.0, "Fly the gunship", enter)
	rotor_snd = Sfx.attach_loop(self, "loop_rotor", -4.0)


func _rotor(mat: Material, r: float, blades: int, at: Vector3, side: bool) -> Node3D:
	var n := Node3D.new()
	n.position = at
	if side:
		n.rotation.z = PI * 0.5
	add_child(n)
	var k := Kit.new()
	for b in blades:
		var a := TAU * b / blades
		k.box(Transform3D(Basis(Vector3.UP, a), Vector3.ZERO), Vector3(r * 0.5, 0, 0), Vector3(r, 0.06, 0.32 if not side else 0.14), k.col(Kit.METAL, 0.2))
	k.tube(Vector3(0, -0.2, 0), Vector3(0, 0.2, 0), 0.3 if not side else 0.12, 8, k.col(Kit.TRIM, 0.2), true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	n.add_child(mi)
	return n


func enter(p: Player) -> void:
	if pilot:
		return
	pilot = p
	ai = false
	engine_on = true
	p.enter_vehicle(self)
	cam = VehicleCam.new()
	get_tree().root.add_child(cam)
	var ex: Array[RID] = [get_rid()]
	cam.attach(self, 18.0, 3.5, ex)
	cam.min_pitch = -1.3
	_heading = global_rotation.y
	if G.hud:
		G.hud.message("Gunship: A / Space climb, B / C sink, stick / WASD fly, RT / LMB chin gun, LB / G rockets")


func exit(p: Player) -> void:
	if pilot != p:
		return
	var alt := global_position.y - G.world.ground_at(global_position.x, global_position.z)
	if alt > 6.0 and linear_velocity.length() > 4.0:
		if G.hud:
			G.hud.message("Land first (or slow to a hover under 6 m) to get out")
		return
	pilot = null
	var out := global_transform * Vector3(-2.6, 0.5, -1.5)
	out.y = maxf(out.y, G.world.ground_at(out.x, out.z) + 0.2)
	p.exit_vehicle(out)
	if cam:
		cam.queue_free()
		cam = null


func hud_text() -> String:
	var alt := global_position.y - G.world.ground_at(global_position.x, global_position.z)
	return "GUNSHIP  %3d km/h  ALT %4d m\nGUN %s   ROCKETS %d" % [int(linear_velocity.length() * 3.6), int(alt), "READY" if gun_t <= 0.0 else "...", rockets]


func _process(delta: float) -> void:
	var want := 1.0 if (engine_on or pilot or ai) else 0.0
	rotor_speed = move_toward(rotor_speed, want, delta * 0.4)
	rotor.rotation.y += rotor_speed * 32.0 * delta
	if rotor_snd:
		rotor_snd.pitch_scale = maxf(0.2, rotor_speed)
		rotor_snd.volume_db = -60.0 + rotor_speed * 58.0
	tail.rotation.y += rotor_speed * 60.0 * delta
	gun_t = maxf(0.0, gun_t - delta)
	rocket_t = maxf(0.0, rocket_t - delta)
	if pilot and cam:
		if Input.is_action_pressed("fire") or Controls.trigger(true) > 0.4:
			_gun(cam.aim_point([get_rid()]))
		if Input.is_action_just_pressed("grenade"):
			_rocket_salvo(cam.aim_point([get_rid()]))


func _gun(at: Vector3) -> void:
	if gun_t > 0.0:
		return
	gun_t = 0.07
	var o := global_transform * Vector3(0, 0.95, -6.6)
	var dir := (at - o).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.006).normalized()
	if G.combat and G.combat.has_method("bullet"):
		G.combat.bullet(o, dir, 1100.0, 34.0, faction, [get_rid()], true)
	elif G.fx:
		G.fx.shot(o, o + dir * 600.0, faction, false)


func _rocket_salvo(at: Vector3) -> void:
	if rocket_t > 0.0 or rockets <= 0:
		return
	rocket_t = 1.2
	for k in 4:
		if rockets <= 0:
			break
		rockets -= 1
		_gun_side = 1 - _gun_side
		var o := global_transform * Vector3((_gun_side * 2 - 1) * 2.1, 1.8, -2.2)
		var spread := Vector3(randf_range(-6, 6), randf_range(-2, 2), randf_range(-6, 6))
		if G.fx:
			G.fx.rocket(o, at + spread, faction)


func _physics_process(delta: float) -> void:
	var up := 0.0
	var mv := Vector2.ZERO
	if pilot and cam:
		mv = Controls.move_vector()
		up = float(Input.is_action_pressed("ascend")) - float(Input.is_action_pressed("descend"))
		up += Controls.trigger(false) * 0.0
		_heading = lerp_angle(_heading, cam.yaw, 1.0 - exp(-delta * 2.5))
	elif ai:
		var r := _ai_steer(delta)
		mv = Vector2(r.x, r.y)
		up = r.z
	else:
		# Parked: gravity and skids.
		return
	var basis_h := Basis(Vector3.UP, _heading)
	var hv := basis_h * Vector3(mv.x, 0.0, -mv.y) * MAX_SPEED
	var target := Vector3(hv.x, up * CLIMB, hv.z)
	# Hover assist: hold altitude when there is no climb input.
	var a := (target - linear_velocity) * 1.6
	a.y += 9.81
	a = a.limit_length(26.0)
	apply_central_force(a * mass)
	# Attitude: heading from the camera, pitch and roll into the horizontal acceleration.
	var lateral := basis_h.inverse() * Vector3(a.x, 0, a.z)
	var want_pitch := clampf(lateral.z * 0.03, -0.45, 0.45)
	var want_roll := clampf(-lateral.x * 0.03, -0.5, 0.5)
	var want := Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, want_pitch) * Basis(Vector3.FORWARD, want_roll)
	var err := (want * global_transform.basis.inverse()).get_rotation_quaternion()
	var axis := err.get_axis()
	var ang := err.get_angle()
	if ang > PI:
		ang -= TAU
	if axis.is_finite():
		apply_torque((axis * ang * 9.0 - angular_velocity * 3.5) * mass * 4.0)


## AI: orbit a point (the front), climb to altitude, attack enemy soldiers below with the gun and rockets.
func _ai_steer(delta: float) -> Vector3:
	ai_angle += delta * 0.07
	var goal := ai_orbit + Vector3(cos(ai_angle), 0, sin(ai_angle)) * ai_radius
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	_heading = lerp_angle(_heading, atan2(-to.x, -to.z), 1.0 - exp(-delta * 0.8))
	var fwd := clampf(dist / 120.0, 0.0, 0.55)
	var ground := G.world.ground_at(global_position.x, global_position.z)
	var alt_err := (ground + ai_alt) - global_position.y
	# Attack: every few seconds rake the nearest enemy group.
	if G.battle and G.battle.army and gun_t <= 0.0 and randf() < 0.02:
		var e := G.battle.army.nearest_enemy(global_position, faction, 700.0)
		if e >= 0:
			var p: Vector3 = G.battle.army.pos[e] + Vector3(0, 1, 0)
			if randf() < 0.3 and rockets > 0:
				_rocket_salvo(p)
			else:
				for k in 6:
					_gun(p + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
					gun_t = 0.0
				gun_t = 1.5
	if rockets <= 0 and randf() < 0.001:
		rockets = 16
	return Vector3(0.0, fwd, clampf(alt_err / 20.0, -1.0, 1.0))


func damage(amount: float, at: Vector3) -> void:
	hp -= amount
	if hp <= 0.0 and G.combat and G.combat.has_method("destroy_vehicle"):
		G.combat.destroy_vehicle(self)
