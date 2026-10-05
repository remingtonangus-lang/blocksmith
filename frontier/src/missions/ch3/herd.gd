extends Node3D
## A trail herd for the chapter 3 drive: simple cattle (box body, head and horns, seeded hides) that move as a
## flock and are driven the way cattle are: they graze until a rider comes up behind, then move away from the
## pressure and drift toward the drive's goal. Strays break off and wander until a rider turns them back. A
## stampede sends the whole herd running; riding up on the leaders' flank turns them into a mill and stops it.
## Cheap: no physics bodies, heightmap ground, ~24 head updated together.

signal stray_broke(cow: Node3D)
signal head_lost(cow: Node3D)

const GRAZE_SPEED := 0.25
const DRIVE_SPEED := 2.8
const RUN_SPEED := 8.5
const PUSH_RANGE := 26.0
const LOST_RANGE := 160.0

class Cow extends Node3D:
	var vel := Vector3.ZERO
	var heading := 0.0
	var stray := false
	var stray_dir := Vector3.ZERO
	var lost := false
	var bob := 0.0

var cows: Array = []
var goal := Vector3.INF
var pushers: Array = []              # Node3D riders that move cattle (Ruth, outriders)
var stampeding := false
var stampede_dir := Vector3.ZERO
var stampede_t := 0.0
var mill_t := 0.0
var lost_count := 0
var rng := RandomNumberGenerator.new()
var _mesh_body: BoxMesh
var _mesh_head: BoxMesh
var _mesh_horn: BoxMesh
var center_node: Node3D           # follows the middle of the bunch (riders keep station on it)

func setup(center: Vector3, count: int, seed_value: int) -> void:
	rng.seed = seed_value
	name = "Herd"
	_mesh_body = BoxMesh.new()
	_mesh_body.size = Vector3(0.75, 0.85, 1.9)
	_mesh_head = BoxMesh.new()
	_mesh_head.size = Vector3(0.42, 0.42, 0.55)
	_mesh_horn = BoxMesh.new()
	_mesh_horn.size = Vector3(1.1, 0.07, 0.07)
	center_node = Node3D.new()
	center_node.name = "HerdCenter"
	add_child(center_node)
	for i in count:
		var c := Cow.new()
		c.name = "Cow%d" % i
		add_child(c)
		var off := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		c.global_position = _ground(center + off)
		c.heading = rng.randf() * TAU
		c.bob = rng.randf() * TAU
		_dress(c)
		cows.append(c)

func _dress(c: Cow) -> void:
	if Game.headless:
		return
	var hides := [Color(0.42, 0.2, 0.1), Color(0.55, 0.3, 0.14), Color(0.12, 0.09, 0.08), Color(0.62, 0.5, 0.36), Color(0.3, 0.17, 0.1)]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = hides[rng.randi() % hides.size()].lerp(Color(0.5, 0.4, 0.3), rng.randf() * 0.2)
	mat.roughness = 0.95
	var body := MeshInstance3D.new()
	body.mesh = _mesh_body
	body.material_override = mat
	body.position = Vector3(0, 0.95, 0)
	c.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = _mesh_head
	var face := mat
	if rng.randf() < 0.45:          # whiteface
		face = StandardMaterial3D.new()
		face.albedo_color = Color(0.86, 0.83, 0.78)
		face.roughness = 0.9
	head.material_override = face
	head.position = Vector3(0, 1.05, -1.15)
	c.add_child(head)
	var horn := MeshInstance3D.new()
	horn.mesh = _mesh_horn
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.85, 0.8, 0.66)
	horn.material_override = hm
	horn.position = Vector3(0, 1.3, -1.05)
	c.add_child(horn)
	for x in [-0.25, 0.25]:
		for z in [-0.7, 0.7]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.14, 0.6, 0.14)
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(x, 0.3, z)
			c.add_child(leg)

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, Game.world.height(p.x, p.z), p.z)

