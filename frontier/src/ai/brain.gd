extends Node
## NPC behaviour. One brain per Human; the role picks the behaviour set:
## - civilians: daily routine (src/ai/routine.gd when the town provides spots, else wander near home), greet/stare
##   at the player, flee or cower from gunfire, report crimes to the law.
## - gunmen (shale, bandit, syndicate, law in combat): perception (sight cone + hearing), threat memory, cover
##   search by raycasts (blocked when crouched, clear when standing to peek), peek-and-shoot bursts, reloads in
##   cover, flanking, suppression, retreat/surrender when broken, group target sharing.
## The brain only writes the body's `intent`; the body moves and shoots.

enum State { IDLE, ROUTINE, ALERT, COMBAT, FLEE, COWER, SURRENDER, DEAD }

const HOSTILE := {
	"shale": ["player", "outfit", "law", "civilian_defender"],
	"bandit": ["player", "outfit", "law"],
	"syndicate": [],
	"law": [],
	"civilian": [],
	"outfit": ["shale", "bandit"],
}

var body: Human
var state: int = State.IDLE
var home := Vector3.ZERO
var target: Node3D = null
var target_last_seen := Vector3.ZERO
var target_seen_t := 999.0
var cover := Vector3.INF
var cover_t := 0.0
var peek_t := 0.0
var peeking := false
var burst := 0
var aim_t := 0.0
var flank_t := 0.0
var suppress := 0.0
var think_t := 0.0
var skill := 0.5               # 0 poor .. 1 sharpshooter
var bravery := 0.6
var aggressive := false         # starts hostile to the player (bandits/Shales on missions)
var wander_t := 0.0
var rng := RandomNumberGenerator.new()
var group: Array = []          # allies sharing targets
var sight_range := 80.0
var debug_state := ""
var combat_t := 0.0             # seconds since this engagement started (reaction time, warm-up inaccuracy)

func setup(b: Human, opts: Dictionary) -> void:
	body = b
	home = b.global_position
	rng.seed = b.seed
	skill = float(opts.get("skill", 0.35 + rng.randf() * 0.4))
	bravery = float(opts.get("bravery", 0.4 + rng.randf() * 0.5))
	aggressive = bool(opts.get("aggressive", b.faction in ["shale", "bandit"]))
	state = State.ROUTINE if b.faction in ["civilian", "law"] else State.IDLE
	think_t = rng.randf() * 0.3
	Game.noise.connect(_on_noise)

func _physics_process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_physics_process_impl(dt)
	Game.acc("brain", _pt0)

func _physics_process_impl(dt: float) -> void:
	if body == null or not body.alive:
		return
	think_t -= dt
	suppress = maxf(suppress - dt * 0.6, 0.0)
	target_seen_t += dt
	if think_t <= 0.0:
		think_t = 0.2
		_perceive()
	match state:
		State.IDLE, State.ROUTINE:
			_routine(dt)
		State.ALERT:
			_alert(dt)
		State.COMBAT:
			_combat(dt)
		State.FLEE:
			_flee(dt)
		State.COWER, State.SURRENDER:
			body.intent.move_to = null
			body.intent.crouch = true
	debug_state = State.keys()[state]

# ------------------------------------------------------------------ perception
func is_hostile_to(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var f := "player" if n == Game.player else str(n.get("faction"))
	if f == "player" and aggressive:
		return true
	return f in HOSTILE.get(body.faction, [])

func _visible(n: Node3D) -> bool:
	var eye := body.global_position + Vector3(0, 1.6, 0)
	var tp := n.global_position + Vector3(0, 1.3, 0)
	var to := tp - eye
	var dist := to.length()
	var range := sight_range * (0.45 if Game.sky and Game.sky.is_night() else 1.0)
	if dist > range:
		return false
	var fwd := Vector3(-sin(body.facing), 0, -cos(body.facing))
	if state != State.COMBAT and fwd.dot(to.normalized()) < cos(deg_to_rad(70.0)) and dist > 6.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, tp, 1)
	q.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _perceive() -> void:
	var cands: Array = []
	if Game.player and is_instance_valid(Game.player):
		cands.append(Game.player)
	for n in get_tree().get_nodes_in_group("humans"):
		if n != body and n.alive:
			cands.append(n)
	var best: Node3D = null
	var bd := INF
	for c in cands:
		if not is_hostile_to(c):
			continue
		var d := body.global_position.distance_to(c.global_position)
		if d < bd and _visible(c):
			bd = d
			best = c
	if best != null:
		target = best
		target_last_seen = best.global_position
		target_seen_t = 0.0
		if state in [State.IDLE, State.ROUTINE, State.ALERT]:
			_enter_combat()
		for a in group:
			if is_instance_valid(a) and a.alive and a.brain.target == null:
				a.brain.share_target(best)

