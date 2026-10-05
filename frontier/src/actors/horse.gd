class_name Horse
extends CharacterBody3D
## A rideable horse: momentum-based riding controller (turning circles grow with speed, pace control by tapping
## sprint up to a gallop, skid stops, slopes, fording/swimming, collisions that stumble or throw the rider,
## jumping), cores (health/stamina with outer bars and inner cores), fear (rears/shies at gunfire and predators),
## bonding levels that unlock moves, care state (dirt/mud/wet/sweat shown in the coat), whistle calling, hitching
## and mount/dismount on either side. Bots drive it through the rider's `intent` dict exactly like a human.
## Visual body, animation and foot IK: HorseVisual. Appearance: HorseCoats.
##
## API: Horse.spawn(seed, breed) -> Horse; mount(rider, side); dismount(side); call_to(target); hitch(pos);
## unhitch(); brush(); feed(kind); alarm(pos, radius, strength) (static, gunfire etc.); stats via `info()`.

signal mounted_by(rider: Node3D)
signal dismounted_by(rider: Node3D)
signal fell
signal spooked(kind: String)

enum State { FREE, RIDDEN, CALLED, HITCHED, FALLEN, DEAD }

const PACE_NAMES := ["walk", "trot", "canter", "gallop"]
const DEFAULT_SPEEDS := {"walk": 1.67, "trot": 3.75, "canter": 6.36, "gallop": 12.77}
const GRAVITY := 9.81
const BOND_XP := [0.0, 150.0, 450.0, 1000.0]
const MOUNT_TIME := 0.85
const SEAT_DROP := 0.78          # rider origin (feet) below the saddle seat point

static var player_horse: Horse
static var all: Array = []

var seed_value := 0
var breed := "quarter"
var coat: Dictionary = {}
var stats: Dictionary = {}
var visual: HorseVisual
var state := State.FREE
var rider: Node3D = null
var rider_side := -1.0                       # -1 left (near side), +1 right
# motion
var speed := 0.0                             # signed forward speed m/s
var yaw := 0.0
var yaw_rate := 0.0
var vy := 0.0
var airborne := false
var pace := 0                                # 0 walk .. 3 gallop (rider's request)
var gait := "idle"
var lead_right := false
var swimming := false
var water_depth := 0.0
var slope_deg := 0.0
var auto_road := false
var debug_pace := -1                         # bots: force a pace
# cores (0..100) and outer bars
var health := 100.0
var health_max := 100.0
var stamina := 100.0
var stamina_max := 100.0
var health_core := 100.0
var stamina_core := 100.0
# care, fear, bond
var dirt := 0.0
var mud := 0.0
var wet := 0.0
var sweat := 0.0
var fear := 0.0
var bond_xp := 0.0
var bond_level := 1
var saddlebags: Array = []                   # [{item, count}]
# AI / misc
var call_target: Node3D = null
var hitch_point = null                       # Vector3 or null
var stumbles := 0
var falls := 0
var record_gait := false
var gait_samples: Array = []
var distance_travelled := 0.0

var _sprint_was := false
var _last_tap := -10.0
var _mount_t := -1.0
var _mount_from := Transform3D.IDENTITY
var _rider_layers := Vector2i(0, 0)
var _cam_idle := 0.0
var _cam_target := Vector3.ZERO
var _cam_dist := 5.5
var _lead_timer := 0.0
var _idle_timer := 4.0
var _idle_kind := "idle"
var _react_cooldown := 0.0
var _flee_time := 0.0
var _flee_dir := Vector3.ZERO
var _fall_timer := 0.0
var _stuck_t := 0.0
var _stuck_anchor := Vector3.ZERO
var _ground_extra := 0.0
var _tilt := Vector2.ZERO                    # pitch, roll (smoothed)
var _vis_y := 0.0
var _t := 0.0
var _prev_pos := Vector3.ZERO
var _refuse_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _speeds := DEFAULT_SPEEDS.duplicate()          # top speed per pace (gallop from the breed)
var _anim_speeds := DEFAULT_SPEEDS.duplicate()     # authored ground speed of each gait cycle (x model scale)
var _terrain_rid := RID()

## Create a horse (not yet in the tree). breed: one of HorseCoats.BREEDS ("" = picked from the seed).
static func spawn(seed: int, breed_name: String = "") -> Horse:
	var h := Horse.new()
	h.setup(seed, breed_name)
	return h