func live_cows() -> Array:
	return cows.filter(func(c): return not c.lost)

func head() -> int:
	return live_cows().size()

func center() -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for c in cows:
		if not c.lost and not c.stray:
			s += c.global_position
			n += 1
	if n == 0:
		for c in cows:
			if not c.lost:
				s += c.global_position
				n += 1
	return s / maxf(n, 1.0)

func strays() -> Array:
	return cows.filter(func(c): return c.stray and not c.lost)

## Send one cow off on its own (from the edge of the herd, away from the middle).
func make_stray() -> Node3D:
	var cen := center()
	var best: Cow = null
	var bd := -1.0
	for c in cows:
		if c.lost or c.stray:
			continue
		var d: float = c.global_position.distance_to(cen)
		if d > bd:
			bd = d
			best = c
	if best == null:
		return null
	best.stray = true
	var away := best.global_position - cen
	away.y = 0
	if away.length() < 0.5:
		away = Vector3(1, 0, 0)
	best.stray_dir = away.normalized().rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
	stray_broke.emit(best)
	Game.log_event("herd_stray", {"cow": str(best.name)})
	return best

func stampede(dir: Vector3) -> void:
	stampeding = true
	stampede_t = 0.0
	mill_t = 0.0
	var d := dir
	d.y = 0
	stampede_dir = d.normalized() if d.length() > 0.1 else Vector3(1, 0, 0)
	for c in cows:
		c.stray = false
	Game.log_event("herd_stampede", {})

## The cow furthest along the run: the one to ride for.
func leader() -> Node3D:
	var best: Cow = null
	var bs := -INF
	for c in cows:
		if c.lost:
			continue
		var s: float = c.global_position.dot(stampede_dir)
		if s > bs:
			bs = s
			best = c
	return best

func calm() -> void:
	stampeding = false
	mill_t = 0.0
	Game.log_event("herd_calmed", {"t": snappedf(stampede_t, 0.1)})

## Lose some head in a stampede that ran on too long (they scatter into the rocks).
func scatter(n: int) -> void:
	var lc := live_cows()
	for i in mini(n, lc.size() - 1):
		var c: Cow = lc[rng.randi() % lc.size()]
		if not c.lost:
			_lose(c)

func _lose(c: Cow) -> void:
	c.lost = true
	c.visible = false
	lost_count += 1
	head_lost.emit(c)
	Game.log_event("herd_lost", {"cow": str(c.name)})

## Bots / resume: put the herd at a point in a loose bunch.
func teleport_to(p: Vector3) -> void:
	for c in cows:
		if c.lost:
			continue
		c.stray = false
		c.global_position = _ground(p + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)))
	stampeding = false

func count_near(p: Vector3, r: float) -> int:
	var n := 0
	for c in cows:
		if not c.lost and Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < r:
			n += 1
	return n

