class_name Crawler
extends RigidBody3D
## Six-wheeled armoured crawler: 9.4 m long, 18 t, raycast suspension on Jolt, all-wheel drive, front and rear
## axles steer (opposite), a turret with a 30 mm autocannon that follows the camera, a flat rear deck to ride on.
## The driver steers Halo-style (the left stick / WASD pushes toward where the camera looks); AI drives along a
## road with pure pursuit. Capital crawlers are white with grey trim, Cinder ones olive and rust.

const WHEEL_R := 0.85
const REST := 0.55
const MASS := 18000.0
const ENGINE := 160000.0
const MAX_SPEED := 24.0
const WHEELS := [Vector3(-1.75, 0.9, -3.2), Vector3(1.75, 0.9, -3.2), Vector3(-1.75, 0.9, 0.0), Vector3(1.75, 0.9, 0.0),
	Vector3(-1.75, 0.9, 3.2), Vector3(1.75, 0.9, 3.2)]

var faction := 0
var driver: Player = null
var cam: VehicleCam
var wheel_nodes: Array[Node3D] = []
var wheel_spin := 0.0
var steer := 0.0
var _prev_comp := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var turret: Node3D
var gun: Node3D
var muzzle: Node3D
var fire_t := 0.0
var lights: Array[SpotLight3D] = []
var path := PackedVector3Array()
var path_i := 0
var ai_speed := 11.0
var hp := 1400.0
var _grounded := 0
var throttle_in := 0.0
var steer_in := 0.0
var brake_in := false
var boost_in := false