func share_target(t: Node3D) -> void:
	target = t
	target_last_seen = t.global_position
	target_seen_t = 0.5
	if state in [State.IDLE, State.ROUTINE, State.ALERT]:
		_enter_combat()

func _on_noise(pos: Vector3, radius: float, source: Node) -> void:
	if body == null or not body.alive or source == body:
		return
	var d := body.global_position.distance_to(pos)
	if d > radius:
		return
	if body.faction in ["civilian"]:
		if state in [State.IDLE, State.ROUTINE, State.ALERT]:
			state = State.COWER if rng.randf() > bravery and d < 25.0 else State.FLEE
			Game.log_event("npc_react", {"npc": str(body.name), "react": State.keys()[state]})
		return
	if source != null and is_hostile_to(source):
		target = source as Node3D
		target_last_seen = pos
		target_seen_t = 1.0
		if state in [State.IDLE, State.ROUTINE]:
			state = State.ALERT
	if d < 6.0 and state == State.COMBAT:
		suppress = minf(suppress + 0.5, 2.0)

func on_damaged(info: Dictionary) -> void:
	var att = info.get("attacker")
	if att != null and att != body:
		target = att
		target_last_seen = att.global_position
		target_seen_t = 0.0
		if body.faction == "civilian":
			state = State.FLEE
		elif state != State.COMBAT:
			_enter_combat()
	suppress = 2.0
	if body.damageable.health < 30.0 and rng.randf() > bravery:
		state = State.SURRENDER if rng.randf() < 0.4 else State.FLEE

func on_died(_info: Dictionary) -> void:
	state = State.DEAD
	for a in group:
		if is_instance_valid(a) and a.alive:
			a.brain.bravery -= 0.15

func on_stuck() -> void:
	cover = Vector3.INF
	wander_t = 0.0

# ------------------------------------------------------------------ behaviours
func _routine(dt: float) -> void:
	body.intent.aim_at = null
	body.intent.crouch = false
	body.gun.drawn = false
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(6.0, 18.0)
		if rng.randf() < 0.6:
			var p := home + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			body.intent.move_to = p
			body.intent.speed = Human.WALK
		else:
			body.intent.move_to = null
	# look at the player when close (people notice a stranger)
	if Game.player and body.global_position.distance_to(Game.player.global_position) < 6.0:
		body.intent.face = Game.player.global_position - body.global_position
	else:
		body.intent.face = null

func _alert(dt: float) -> void:
	body.intent.move_to = target_last_seen
	body.intent.speed = Human.WALK
	body.gun.drawn = true
	body.intent.aim_at = target_last_seen + Vector3(0, 1.3, 0)
	if target_seen_t > 20.0:
		state = State.ROUTINE

func _enter_combat() -> void:
	state = State.COMBAT
	combat_t = 0.0
	cover = Vector3.INF
	flank_t = rng.randf_range(8.0, 16.0)
	body.gun.drawn = true
	Game.log_event("npc_combat", {"npc": str(body.name), "target": str(target.name) if target else ""})