func _physics_process(dt: float) -> void:
	if cows.is_empty() or Game.world == null:
		return
	var cen := center()
	var live := live_cows()
	center_node.global_position = cen
	var lead: Node3D = leader() if stampeding else null
	if stampeding:
		stampede_t += dt
		# turning the leaders: a rider close on the lead cow's flank bends the run into a circle
		var turning := false
		for r in pushers:
			if not is_instance_valid(r) or lead == null:
				continue
			var rel: Vector3 = r.global_position - lead.global_position
			rel.y = 0
			# on the flank and up level with the lead cow, not trailing behind the run
			if rel.length() < 10.0 and rel.dot(stampede_dir) > -3.0:
				turning = true
				var side: Vector3 = r.global_position - lead.global_position
				side.y = 0
				var bend := -side.normalized()
				stampede_dir = stampede_dir.slerp(bend, clampf(dt * 0.9, 0.0, 1.0)).normalized()
		mill_t = mill_t + dt if turning else maxf(mill_t - dt * 0.7, 0.0)
	for c in live:
		var p: Vector3 = c.global_position
		var want := Vector3.ZERO
		var spd := GRAZE_SPEED
		# separation from neighbours
		var sep := Vector3.ZERO
		for o in live:
			if o == c:
				continue
			var d: Vector3 = p - o.global_position
			d.y = 0
			var dl := d.length()
			if dl < 2.4 and dl > 0.01:
				sep += d / dl * (2.4 - dl)
		if stampeding:
			want = stampede_dir * 1.0 + sep * 0.4 + (cen - p).normalized() * 0.15
			spd = RUN_SPEED if mill_t < 2.5 else lerpf(RUN_SPEED, GRAZE_SPEED, clampf((mill_t - 2.5) / 2.0, 0.0, 1.0))
		elif c.stray:
			want = c.stray_dir + sep * 0.3
			spd = 1.4
			for r in pushers:
				if not is_instance_valid(r):
					continue
				var rd: Vector3 = p - r.global_position
				rd.y = 0
				if rd.length() < 14.0:
					# a rider turns it: pressure from the outside sends it back toward the bunch
					c.stray_dir = c.stray_dir.slerp((cen - p).normalized(), clampf(dt * 2.0, 0.0, 1.0)).normalized()
					spd = DRIVE_SPEED * 1.2
			if p.distance_to(cen) < 14.0 and c.stray_dir.dot((cen - p).normalized()) > 0.0:
				c.stray = false
		else:
			var push := Vector3.ZERO
			for r in pushers:
				if not is_instance_valid(r):
					continue
				var rd: Vector3 = p - r.global_position
				rd.y = 0
				var dl := rd.length()
				if dl < PUSH_RANGE and dl > 0.01:
					push += rd / dl * (1.0 - dl / PUSH_RANGE)
			var coh := (cen - p)
			coh.y = 0
			var to_goal := Vector3.ZERO
			if goal != Vector3.INF:
				to_goal = Vector3(goal.x - p.x, 0, goal.z - p.z).normalized()
			if push.length() > 0.05:
				# pushed: move off the pressure, bending toward the trail
				want = push.normalized() * 1.0 + to_goal * 0.8 + coh * 0.04 + sep * 0.5
				spd = lerpf(GRAZE_SPEED, DRIVE_SPEED, clampf(push.length() * 1.6, 0.0, 1.0))
			else:
				want = coh * 0.03 + sep * 0.5
				if coh.length() < 6.0 and sep.length() < 0.1:
					want = Vector3(sin(c.bob), 0, cos(c.bob)) * 0.2
				spd = GRAZE_SPEED
		want.y = 0
		if want.length() > 0.01:
			var dir := _avoid(p, want.normalized())
			c.vel = c.vel.lerp(dir * spd, clampf(dt * 2.5, 0.0, 1.0))
		else:
			c.vel = c.vel.lerp(Vector3.ZERO, clampf(dt * 2.0, 0.0, 1.0))
		var np: Vector3 = p + c.vel * dt
		c.global_position = _ground(np)
		if c.vel.length() > 0.15:
			c.heading = lerp_angle(c.heading, atan2(-c.vel.x, -c.vel.z), clampf(dt * 4.0, 0.0, 1.0))
		c.bob += dt * (0.3 + c.vel.length() * 2.2)
		c.rotation = Vector3(sin(c.bob) * 0.02 * minf(c.vel.length(), 3.0), c.heading, 0)
		if c.stray and p.distance_to(cen) > LOST_RANGE:
			_lose(c)

## Steer around water and steep ground (probe a few metres ahead).
func _avoid(p: Vector3, dir: Vector3) -> Vector3:
	var w: WorldData = Game.world
	for a in [0.0, 0.5, -0.5, 1.1, -1.1, 1.8, -1.8, PI]:
		var d := dir.rotated(Vector3.UP, a)
		var q := p + d * 3.5
		if w.is_water(q.x, q.z):
			continue
		if absf(w.height(q.x, q.z) - w.height(p.x, p.z)) > 2.2:
			continue
		return d
	return dir