func setup(seed: int, breed_name: String = "") -> void:
	seed_value = seed
	_rng.seed = hash(seed * 31 + 5)
	if breed_name == "" or not HorseCoats.BREEDS.has(breed_name):
		var names := HorseCoats.breed_names()
		breed_name = names[_rng.randi_range(0, names.size() - 1)]
	breed = breed_name
	stats = HorseCoats.breed(breed).duplicate()
	coat = HorseCoats.roll(seed, breed)
	health_max = stats.health
	health = health_max
	stamina_max = stats.stamina
	stamina = stamina_max
	name = "Horse_%s_%d" % [breed, seed]
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 2.1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.x = PI * 0.5
	cs.position = Vector3(0, 1.2, 0.0)
	add_child(cs)
	var neck := CollisionShape3D.new()
	var ns := SphereShape3D.new()
	ns.radius = 0.3
	neck.shape = ns
	neck.position = Vector3(0, 1.75, -1.15)
	add_child(neck)
	visual = HorseVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(coat)
	visual.scale = Vector3.ONE * float(stats.scale)
	if visual.ik:
		visual.ik.ground_fn = ground_at
	for g in PACE_NAMES:
		var info := visual.gait_info(g)
		var sp: float = float(info.get("speed", DEFAULT_SPEEDS[g])) * float(stats.scale)
		_speeds[g] = sp
		_anim_speeds[g] = sp
	_speeds["gallop"] = float(stats.speed)

func _ready() -> void:
	all.append(self)
	yaw = rotation.y
	_prev_pos = global_position
	_cam_target = global_position + Vector3(0, 2.3, 0)
	if Game.terrain != null and Game.terrain.get("_coll_body") != null:
		add_collision_exception_with(Game.terrain._coll_body)
	InputSetup.ensure()

func _exit_tree() -> void:
	all.erase(self)
	if player_horse == self:
		player_horse = null

## Top speed of a pace (m/s) for this horse.
func pace_speed(p: int) -> float:
	return _speeds[PACE_NAMES[clampi(p, 0, 3)]]

func info() -> Dictionary:
	return {"breed": breed, "coat": coat.get("name", ""), "health": health, "stamina": stamina, "health_core": health_core,
		"stamina_core": stamina_core, "bond": bond_level, "dirt": dirt, "mud": mud, "fear": fear, "speed": speed,
		"gait": gait, "state": State.keys()[state]}

# ================================================================== ground
## Ground height under (x, z): terrain heightmap (+ a cached offset when standing on a structure); 0 with no world.
func ground_at(x: float, z: float) -> float:
	if Game.world == null:
		return 0.0
	return Game.world.height(x, z) + _ground_extra