func _combat(dt: float) -> void:
	if target == null or not is_instance_valid(target) or (target.get("alive") == false) or \
		(target == Game.player and Game.player.damageable and not Game.player.damageable.alive):
		target = null
		state = State.ALERT if target_seen_t < 10.0 else State.ROUTINE
		return
	if target_seen_t > 25.0:
		state = State.ALERT
		return
	var my := body.global_position
	var tp := target.global_position
	var dist := my.distance_to(tp)
	flank_t -= dt
	combat_t += dt
	# point-blank: fight in the open
	if dist < 5.0:
		body.intent.move_to = my + (my - tp).normalized().rotated(Vector3.UP, 1.2) * 3.0
		body.intent.speed = Human.JOG
		body.intent.crouch = false
		_try_shoot(dt, tp, 1.3)
		return
	# need cover?
	cover_t -= dt
	if cover == Vector3.INF or cover_t <= 0.0 or flank_t <= 0.0 or not _cover_still_good(cover, tp):
		var flank := flank_t <= 0.0
		cover = _find_cover(tp, flank)
		cover_t = 6.0
		if flank:
			flank_t = rng.randf_range(10.0, 20.0)
	if cover != Vector3.INF and my.distance_to(cover) > 1.0:
		# move to cover; shoot on the move only if steady
		body.intent.move_to = cover
		body.intent.speed = Human.SPRINT if my.distance_to(cover) > 6.0 else Human.JOG
		body.intent.crouch = false
		body.intent.aim_at = tp + Vector3(0, 1.2, 0)
		if rng.randf() < 0.01 + skill * 0.01:
			_try_shoot(dt, tp, 2.5)
		return
	# in cover (or none found): peek-and-shoot cycle
	body.intent.move_to = null
	peek_t -= dt
	if peeking:
		body.intent.crouch = false
		body.intent.aim_at = tp + Vector3(0, 1.2, 0)
		aim_t += dt
		if aim_t > lerpf(1.0, 0.45, skill) and burst > 0:
			if _try_shoot(dt, tp, 1.0):
				burst -= 1
				aim_t = lerpf(0.5, 0.25, skill)
		if burst <= 0 or peek_t <= 0.0 or suppress > 1.2:
			peeking = false
			peek_t = rng.randf_range(0.8, 1.8) + suppress * 0.7
	else:
		body.intent.crouch = cover != Vector3.INF
		if body.gun.clip.get(body.gun.weapon_id(), 0) < 2:
			body.gun.start_reload()
		if peek_t <= 0.0 and not body.gun.reloading:
			peeking = true
			burst = rng.randi_range(2, 4)
			aim_t = 0.0
			peek_t = rng.randf_range(2.5, 4.0)

func _try_shoot(_dt: float, tp: Vector3, scale: float) -> bool:
	if target_seen_t > 1.5 or combat_t < lerpf(1.6, 0.7, skill):
		return false
	# accuracy: distance, target speed, skill, suppression; first shots of an engagement are less accurate
	var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	var warmup := lerpf(2.2, 1.0, clampf(combat_t / 8.0, 0.0, 1.0))
	var dist := body.global_position.distance_to(tp)
	# tuned so a steady target at 25-40 m is hit roughly one shot in four by an average gunman: a real threat,
	# survivable because Ruth's damage scale and regen are generous
	var s := scale * lerpf(2.4, 1.0, skill) * warmup * (1.0 + tv.length() * 0.12) * (1.0 + suppress * 0.5) * (1.0 + dist / 90.0)
	var aim_point := tp + Vector3(0, rng.randf_range(0.9, 1.5), 0) + tv * 0.08
	return body.shoot_at(aim_point, s)

func _cover_still_good(c: Vector3, tp: Vector3) -> bool:
	return _blocked(c + Vector3(0, 0.9, 0), tp + Vector3(0, 1.2, 0))

func _blocked(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.position.distance_to(b) > 0.8

## Cover candidates on rings around the body: crouched view of the target blocked, standing view clear (peekable),
## walkable ground, preferred range 8-35 m, flanking prefers positions rotated around the target.
func _find_cover(tp: Vector3, flank: bool) -> Vector3:
	var my := body.global_position
	var w: WorldData = Game.world
	var best := Vector3.INF
	var best_s := -INF
	var base_ang := atan2(my.x - tp.x, my.z - tp.z)
	for ring in [4.0, 8.0, 13.0]:
		for i in 10:
			var a := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
			var c := my + Vector3(sin(a) * ring, 0, cos(a) * ring)
			c.y = w.height(c.x, c.z)
			if w.is_water(c.x, c.z) or (1.0 - w.normal(c.x, c.z).y) > 0.4:
				continue
			var low := _blocked(c + Vector3(0, 0.9, 0), tp + Vector3(0, 1.2, 0))
			if not low:
				continue
			var high := not _blocked(c + Vector3(0, 1.6, 0), tp + Vector3(0, 1.4, 0))
			var d := c.distance_to(tp)
			var s := (2.0 if high else 0.6) - absf(d - 18.0) * 0.05 - c.distance_to(my) * 0.08
			if flank:
				var ang := atan2(c.x - tp.x, c.z - tp.z)
				s += absf(angle_difference(ang, base_ang)) * 1.5
			if s > best_s:
				best_s = s
				best = c
	return best

func _flee(_dt: float) -> void:
	var from := target_last_seen if target != null else body.global_position + Vector3(1, 0, 0)
	var away := (body.global_position - from)
	away.y = 0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	body.intent.move_to = body.global_position + away.normalized() * 15.0
	body.intent.speed = Human.SPRINT
	body.intent.aim_at = null
	body.intent.crouch = false
	body.gun.drawn = false
	if body.global_position.distance_to(from) > 120.0:
		state = State.ROUTINE
		home = body.global_position
