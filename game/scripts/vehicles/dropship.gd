class_name Dropship
extends AnimatableBody3D
## The Capital's VTOL dropship: a white lifting body with two tilting ducted fans, a rear ramp and a troop bay.
## AI flight on a schedule: lift off from its pad, climb, cruise to a landing zone near the front, descend,
## lower the ramp, unload a squad, lift off and return. The player can ride along as a passenger (use the ramp
## while it is down); landing at the front lets them out.

enum { PARKED, LIFT, CRUISE, DESCEND, UNLOAD, RETURN_LIFT, RETURN, RETURN_DESCEND }

var faction := 0
var state := PARKED
var home := Vector3.ZERO
var lz := Vector3.ZERO
var t := 0.0
var wait := 0.0
var fans: Array[Node3D] = []
var ramp: Node3D
var passenger: Player = null
var cam: VehicleCam
var vel := Vector3.ZERO
var cruise_alt := 160.0
var squad_count := 0
var _yaw := 0.0
var hp := 1500.0


func build(f: int, mat: Material, pad: Vector3, landing: Vector3) -> void:
	faction = f
	home = pad
	lz = landing
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	var main := Kit.STONE
	var k := Kit.new()
	# Lifting body: wide chamfered hull, raised cockpit, tail booms with a high tailplane.
	var plan := PackedVector2Array([Vector2(-2.2, -9.0), Vector2(2.2, -9.0), Vector2(3.6, -6.0), Vector2(3.8, 5.0),
		Vector2(3.0, 8.0), Vector2(-3.0, 8.0), Vector2(-3.8, 5.0), Vector2(-3.6, -6.0)])
	k.prism(Transform3D.IDENTITY, plan, 0.8, 4.0, k.col(main, 0.6, 3.2, false), true, true, k.col(main, 0.6, 3.2, false))
	k.prism(Transform3D.IDENTITY, Kit.inset(plan, 0.5), 4.0, 4.5, k.col(Kit.TRIM, 0.6), true)
	k.box(Transform3D.IDENTITY, Vector3(0, 3.6, -8.4), Vector3(3.2, 1.0, 1.4), k.col(Kit.DARKGLASS, 0.6, 1.0, false))
	for s in [-1.0, 1.0]:
		k.box(Transform3D.IDENTITY, Vector3(s * 2.6, 3.4, 10.5), Vector3(0.35, 0.8, 6.0), k.col(main, 0.6))
		k.box(Transform3D.IDENTITY, Vector3(s * 2.6, 5.0, 13.0), Vector3(0.25, 3.0, 1.6), k.col(main, 0.6))
		k.box(Transform3D.IDENTITY, Vector3(s * 3.85, 2.4, 0.0), Vector3(0.05, 0.5, 8.0), k.col(Kit.DARKGLASS, 0.6, 1.0, true))
		# Landing struts.
		k.tube(Vector3(s * 2.6, 0.9, -5.0), Vector3(s * 2.8, 0.0, -5.0), 0.12, 6, k.col(Kit.METAL, 0.6), true)
		k.tube(Vector3(s * 2.6, 0.9, 5.0), Vector3(s * 2.8, 0.0, 5.0), 0.12, 6, k.col(Kit.METAL, 0.6), true)
	k.box(Transform3D.IDENTITY, Vector3(0, 6.4, 13.0), Vector3(6.0, 0.25, 1.4), k.col(Kit.TRIM, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	add_child(mi)
	for s in [-1.0, 1.0]:
		var fan := Node3D.new()
		fan.position = Vector3(s * 5.6, 3.0, -1.0)
		add_child(fan)
		var fk := Kit.new()
		fk.prism(Transform3D.IDENTITY, Kit.ngon(2.4, 20), -0.9, 0.9, fk.col(main, 0.6, 1.0, false), false)
		fk.prism(Transform3D.IDENTITY, Kit.ngon(2.0, 20), -0.9, 0.9, fk.col(Kit.METAL, 0.6, 1.0, false), false)
		for b in 6:
			fk.box(Transform3D(Basis(Vector3.UP, TAU * b / 6.0), Vector3.ZERO), Vector3(1.0, 0, 0), Vector3(1.9, 0.05, 0.4), fk.col(Kit.METAL, 0.6))
		fk.box(Transform3D.IDENTITY, Vector3(-s * 1.6, 0, 0), Vector3(1.6, 0.5, 1.2), fk.col(Kit.TRIM, 0.6))
		var fmi := MeshInstance3D.new()
		fmi.mesh = fk.commit()
		fmi.material_override = mat
		fan.add_child(fmi)
		fans.append(fan)
	ramp = Node3D.new()
	ramp.position = Vector3(0, 0.9, 8.0)
	add_child(ramp)
	var rk := Kit.new()
	rk.box(Transform3D.IDENTITY, Vector3(0, 1.4, 0.15), Vector3(5.6, 2.9, 0.3), rk.col(main, 0.6))
	var rmi := MeshInstance3D.new()
	rmi.mesh = rk.commit()
	rmi.material_override = mat
	ramp.add_child(rmi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.4, 3.2, 17.0)
	cs.shape = box
	cs.position = Vector3(0, 2.4, -0.5)
	add_child(cs)
	global_position = home
	_yaw = atan2(-(lz - home).x, -(lz - home).z)
	rotation.y = _yaw
	wait = randf_range(5.0, 30.0)
	G.add_interactable(self, Vector3(0, 1.5, 9.5), 5.0, "Ride the dropship to the front", _board)


func _board(p: Player) -> void:
	if passenger or not (state == PARKED or state == UNLOAD):
		return
	passenger = p
	p.enter_vehicle(self)
	cam = VehicleCam.new()
	get_tree().root.add_child(cam)
	var ex: Array[RID] = [get_rid()]
	cam.attach(self, 26.0, 5.0, ex)
	if state == PARKED:
		wait = 2.0
	if G.hud:
		G.hud.message("Dropship to the front: the ramp opens at the landing zone")


func exit(p: Player) -> void:
	if passenger != p or not (state == PARKED or state == UNLOAD):
		if G.hud and passenger == p:
			G.hud.message("Wait until the ramp is down")
		return
	_drop_passenger()


func _drop_passenger() -> void:
	if passenger == null:
		return
	var out := global_transform * Vector3(0, 0.5, 13.0)
	out.y = G.world.ground_at(out.x, out.z) + 0.3
	passenger.exit_vehicle(out)
	passenger = null
	if cam:
		cam.queue_free()
		cam = null


func hud_text() -> String:
	return "DROPSHIP  %s" % ["ON THE PAD", "LIFTING", "EN ROUTE TO THE FRONT", "LANDING", "RAMP DOWN", "LIFTING", "RETURNING", "LANDING"][state]


func _physics_process(delta: float) -> void:
	t += delta
	var p := global_position
	var ground := G.world.ground_at(p.x, p.z)
	var target_vel := Vector3.ZERO
	match state:
		PARKED:
			wait -= delta
			_ramp(1.0, delta)
			if wait <= 0.0:
				state = LIFT
		LIFT, RETURN_LIFT:
			_ramp(0.0, delta)
			target_vel = Vector3(0, 9.0, 0)
			if p.y > ground + 45.0:
				state = CRUISE if state == LIFT else RETURN
		CRUISE, RETURN:
			var goal := lz if state == CRUISE else home
			var to := goal - p
			to.y = 0.0
			var d := to.length()
			var alt := maxf(ground + cruise_alt * 0.5, _max_ahead(p, to.normalized())) + 40.0
			var speed := clampf(d * 0.25, 8.0, 55.0)
			target_vel = to.normalized() * speed
			target_vel.y = clampf(alt - p.y, -8.0, 8.0)
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-delta * 0.8))
			if d < 25.0:
				state = DESCEND if state == CRUISE else RETURN_DESCEND
		DESCEND, RETURN_DESCEND:
			var goal := lz if state == DESCEND else home
			var gy := G.world.ground_at(goal.x, goal.z) if state == DESCEND else goal.y
			var to := goal - p
			to.y = 0.0
			target_vel = to * 0.5
			target_vel.y = clampf((gy - p.y) * 0.5, -7.0, -0.6)
			if p.y - gy < 0.3:
				global_position.y = gy
				vel = Vector3.ZERO
				if state == DESCEND:
					state = UNLOAD
					wait = 9.0
					_unload()
				else:
					state = PARKED
					wait = randf_range(40.0, 90.0)
				return
		UNLOAD:
			_ramp(1.0, delta)
			wait -= delta
			if wait < 6.0 and passenger:
				_drop_passenger()
			if wait <= 0.0:
				state = RETURN_LIFT
	vel = vel.lerp(target_vel, 1.0 - exp(-delta * 1.2))
	global_position = p + vel * delta
	var bank := clampf(-vel.dot(global_transform.basis.x) * 0.01, -0.25, 0.25)
	var pitch := clampf(vel.dot(-global_transform.basis.z) * -0.004, -0.2, 0.2)
	rotation = Vector3(pitch, _yaw, bank)
	for f in fans:
		f.rotation.x = clampf(-vel.dot(-global_transform.basis.z) * 0.012, -1.2, 0.0)


func _max_ahead(p: Vector3, dir: Vector3) -> float:
	var m := -1e9
	for k in 6:
		var q := p + dir * (k * 120.0)
		m = maxf(m, G.world.ground_at(q.x, q.z))
	return m


func _ramp(open: float, delta: float) -> void:
	ramp.rotation.x = move_toward(ramp.rotation.x, open * 1.25, delta * 0.8)


func _unload() -> void:
	if G.battle == null or G.battle.army == null:
		return
	var out := global_transform * Vector3(0, 0, 16.0)
	var obj: Vector3 = G.battle._pick_objective(faction)
	G.battle._new_squad(faction, Vector3(out.x, 0, out.z), obj, 40.0)
	squad_count += 1


func damage(amount: float, _at: Vector3) -> void:
	hp -= amount
	if hp <= 0.0 and G.combat:
		G.combat.destroy_vehicle(self)
