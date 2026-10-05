extends RefCounted
## Chapter 4 (Silver and Snow) helpers: places in Coldwater and up the Kestrel Range, and staged props — the mine
## portal (settlements have no mine interior, so the Kestrel mine is played at its mouth), a line shack, a powder
## blast. Props are boxes and particles in code, tracked by the director so they go with the mission.

const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")

const MINE_YARD := Vector3(-1691.0, 0, -2848.0)
const ADIT := Vector3(-1684.0, 0, -2918.0)
const FACE_FOOT := Vector3(-1640.0, 0, -3362.0)
const PASS := Vector3(-1611.0, 0, -3621.0)
const LINE_SHACK := Vector3(-1236.0, 0, -3621.0)

static func at(p: Vector3) -> Vector3:
	return C3.dry(p)

static func town(dx: float, dz: float) -> Vector3:
	return C2.spot("coldwater", dx, dz)

## Holds up a face, evenly from a to b (ground height at each).
static func holds(a: Vector3, b: Vector3, n: int) -> Array:
	var out := []
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		out.append(Vector3(p.x, Game.world.height(p.x, p.z), p.z))
	return out

static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	m.material_override = mat
	m.position = pos
	parent.add_child(m)

## Timber mine portal set into the hillside, facing `toward`.
static func portal(d, pos: Vector3, toward: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "MinePortal"
	Game.main.add_child(n)
	n.global_position = Vector3(pos.x, Game.world.height(pos.x, pos.z), pos.z)
	d.track(n)
	if Game.headless:
		return n
	n.look_at(Vector3(toward.x, n.global_position.y, toward.z), Vector3.UP)
	var timber := Color(0.33, 0.24, 0.16)
	_box(n, Vector3(0.35, 3.2, 0.35), Vector3(-1.6, 1.6, 0), timber)
	_box(n, Vector3(0.35, 3.2, 0.35), Vector3(1.6, 1.6, 0), timber)
	_box(n, Vector3(4.0, 0.4, 0.45), Vector3(0, 3.3, 0), timber)
	_box(n, Vector3(3.0, 3.0, 2.5), Vector3(0, 1.5, 1.4), Color(0.05, 0.04, 0.04))
	_box(n, Vector3(0.12, 0.12, 9.0), Vector3(-0.6, 0.06, -4.5), Color(0.25, 0.22, 0.2))
	_box(n, Vector3(0.12, 0.12, 9.0), Vector3(0.6, 0.06, -4.5), Color(0.25, 0.22, 0.2))
	return n

## Rubble across the portal after the blast (one heap per dig point).
static func rubble(d, points: Array) -> void:
	if Game.headless:
		return
	for p in points:
		var n := Node3D.new()
		Game.main.add_child(n)
		n.global_position = Vector3(p.x, Game.world.height(p.x, p.z), p.z)
		d.track(n)
		_box(n, Vector3(1.6, 0.9, 1.3), Vector3(0, 0.45, 0), Color(0.42, 0.38, 0.34))
		_box(n, Vector3(2.2, 0.25, 0.3), Vector3(0.2, 0.9, 0), Color(0.33, 0.24, 0.16))

## A board line shack with a lean-to.
static func shack(d, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "LineShack"
	Game.main.add_child(n)
	n.global_position = Vector3(pos.x, Game.world.height(pos.x, pos.z), pos.z)
	d.track(n)
	if Game.headless:
		return n
	var wood := Color(0.36, 0.28, 0.2)
	_box(n, Vector3(5.0, 2.6, 4.0), Vector3(0, 1.3, 0), wood)
	_box(n, Vector3(5.6, 0.3, 4.6), Vector3(0, 2.75, 0), Color(0.85, 0.87, 0.9))
	_box(n, Vector3(0.5, 3.6, 0.5), Vector3(1.8, 1.8, -1.5), Color(0.3, 0.29, 0.28))
	_box(n, Vector3(3.0, 2.0, 2.5), Vector3(-4.2, 1.0, 0.5), wood.darkened(0.2))
	return n

## A powder blast: a dust cloud, a bang heard across the canyon, horses spooked, people ducking.
static func blast(d, pos: Vector3) -> void:
	Game.noise.emit(pos, 120.0, null)
	if not d.autopilot:
		Horse.alarm(pos, 80.0, 1.0, "explosion")
	if Game.audio and Game.audio.has_method("play"):
		Game.audio.play("explosion", pos, {"volume_db": 4.0})
	Game.log_event("blast", {})
	if Game.headless:
		return
	var n := Node3D.new()
	Game.main.add_child(n)
	n.global_position = pos + Vector3(0, 1.5, 0)
	d.track(n)
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.amount = 160
	ps.lifetime = 4.0
	ps.direction = Vector3.UP
	ps.spread = 70.0
	ps.initial_velocity_min = 3.0
	ps.initial_velocity_max = 11.0
	ps.gravity = Vector3(0, -2.0, 0)
	ps.scale_amount_min = 1.5
	ps.scale_amount_max = 4.0
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.45, 0.4, 0.35, 0.6)
	q.material = m
	ps.mesh = q
	n.add_child(ps)
	ps.emitting = true