func build(f: int, mat: Material) -> void:
	faction = f
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.9, 0)
	linear_damp = 0.05
	angular_damp = 1.2
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	can_sleep = false
	var main := Kit.STONE if f == 0 else Kit.OLIVE
	var trim := Kit.TRIM if f == 0 else Kit.RUST
	var k := Kit.new()
	# Side silhouette (z, y): low bumper, angled glacis, cabin, long flat rear deck.
	var side := PackedVector2Array([Vector2(-4.7, 1.0), Vector2(-4.7, 1.55), Vector2(-3.6, 2.35), Vector2(-1.9, 2.55),
		Vector2(-1.2, 3.25), Vector2(0.8, 3.25), Vector2(1.2, 2.6), Vector2(4.6, 2.6), Vector2(4.7, 2.2), Vector2(4.4, 1.0)])
	# Extrude the silhouette across the width: map profile (x=z_world, y=y_world) with the prism axis along +x.
	var xf := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(-1.55, 0, 0))
	k.prism(xf, side, 0.0, 3.1, k.col(main, 0.3, 2.0, false), true, true, k.col(main, 0.3, 2.0, false))
	# Fenders over the wheels, a trim stripe, windows, lights.
	for w in WHEELS:
		k.box(Transform3D.IDENTITY, Vector3(w.x * 1.02, 1.95, w.z), Vector3(0.55, 0.18, 2.3), k.col(trim, 0.3))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.0, 0.3), Vector3(3.16, 0.14, 8.4), k.col(trim, 0.3))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.92, -1.25), Vector3(2.7, 0.42, 0.06), k.col(Kit.DARKGLASS, 0.3, 1.0, false))
	for s in [-1.0, 1.0]:
		k.box(Transform3D.IDENTITY, Vector3(s * 1.56, 2.9, -0.2), Vector3(0.06, 0.38, 1.6), k.col(Kit.DARKGLASS, 0.3, 1.0, false))
		k.box(Transform3D.IDENTITY, Vector3(s * 1.2, 1.6, -4.66), Vector3(0.5, 0.18, 0.08), k.col(Kit.PAD, 0.9, 1.0, true))
	# Deck rails and a stowage box on the rear deck.
	for s in [-1.0, 1.0]:
		k.box(Transform3D.IDENTITY, Vector3(s * 1.45, 2.95, 3.0), Vector3(0.08, 0.7, 2.8), k.col(Kit.METAL, 0.3))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.85, 4.2), Vector3(2.4, 0.5, 0.6), k.col(trim, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	add_child(mi)
	# Collision: hull and cabin.
	var cs := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(3.1, 1.55, 9.2)
	cs.shape = hull
	cs.position = Vector3(0, 1.8, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cab := BoxShape3D.new()
	cab.size = Vector3(3.0, 0.7, 2.2)
	cs2.shape = cab
	cs2.position = Vector3(0, 2.9, -0.2)
	add_child(cs2)
	# Wheels.
	for w in WHEELS:
		var wn := Node3D.new()
		wn.position = w
		add_child(wn)
		var spin := Node3D.new()
		wn.add_child(spin)
		var wk := Kit.new()
		wk.tube(Vector3(-0.32, 0, 0), Vector3(0.32, 0, 0), WHEEL_R, 14, wk.col(Kit.METAL, 0.1), true)
		wk.tube(Vector3(-0.34, 0, 0), Vector3(0.34, 0, 0), 0.42, 8, wk.col(trim, 0.1), true)
		for t in 7:
			var a := TAU * t / 7.0
			wk.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO), Vector3(0, WHEEL_R - 0.05, 0), Vector3(0.66, 0.12, 0.3), wk.col(Kit.METAL, 0.2))
		var wmi := MeshInstance3D.new()
		wmi.mesh = wk.commit()
		wmi.material_override = mat
		spin.add_child(wmi)
		wheel_nodes.append(wn)
	# Turret with a 30 mm autocannon.
	turret = Node3D.new()
	turret.position = Vector3(0, 3.25, 0.0)
	add_child(turret)
	var tk := Kit.new()
	tk.prism(Transform3D.IDENTITY, Kit.ngon(1.0, 8, PI / 8.0), 0.0, 0.55, tk.col(main, 0.4, 2.0, false), true)
	tk.box(Transform3D.IDENTITY, Vector3(0.6, 0.75, 0.2), Vector3(0.5, 0.4, 0.6), tk.col(Kit.DARKGLASS, 0.4))
	var tmi := MeshInstance3D.new()
	tmi.mesh = tk.commit()
	tmi.material_override = mat
	turret.add_child(tmi)
	gun = Node3D.new()
	gun.position = Vector3(0, 0.38, -0.5)
	turret.add_child(gun)
	var gk := Kit.new()
	gk.box(Transform3D.IDENTITY, Vector3(0, 0, 0.1), Vector3(0.5, 0.42, 0.9), gk.col(trim, 0.4))
	gk.tube(Vector3(0, 0, -0.3), Vector3(0, 0, -2.6), 0.07, 8, gk.col(Kit.METAL, 0.4), true)
	gk.tube(Vector3(0, 0, -2.4), Vector3(0, 0, -2.75), 0.11, 8, gk.col(Kit.METAL, 0.4), true)
	var gmi := MeshInstance3D.new()
	gmi.mesh = gk.commit()
	gmi.material_override = mat
	gun.add_child(gmi)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -2.85)
	gun.add_child(muzzle)
	for s in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(s * 1.2, 1.6, -4.8)
		l.rotation.x = -0.08
		l.spot_range = 70.0
		l.spot_angle = 28.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 250.0
		l.distance_fade_length = 50.0
		add_child(l)
		lights.append(l)
	G.add_interactable(self, Vector3(-1.9, 1.6, -0.8), 4.0, "Drive the crawler", enter)
	G.add_interactable(self, Vector3(0, 2.7, 3.2), 3.5, "Climb onto the deck", _climb)


func _climb(p: Player) -> void:
	p.global_position = global_transform * Vector3(0, 3.0, 3.0)
	p.velocity = linear_velocity


func enter(p: Player) -> void:
	if driver:
		return
	driver = p
	p.enter_vehicle(self)
	cam = VehicleCam.new()
	get_tree().root.add_child(cam)
	var ex: Array[RID] = [get_rid()]
	cam.attach(self, 15.0, 3.6, ex)
	path = PackedVector3Array()
	if G.hud:
		G.hud.message("Crawler: stick / WASD toward the camera to drive, RT / LMB fires the 30 mm, A / Space brakes")


