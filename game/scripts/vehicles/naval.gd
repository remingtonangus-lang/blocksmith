class_name NavalShip
extends AnimatableBody3D
## Warships at sea (kinematic, riding the swell): the Capital destroyer (150 m, white, two twin turrets forward
## and one aft, a stepped superstructure with a glass bridge and a sensor mast) and Cinder gunboats (40 m,
## rusted, one deck gun). They patrol waypoint loops, leave foam wakes and duel when an enemy ship is in range.

var faction := 0
var route: Array[Vector3] = []
var route_i := 0
var speed := 0.0
var cruise := 9.0
var yaw := 0.0
var turrets: Array = []          # [node, barrel, muzzle, reload]
var length := 150.0
var hp := 8000.0
var mat: Material
var _t := 0.0
var _wake_t := 0.0


func build(f: int, m: Material, start: Vector3, loop: Array[Vector3]) -> void:
	faction = f
	mat = m
	route = loop
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	if f == 0:
		_destroyer()
	else:
		_gunboat()
	global_position = start
	_t = randf() * 10.0


func _hull(k: Kit, length_: float, beam: float, draft: float, freeboard: float, style: int) -> void:
	# Plan: a pointed bow, parallel midbody, a squared stern.
	var plan := PackedVector2Array([Vector2(0, -length_ * 0.5), Vector2(beam * 0.35, -length_ * 0.36),
		Vector2(beam * 0.5, -length_ * 0.15), Vector2(beam * 0.5, length_ * 0.42), Vector2(beam * 0.42, length_ * 0.5),
		Vector2(-beam * 0.42, length_ * 0.5), Vector2(-beam * 0.5, length_ * 0.42), Vector2(-beam * 0.5, -length_ * 0.15),
		Vector2(-beam * 0.35, -length_ * 0.36)])
	k.prism(Transform3D.IDENTITY, Kit.scaled(plan, 0.86), -draft, 0.0, k.col(Kit.METAL, 0.2, 2.0, false), false, true)
	k.prism(Transform3D.IDENTITY, plan, 0.0, freeboard, k.col(style, 0.4, 2.0, false), true, false, k.col(Kit.CONCRETE if style != Kit.RUST else Kit.OLIVE, 0.4))
	k.band(Transform3D.IDENTITY, plan, freeboard - 0.3, 0.4, 0.15, k.col(Kit.TRIM if style != Kit.RUST else Kit.RUST, 0.4), false)


func _destroyer() -> void:
	length = 150.0
	var k := Kit.new()
	_hull(k, 150.0, 17.0, 5.0, 6.0, Kit.STONE)
	var I := Transform3D.IDENTITY
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 5.0)), Kit.chamfer_rect(13.0, 40.0, 3.0), 0.0, 6.0, k.col(Kit.BANDED, 0.6, 3.0), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 12.0, -2.0)), Kit.chamfer_rect(11.0, 16.0, 3.0), 0.0, 5.0, k.col(Kit.STONE, 0.6, 2.5, false), true)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 17.0, -4.0)), Kit.chamfer_rect(12.0, 6.0, 2.0), 0.0, 3.2, k.col(Kit.GLASS, 0.6, 3.2), true)
	k.tube(Vector3(0, 20.0, 2.0), Vector3(0, 40.0, 2.0), 0.6, 6, k.col(Kit.METAL, 0.6), true)
	k.box(I, Vector3(0, 32.0, 2.0), Vector3(8.0, 0.4, 0.4), k.col(Kit.METAL, 0.6))
	k.sphere(Vector3(0, 41.5, 2.0), 1.8, 6, 10, k.col(Kit.STONE, 0.6))
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 40.0)), Kit.chamfer_rect(10.0, 18.0, 2.5), 0.0, 4.0, k.col(Kit.STONE, 0.6, 2.0, false), true)
	_finish(k, Vector3(0, 0, 0), Vector3(17.0, 12.0, 150.0))
	for z in [-50.0, -32.0, 58.0]:
		_turret(Vector3(0, 6.0, z), 4.0, 7.0, z > 0.0)


func _gunboat() -> void:
	length = 40.0
	cruise = 12.0
	var k := Kit.new()
	_hull(k, 40.0, 7.0, 2.0, 3.0, Kit.RUST)
	k.prism(Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 4.0)), Kit.rect(5.0, 9.0), 0.0, 3.2, k.col(Kit.OLIVE, 0.6, 2.0, false), true, false, k.col(Kit.RUST, 0.6))
	k.box(Transform3D.IDENTITY, Vector3(0, 5.2, 2.2), Vector3(4.4, 0.9, 0.08), k.col(Kit.DARKGLASS, 0.6))
	k.tube(Vector3(0, 6.2, 6.0), Vector3(0, 13.0, 6.0), 0.2, 5, k.col(Kit.METAL, 0.6), true)
	_finish(k, Vector3.ZERO, Vector3(7.0, 6.0, 40.0))
	_turret(Vector3(0, 3.0, -11.0), 1.6, 3.5, false)


