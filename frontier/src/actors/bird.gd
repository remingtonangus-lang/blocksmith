class_name Bird
extends Node3D
## Birds: wild turkeys and sage grouse (ground flocks that run, then flush in a short burst and glide down
## again), crows (flocks foraging on fields and perching on town hitch rails, all lifting off at a gunshot and
## circling before they settle), and the red-tailed hawk (soars in thermal circles and stoops on rabbits).
## Generated models from tools/animals/bird.py; a stand-in when they are missing. The flight model is a cheap
## kinematic one: a speed, a heading with a turn-rate limit, a climb rate, bank from the turn rate. No physics
## body; one hit sphere on the body. Shot birds tumble to the ground and can be plucked (meat, feathers).
## API: Bird.spawn(parent, pos, species, seed) -> Bird; flush(from); flock (Array of the flock's birds).

const SPECIES := {
	"turkey": {"name": "Wild Turkey", "kind": "ground", "flock": [4, 10], "hp": 18.0, "wary": 38.0, "flush": 12.0,
		"walk": 0.9, "run": 6.0, "fly": 12.0, "alt": [3.0, 9.0], "flight_dist": [60.0, 140.0], "biomes": [0.5, 0.95],
		"active": "day", "meat": 1.0, "feathers": 0.6, "size": 0.5},
	"sage_grouse": {"name": "Sage Grouse", "kind": "ground", "flock": [3, 8], "hp": 8.0, "wary": 22.0, "flush": 9.0,
		"walk": 0.6, "run": 3.5, "fly": 14.0, "alt": [2.0, 6.0], "flight_dist": [80.0, 200.0], "biomes": [0.15, 0.5],
		"active": "day", "meat": 0.5, "feathers": 0.3, "size": 0.25},
	"crow": {"name": "Crow", "kind": "flock", "flock": [6, 14], "hp": 6.0, "wary": 30.0, "flush": 22.0,
		"walk": 0.5, "run": 1.5, "fly": 10.0, "alt": [12.0, 30.0], "flight_dist": [60.0, 160.0], "biomes": [0.0, 1.0],
		"active": "day", "meat": 0.2, "feathers": 0.4, "size": 0.2},
	"red_tailed_hawk": {"name": "Red-tailed Hawk", "kind": "raptor", "flock": [1, 1], "hp": 12.0, "wary": 60.0, "flush": 25.0,
		"walk": 0.4, "run": 1.0, "fly": 12.0, "alt": [40.0, 75.0], "flight_dist": [0.0, 0.0], "biomes": [0.0, 1.0],
		"active": "day", "meat": 0.3, "feathers": 1.0, "size": 0.25},
}

enum Mode { GROUND, RUN, TAKEOFF, FLY, LAND, SOAR, DIVE, CLIMB, FALLING, DEAD }

var species := "crow"
var spec: Dictionary
var mode := Mode.GROUND
var vis: HorseVisual
var stand_in: Node3D
var damageable: Damageable
var flock: Array = []
var alive := true
var plucked := false
var heading := 0.0
var speed := 0.0
var climb := 0.0                     # vertical speed m/s
var bank := 0.0
var target := Vector3.INF
var home := Vector3.ZERO             # flock centre on the ground / soaring centre
var soar_phase := 0.0
var rng := RandomNumberGenerator.new()
var t_mode := 0.0
var _anim := ""
var _ground_y := 0.0
var _prey: Node3D = null
var flushes := 0                     # stats for the bird oracle
var dives := 0
var kills := 0
var air_time := 0.0

static func spawn(parent: Node, pos: Vector3, sp: String, seed: int) -> Bird:
	var b := Bird.new()
	b.species = sp
	b.spec = SPECIES[sp]
	b.rng.seed = seed
	b.name = "%s_%d" % [sp, seed % 100000]
	parent.add_child(b)
	b.global_position = pos
	b.home = pos
	b._setup()
	return b

