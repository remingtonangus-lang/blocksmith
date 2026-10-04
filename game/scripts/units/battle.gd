class_name Battle
extends Node3D
## The war: a front line between Fort Lumen (the Capital) and the Cinder Pact outposts with three capture points,
## squads of eight per side (sergeant, heavy, six riflemen; an officer with every third squad), reinforcement
## waves, mortar and artillery barrages on concentrations, and Capital garrisons patrolling the citadel and the
## city plaza. The front runs at full detail while the camera is within ACTIVE_RANGE; elsewhere it pauses.

const ACTIVE_RANGE := 3200.0
const SQUAD_SIZE := 8
const CAP := {0: 96, 1: 104}
const REINFORCE := 40.0

var army: Army
var fx: Fx
var front := Vector3.ZERO
var stage := [Vector3.ZERO, Vector3.ZERO]
var points: Array = []          # [{pos, owner (-1/0/1), hold (−1..1)}]
var _reinforce_t := [5.0, 9.0]
var _barrage_t := [30.0, 45.0]
var _barrages: Array = []       # [impact time, position, power]
var _garrison_t := 0.0
var active := false
var rng := RandomNumberGenerator.new()
var started := false


func setup() -> void:
	rng.seed = 99
	G.battle = self
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup()
	G.fx = fx
	army = Army.new()
	army.name = "Army"
	add_child(army)
	army.setup()
	army.fx = fx
	var gen := G.gen as WorldGen
	front = gen.sites["front"]
	stage[0] = _ground(front + Vector3(520, 0, 40))
	stage[1] = _ground(front + Vector3(-520, 0, 260))
	for off in [Vector3(-60, 0, -280), Vector3(0, 0, 0), Vector3(80, 0, 300)]:
		points.append({"pos": _ground(front + off), "owner": -1, "hold": 0.0})
	_garrisons()


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, G.world.ground_at(p.x, p.z), p.z)


func _new_squad(faction: int, at: Vector3, objective: Vector3, spread: float, kind: String = "assault") -> int:
	var id := army.squads.size()
	army.squads.append({"faction": faction, "members": [], "objective": objective, "spread": spread, "kind": kind})
	var ranks := [1, 3, 0, 0, 0, 0, 0, 0]
	if id % 3 == 0:
		ranks[7] = 2
	for k in SQUAD_SIZE:
		var p := at + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		if G.gen.water_at(p.x, p.z) > -100.0:
			p = at
		var i := army.spawn(p, faction, ranks[k], id)
		if i >= 0:
			army.squads[id]["members"].append(i)
	return id


func _garrisons() -> void:
	# Ceremonial guards and patrols: the citadel plaza and the Capital's central plaza.
	var cit: Vector3 = (G.world.bases as Bases).sites["citadel"]["pos"]
	_new_squad(Army.CAPITAL, cit + Vector3(0, 6, 90), cit + Vector3(0, 6, 60), 30.0, "patrol")
	var city: CapitalCity = G.world.city_list[0]
	var c := Vector3(city.center.x, city.podium_y, city.center.z)
	_new_squad(Army.CAPITAL, c + Vector3(120, 0, 60), c + Vector3(0, 0, 80), 60.0, "patrol")
	_new_squad(Army.CAPITAL, c + Vector3(-120, 0, -60), c + Vector3(0, 0, -80), 60.0, "patrol")


func start() -> void:
	if started:
		return
	started = true
	for side in 2:
		for k in 6:
			var obj: Vector3 = points[k % 3]["pos"]
			_new_squad(side, stage[side] + Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-120, 120)), obj, 45.0)


## Benchmark / shots: a full battle in progress right away.
func bench_battle() -> void:
	start()
	# Bring both sides close to the middle so the fight is on.
	for sq in army.squads:
		if sq["kind"] != "assault":
			continue
		for i in sq["members"]:
			var side: int = sq["faction"]
			var p := front.lerp(stage[side], rng.randf_range(0.15, 0.45)) + Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-200, 200))
			army.pos[i] = _ground(p)
			army.goal[i] = army.pos[i]
	army.grid.clear()
	for i in army.n:
		if army.state[i] != Army.S_DEAD and army.state[i] != 255:
			army._grid_add(i)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := cam.global_position.distance_to(front) < ACTIVE_RANGE
	if near and not started:
		start()
	active = near
	army.set_process(true)
	if not started:
		return
	_update_points(delta)
	for side in 2:
		_reinforce_t[side] -= delta
		if _reinforce_t[side] <= 0.0:
			_reinforce_t[side] = REINFORCE * rng.randf_range(0.8, 1.3)
			if army.count_alive(side) < CAP[side]:
				var target := _pick_objective(side)
				_new_squad(side, stage[side] + Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-120, 120)), target, 40.0)
		_barrage_t[side] -= delta
		if _barrage_t[side] <= 0.0:
			_barrage_t[side] = rng.randf_range(35.0, 70.0)
			_call_barrage(side)
	_retask(delta)
	var keep := []
	var now := Time.get_ticks_msec() / 1000.0
	for b in _barrages:
		if now >= b[0]:
			fx.explosion(b[1], b[2])
		else:
			keep.append(b)
	_barrages = keep