func _probe_structure() -> void:
	# a structure (bridge, porch) under the horse: raycast against non-terrain colliders
	_ground_extra = 0.0
	if Game.world == null or not is_inside_tree():
		return
	var p := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.6, 0), p + Vector3(0, -1.5, 0))
	q.collision_mask = 1
	var ex: Array[RID] = [get_rid()]
	if Game.terrain != null and Game.terrain.get("_coll_body") != null:
		ex.append(Game.terrain._coll_body.get_rid())
	if rider is CollisionObject3D:
		ex.append(rider.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var th := Game.world.height(p.x, p.z)
		if hit.position.y > th + 0.05 and hit.normal.y > 0.7:
			_ground_extra = hit.position.y - th

# ================================================================== main loop
func _physics_process(dt: float) -> void:
	_t += dt
	_react_cooldown = maxf(_react_cooldown - dt, 0.0)
	_refuse_cd = maxf(_refuse_cd - dt, 0.0)
	if state == State.DEAD:
		_settle_dead(dt)
		return
	if state == State.FALLEN:
		_fallen(dt)
		return
	var ctl := _control(dt)          # {dir: Vector3 (world, may be ZERO), speed: target, brake: bool, jump: bool}
	_steer(ctl, dt)
	_move(dt)
	_vertical(ctl, dt)
	_cores(dt)
	_care(dt)
	_fear_update(dt)
	_animate(dt)
	if record_gait and visual != null:
		var s := {"t": _t, "pos": {}, "ground": {}}
		for leg in ["LF", "RF", "LH", "RH"]:
			var p := visual.sole_world(leg)
			s.pos[leg] = p
			s.ground[leg] = ground_at(p.x, p.z)
		gait_samples.append(s)

func _process(dt: float) -> void:
	if state == State.RIDDEN and rider != null:
		_place_rider(dt)
		if rider.get("camera") != null and rider.camera != null and not (rider.get("bot_driven") and Game.args.has("bot_no_cam")):
			_ride_camera(dt)
	elif rider == null and player_horse == self and Game.player != null and Game.player.get("on_horse") == null:
		if not Game.player.get("bot_driven") and Input.is_action_just_pressed("whistle"):
			call_to(Game.player)
	if rider == null and Game.player != null and Game.player.get("on_horse") == null and not Game.player.get("bot_driven"):
		if Input.is_action_just_pressed("mount") and global_position.distance_to(Game.player.global_position) < 2.8:
			if _nearest_to_player():
				mount(Game.player)

func _nearest_to_player() -> bool:
	var best: Horse = null
	var bd := INF
	for h in all:
		if h.rider == null and h.state != State.DEAD:
			var d: float = h.global_position.distance_to(Game.player.global_position)
			if d < bd:
				bd = d
				best = h
	return best == self

# ================================================================== control (rider / AI)
func _control(dt: float) -> Dictionary:
	var c := {"dir": Vector3.ZERO, "speed": 0.0, "brake": false, "jump": false}
	var fwd := forward()
	if state == State.RIDDEN and rider != null and _mount_t < 0.0:
		var it: Dictionary = rider.intent
		if not rider.get("bot_driven"):
			_read_rider_input(dt)
		var mv: Vector2 = it.get("move", Vector2.ZERO)
		var sprint: bool = it.get("sprint", false)
		if sprint and not _sprint_was:
			pace = mini(pace + 1, 3)
			_last_tap = _t
		_sprint_was = sprint
		if sprint:
			_last_tap = _t                              # holding the button keeps the pace up
		if pace == 3 and _t - _last_tap > 2.6:
			pace = 2                                    # stop pushing: settle back into a canter
		if it.get("walk", false):
			pace = 0
		if debug_pace >= 0:
			pace = debug_pace
		var cam_yaw: float = rider.get("cam_yaw") if rider.get("cam_yaw") != null else yaw
		var want := Vector3.ZERO
		if mv.length() > 0.12:
			want = (Basis(Vector3.UP, cam_yaw) * Vector3(mv.x, 0, -mv.y)).normalized()
		if auto_road and (mv.length() < 0.12 or mv.y > 0.5):
			var rd := _road_direction()
			if rd != Vector3.ZERO:
				want = rd
				pace = maxi(pace, 1)
		if want != Vector3.ZERO:
			if want.dot(fwd) < -0.55 and absf(speed) > 0.6 and not auto_road:
				c.brake = true
			elif want.dot(fwd) < -0.55 and absf(speed) <= 0.6:
				c.dir = -want                               # back up: keep facing, move backwards
				c.speed = -1.0
			else:
				c.dir = want
				c.speed = pace_speed(pace) * clampf(mv.length() * 1.2, 0.35, 1.0) if not auto_road else pace_speed(pace)
		else:
			if pace > 0 and _t - _last_tap > 1.0:
				pace = 0
		c.jump = it.get("jump", false)
		it["jump"] = false
		if c.jump and absf(speed) < 0.5 and bond_level >= 3:
			c.jump = false
			_try_action("rear")
	elif state == State.CALLED and call_target != null and is_instance_valid(call_target):
		var to := call_target.global_position - global_position
		to.y = 0
		var d := to.length()
		if d < 3.2:
			state = State.FREE
			call_target = null
		else:
			c.dir = _avoid(to.normalized())
			c.speed = pace_speed(3 if d > 40.0 else (2 if d > 14.0 else (1 if d > 6.0 else 0)))
			_unstick(dt, d)
	elif state == State.HITCHED and hitch_point != null:
		var to: Vector3 = hitch_point - global_position
		to.y = 0
		if to.length() > 1.4:
			c.dir = to.normalized()
			c.speed = pace_speed(0)
	elif _flee_time > 0.0:
		_flee_time -= dt
		c.dir = _avoid(_flee_dir)
		c.speed = pace_speed(3) * 0.85
	if not stamina_ok() and c.speed > pace_speed(2):
		c.speed = pace_speed(2)
	return c

func _read_rider_input(dt: float) -> void:
	var it: Dictionary = rider.intent
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	it["move"] = Vector2(mv.x, -mv.y)
	it["sprint"] = Input.is_action_pressed("sprint")
	if Input.is_action_just_pressed("jump"):
		it["jump"] = true
	if Input.is_action_just_pressed("walk_toggle"):
		it["walk"] = not it.get("walk", false)
	if Input.is_action_just_pressed("ride_auto"):
		auto_road = not auto_road
		Game.say("Following the road" if auto_road else "Riding free", 2.0)
	if Input.is_action_just_pressed("mount"):
		dismount()
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.05:
		rider.cam_yaw -= look.x * 2.6 * dt
		rider.cam_pitch = clampf(rider.cam_pitch - look.y * 1.8 * dt, -1.1, 0.7)
		_cam_idle = 0.0

func stamina_ok() -> bool:
	return stamina > 4.0

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

## Probe ahead for steep ground / water / obstacles and bend the desired direction away (AI and calls).
func _avoid(dir: Vector3) -> Vector3:
	if Game.world == null:
		return dir
	var best := dir
	var best_s := -INF
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var d := dir.rotated(Vector3.UP, a)
		var p := global_position + d * 6.0
		var h0 := ground_at(global_position.x, global_position.z)
		var h1 := ground_at(p.x, p.z)
		var sl := rad_to_deg(atan2(absf(h1 - h0), 6.0))
		var s := d.dot(dir) - (2.0 if sl > 32.0 else 0.0) - (1.5 if Game.world.water_level(p.x, p.z) > h1 + 1.2 else 0.0)
		if s > best_s:
			best_s = s
			best = d
	return best

func _unstick(dt: float, dist: float) -> void:
	_stuck_t += dt
	if _stuck_t > 5.0:
		if global_position.distance_to(_stuck_anchor) < 2.0 and call_target != null:
			# stuck while called: come round by another way (teleport out of view toward the caller)
			var tp := call_target.global_position + (global_position - call_target.global_position).normalized() * minf(dist, 25.0)
			tp.y = ground_at(tp.x, tp.z)
			global_position = tp
		_stuck_t = 0.0
		_stuck_anchor = global_position

# ================================================================== steering, speed, movement
func _steer(c: Dictionary, dt: float) -> void:
	var fwd := forward()
	var handling: float = stats.get("handling", 1.0)
	var v := absf(speed)
	# turning circle grows with speed: r = 1.2 + 0.12 v^2  ->  yaw rate = v / r (in-place turn when slow)
	var radius := 1.2 + 0.12 * v * v
	var max_rate := (v / radius if v > 0.6 else 1.5) * handling
	max_rate = maxf(max_rate, 0.5 if v > 8.0 else 0.9)
	var want_rate := 0.0
	var dir: Vector3 = c.dir
	if dir != Vector3.ZERO:
		var face := dir if c.speed >= 0.0 else -dir
		var err := wrapf(atan2(-face.x, -face.z) - yaw, -PI, PI)
		want_rate = clampf(err * 3.0, -max_rate, max_rate)
	yaw_rate = move_toward(yaw_rate, want_rate, 4.0 * dt)
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	rotation.y = yaw
	# target speed with slope, water, fear and stamina factors
	var target: float = c.speed
	if dir == Vector3.ZERO:
		target = 0.0
	elif c.speed > 0.0:
		var align := clampf(forward().dot(dir), 0.0, 1.0)
		target *= lerpf(0.35, 1.0, align)          # slow into sharp turns
	slope_deg = _slope_ahead(signf(target) if target != 0.0 else 1.0)
	if target > 0.0:
		if slope_deg > 40.0 or slope_deg < -48.0:
			target = 0.0
			if _refuse_cd <= 0.0 and v > 1.0:
				_refuse_cd = 3.0
				_try_action("refuse")
				if rider == Game.player:
					Game.say("Too steep for your horse", 2.0)
		elif slope_deg > 0.0:
			target *= clampf(1.0 - slope_deg / 45.0 * 0.75, 0.25, 1.0)
		else:
			target *= clampf(1.0 + slope_deg / 60.0 * 0.5, 0.55, 1.05)
	if water_depth > 0.35 and not swimming:
		target = minf(target, lerpf(pace_speed(2), pace_speed(0), clampf((water_depth - 0.35) / 1.0, 0.0, 1.0)))
	if swimming:
		target = clampf(target, -0.5, 2.2)
	var accel: float = stats.get("accel", 4.5)
	var rate := accel if absf(target) > absf(speed) else 5.5
	if c.brake:
		target = 0.0
		rate = 9.0
		if bond_level >= 2 and speed > pace_speed(2) * 0.9:
			rate = 14.0
			_try_action("skid_stop")
	if airborne:
		rate = 0.0
	speed = move_toward(speed, target, rate * dt)

func _slope_ahead(sgn: float) -> float:
	if Game.world == null:
		return 0.0
	var f := forward() * sgn
	var p := global_position
	var hf := ground_at(p.x + f.x * 1.2, p.z + f.z * 1.2)
	var hb := ground_at(p.x - f.x * 1.0, p.z - f.z * 1.0)
	return rad_to_deg(atan2(hf - hb, 2.2))

func _move(dt: float) -> void:
	var fwd := forward()
	var pre := speed
	velocity = fwd * speed
	velocity.y = 0.0
	move_and_slide()
	var hit_wall := 0.0
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if n.y < 0.6:
			hit_wall = maxf(hit_wall, -fwd.dot(n) * absf(pre))
	if hit_wall > 7.0:
		_fall("collision")
	elif hit_wall > 3.5:
		_stumble()
	var moved := global_position - _prev_pos
	moved.y = 0.0
	if hit_wall > 0.5:
		speed = signf(speed) * minf(absf(speed), moved.length() / maxf(dt, 1e-4))
	distance_travelled += moved.length()
	if state == State.RIDDEN:
		bond_xp += moved.length() * 0.02
	_prev_pos = global_position

func _vertical(c: Dictionary, dt: float) -> void:
	var p := global_position
	if int(_t * 60.0) % 6 == 0:
		_probe_structure()
	var g := ground_at(p.x, p.z)
	var wl := Game.world.water_level(p.x, p.z) if Game.world != null else -INF
	water_depth = maxf(wl - g, 0.0)
	var was_swim := swimming
	swimming = water_depth > (1.25 if was_swim else 1.45)
	var floor_y := g
	if swimming:
		floor_y = maxf(g, wl - 1.05)
	if c.jump and not airborne and not swimming and _mount_t < 0.0:
		if absf(speed) > 2.5 and stamina > 10.0:
			vy = 4.7
			airborne = true
			stamina -= 6.0
			visual.play_action("jump")
	if airborne:
		vy -= GRAVITY * dt
		p.y += vy * dt
		if p.y <= floor_y and vy <= 0.0:
			p.y = floor_y
			airborne = false
			if vy < -9.5:
				var dmg := (-vy - 9.5) * 9.0
				health -= dmg
				_stumble()
			vy = 0.0
	else:
		if p.y > floor_y + 0.6 and not swimming:
			airborne = true                       # ran off a drop
			vy = 0.0
		else:
			p.y = lerpf(p.y, floor_y, 1.0 - exp(-18.0 * dt)) if absf(p.y - floor_y) < 0.6 else floor_y
	global_position = p
	_update_tilt(dt)

## Body pitch/roll and height from the ground under the four hooves (plus a lean into turns).
func _update_tilt(dt: float) -> void:
	if visual == null:
		return
	var g := {}
	var avg := 0.0
	for leg in ["LF", "RF", "LH", "RH"]:
		var sp := visual.sole_world(leg)
		g[leg] = ground_at(sp.x, sp.z)
		avg += g[leg]
	avg *= 0.25
	var front: float = (g.LF + g.RF) * 0.5
	var hind: float = (g.LH + g.RH) * 0.5
	var left: float = (g.LF + g.LH) * 0.5
	var right: float = (g.RF + g.RH) * 0.5
	var pitch := atan2(front - hind, 1.25 * float(stats.scale))
	var roll := atan2(left - right, 0.28) * 0.3
	if swimming or airborne:
		pitch = 0.0 if swimming else _tilt.x
		roll = 0.0
	var lean := clampf(-yaw_rate * absf(speed) * 0.03, -0.2, 0.2)
	_tilt.x = lerpf(_tilt.x, clampf(pitch, -0.6, 0.6), 1.0 - exp(-8.0 * dt))
	_tilt.y = lerpf(_tilt.y, clampf(roll, -0.15, 0.15) + lean, 1.0 - exp(-6.0 * dt))
	visual.rotation = Vector3(_tilt.x, 0.0, _tilt.y)
	var target_y := 0.0 if (swimming or airborne) else avg - global_position.y - 0.01
	_vis_y = lerpf(_vis_y, clampf(target_y, -0.4, 0.4), 1.0 - exp(-12.0 * dt))
	visual.position.y = _vis_y

# ================================================================== animation
func _animate(dt: float) -> void:
	if visual == null:
		return
	var v := absf(speed)
	var st := gait
	var walk_s: float = _anim_speeds.walk
	var trot_s: float = _anim_speeds.trot
	var cant_s: float = _anim_speeds.canter
	var gal_s: float = _anim_speeds.gallop
	var t1 := (walk_s + trot_s) * 0.5 + 0.35
	var t2 := (trot_s + cant_s) * 0.5
	var t3 := (cant_s + float(_speeds.gallop)) * 0.5 - 0.6
	var up := 1.05
	var dn := 0.92
	if swimming:
		st = "swim"
	elif v < 0.25:
		st = "idle" if absf(yaw_rate) < 0.35 else "walk"
	else:
		match gait:
			"walk", "idle", "swim":
				st = "walk"
				if v > t1 * up: st = "trot"
			"trot":
				st = "trot"
				if v > t2 * up: st = "canter"
				elif v < t1 * dn: st = "walk"
			"canter":
				st = "canter"
				if v > t3 * up: st = "gallop"
				elif v < t2 * dn: st = "trot"
			"gallop":
				st = "gallop"
				if v < t3 * dn: st = "canter"
			_:
				st = "walk"
		if v > t3 * 1.3 and st != "gallop":
			st = "gallop"
		elif v > t2 * 1.25 and st in ["walk", "trot"]:
			st = "canter"
	gait = st
	# lead follows the turn direction (flying change after a sustained turn)
	if gait in ["canter", "gallop"]:
		var want_right := yaw_rate < -0.12
		var want_left := yaw_rate > 0.12
		if (want_right and not lead_right) or (want_left and lead_right):
			_lead_timer += dt
			if _lead_timer > 0.5:
				lead_right = want_right
				_lead_timer = 0.0
		else:
			_lead_timer = 0.0
	var anim := gait
	if gait in ["canter", "gallop"] and lead_right:
		anim += "_r"
	var ts := 1.0
	match gait:
		"idle":
			anim = _idle_variant(dt)
		"walk":
			ts = clampf(v / walk_s, 0.55, 1.6) if v >= 0.25 else 0.7
			if speed < -0.1:
				ts = -ts
		"trot":
			ts = clampf(v / trot_s, 0.6, 1.5)
		"canter":
			ts = clampf(v / cant_s, 0.6, 1.5)
		"gallop":
			ts = clampf(v / gal_s, 0.6, 1.35)
		"swim":
			ts = 0.7
	visual.set_locomotion(anim, ts)
	visual.set_motion_amount(clampf(v / 12.0, 0.0, 1.0))
	visual.set_care(dirt, mud, wet, sweat)

func _idle_variant(dt: float) -> String:
	_idle_timer -= dt
	if _idle_timer <= 0.0:
		_idle_timer = _rng.randf_range(6.0, 14.0)
		var r := _rng.randf()
		if state == State.RIDDEN:
			_idle_kind = "idle"
		else:
			_idle_kind = "idle" if r < 0.45 else ("idle_rest" if r < 0.75 else "graze")
		if _rng.randf() < 0.5:
			_try_action(["head_shake", "ear_flick", "tail_swish"][_rng.randi_range(0, 2)])
	return _idle_kind

func _try_action(a: String) -> bool:
	if visual == null or visual.action_playing():
		return false
	return visual.play_action(a)

# ================================================================== cores, care, fear, bond
func _cores(dt: float) -> void:
	var v := absf(speed)
	var drain := 0.0
	if v > pace_speed(2) * 1.15:
		drain = 2.8 * 100.0 / stamina_max             # ~35 s of flat-out gallop on a full bar
	if swimming:
		drain += 3.0
	if drain > 0.0:
		stamina = maxf(stamina - drain * dt, 0.0)
		stamina_core = maxf(stamina_core - drain * 0.01 * dt, 0.0)
	else:
		var regen := (2.0 + 4.0 * stamina_core / 100.0) * (0.45 if v > pace_speed(1) * 1.2 else 1.0)
		stamina = minf(stamina + regen * dt, stamina_max)
	stamina_core = maxf(stamina_core - dt * 0.008, 0.0)
	health_core = maxf(health_core - dt * 0.004, 0.0)
	health = minf(health + 0.3 * health_core / 100.0 * dt, health_max)
	if health <= 0.0 and state != State.DEAD:
		die()
	var lvl := 1
	for i in BOND_XP.size():
		if bond_xp >= BOND_XP[i]:
			lvl = i + 1
	bond_level = lvl

func _care(dt: float) -> void:
	var v := absf(speed)
	var moved := v * dt
	dirt = minf(dirt + moved * 0.00025, 1.0)
	var wet_ground := 0.0
	if Game.world != null:
		var c := Game.world.ctrl(global_position.x, global_position.z)
		wet_ground = clampf(c.g - 0.55, 0.0, 1.0) * 2.0
		if Game.sky != null and Game.sky.get("wet") != null:
			wet_ground = maxf(wet_ground, float(Game.sky.wet))
	if water_depth > 0.05 and water_depth < 1.0:
		mud = minf(mud + moved * 0.02, 1.0)
	elif wet_ground > 0.2:
		mud = minf(mud + moved * 0.004 * wet_ground, 1.0)
	if water_depth > 0.6:
		wet = 1.0
		mud = maxf(mud - dt * 0.05 * clampf(water_depth - 0.6, 0.0, 1.0), 0.0)
		dirt = maxf(dirt - dt * 0.02, 0.0)
	else:
		wet = maxf(wet - dt / 150.0, 0.0)
	sweat = clampf(sweat + (dt * 0.04 if v > pace_speed(2) * 1.1 else -dt * 0.01), 0.0, 1.0)

## Brush the horse: clears dirt and mud, builds bond.
func brush() -> void:
	dirt = 0.0
	mud = 0.0
	sweat = 0.0
	bond_xp += 15.0
	fear = maxf(fear - 0.3, 0.0)
	_try_action("head_shake")

## Feed the horse: "hay" (stamina core), "oats" (both), "carrot"/"apple" (small, bond), "tonic" (outer bars).
func feed(kind: String = "carrot") -> void:
	match kind:
		"hay": stamina_core = minf(stamina_core + 40.0, 100.0)
		"oats":
			stamina_core = minf(stamina_core + 30.0, 100.0)
			health_core = minf(health_core + 30.0, 100.0)
		"tonic":
			stamina = stamina_max
			health = minf(health + 50.0, health_max)
		_:
			stamina_core = minf(stamina_core + 12.0, 100.0)
			health_core = minf(health_core + 8.0, 100.0)
	bond_xp += 10.0

## Something frightening at `pos` (gunfire 1.0, explosion 2.0, predator 0.6): every horse in range gets scared.
static func alarm(pos: Vector3, radius: float = 40.0, strength: float = 1.0, kind: String = "gunfire") -> void:
	for h in all:
		if not is_instance_valid(h):
			continue
		var d: float = h.global_position.distance_to(pos)
		if d < radius:
			h._frighten(strength * (1.0 - d / radius) * (1.3 - 0.15 * h.bond_level), pos, kind)

func _frighten(amount: float, from: Vector3, kind: String) -> void:
	fear = clampf(fear + amount, 0.0, 1.5)
	if fear > 0.7 and _react_cooldown <= 0.0 and state != State.DEAD and state != State.FALLEN:
		_react_cooldown = 4.0
		spooked.emit(kind)
		if state == State.RIDDEN:
			if _try_action("rear"):
				speed *= 0.3
				if bond_level <= 1 and _rng.randf() < 0.35:
					_throw_rider()
		else:
			_try_action("shy")
			_flee_dir = (global_position - from)
			_flee_dir.y = 0
			_flee_dir = _flee_dir.normalized() if _flee_dir.length() > 0.1 else -forward()
			_flee_time = 4.0 + fear * 2.0

func _fear_update(dt: float) -> void:
	fear = maxf(fear - dt * 0.22, 0.0)
	if int(_t * 2.0) != int((_t - dt) * 2.0):
		for n in get_tree().get_nodes_in_group("predator"):
			if n is Node3D and n.global_position.distance_to(global_position) < 25.0:
				_frighten(0.35, n.global_position, "predator")

# ================================================================== falls, stumbles, death
func _stumble() -> void:
	stumbles += 1
	speed *= 0.2
	_try_action("stumble")
	Game.log_event("horse_stumble", {"speed": speed})

func _fall(why: String) -> void:
	falls += 1
	Game.log_event("horse_fall", {"why": why})
	fell.emit()
	_throw_rider()
	state = State.FALLEN
	_fall_timer = 2.4
	speed = 0.0
	health -= 15.0
	visual.set_locomotion("fallen", 1.0)

func _fallen(dt: float) -> void:
	_fall_timer -= dt
	if _fall_timer <= 0.0:
		state = State.FREE
		visual.play_action("getup")

func die() -> void:
	_throw_rider()
	state = State.DEAD
	speed = 0.0
	visual.set_locomotion("dead", 1.0)

func _settle_dead(dt: float) -> void:
	var p := global_position
	p.y = lerpf(p.y, ground_at(p.x, p.z), 1.0 - exp(-6.0 * dt))
	global_position = p

func _throw_rider() -> void:
	if rider == null:
		return
	var r := rider
	dismount(rider_side, true)
	if r is CharacterBody3D:
		r.velocity = forward() * maxf(absf(speed) * 0.6, 2.0) + Vector3(0, 3.0, 0)

# ================================================================== calling, hitching
## Whistle: the horse comes to `target` (paths around steep ground/water; teleports closer if far or stuck).
func call_to(target: Node3D) -> void:
	if state == State.DEAD or state == State.RIDDEN:
		return
	unhitch()
	var d := global_position.distance_to(target.global_position)
	if d > 160.0:
		var away := (global_position - target.global_position)
		away.y = 0
		var tp := target.global_position + away.normalized() * 60.0
		tp.y = ground_at(tp.x, tp.z)
		global_position = tp
		if Game.terrain != null:
			Game.terrain.ensure_collision_at(tp)
	call_target = target
	state = State.CALLED
	_stuck_anchor = global_position
	_stuck_t = 0.0

func hitch(pos: Vector3) -> void:
	hitch_point = pos
	state = State.HITCHED

func unhitch() -> void:
	hitch_point = null
	if state == State.HITCHED:
		state = State.FREE

# ================================================================== mounting
## Mount from the left (side -1) or right (+1); side 0 picks the side the rider stands on.
func mount(r: Node3D, side: float = 0.0) -> bool:
	if rider != null or state == State.DEAD or state == State.FALLEN:
		return false
	if side == 0.0:
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		side = 1.0 if (r.global_position - global_position).dot(right) > 0.0 else -1.0
	rider = r
	rider_side = side
	unhitch()
	state = State.RIDDEN
	call_target = null
	_flee_time = 0.0
	speed = 0.0
	pace = 0
	if r is CollisionObject3D:
		_rider_layers = Vector2i(r.collision_layer, r.collision_mask)
		r.collision_layer = 0
		r.collision_mask = 0
		add_collision_exception_with(r)
	if r is CharacterBody3D:
		r.velocity = Vector3.ZERO
	r.set("on_horse", self)
	if r.get("cam_yaw") != null:
		r.cam_yaw = yaw
	var side_pt := global_transform * Vector3(side * 0.85, 0.0, -0.1)
	side_pt.y = ground_at(side_pt.x, side_pt.z)
	_mount_from = Transform3D(Basis(Vector3.UP, yaw), side_pt)
	_mount_t = 0.0
	if r.has_signal("mounted"):
		r.emit_signal("mounted", self)
	mounted_by.emit(r)
	Game.log_event("horse_mount", {"side": "right" if side > 0 else "left"})
	return true

## Get off on the given side (-1 left, +1 right; 0 = the side mounted from), falling back to the other side
## when that side is blocked or too steep.
func dismount(side: float = 0.0, thrown := false) -> bool:
	if rider == null:
		return false
	var r := rider
	if side == 0.0:
		side = rider_side
	var pt := _dismount_point(side)
	if pt == Vector3.INF:
		pt = _dismount_point(-side)
	if pt == Vector3.INF:
		pt = global_position + Vector3(0, 0, 0) + forward() * -2.6
		pt.y = ground_at(pt.x, pt.z)
	rider = null
	_mount_t = -1.0
	state = State.FREE
	speed = speed if thrown else 0.0
	pace = 0
	auto_road = false
	r.global_position = pt + Vector3(0, 0.05, 0)
	r.rotation = Vector3.ZERO
	if r is CollisionObject3D:
		r.collision_layer = _rider_layers.x if _rider_layers.x != 0 else 2
		r.collision_mask = _rider_layers.y if _rider_layers.y != 0 else 5
		remove_collision_exception_with(r)
	r.set("on_horse", null)
	if r.get("facing") != null:
		r.facing = yaw
	if r.has_signal("dismounted"):
		r.emit_signal("dismounted")
	dismounted_by.emit(r)
	# auto-hitch near a post
	for post in get_tree().get_nodes_in_group("hitching_post"):
		if post is Node3D and post.global_position.distance_to(global_position) < 5.0:
			hitch(post.global_position)
			break
	return true

func _dismount_point(side: float) -> Vector3:
	var pt := global_transform * Vector3(side * 1.05, 0.0, 0.0)
	pt.y = ground_at(pt.x, pt.z)
	if absf(pt.y - global_position.y) > 0.9:
		return Vector3.INF
	if Game.world != null and Game.world.is_water(pt.x, pt.z) and Game.world.water_level(pt.x, pt.z) - pt.y > 1.0:
		return Vector3.INF
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.6
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, pt + Vector3(0, 1.0, 0))
		q.collision_mask = 1
		var ex: Array[RID] = [get_rid()]
		if Game.terrain != null and Game.terrain.get("_coll_body") != null:
			ex.append(Game.terrain._coll_body.get_rid())
		q.exclude = ex
		if not space.intersect_shape(q, 1).is_empty():
			return Vector3.INF
	return pt