func _setup() -> void:
	add_to_group("birds")
	heading = rng.randf() * TAU
	damageable = Damageable.new()
	damageable.max_health = spec.hp
	damageable.kind = "animal"
	add_child(damageable)
	damageable.died.connect(_on_died)
	var path := HorseVisual.model_path_for(species)
	var hb_parent: Node3D = self
	if path != "":
		vis = HorseVisual.new()
		vis.build(BirdLooks.roll(species, int(rng.seed % 100003)), species)
		if vis.has_model:
			add_child(vis)
			hb_parent = vis
		else:
			vis.free()
			vis = null
	if vis == null:
		stand_in = _make_stand_in()
		add_child(stand_in)
		hb_parent = stand_in
	var an: Dictionary = vis.meta.get("anchors", {}) if vis else {}
	var bc: Array = an.get("body", [0.0, 0.0, float(spec.size)])
	var br: Array = an.get("body_r", [0.1, 0.15, 0.1])
	var sph := SphereShape3D.new()
	sph.radius = maxf(float(br[1]) * 1.1, 0.08)
	Damageable.make_hitbox(hb_parent, damageable, "chest", sph, Transform3D(Basis.IDENTITY, Vector3(0, float(bc[2]), 0)))
	if Game.noise and not Game.noise.is_connected(_on_noise):
		Game.noise.connect(_on_noise)
	if spec.kind == "raptor":
		mode = Mode.SOAR
		_ground_y = _terrain_y(global_position)
		global_position.y = _ground_y + rng.randf_range(spec.alt[0], spec.alt[1])
		speed = float(spec.fly)
		soar_phase = rng.randf() * TAU
		t_mode = rng.randf_range(15.0, 40.0)
	else:
		_snap_ground()
		t_mode = rng.randf_range(1.0, 5.0)

func _make_stand_in() -> Node3D:
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var sz := float(spec.size)
	sm.radius = sz * 0.4
	sm.height = sz * 0.6
	m.mesh = sm
	m.position.y = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.09, 0.08)
	m.material_override = mat
	n.add_child(m)
	return n

func _terrain_y(p: Vector3) -> float:
	return Game.world.height(p.x, p.z) if Game.world else 0.0

func _snap_ground() -> void:
	_ground_y = _terrain_y(global_position)
	global_position.y = _ground_y

func _anim_to(st: String, ts := 1.0) -> void:
	if vis == null:
		return
	if st != _anim:
		_anim = st
	vis.set_locomotion(st, ts)

func _action(a: String) -> void:
	if vis:
		vis.play_action(a)

# ------------------------------------------------------------------------------------------------- reactions
func _on_noise(pos: Vector3, radius: float, _source: Node) -> void:
	if not alive or not is_inside_tree():
		return
	var d := global_position.distance_to(pos)
	if d < radius * (1.4 if spec.kind == "flock" else 0.8):
		flush(pos)

## Take off away from `from` (ground birds and crows); a soaring hawk ignores it unless close.
func flush(from: Vector3) -> void:
	if not alive:
		return
	if mode in [Mode.GROUND, Mode.RUN]:
		mode = Mode.TAKEOFF
		t_mode = 0.45
		flushes += 1
		var away := global_position - from
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		away = away.normalized().rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		heading = atan2(-away.x, -away.z)
		var dist := rng.randf_range(spec.flight_dist[0], spec.flight_dist[1])
		target = global_position + away * dist
		target.y = _terrain_y(target) + rng.randf_range(spec.alt[0], spec.alt[1])
		climb = 3.5
		speed = 3.0
		_action("takeoff")
		Game.log_event("bird_flush", {"species": species})
		for b in flock:
			if is_instance_valid(b) and b != self and b.mode in [Mode.GROUND, Mode.RUN]:
				b.call_deferred("flush", from + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))

func _on_died(_info: Dictionary) -> void:
	alive = false
	Game.log_event("animal_killed", {"species": species})
	if Game.state:
		Game.state.kills.animal += 1
	if global_position.y > _terrain_y(global_position) + 0.5:
		mode = Mode.FALLING
		_anim_to("fall")
	else:
		mode = Mode.DEAD
		_snap_ground()
		_anim_to("death")
	add_to_group("interactable")

func interact_prompt() -> String:
	return "" if alive or plucked or mode == Mode.FALLING else "Pluck the %s" % str(spec.name).to_lower()

func interact(_who: Node) -> void:
	if alive or plucked:
		return
	plucked = true
	if Game.state:
		Game.state.add_item("meat_" + species, 1)
		Game.state.add_item("feathers_" + species, 1)
	if Game.hud:
		Game.hud.notice("%s: meat and feathers" % spec.name, 3.0)
	Game.log_event("plucked", {"species": species})
	remove_from_group("interactable")

# ------------------------------------------------------------------------------------------------- update
func _physics_process(dt: float) -> void:
	t_mode -= dt
	var far := Game.player != null and is_instance_valid(Game.player) and Game.player.global_position.distance_to(global_position) > 260.0
	if vis and vis.tree:
		vis.tree.active = not far or not alive
	match mode:
		Mode.GROUND, Mode.RUN:
			_ground(dt)
		Mode.TAKEOFF:
			_takeoff(dt)
		Mode.FLY:
			_fly(dt)
		Mode.LAND:
			_land(dt)
		Mode.SOAR:
			_soar(dt)
		Mode.DIVE:
			_dive(dt)
		Mode.CLIMB:
			_climb(dt)
		Mode.FALLING:
			_fall(dt)
		Mode.DEAD:
			pass
	if mode in [Mode.TAKEOFF, Mode.FLY, Mode.LAND, Mode.SOAR, Mode.DIVE, Mode.CLIMB]:
		air_time += dt
	_orient(dt)