func exit(p: Player) -> void:
	if driver != p:
		return
	driver = null
	var out := global_transform * Vector3(-3.4, 1.0, -0.8)
	out.y = maxf(out.y, G.world.ground_at(out.x, out.z) + 0.2)
	p.exit_vehicle(out)
	if cam:
		cam.queue_free()
		cam = null


func hud_text() -> String:
	var v := linear_velocity.length() * 3.6
	return "CRAWLER  %3d km/h\n30 MM  %s" % [int(v), "READY" if fire_t <= 0.0 else "..."]


func _process(delta: float) -> void:
	var fwd_speed := -linear_velocity.dot(global_transform.basis.z)
	wheel_spin += fwd_speed / WHEEL_R * delta
	for i in wheel_nodes.size():
		var wn := wheel_nodes[i]
		var st := steer if i < 2 else (-steer * 0.5 if i > 3 else 0.0)
		wn.rotation.y = st
		(wn.get_child(0) as Node3D).rotation.x = -wheel_spin
	var night := 1.0 - (G.sky.daylight if G.sky else 1.0)
	for l in lights:
		l.light_energy = 6.0 * night if driver or path.size() > 0 else 0.0
	fire_t = maxf(0.0, fire_t - delta)
	if driver and cam:
		_aim_turret(cam.aim_point([get_rid()]), delta)
		if Input.is_action_pressed("fire") or Controls.trigger(true) > 0.4:
			_fire()


func _aim_turret(p: Vector3, delta: float) -> void:
	var local := turret.global_transform.affine_inverse() * p
	var want_yaw := atan2(-local.x, -local.z)
	turret.rotation.y += clampf(angle_difference(0.0, want_yaw), -1.6 * delta, 1.6 * delta)
	var g := gun.global_transform.affine_inverse() * p
	var want_pitch := atan2(g.y, -g.z)
	gun.rotation.x = clampf(gun.rotation.x + clampf(want_pitch, -1.0 * delta, 1.0 * delta), deg_to_rad(-10.0), deg_to_rad(55.0))


func _fire() -> void:
	if fire_t > 0.0:
		return
	fire_t = 0.24
	var o := muzzle.global_position
	var dir := -muzzle.global_transform.basis.z
	if G.combat and G.combat.has_method("cannon_round"):
		G.combat.cannon_round(o, dir, 900.0, faction, [get_rid()])
	elif G.fx:
		G.fx.flash(o, 1.2)
	apply_impulse(-dir * 1800.0, muzzle.global_position - global_position)
	if driver:
		Controls.rumble(0.3, 0.5, 0.08)