func _finish(k: Kit, _c: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.visibility_range_end = 12000.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = Vector3(0, size.y * 0.5 - 2.0, 0)
	add_child(cs)


func _turret(at: Vector3, r: float, barrel: float, aft: bool) -> void:
	var y := Node3D.new()
	y.position = at
	if aft:
		y.rotation.y = PI
	add_child(y)
	var k := Kit.new()
	var house := PackedVector2Array([Vector2(-r * 0.8, -r), Vector2(r * 0.8, -r), Vector2(r, 0.0), Vector2(r * 0.9, r), Vector2(-r * 0.9, r), Vector2(-r, 0.0)])
	k.prism(Transform3D.IDENTITY, house, 0.0, r * 0.6, k.col(Kit.TRIM if faction == 0 else Kit.OLIVE, 0.5, 1.0, false), true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	y.add_child(mi)
	var b := Node3D.new()
	b.position = Vector3(0, r * 0.35, -r * 0.8)
	y.add_child(b)
	var g := Kit.new()
	var n := 2 if faction == 0 else 1
	for i in n:
		var x := (i - (n - 1) * 0.5) * r * 0.45
		g.tube(Vector3(x, 0, 0), Vector3(x, 0, -barrel), r * 0.07, 8, g.col(Kit.METAL, 0.5), true)
	var gmi := MeshInstance3D.new()
	gmi.mesh = g.commit()
	gmi.material_override = mat
	b.add_child(gmi)
	var m := Node3D.new()
	m.position = Vector3(0, 0, -barrel - 0.4)
	b.add_child(m)
	turrets.append([y, b, m, randf() * 8.0])


func _physics_process(delta: float) -> void:
	_t += delta
	var p := global_position
	if route.size() > 0:
		var goal := route[route_i]
		var to := goal - p
		to.y = 0.0
		if to.length() < length * 1.5:
			route_i = (route_i + 1) % route.size()
		yaw += clampf(angle_difference(yaw, atan2(-to.x, -to.z)), -1.0, 1.0) * 0.05 * delta
		speed = move_toward(speed, cruise, delta * 0.5)
	var sea: float = G.world.water.sea_state if G.world and G.world.water else 0.4
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var heave := sin(_t * 0.7) * (0.3 + sea * 0.9) * (40.0 / length)
	var pitch := sin(_t * 0.55 + 1.0) * (0.01 + sea * 0.03) * (60.0 / length)
	var roll := sin(_t * 0.43) * (0.015 + sea * 0.05) * (60.0 / length)
	var np := p + fwd * speed * delta
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll), Vector3(np.x, heave, np.z))
	_wake_t += delta
	if G.fx and _wake_t > 0.12 and _near(1500.0):
		_wake_t = 0.0
		var stern := global_transform * Vector3(randf_range(-length * 0.05, length * 0.05), 0.2, length * 0.48)
		G.fx._emit(G.fx.dust, stern, Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), Color(0.95, 0.97, 1.0, 0.8))
		var bow := global_transform * Vector3(randf_range(-2, 2), 0.3, -length * 0.45)
		G.fx._emit(G.fx.dust, bow, fwd * 2.0 + Vector3(randf_range(-2, 2), 1.0, 0), Color(0.95, 0.97, 1.0, 0.7))


func _near(d: float) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_squared_to(global_position) < d * d


func _process(delta: float) -> void:
	# Engage the nearest enemy ship within 3 km.
	var target: NavalShip = null
	var bd := 3000.0
	for s in get_parent().get_children():
		if s is NavalShip and s.faction != faction and s.hp > 0.0:
			var d := global_position.distance_to(s.global_position)
			if d < bd:
				bd = d
				target = s
	if target == null:
		return
	for t in turrets:
		var y: Node3D = t[0]
		var b: Node3D = t[1]
		t[3] = maxf(0.0, t[3] - delta)
		var local := y.global_transform.affine_inverse() * target.global_position
		var want := atan2(-local.x, -local.z)
		y.rotation.y += clampf(angle_difference(0.0, want), -0.4 * delta, 0.4 * delta)
		b.rotation.x = lerpf(b.rotation.x, clampf(bd / 18000.0, 0.02, 0.5), 1.0 - exp(-delta))
		if absf(want) < 0.06 and t[3] <= 0.0:
			t[3] = 8.0 + randf() * 6.0
			var m: Node3D = t[2]
			var miss := Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
			if G.fx:
				G.fx.flash(m.global_position, 3.0 if faction == 0 else 1.5)
				if G.combat and G.combat.has_method("shell"):
					G.combat.shell(m.global_position, -m.global_transform.basis.z, 420.0, 1.2, faction, [get_rid()])
				else:
					G.fx.explosion(target.global_position + miss, 1.0)


func damage(amount: float, _at: Vector3) -> void:
	hp -= amount
	if hp <= 0.0 and G.combat:
		G.combat.destroy_vehicle(self)
