extends Node3D
## The Meridian & Western express for chapter 5: a 4-4-0 locomotive, tender, express car, coach and caboose built
## procedurally (boxes and cylinders, two LODs per car: full detail to 260 m, a painted shell to 2.5 km), running
## along the worldgen railroad (`features.rail`) with its own track laid for the stretch the mission uses (rails +
## a MultiMesh of ties). Kinematic and robust: cars are placed on the path each physics tick by distance along it,
## each car carries an AnimatableBody3D box so bullets and horses meet it. Speed eases toward `target_speed`;
## `slow_zones` [{s, r, v}] cap it (water stops); `brake()` stops it.

const CARS := [
	{"kind": "loco", "len": 10.5, "w": 2.6, "h": 4.2},
	{"kind": "tender", "len": 7.0, "w": 2.7, "h": 2.8},
	{"kind": "express", "len": 13.0, "w": 2.9, "h": 3.9},
	{"kind": "coach", "len": 14.0, "w": 2.9, "h": 3.9},
	{"kind": "caboose", "len": 9.0, "w": 2.7, "h": 4.1},
]
const GAP := 1.0

var pts := PackedVector3Array()     # densified path (direction of travel), ground height
var cum := PackedFloat32Array()     # distance along the path at each point
var s := 0.0                        # front of the locomotive, metres along the path
var speed := 0.0
var target_speed := 11.0
var accel := 0.9
var slow_zones: Array = []
var braking := false
var cars: Array = []                # {node, body, len, offset}
var car_specs: Array = CARS         # set before setup() for other vehicles (a road locomobile is one "carriage")
var smoke: CPUParticles3D
var track: Node3D

## from_end: run the rail from its last point (Port Linden) toward the first (west).
func setup(rail: Array, from_end := true, with_cars := true) -> void:
	name = "MeridianExpress"
	var raw: Array = rail.duplicate()
	if from_end:
		raw.reverse()
	var w: WorldData = Game.world
	var prev := Vector3.INF
	for p in raw:
		var v := Vector3(float(p[0]), 0.0, float(p[1]))
		if prev != Vector3.INF:
			var n := int(ceil(prev.distance_to(v) / 4.0))
			for k in range(1, n):
				var q := prev.lerp(v, float(k) / n)
				_push(Vector3(q.x, w.height(q.x, q.z), q.z))
		_push(Vector3(v.x, w.height(v.x, v.z), v.z))
		prev = v
	# smooth the grade a little so cars don't pitch on every terrain bump
	var sm := pts.duplicate()
	for i in range(2, pts.size() - 2):
		sm[i].y = (pts[i - 2].y + pts[i - 1].y + pts[i].y + pts[i + 1].y + pts[i + 2].y) / 5.0
	pts = sm
	if not with_cars:
		return
	var off := 0.0
	for c in car_specs:
		var car := _build_car(c)
		cars.append({"node": car.node, "body": car.body, "len": float(c.len), "offset": off + float(c.len) * 0.5, "kind": c.kind})
		off += float(c.len) + GAP

func _push(v: Vector3) -> void:
	if pts.is_empty():
		cum.append(0.0)
	else:
		cum.append(cum[cum.size() - 1] + Vector2(v.x - pts[pts.size() - 1].x, v.z - pts[pts.size() - 1].z).length())
	pts.append(v)

func length() -> float:
	return cum[cum.size() - 1] if cum.size() > 0 else 0.0

## Point on the path at distance d (clamped).
func at(d: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	d = clampf(d, 0.0, length())
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] < d:
			lo = mid
		else:
			hi = mid
	var f := (d - cum[lo]) / maxf(cum[hi] - cum[lo], 0.001)
	return pts[lo].lerp(pts[hi], f)

## Distance along the path of the point nearest to p (coarse search, then refine).
func nearest_s(p: Vector3) -> float:
	var best := 0
	var bd := INF
	for i in range(0, pts.size(), 8):
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	for i in range(maxi(best - 8, 0), mini(best + 9, pts.size())):
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return cum[best]

