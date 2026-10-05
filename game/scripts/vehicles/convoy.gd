class_name Convoy
extends Node3D
## A column of trucks driving a road polyline (kinematic: distance along the road, height from the road
## profile, heading from its tangent), turning around at each end after a pause. Capital trucks: white cabs,
## grey canvas; Cinder trucks: olive cabs, rust tarps. Each truck carries an AnimatableBody3D so the player can
## climb on the cargo bed and ride; collision is only enabled near the player.

var faction := 0
var pts := PackedVector3Array()
var cum := PackedFloat32Array()
var total := 0.0
var s := 0.0
var dir := 1.0
var speed := 13.0
var spacing := 26.0
var trucks: Array[AnimatableBody3D] = []
var wheels: Array = []
var pause := 0.0
var mat: Material
var hp: Array = []


func build(f: int, m: Material, road_pts: PackedVector3Array, count: int) -> void:
	faction = f
	mat = m
	pts = road_pts
	cum.resize(pts.size())
	cum[0] = 0.0
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	total = cum[cum.size() - 1]
	s = randf_range(0.2, 0.8) * total
	for i in count:
		var t := _truck(i)
		trucks.append(t)
		hp.append(500.0)
	_place()


func _truck(i: int) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.collision_layer = 4
	b.collision_mask = 0
	add_child(b)
	var main := Kit.STONE if faction == 0 else Kit.OLIVE
	var canvas := Kit.TRIM if faction == 0 else Kit.RUST
	var k := Kit.new()
	k.box(Transform3D.IDENTITY, Vector3(0, 1.25, 0.6), Vector3(2.4, 0.35, 8.4), k.col(Kit.METAL, 0.3))
	var cab := PackedVector2Array([Vector2(-3.6, 1.4), Vector2(-3.6, 2.4), Vector2(-3.0, 3.2), Vector2(-1.6, 3.2), Vector2(-1.6, 1.4)])
	var xf := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(-1.2, 0, 0))
	k.prism(xf, cab, 0.0, 2.4, k.col(main, 0.4, 2.0, false), true, true, k.col(main, 0.4, 2.0, false))
	k.box(Transform3D.IDENTITY, Vector3(0, 2.75, -3.12), Vector3(2.2, 0.55, 0.06), k.col(Kit.DARKGLASS, 0.4, 1.0, false))
	# Cargo bed with a canvas cover over hoops (rear half open so it can be boarded).
	k.box(Transform3D.IDENTITY, Vector3(0, 1.6, 1.5), Vector3(2.5, 0.3, 6.0), k.col(main, 0.4))
	for sd in [-1.0, 1.0]:
		k.box(Transform3D.IDENTITY, Vector3(sd * 1.22, 2.0, 1.5), Vector3(0.08, 0.6, 6.0), k.col(main, 0.4))
	var arch := PackedVector2Array()
	for a in 9:
		var ang := PI * a / 8.0
		arch.append(Vector2(cos(ang) * 1.25, sin(ang) * 1.1))
	var cxf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 2.3, 2.6))
	k.prism(cxf, arch, 0.0, 3.6, k.col(canvas, 0.5, 2.0, false), true, true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.visibility_range_end = 3000.0
	b.add_child(mi)
	var ws := []
	for z in [-2.6, 1.2, 3.2]:
		for sd in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(sd * 1.15, 0.55, z)
			b.add_child(w)
			var wk := Kit.new()
			wk.tube(Vector3(-0.22, 0, 0), Vector3(0.22, 0, 0), 0.55, 10, wk.col(Kit.METAL, 0.1), true)
			wk.box(Transform3D.IDENTITY, Vector3(0, 0.3, 0), Vector3(0.46, 0.1, 0.12), wk.col(main, 0.1))
			var wmi := MeshInstance3D.new()
			wmi.mesh = wk.commit()
			wmi.material_override = mat
			wmi.visibility_range_end = 800.0
			w.add_child(wmi)
			ws.append(w)
	wheels.append(ws)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 1.8, 8.4)
	cs.shape = box
	cs.position = Vector3(0, 0.95, 0.6)
	cs.disabled = true
	cs.name = "Col"
	b.add_child(cs)
	if i == 0:
		Sfx.attach_loop(b, "loop_truck", -4.0)
	# A bound method, not a lambda: a lambda kept in G's static registry outlived its script at exit and
	# corrupted the heap (glibc abort, exit 134, CI run 9).
	G.add_interactable(b, Vector3(0, 1.8, 4.5), 3.5, "Climb into the truck bed", _board.bind(b))
	return b


func _board(p: Player, b: AnimatableBody3D) -> void:
	p.global_position = b.global_transform * Vector3(0, 2.0, 2.5)


func _at(d: float) -> Array:
	d = clampf(d, 0.0, total)
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] < d:
			lo = mid
		else:
			hi = mid
	var t := (d - cum[lo]) / maxf(cum[hi] - cum[lo], 0.001)
	var p := pts[lo].lerp(pts[hi], t)
	var tan := (pts[hi] - pts[lo]).normalized()
	return [p, tan]


func _place() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cp := cam.global_position if cam else Vector3(1e9, 0, 0)
	for i in trucks.size():
		var d := s - dir * i * spacing
		var r := _at(d)
		var p: Vector3 = r[0]
		var tan: Vector3 = r[1] * dir
		var yaw := atan2(-tan.x, -tan.z)
		var pitch := asin(clampf(tan.y, -1.0, 1.0))
		var b := trucks[i]
		b.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), p + Vector3(0, 0.12, 0))
		var near := p.distance_squared_to(cp) < 250.0 * 250.0
		(b.get_node("Col") as CollisionShape3D).disabled = not near


func _physics_process(delta: float) -> void:
	if pause > 0.0:
		pause -= delta
		return
	s += dir * speed * delta
	if (dir > 0 and s >= total) or (dir < 0 and s <= 0.0):
		# Turn around: the tail truck becomes the lead and the column drives back.
		s = clampf(s, 0.0, total)
		var tail := s - dir * (trucks.size() - 1) * spacing
		trucks.reverse()
		wheels.reverse()
		hp.reverse()
		dir = -dir
		s = tail
		pause = 25.0
	_place()
	for ws in wheels:
		for w in ws:
			(w as Node3D).rotation.x -= speed * delta / 0.55