func _senses() -> Node3D:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return null
	var d: float = p.global_position.distance_to(global_position)
	var crouch: bool = p.intent.get("crouch", false) if p.get("intent") != null else false
	var r: float = float(spec.flush) * (0.6 if crouch else 1.0) * (1.6 if p.get("on_horse") != null else 1.0)
	return p if d < r else null

func _ground(dt: float) -> void:
	var t := _senses()
	if t != null:
		if species == "turkey" and mode == Mode.GROUND and t.global_position.distance_to(global_position) > float(spec.flush) * 0.6:
			mode = Mode.RUN                       # turkeys run first, flush when pressed
			var away := global_position - t.global_position
			heading = atan2(-away.x, -away.z)
			t_mode = 3.0
		else:
			flush(t.global_position)
			return
	if mode == Mode.RUN:
		speed = move_toward(speed, float(spec.run), 8.0 * dt)
		if t_mode <= 0.0:
			mode = Mode.GROUND
	else:
		if t_mode <= 0.0:
			t_mode = rng.randf_range(2.0, 7.0)
			var r := rng.randf()
			if r < 0.45:
				target = home + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			else:
				target = Vector3.INF
				_anim_to("peck" if r < 0.85 else "idle")
		if target != Vector3.INF:
			var to := target - global_position
			to.y = 0.0
			if to.length() < 0.5:
				target = Vector3.INF
				speed = 0.0
			else:
				heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-3.0 * dt))
				speed = move_toward(speed, float(spec.walk), 3.0 * dt)
		else:
			speed = move_toward(speed, 0.0, 4.0 * dt)
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	global_position += fwd * speed * dt
	_snap_ground()
	if speed > 0.05:
		var ws: float = float(vis.gait_info("walk").get("speed", 0.6)) if vis else 0.6
		_anim_to("walk", clampf(speed / maxf(ws, 0.05), 0.5, 3.0))
	elif _anim == "walk":
		_anim_to("idle")

func _takeoff(dt: float) -> void:
	_anim_to("flap", 1.2)
	speed = move_toward(speed, float(spec.fly), 10.0 * dt)
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt + Vector3(0, climb * dt, 0)
	if t_mode <= 0.0:
		mode = Mode.FLY
		t_mode = 30.0

## Cruise toward `target` (flap when climbing or slow, glide otherwise); land near it.
func _fly(dt: float) -> void:
	if target == Vector3.INF:
		target = home
	var to := target - global_position
	var hd := Vector2(to.x, to.z).length()
	var want_h := atan2(-to.x, -to.z)
	var turn := clampf(wrapf(want_h - heading, -PI, PI), -1.6 * dt, 1.6 * dt)
	heading += turn
	bank = lerpf(bank, clampf(turn / maxf(dt, 1e-4) * speed * 0.06, -0.8, 0.8), 1.0 - exp(-4.0 * dt))
	var gy := _terrain_y(global_position)
	var want_y: float = maxf(target.y, gy + float(spec.alt[0])) if hd > 25.0 else gy + 1.0
	climb = clampf((want_y - global_position.y) * 0.8, -4.0, 3.0)
	speed = move_toward(speed, float(spec.fly), 4.0 * dt)
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt + Vector3(0, climb * dt, 0)
	if global_position.y < gy + 0.5:
		global_position.y = gy + 0.5
	var flapping: bool = climb > 0.6 or speed < float(spec.fly) * 0.8 or (species == "crow" and fmod(t_mode, 3.0) > 1.0) or \
		(spec.kind == "ground" and fmod(t_mode, 4.0) > 2.5)
	_anim_to("flap" if flapping else "glide")
	if hd < 6.0 and global_position.y - gy < 2.5:
		mode = Mode.LAND
		t_mode = 0.6
		_action("land")
	elif t_mode <= 0.0:
		target = home

func _land(dt: float) -> void:
	speed = move_toward(speed, 0.0, 12.0 * dt)
	var gy := _terrain_y(global_position)
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt
	global_position.y = move_toward(global_position.y, gy, 4.0 * dt)
	if t_mode <= 0.0:
		mode = Mode.GROUND
		home = global_position
		_snap_ground()
		speed = 0.0
		t_mode = rng.randf_range(2.0, 6.0)
		_anim_to("alert")
		Game.log_event("bird_land", {"species": species})