func _place_rider(dt: float) -> void:
	var seat := visual.seat_transform()
	var target := Transform3D(seat.basis.orthonormalized(), seat.origin - seat.basis.y.normalized() * SEAT_DROP)
	if _mount_t >= 0.0:
		_mount_t += dt
		var f := clampf(_mount_t / MOUNT_TIME, 0.0, 1.0)
		var e := f * f * (3.0 - 2.0 * f)
		var mid := _mount_from.interpolate_with(target, e)
		mid.origin.y += sin(e * PI) * 0.35
		rider.global_transform = mid
		if f >= 1.0:
			_mount_t = -1.0
	else:
		rider.global_transform = target
	var vis = rider.get("visual")
	if vis != null:
		vis.rotation = Vector3.ZERO
		if vis.has_method("set_locomotion"):
			vis.set_locomotion(absf(speed), "ride", true)

func _ride_camera(dt: float) -> void:
	var cam: Camera3D = rider.camera
	_cam_idle += dt
	if Input.get_last_mouse_velocity().length() > 1.0:
		_cam_idle = 0.0
	var moving := absf(speed) > 1.0
	if moving and _cam_idle > 1.5:
		rider.cam_yaw = lerp_angle(rider.cam_yaw, yaw, 1.0 - exp(-1.6 * dt))
		rider.cam_pitch = lerpf(rider.cam_pitch, -0.16, 1.0 - exp(-1.0 * dt))
	var want_dist := 5.4 + clampf(absf(speed) - 4.0, 0.0, 9.0) * 0.18
	var pivot := global_position + Vector3(0, 2.35 + _vis_y, 0)
	_cam_target = _cam_target.lerp(pivot, 1.0 - exp(-10.0 * dt))
	var basis := Basis(Vector3.UP, rider.cam_yaw) * Basis(Vector3.RIGHT, rider.cam_pitch)
	var back := basis * Vector3(0.0, 0.25, want_dist)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_cam_target, _cam_target + back)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	var d := back.length()
	if not hit.is_empty():
		d = maxf(_cam_target.distance_to(hit.position) - 0.3, 1.2)
	_cam_dist = lerpf(_cam_dist, d, 1.0 - exp(-(18.0 if d < _cam_dist else 4.0) * dt))
	var pos := _cam_target + back.normalized() * _cam_dist
	if Game.world != null:
		pos.y = maxf(pos.y, ground_at(pos.x, pos.z) + 0.4)
	cam.global_position = pos
	cam.global_basis = basis
	cam.fov = lerpf(cam.fov, 62.0 + clampf(absf(speed) - 5.0, 0.0, 8.0) * 1.2, 1.0 - exp(-4.0 * dt))