func _update_points(delta: float) -> void:
	for pt in points:
		var counts := [0, 0]
		var p: Vector3 = pt["pos"]
		var c := army._cell(p)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var cc := c + Vector2i(dx, dz)
				if not army.grid.has(cc):
					continue
				for j in army.grid[cc]:
					if army.pos[j].distance_squared_to(p) < 60.0 * 60.0:
						counts[army.fac[j]] += 1
		var d: float = (counts[0] - counts[1]) * 0.02 * delta
		pt["hold"] = clampf(pt["hold"] + d, -1.0, 1.0)
		if pt["hold"] > 0.6:
			pt["owner"] = 0
		elif pt["hold"] < -0.6:
			pt["owner"] = 1


func _pick_objective(side: int) -> Vector3:
	# Prefer points the enemy holds or that are contested; else the middle.
	var best: Vector3 = points[1]["pos"]
	var score := -1e9
	for pt in points:
		var s: float = -pt["hold"] if side == 0 else pt["hold"]
		s += rng.randf() * 0.3
		if s > score:
			score = s
			best = pt["pos"]
	return best


var _retask_t := 0.0


func _retask(delta: float) -> void:
	_retask_t -= delta
	if _retask_t > 0.0:
		return
	_retask_t = 12.0
	for sq in army.squads:
		var side: int = sq["faction"]
		var alive := 0
		for i in sq["members"]:
			if army.alive(i):
				alive += 1
		if sq["kind"] == "patrol":
			var o: Vector3 = sq["objective"]
			sq["objective"] = o + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40)).limit_length(60.0)
			continue
		if alive <= 2:
			sq["objective"] = stage[side]          # broken squads fall back
		elif rng.randf() < 0.35:
			sq["objective"] = _pick_objective(side)


## Mortars (Cinder) or the artillery park's guns (Capital) shell the densest enemy group.
func _call_barrage(side: int) -> void:
	var enemy := 1 - side
	var best := Vector3.ZERO
	var bc := 0
	for k in 12:
		var i := rng.randi_range(0, maxi(0, army.n - 1))
		if not army.alive(i) or army.fac[i] != enemy:
			continue
		var c := 0
		for j in army.grid.get(army._cell(army.pos[i]), PackedInt32Array()):
			if army.fac[j] == enemy:
				c += 1
		if c > bc:
			bc = c
			best = army.pos[i]
	if bc < 3:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var shells := 6 if side == 0 else 4
	var power := 1.4 if side == 0 else 0.8
	for k in shells:
		var p := best + Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35))
		_barrages.append([now + 3.0 + k * rng.randf_range(0.4, 1.1), _ground(p), power])
	if side == 0 and Sfx.has_method("distant_guns"):
		Sfx.distant_guns(G.gen.sites["artillery"])


## Runs the battle forward without rendering (shots and the benchmark start mid-fight).
func simulate(seconds: float) -> void:
	var steps := int(seconds / 0.1)
	for k in steps:
		army._process(0.1)
		_process(0.1)
		fx._process(0.1)
	print("battle: %d soldiers (Capital %d, Cinder %d alive), kills %s, drawn %s" % [army.n, army.count_alive(0), army.count_alive(1), str(army.kills), str(army.counts)])


## Debug / shots: a row of soldiers (every rank of both factions, in each pose) facing `face`.
func lineup(at: Vector3, face: Vector3) -> void:
	var dir := (face - at)
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var k := 0
	for f in 2:
		for rank in 4:
			var p := at + side * (k - 3.5) * 1.6
			var i := army.spawn(p, f, rank, -1)
			army.yaw[i] = atan2(-dir.x, -dir.z)
			army.moving[i] = 0
			army.think_t[i] = 1e9
			army.state[i] = [Army.S_IDLE, Army.S_WALK, Army.S_AIM, Army.S_CROUCH][rank]
			army.phase[i] = 0.2 * k
			k += 1