## Raptor: thermal circles around `home`, now and then a stoop on a rabbit (or a practice stoop).
func _soar(dt: float) -> void:
	var r := 45.0
	var w := float(spec.fly) / r
	soar_phase += w * dt
	var gy := _terrain_y(home)
	var alt := gy + lerpf(spec.alt[0], spec.alt[1], 0.5 + 0.5 * sin(soar_phase * 0.15))
	var want := home + Vector3(cos(soar_phase) * r, 0, sin(soar_phase) * r)
	var to := want - global_position
	heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-2.0 * dt))
	bank = lerpf(bank, -0.35, 1.0 - exp(-2.0 * dt))
	climb = clampf((alt - global_position.y) * 0.3, -2.0, 2.0)
	speed = float(spec.fly)
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt + Vector3(0, climb * dt, 0)
	_anim_to("soar" if climb < 0.8 else "flap", 0.8)
	if t_mode <= 0.0:
		t_mode = rng.randf_range(20.0, 50.0)
		_prey = _find_prey()
		var aim: Vector3
		if _prey != null:
			aim = _prey.global_position
		else:
			aim = global_position + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40))
			aim.y = _terrain_y(aim)
		target = aim
		mode = Mode.DIVE
		dives += 1
		Game.log_event("hawk_dive", {"prey": str(_prey.get("species")) if _prey else ""})

func _find_prey() -> Node3D:
	var best: Node3D = null
	var bd := 140.0
	for a in get_tree().get_nodes_in_group("animals"):
		if a.get("alive") and str(a.get("species")) == "rabbit":
			var d := Vector2(a.global_position.x - global_position.x, a.global_position.z - global_position.z).length()
			if d < bd:
				bd = d
				best = a
	return best

func _dive(dt: float) -> void:
	if _prey != null and is_instance_valid(_prey) and _prey.get("alive"):
		target = _prey.global_position + Vector3(0, 0.2, 0)
	var to := target - global_position
	var d := to.length()
	speed = move_toward(speed, 26.0, 14.0 * dt)
	var dir := to.normalized()
	heading = lerp_angle(heading, atan2(-dir.x, -dir.z), 1.0 - exp(-5.0 * dt))
	climb = dir.y * speed
	global_position += dir * speed * dt
	bank = lerpf(bank, 0.0, 1.0 - exp(-4.0 * dt))
	_anim_to("dive")
	if d < 1.5 or global_position.y < _terrain_y(global_position) + 0.6:
		if _prey != null and is_instance_valid(_prey) and _prey.get("alive") and d < 2.5 and rng.randf() < 0.5:
			var dmg: Damageable = _prey.get("damageable")
			if dmg:
				dmg.apply_hit({"amount": 50.0, "zone": "chest", "attacker": self})
				kills += 1
				Game.log_event("predation", {"predator": species, "prey": "rabbit"})
		mode = Mode.CLIMB
		_prey = null
		target = Vector3.INF

func _climb(dt: float) -> void:
	var gy := _terrain_y(home)
	speed = move_toward(speed, float(spec.fly), 6.0 * dt)
	climb = 3.0
	var to := home - global_position
	heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-1.5 * dt))
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt + Vector3(0, climb * dt, 0)
	_anim_to("flap")
	if global_position.y > gy + float(spec.alt[0]):
		mode = Mode.SOAR

func _fall(dt: float) -> void:
	climb -= 9.81 * dt
	speed = move_toward(speed, 0.0, 3.0 * dt)
	global_position += Vector3(-sin(heading), 0, -cos(heading)) * speed * dt + Vector3(0, climb * dt, 0)
	var gy := _terrain_y(global_position)
	if global_position.y <= gy:
		global_position.y = gy
		mode = Mode.DEAD
		_anim_to("dead")
		bank = 0.0

## Visual attitude: yaw = heading, bank into turns, pitch from the climb (flight only).
func _orient(dt: float) -> void:
	var node: Node3D = vis if vis else stand_in
	if node == null:
		return
	var flying := mode in [Mode.TAKEOFF, Mode.FLY, Mode.SOAR, Mode.DIVE, Mode.CLIMB, Mode.FALLING]
	var pitch := atan2(climb, maxf(speed, 1.0)) if flying else 0.0
	var roll := bank if flying else 0.0
	var b := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	node.basis = node.basis.slerp(b.orthonormalized(), 1.0 - exp(-8.0 * dt))