# ================================================================== roads
static var _road_segs: Array = []

static func _roads() -> Array:
	if _road_segs.is_empty() and Game.world != null:
		for r in Game.world.features.get("roads", []):
			var pts: Array = r.points
			for i in range(pts.size() - 1):
				_road_segs.append([Vector2(pts[i][0], pts[i][1]), Vector2(pts[i + 1][0], pts[i + 1][1])])
	return _road_segs

## Direction along the nearest road (the way the horse is already heading), aiming 12 m ahead.
func _road_direction() -> Vector3:
	var p := Vector2(global_position.x, global_position.z)
	var best_d := 60.0
	var best: Array = []
	var best_t := 0.0
	for s in _roads():
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if absf(a.x - p.x) > 90.0 and absf(b.x - p.x) > 90.0:
			continue
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = s
			best_t = t
	if best.is_empty():
		return Vector3.ZERO
	var a2: Vector2 = best[0]
	var b2: Vector2 = best[1]
	var dir := (b2 - a2).normalized()
	var f := Vector2(forward().x, forward().z)
	if dir.dot(f) < 0.0:
		dir = -dir
	var closest := a2 + (b2 - a2) * best_t
	var aim := closest + dir * 12.0
	var to := aim - p
	return Vector3(to.x, 0, to.y).normalized()