func car_center(i: int) -> Vector3:
	return at(s - float(cars[i].offset))

func car_index(kind: String) -> int:
	for i in cars.size():
		if cars[i].kind == kind:
			return i
	return 0

## Unit vector along the direction of travel at distance d.
func tangent(d: float) -> Vector3:
	var a := at(d - 2.0)
	var b := at(d + 2.0)
	var t := Vector3(b.x - a.x, 0, b.z - a.z)
	return t.normalized() if t.length() > 0.01 else Vector3(1, 0, 0)

func brake() -> void:
	braking = true

func _physics_process(dt: float) -> void:
	if pts.size() < 2:
		return
	var want := 0.0 if braking else target_speed
	for z in slow_zones:
		if absf(s - float(z.s)) < float(z.r):
			want = minf(want, float(z.v))
	var a := accel * (2.2 if want < speed else 1.0)
	speed = move_toward(speed, want, a * dt)
	s = minf(s + speed * dt, length())
	_place()
	# solid when stopped (cover, a platform to stand by); ghosted while rolling so a horse alongside can't clip it
	for c in cars:
		if c.body:
			c.body.collision_layer = 1 if speed < 0.5 else 0
	if smoke:
		smoke.emitting = speed > 0.5 or not braking
		smoke.amount_ratio = clampf(0.3 + speed / 12.0, 0.3, 1.0)

func _place() -> void:
	for c in cars:
		var mid := s - float(c.offset)
		var f := at(mid + float(c.len) * 0.4)
		var b := at(mid - float(c.len) * 0.4)
		var center := (f + b) * 0.5
		var fwd := f - b
		if fwd.length() < 0.01:
			continue
		var xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), center)
		c.node.global_transform = xf
		if c.body:
			c.body.global_transform = xf

## Put the whole train at a distance along the path (front of the engine there), at a speed.
func place_at(d: float, v: float) -> void:
	s = d
	speed = v
	_place()

# ------------------------------------------------------------------ the kit
func _mat(col: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.45 if metal else 0.85
	m.metallic = 0.6 if metal else 0.0
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, vis_end := 260.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = vis_end
	parent.add_child(mi)

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, mat: Material, vis_end := 260.0) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.visibility_range_end = vis_end
	parent.add_child(mi)