func _physics_process(delta: float) -> void:
	# Inputs: the player (Halo-style relative to the camera) or the AI on its path.
	var throttle := 0.0
	var steer_target := 0.0
	var brake := false
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	if driver and cam:
		var mv := Controls.move_vector()
		brake = Input.is_action_pressed("brake")
		if mv.length() > 0.1:
			var cam_fwd := cam.aim_dir()
			cam_fwd.y = 0.0
			cam_fwd = cam_fwd.normalized()
			var cam_right := Vector3(-cam_fwd.z, 0, cam_fwd.x)
			var want := (cam_fwd * mv.y + cam_right * mv.x).normalized()
			var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
			var ang := flat_fwd.signed_angle_to(want, Vector3.UP)
			if absf(ang) > deg_to_rad(115.0):
				throttle = -mv.length()
				ang = angle_difference(PI, ang) * -1.0
				steer_target = clampf(-ang * 1.4, -0.55, 0.55)
			else:
				throttle = mv.length()
				steer_target = clampf(ang * 1.4, -0.55, 0.55)
		if Input.is_action_pressed("boost"):
			throttle *= 1.35
	elif path.size() > 1:
		var r := _pursuit()
		throttle = r.x
		steer_target = r.y
	steer = move_toward(steer, steer_target, delta * 1.2)
	# Suspension, drive and grip per wheel.
	var space := get_world_3d().direct_space_state
	var per := mass / 6.0
	var k := per * 9.81 / 0.25
	var c := 2.0 * sqrt(k * per) * 0.45
	_grounded = 0
	for i in WHEELS.size():
		var mount: Vector3 = global_transform * (WHEELS[i] + Vector3(0, REST, 0))
		var down := -global_transform.basis.y
		var q := PhysicsRayQueryParameters3D.create(mount, mount + down * (REST + WHEEL_R + 0.3))
		q.exclude = [get_rid()]
		q.collision_mask = 1 | 4
		var hit := space.intersect_ray(q)
		var dist := REST + WHEEL_R + 0.3
		var nrm := Vector3.UP
		if not hit.is_empty():
			dist = mount.distance_to(hit["position"])
			nrm = hit["normal"]
		var comp := (REST + WHEEL_R) - dist
		var wn := wheel_nodes[i]
		wn.position.y = WHEELS[i].y + REST - clampf(dist - WHEEL_R, 0.0, REST + 0.3) + REST * 0.0
		if comp <= 0.0:
			_prev_comp[i] = 0.0
			continue
		_grounded += 1
		var dc := (comp - _prev_comp[i]) / delta
		_prev_comp[i] = comp
		var fz := maxf(0.0, k * comp + c * dc)
		var at := (hit["position"] as Vector3) - global_position
		apply_force(nrm * fz, at)
		var st := steer if i < 2 else (-steer * 0.5 if i > 3 else 0.0)
		var wfwd := fwd.rotated(global_transform.basis.y, st)
		wfwd = (wfwd - nrm * wfwd.dot(nrm)).normalized()
		var wright := nrm.cross(wfwd).normalized() * -1.0
		var vel := linear_velocity + angular_velocity.cross(at)
		var lat := vel.dot(wright)
		var lon := vel.dot(wfwd)
		var grip := minf(fz * 1.1, absf(lat) * per * 4.0)
		apply_force(-wright * signf(lat) * grip, at)
		var speed := -linear_velocity.dot(global_transform.basis.z)
		var drive := 0.0
		if absf(speed) < MAX_SPEED * (1.35 if Input.is_action_pressed("boost") and driver else 1.0):
			drive = throttle * ENGINE / 6.0
		if brake or (absf(throttle) < 0.05):
			drive = -signf(lon) * minf(absf(lon) * per * 1.2, fz * (0.9 if brake else 0.12))
		apply_force(wfwd * drive, at)
	# Keep it upright-ish in the air.
	if _grounded == 0:
		apply_torque(global_transform.basis.y.cross(Vector3.UP) * mass * 6.0)


## Pure pursuit along `path`: returns (throttle, steer).
func _pursuit() -> Vector2:
	var p := global_position
	while path_i < path.size() - 1 and p.distance_to(path[path_i]) < 22.0:
		path_i += 1
	if path_i >= path.size() - 1 and p.distance_to(path[path.size() - 1]) < 12.0:
		return Vector2(0, 0)
	var t := path[path_i]
	var fwd := -global_transform.basis.z
	var to := t - p
	to.y = 0.0
	var ang := Vector3(fwd.x, 0, fwd.z).normalized().signed_angle_to(to.normalized(), Vector3.UP)
	var speed := -linear_velocity.dot(global_transform.basis.z)
	var want := ai_speed * clampf(1.0 - absf(ang) * 0.8, 0.35, 1.0)
	return Vector2(clampf((want - speed) * 0.25, -0.6, 1.0), clampf(ang * 1.3, -0.5, 0.5))


func follow(points: PackedVector3Array) -> void:
	path = points
	path_i = 0


func damage(amount: float, at: Vector3) -> void:
	hp -= amount
	if hp <= 0.0 and G.combat and G.combat.has_method("destroy_vehicle"):
		G.combat.destroy_vehicle(self)