## One car: detail meshes (-Z is forward), a far shell, and a kinematic box body.
func _build_car(c: Dictionary) -> Dictionary:
	var node := Node3D.new()
	node.name = str(c.kind).capitalize()
	add_child(node)
	var L: float = c.len
	var W: float = c.w
	var H: float = c.h
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H - 0.6, L)
	cs.shape = bs
	cs.position = Vector3(0, 0.6 + (H - 0.6) * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	if Game.headless:
		return {"node": node, "body": body}
	var black := _mat(Color(0.08, 0.08, 0.09), true)
	var iron := _mat(Color(0.2, 0.2, 0.22), true)
	var brass := _mat(Color(0.75, 0.6, 0.3), true)
	var red := _mat(Color(0.48, 0.12, 0.09))
	var green := _mat(Color(0.18, 0.28, 0.2))
	var yellow := _mat(Color(0.7, 0.55, 0.25))
	var roofm := _mat(Color(0.22, 0.2, 0.19))
	# wheels and frame for every car
	var wheel_z: Array = [-L * 0.36, -L * 0.24, L * 0.24, L * 0.36]
	if c.kind == "loco":
		wheel_z = [-L * 0.42, -L * 0.3, L * 0.05, L * 0.3]
	var road: bool = c.kind == "carriage" or c.kind == "wagon" or c.kind == "stagecoach"
	if road:
		wheel_z = [-L * 0.34, L * 0.34]
	for wz in wheel_z:
		for sx in [-1.0, 1.0]:
			var r := 0.85 if (c.kind == "loco" and float(wz) > -L * 0.2) else 0.45
			if road:
				r = 0.42 if float(wz) < 0.0 else 0.62
			_cyl(node, r, 0.12, Vector3(sx * 0.75, r, wz), Vector3(0, 0, PI * 0.5), iron)
	_box(node, Vector3(W * 0.8, 0.3, L), Vector3(0, 0.95, 0), black)
	match c.kind:
		"loco":
			_cyl(node, 0.85, L * 0.6, Vector3(0, 2.05, -L * 0.12), Vector3(PI * 0.5, 0, 0), black)          # boiler
			_cyl(node, 0.3, 1.3, Vector3(0, 3.3, -L * 0.36), Vector3.ZERO, black)                            # stack
			_cyl(node, 0.5, 0.4, Vector3(0, 3.9, -L * 0.36), Vector3.ZERO, black)
			_cyl(node, 0.32, 0.5, Vector3(0, 3.05, -L * 0.05), Vector3.ZERO, brass)                          # dome
			_box(node, Vector3(W, 2.4, 3.0), Vector3(0, 2.5, L * 0.32), red)                                 # cab
			_box(node, Vector3(W + 0.3, 0.15, 3.4), Vector3(0, 3.75, L * 0.32), roofm)
			_box(node, Vector3(1.8, 0.9, 1.2), Vector3(0, 0.9, -L * 0.5), iron)                              # pilot
			_cyl(node, 0.22, 0.35, Vector3(0, 2.7, -L * 0.46), Vector3(PI * 0.5, 0, 0), brass)              # headlamp
			smoke = CPUParticles3D.new()
			smoke.amount = 60
			smoke.lifetime = 3.0
			smoke.direction = Vector3(0, 1, 0.3)
			smoke.spread = 18.0
			smoke.initial_velocity_min = 2.0
			smoke.initial_velocity_max = 4.0
			smoke.gravity = Vector3(0, 0.4, 0)
			smoke.scale_amount_min = 0.8
			smoke.scale_amount_max = 2.4
			var q := QuadMesh.new()
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm.albedo_color = Color(0.25, 0.24, 0.24, 0.45)
			q.material = sm
			smoke.mesh = q
			smoke.position = Vector3(0, 4.2, -L * 0.36)
			smoke.local_coords = false
			node.add_child(smoke)
		"carriage":
			# a steam road-carriage: buggy body, upright boiler behind the seat, tall stack, brass trim
			_box(node, Vector3(W, 0.6, L * 0.7), Vector3(0, 1.3, -L * 0.1), red)
			_box(node, Vector3(W * 0.9, 0.5, 0.5), Vector3(0, 1.8, -L * 0.05), _mat(Color(0.15, 0.1, 0.08)))
			_cyl(node, 0.42, 1.2, Vector3(0, 1.9, L * 0.32), Vector3.ZERO, black)
			_cyl(node, 0.1, 1.4, Vector3(0, 3.1, L * 0.32), Vector3.ZERO, brass)
			smoke = CPUParticles3D.new()
			smoke.amount = 30
			smoke.lifetime = 2.0
			smoke.direction = Vector3(0, 1, 0.2)
			smoke.spread = 15.0
			smoke.initial_velocity_min = 1.0
			smoke.initial_velocity_max = 2.0
			smoke.scale_amount_min = 0.4
			smoke.scale_amount_max = 1.2
			var q2 := QuadMesh.new()
			var sm2 := StandardMaterial3D.new()
			sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm2.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm2.albedo_color = Color(0.85, 0.85, 0.85, 0.4)
			q2.material = sm2
			smoke.mesh = q2
			smoke.position = Vector3(0, 3.8, L * 0.32)
			smoke.local_coords = false
			node.add_child(smoke)
		"wagon":
			# a farm wagon and its team: plank bed, a canvas bow top, two horses and the tongue between them
			var plank := _mat(Color(0.42, 0.3, 0.18))
			var canvas := _mat(Color(0.86, 0.83, 0.74))
			var bay := _mat(Color(0.33, 0.2, 0.12))
			_box(node, Vector3(W, 0.7, L * 0.9), Vector3(0, 1.45, 0), plank)
			_box(node, Vector3(W * 1.02, 1.3, L * 0.7), Vector3(0, 2.4, L * 0.05), canvas)
			_box(node, Vector3(W * 0.8, 0.12, 0.5), Vector3(0, 1.95, -L * 0.42), plank)                  # seat
			_box(node, Vector3(0.12, 0.12, 3.2), Vector3(0, 0.9, -L * 0.5 - 1.6), plank)                 # tongue
			for sx in [-0.65, 0.65]:
				_box(node, Vector3(0.55, 0.75, 2.0), Vector3(sx, 1.45, -L * 0.5 - 2.4), bay)              # barrel
				_box(node, Vector3(0.3, 0.75, 0.6), Vector3(sx, 2.0, -L * 0.5 - 3.5), bay)                # neck
				_box(node, Vector3(0.24, 0.3, 0.6), Vector3(sx, 2.25, -L * 0.5 - 3.95), bay)              # head
				for lz in [-1.5, -3.2]:
					_box(node, Vector3(0.14, 1.1, 0.14), Vector3(sx, 0.55, -L * 0.5 + lz), bay)           # legs
		"stagecoach":
			# a Sable Valley Stage Line coach: lacquered body slung between the axles, driver's box up front, a rail
			# of luggage on the roof, the leather boot behind, and a four-horse team on the pole
			var lacquer := _mat(Color(0.36, 0.1, 0.08))
			var trim := _mat(Color(0.72, 0.55, 0.22))
			var leather := _mat(Color(0.22, 0.14, 0.09))
			var team := [_mat(Color(0.33, 0.2, 0.12)), _mat(Color(0.18, 0.12, 0.08))]
			_box(node, Vector3(W, 1.55, L * 0.5), Vector3(0, 2.05, L * 0.02), lacquer)                     # body
			_box(node, Vector3(W + 0.06, 0.08, L * 0.52), Vector3(0, 1.3, L * 0.02), trim)                  # sill
			_box(node, Vector3(W + 0.1, 0.1, L * 0.54), Vector3(0, 2.86, L * 0.02), roofm)                 # roof
			for sx in [-1.0, 1.0]:
				_box(node, Vector3(0.04, 0.6, 0.7), Vector3(sx * (W * 0.5 + 0.02), 2.3, L * 0.02), _mat(Color(0.1, 0.09, 0.08)))   # windows
			_box(node, Vector3(W * 0.8, 0.45, 0.9), Vector3(0, 3.15, L * 0.1), leather)          # luggage
			_box(node, Vector3(W * 0.9, 0.5, 0.7), Vector3(0, 2.55, -L * 0.33), lacquer)                   # driver's box
			_box(node, Vector3(W * 0.9, 0.12, 0.5), Vector3(0, 2.85, -L * 0.3), leather)                   # seat
			_box(node, Vector3(W * 0.8, 1.0, 0.6), Vector3(0, 1.9, L * 0.37), leather)                     # boot
			_box(node, Vector3(0.12, 0.12, 5.6), Vector3(0, 0.95, -L * 0.5 - 2.8), leather)                # pole
			for row in 2:
				for sx in [-0.65, 0.65]:
					var bz := -L * 0.5 - 2.2 - float(row) * 2.6
					var hm: StandardMaterial3D = team[(row + int(sx > 0.0)) % 2]
					_box(node, Vector3(0.55, 0.75, 2.0), Vector3(sx, 1.45, bz), hm)                       # barrel
					_box(node, Vector3(0.3, 0.75, 0.6), Vector3(sx, 2.0, bz - 1.1), hm)                   # neck
					_box(node, Vector3(0.24, 0.3, 0.6), Vector3(sx, 2.25, bz - 1.55), hm)                 # head
					for lz in [0.75, -0.75]:
						_box(node, Vector3(0.14, 1.1, 0.14), Vector3(sx, 0.55, bz + lz), hm)              # legs
		"tender":
			_box(node, Vector3(W, 1.7, L * 0.95), Vector3(0, 1.95, 0), black)
			_box(node, Vector3(W * 0.85, 0.5, L * 0.6), Vector3(0, 3.0, L * 0.1), _mat(Color(0.05, 0.05, 0.05)))   # coal
		"express", "coach", "caboose":
			var col: StandardMaterial3D = green if c.kind == "express" else (yellow if c.kind == "coach" else red)
			_box(node, Vector3(W, H - 1.3, L - 1.6), Vector3(0, 1.1 + (H - 1.3) * 0.5, 0), col)
			_box(node, Vector3(W + 0.2, 0.2, L - 1.2), Vector3(0, H - 0.1, 0), roofm)
			for z in [-L * 0.5 + 0.5, L * 0.5 - 0.5]:
				_box(node, Vector3(W * 0.8, 0.1, 0.9), Vector3(0, 1.1, z), iron)                          # platforms
			if c.kind == "express":
				_box(node, Vector3(0.05, 1.9, 1.6), Vector3(W * 0.5 + 0.03, 2.1, 0), _mat(Color(0.12, 0.1, 0.08)))   # sliding doors
				_box(node, Vector3(0.05, 1.9, 1.6), Vector3(-W * 0.5 - 0.03, 2.1, 0), _mat(Color(0.12, 0.1, 0.08)))
			elif c.kind == "coach":
				for k in 6:
					_box(node, Vector3(W + 0.04, 0.7, 0.8), Vector3(0, 2.4, -L * 0.36 + k * L * 0.145), _mat(Color(0.95, 0.8, 0.45)))
			else:
				_box(node, Vector3(1.4, 0.9, 2.4), Vector3(0, H + 0.4, 0), col)                          # cupola
	# far shell
	var far := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(W, H - 0.8, L)
	far.mesh = fm
	far.material_override = _mat(Color(0.15, 0.13, 0.12))
	far.position = Vector3(0, 0.8 + (H - 0.8) * 0.5, 0)
	far.visibility_range_begin = 260.0
	far.visibility_range_end = 2500.0
	node.add_child(far)
	return {"node": node, "body": body}

## Lay rails and ties over [from, to] metres of the path (the stretch the mission plays on).
func lay_track(from: float, to: float) -> void:
	if Game.headless:
		return
	track = Node3D.new()
	track.name = "Track"
	get_parent().add_child(track)
	var n := int((to - from) / 0.65)
	var ties := MultiMesh.new()
	ties.transform_format = MultiMesh.TRANSFORM_3D
	var tm := BoxMesh.new()
	tm.size = Vector3(2.5, 0.15, 0.22)
	ties.mesh = tm
	ties.instance_count = n
	var rails := MultiMesh.new()
	rails.transform_format = MultiMesh.TRANSFORM_3D
	var rm := BoxMesh.new()
	rm.size = Vector3(0.08, 0.12, 4.05)
	rails.mesh = rm
	var nr := int((to - from) / 4.0)
	rails.instance_count = nr * 2
	for i in n:
		var d := from + i * 0.65
		var p := at(d)
		var t := tangent(d)
		ties.set_instance_transform(i, Transform3D(Basis.looking_at(t, Vector3.UP), p + Vector3(0, 0.08, 0)))
	for i in nr:
		var d := from + i * 4.0 + 2.0
		var p := at(d)
		var t := tangent(d)
		var b := Basis.looking_at(t, Vector3.UP)
		var side := b.x
		rails.set_instance_transform(i * 2, Transform3D(b, p + side * 0.72 + Vector3(0, 0.2, 0)))
		rails.set_instance_transform(i * 2 + 1, Transform3D(b, p - side * 0.72 + Vector3(0, 0.2, 0)))
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = ties
	tmi.material_override = _mat(Color(0.3, 0.22, 0.15))
	tmi.visibility_range_end = 350.0
	track.add_child(tmi)
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rails
	rmi.material_override = _mat(Color(0.35, 0.33, 0.32), true)
	rmi.visibility_range_end = 450.0
	track.add_child(rmi)

func _exit_tree() -> void:
	if track and is_instance_valid(track):
		track.queue_free()
