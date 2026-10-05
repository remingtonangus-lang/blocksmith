extends Node
## NPC behaviour. One brain per Human; the role picks the behaviour set:
## - civilians: daily routine (src/ai/routine.gd when the town provides spots, else wander near home), greet/stare
##   at the player, flee or cower from gunfire, report crimes to the law.
## - gunmen (shale, bandit, syndicate, law in combat): perception (sight cone + hearing), threat memory, cover
##   search by raycasts (blocked when crouched, clear when standing to peek), peek-and-shoot bursts, reloads in
##   cover, flanking, suppression, retreat/surrender when broken, group target sharing.
## The brain only writes the body's `intent`; the body moves and shoots.

enum State { IDLE, ROUTINE, ALERT, COMBAT, FLEE, COWER, SURRENDER, DEAD, REPORT, WATCH }

const SERIOUS := ["murder", "murder_lawman", "assault", "robbery"]

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
# town life (src/ai/routine.gd, set by population.gd) and reactions
var routine: TownRoutine = null
var calm_t := 0.0               # FLEE/COWER/WATCH/REPORT/ALERT wear off back to the routine
var flee_goal := Vector3.INF     # a doorway to run inside through when shooting starts
var report_to: Node3D = null
var report_pos := Vector3.ZERO
var report_kind := ""
var watch_pos := Vector3.INF
var watch_spot := Vector3.INF
var nudge_t := 0.0
var nudge_to := Vector3.ZERO
var react_t := 0.0
var looking := false
var surrender_t := 0.0
var _last_state := -1

func setup(b: Human, opts: Dictionary) -> void:
	body = b
	home = b.global_position
	rng.seed = b.seed
	skill = float(opts.get("skill", 0.35 + rng.randf() * 0.4))
	bravery = float(opts.get("bravery", 0.4 + rng.randf() * 0.5))
	aggressive = bool(opts.get("aggressive", b.faction in ["shale", "bandit"]))
	state = State.ROUTINE if b.faction in ["civilian", "law"] else State.IDLE
	think_t = rng.randf() * 0.3
	_last_state = state
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
	if state != _last_state:
		_state_changed(_last_state, state)
		_last_state = state
	match state:
		State.IDLE, State.ROUTINE:
			_routine(dt)
		State.REPORT:
			_report(dt)
		State.WATCH:
			_watch(dt)
		State.ALERT:
			_alert(dt)
		State.COMBAT:
			_combat(dt)
		State.FLEE:
			_flee(dt)
		State.COWER, State.SURRENDER:
			body.intent.move_to = null
			body.intent.crouch = true
			_calm(dt)
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
		if state in [State.IDLE, State.ROUTINE, State.ALERT, State.WATCH, State.REPORT]:
			target_last_seen = pos
			if source != null and source is Node3D:
				target = source
			flee_goal = _shelter(pos) if routine != null else Vector3.INF
			if flee_goal == Vector3.INF and rng.randf() > bravery and d < 25.0:
				state = State.COWER
			else:
				state = State.FLEE
			_alarm_bark(source)
			Game.log_event("npc_react", {"npc": str(body.name), "react": State.keys()[state]})
		calm_t = maxf(calm_t, rng.randf_range(22.0, 40.0))
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
	if routine != null:
		routine.interrupt()
	if Game.population and Game.main and Game.main.settlements and Game.main.settlements.town_at(body.global_position, 10.0) != "":
		Game.population.queue_spectacle(body.global_position)
	for a in group:
		if is_instance_valid(a) and a.alive:
			a.brain.bravery -= 0.15

func on_stuck() -> void:
	cover = Vector3.INF
	wander_t = 0.0
	if state == State.FLEE and flee_goal != Vector3.INF:
		flee_goal = Vector3.INF          # the doorway is blocked: just run

# ------------------------------------------------------------------ town reactions

func _state_changed(a: int, b: int) -> void:
	var v = body.visual
	if routine != null:
		if a in [State.IDLE, State.ROUTINE] and not b in [State.IDLE, State.ROUTINE]:
			routine.interrupt()
		elif b == State.ROUTINE and not a in [State.IDLE, State.ROUTINE]:
			routine.resume()
	if v.has_method("set_activity"):
		v.set_activity("idle_crouch" if b == State.COWER else "")
	if b in [State.FLEE, State.COWER, State.REPORT, State.WATCH, State.ALERT, State.SURRENDER] and calm_t <= 0.0:
		calm_t = rng.randf_range(22.0, 40.0)
	if b == State.SURRENDER:
		surrender_t = 0.0
	if b != State.ROUTINE and looking and v.has_method("clear_look"):
		v.clear_look()
		looking = false
	body.intent.crouch = false

## FLEE/COWER/WATCH/REPORT/SURRENDER end after a quiet spell; back to the day's routine.
func _calm(dt: float) -> void:
	if state == State.SURRENDER:
		# held up but never robbed: once Ruth lowers her gun and steps away, they bolt
		var aimed: bool = Game.player != null and Game.player.get("intent") != null and Game.player.intent.get("aim", false)
		if not aimed and Game.player != null and body.global_position.distance_to(Game.player.global_position) > 6.0:
			surrender_t += dt
		if surrender_t > 10.0:
			state = State.FLEE
			calm_t = rng.randf_range(20.0, 30.0)
		return
	calm_t -= dt
	if calm_t <= 0.0 and body.faction in ["civilian", "law"]:
		flee_goal = Vector3.INF
		state = State.ROUTINE

## Nearest doorway (door_in spot of an enterable building) to run inside through, away from the shooting.
func _shelter(threat: Vector3) -> Vector3:
	var st = Game.main.settlements if Game.main else null
	if st == null or not Game.population or not Game.population.nav_ready(str(routine.res.town)):
		return Vector3.INF
	var my := body.global_position
	var away := my - threat
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.ZERO
	var best := Vector3.INF
	var bs := INF
	for sp in st.spots(str(routine.res.town), "door_in"):
		var o: Vector3 = sp.transform.origin
		var d := o.distance_to(my)
		if d > 45.0 or o.distance_to(threat) < 6.0:
			continue
		var dir := (o - my)
		dir.y = 0.0
		var score := d - (dir.normalized().dot(away) * 10.0 if dir.length() > 0.1 else 0.0)
		if score < bs:
			bs = score
			best = o + sp.transform.basis.z * -1.2        # a step past the doorway, inside
	return best

func _alarm_bark(source: Node) -> void:
	if Game.population == null or not Game.population.can_bark(body.global_position, 2.5):
		return
	var vt := str(body.get_meta("voice_type", "man_town"))
	var line := ("alarm_run__" if source == Game.player and rng.randf() < 0.5 else "alarm_gunfire__") + vt
	if Game.audio and Game.audio.voice_lines.has(line):
		Game.audio.play_voice(line, body)
	elif Game.audio:
		Game.audio.bark("alarm", body)

## WorldState.crime -> witnesses: civilians run to tell the law; lawmen answer.
func on_witness(kind: String, pos: Vector3) -> void:
	if not body.alive or state in [State.DEAD, State.SURRENDER]:
		return
	var serious := kind in SERIOUS
	if body.faction == "law":
		_law_respond(kind, pos)
		return
	if body.faction != "civilian" or state == State.COMBAT:
		return
	if not serious and rng.randf() > 0.4:
		calm_t = maxf(calm_t, 10.0)
		if state in [State.IDLE, State.ROUTINE] and Game.player:
			_look_at_player(true)
		return
	report_to = _nearest_law()
	report_pos = pos
	report_kind = kind
	if report_to == null and _sheriff_door() == Vector3.INF:
		if state in [State.IDLE, State.ROUTINE]:
			state = State.FLEE
		return
	state = State.REPORT
	calm_t = 60.0
	if Game.population and Game.population.can_bark(body.global_position, 2.0):
		var line := "alarm_sheriff__" + str(body.get_meta("voice_type", "man_town"))
		if Game.audio.voice_lines.has(line):
			Game.audio.play_voice(line, body)
		else:
			Game.audio.bark("alarm", body)
	Game.log_event("npc_report", {"npc": str(body.name), "kind": kind})

func _nearest_law() -> Node3D:
	var best: Node3D = null
	var bd := 260.0
	for h in get_tree().get_nodes_in_group("humans"):
		if h != body and h.alive and h.faction == "law":
			var d: float = h.global_position.distance_to(body.global_position)
			if d < bd:
				bd = d
				best = h
	return best

## Where the sheriff's office door is (a witness with no lawman in sight runs there).
func _sheriff_door() -> Vector3:
	if routine == null or Game.population == null:
		return Vector3.INF
	var idx: Dictionary = Game.population.index.get(str(routine.res.town), {})
	var sb: String = idx.get("sheriff", "")
	if sb == "":
		return Vector3.INF
	for sp in idx.buildings[sb].spots:
		if sp.type == "door_out":
			return sp.transform.origin
	return Vector3.INF

func _report(_dt: float) -> void:
	var goal := Vector3.INF
	if report_to != null and is_instance_valid(report_to) and report_to.alive:
		goal = report_to.global_position
	else:
		report_to = null
		goal = _sheriff_door()
	if goal == Vector3.INF:
		state = State.FLEE
		return
	body.intent.move_to = goal
	body.intent.speed = Human.JOG
	body.intent.aim_at = null
	if body.global_position.distance_to(goal) < 3.0:
		if report_to != null and report_to.brain.has_method("on_report"):
			report_to.brain.on_report(report_pos, report_kind, body)
		if Game.population:
			Game.population.stat("reports", 1)
		body.intent.face = goal - body.global_position
		if body.visual.has_method("gesture"):
			body.visual.gesture("talk_directions")
		calm_t = 8.0
		state = State.COWER if rng.randf() < 0.3 else State.ROUTINE
		if state == State.ROUTINE:
			calm_t = 0.0

## A witness tells this lawman what happened.
func on_report(pos: Vector3, kind: String, _who: Node) -> void:
	_law_respond(kind, pos)

func _law_respond(kind: String, pos: Vector3) -> void:
	if state == State.COMBAT:
		return
	var p = Game.player
	if kind in SERIOUS and p != null and is_instance_valid(p) and p.global_position.distance_to(body.global_position) < 90.0:
		aggressive = true
		target = p
		target_last_seen = p.global_position
		target_seen_t = 0.0
		_enter_combat()
		if Game.population and Game.population.can_bark(body.global_position, 1.5):
			Game.audio.play_voice("law_arrest__lawman", body) if Game.audio.voice_lines.has("law_arrest__lawman") else Game.audio.bark("lawman", body)
		return
	target = p if p != null else null
	target_last_seen = pos
	target_seen_t = 0.0
	state = State.ALERT
	calm_t = 20.0
	if Game.population and Game.population.can_bark(body.global_position, 2.0):
		var line := "law_holster__lawman" if kind == "brandish" else "law_easy__lawman"
		if Game.audio.voice_lines.has(line):
			Game.audio.play_voice(line, body)

## Ruth walked into me.
func on_bumped(p: Node3D) -> void:
	if state != State.ROUTINE or not body.alive:
		return
	if Game.population:
		Game.population.stat("nudges", 1)
	var away := body.global_position - p.global_position
	away.y = 0.0
	var pv: Vector3 = p.velocity
	pv.y = 0.0
	var side := pv.normalized().cross(Vector3.UP)
	if side.dot(away) < 0.0:
		side = -side
	if not body.anchored:
		nudge_to = body.global_position + side.normalized() * 1.1 + away.normalized() * 0.3
		nudge_t = 1.2
	_look_at_player(true)
	if Game.population and Game.population.can_bark(body.global_position, 4.0) and rng.randf() < 0.6:
		var vt := str(body.get_meta("voice_type", "man_town"))
		var line := "insult_stare__" + vt
		if Game.audio.voice_lines.has(line):
			Game.audio.play_voice(line, body)
		else:
			Game.audio.bark("greeting", body)

## Gather round a spectacle (a body in the street, a fight) at a few metres and watch.
func watch(pos: Vector3, seconds: float) -> void:
	if body.faction != "civilian" or not state in [State.IDLE, State.ROUTINE] or body.has_meta("child"):
		return
	if routine != null and routine.busy_seated() and body.global_position.distance_to(pos) > 15.0:
		return
	watch_pos = pos
	var a := atan2(body.global_position.x - pos.x, body.global_position.z - pos.z) + rng.randf_range(-0.5, 0.5)
	var r := rng.randf_range(4.0, 7.0)
	watch_spot = pos + Vector3(sin(a) * r, 0.0, cos(a) * r)
	if Game.population:
		var s: Vector3 = Game.population.snap(watch_spot)
		if s != Vector3.INF:
			watch_spot = s
		Game.population.stat("crowd", 1)
	state = State.WATCH
	calm_t = seconds

func _watch(dt: float) -> void:
	calm_t -= dt
	var my := body.global_position
	if Vector2(watch_spot.x - my.x, watch_spot.z - my.z).length() > 0.8:
		body.intent.move_to = watch_spot
		body.intent.speed = Human.WALK
		body.intent.face = null
	else:
		body.intent.move_to = null
		body.intent.face = watch_pos - my
		if body.visual.has_method("look_at_point") and not looking:
			body.visual.look_at_point(watch_pos + Vector3(0, 0.3, 0), 0.7)
			looking = true
			if body.visual.has_method("set_activity"):
				body.visual.set_activity(["idle_wait", "talk_1", "idle_shift"][rng.randi() % 3])
	if calm_t <= 0.0:
		state = State.ROUTINE

func _look_at_player(on: bool) -> void:
	var v = body.visual
	if on and Game.player and v.has_method("look_at_node"):
		v.look_at_node(Game.player, 0.65)
		looking = true
	elif not on and looking and v.has_method("clear_look"):
		v.clear_look()
		looking = false

## People notice Ruth: look at her, greet her (once in a while), back off from a drawn gun.
func _react_to_player() -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var to: Vector3 = p.global_position - body.global_position
	var d := to.length()
	var key := str(body.get_meta("resident", ""))
	var drawn: bool = p.get("gun") != null and p.gun.drawn
	var aiming: bool = p.get("intent") != null and p.intent.get("aim", false)
	# a drawn, levelled gun close by: civilians cower or run inside, lawmen tell her to holster it
	if aiming and d < 12.0 and _visible(p):
		var aim_dir: Vector3 = p.aim_ray().dir if p.has_method("aim_ray") else -p.global_transform.basis.z
		var off := aim_dir.normalized().dot((-to).normalized())
		if body.faction == "law":
			if d < 10.0:
				_law_respond("brandish", p.global_position)
			return
		if off > 0.8 or d < 6.0:
			if Game.population:
				Game.population.remember(key, "threatened")
			flee_goal = _shelter(p.global_position) if routine != null and rng.randf() < 0.5 else Vector3.INF
			state = State.FLEE if flee_goal != Vector3.INF or rng.randf() < 0.4 else State.COWER
			target_last_seen = p.global_position
			calm_t = rng.randf_range(20.0, 35.0)
			if Game.population and Game.population.can_bark(body.global_position, 2.5):
				var line := "hands_dont_shoot__" + str(body.get_meta("voice_type", "man_town"))
				if Game.audio.voice_lines.has(line):
					Game.audio.play_voice(line, body)
				else:
					Game.audio.bark("hands_up", body)
			return
	if d < 7.0 and _visible(p):
		if not looking:
			_look_at_player(true)
		if body.faction == "law" and drawn and Game.population and Game.population.since(key, "warned") > 2.0 \
				and Game.population.can_bark(body.global_position, 3.0):
			Game.population.remember(key, "warned")
			if Game.audio.voice_lines.has("law_holster__lawman"):
				Game.audio.play_voice("law_holster__lawman", body)
			return
		if d < 5.0 and Game.population and Game.population.since(key, "greeted") > 6.0 and rng.randf() < 0.5:
			_greet(key, d)
	elif looking and d > 9.0:
		_look_at_player(false)

func _greet(key: String, _d: float) -> void:
	var pop = Game.population
	if not pop.can_bark(body.global_position, 3.0):
		return
	pop.remember(key, "greeted")
	pop.stat("greetings", 1)
	var vt := str(body.get_meta("voice_type", "man_town"))
	var h: float = Game.sky.hours if Game.sky else 10.0
	var wary: bool = pop.since(key, "threatened") < 24.0 or (Game.state != null and float(Game.state.get("standing")) < -40.0)
	var bases: Array
	if wary:
		bases = ["insult_stare", "insult_back", "threat_walk"]
	elif vt == "shopkeeper" and routine != null and routine.block.get("kind", "") == "work":
		bases = ["shop_help", "greet_maam", "greet_new_face"]
	elif h < 11.5:
		bases = ["greet_morning", "greet_howdy", "greet_hat"]
	elif h < 18.0:
		bases = ["greet_maam", "greet_fine_day", "greet_howdy", "greet_hat", "greet_new_face"]
	else:
		bases = ["greet_howdy", "greet_hat"]
	bases.shuffle()
	var said := false
	for b in bases:
		var line := "%s__%s" % [b, vt]
		if Game.audio.voice_lines.has(line):
			Game.audio.play_voice(line, body)
			said = true
			break
	if not said:
		Game.audio.bark("greeting" if not wary else "insult", body)
	if not wary and body.visual.has_method("gesture") and not (routine != null and routine.busy_seated()) and rng.randf() < 0.6:
		body.visual.gesture("wave")

# ------------------------------------------------------------------ behaviours
func _routine(dt: float) -> void:
	body.intent.aim_at = null
	body.intent.crouch = false
	body.gun.drawn = false
	if routine != null:
		react_t -= dt
		if react_t <= 0.0:
			react_t = 0.35
			_react_to_player()
			if state != State.ROUTINE and state != State.IDLE:
				return
		if nudge_t > 0.0:
			nudge_t -= dt
			body.intent.move_to = nudge_to
			body.intent.speed = Human.WALK
			if nudge_t <= 0.0:
				body.intent.move_to = null
			return
		routine.tick(dt)
		return
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
	body.intent.move_to = target_last_seen if body.global_position.distance_to(target_last_seen) > 6.0 else null
	body.intent.speed = Human.WALK
	body.gun.drawn = true
	if target != null and is_instance_valid(target) and target == Game.player and body.faction == "law" and not aggressive:
		target_last_seen = target.global_position         # keeps her covered, doesn't shoot
	body.intent.aim_at = target_last_seen + Vector3(0, 1.3, 0)
	if body.faction == "law" and routine != null:
		calm_t -= dt
		if calm_t <= 0.0:
			state = State.ROUTINE
			return
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
			peek_t = rng.randf_range(1.0, 2.5) + suppress
	else:
		body.intent.crouch = cover != Vector3.INF
		if body.gun.clip.get(body.gun.weapon_id(), 0) < 2:
			body.gun.start_reload()
		if peek_t <= 0.0 and not body.gun.reloading:
			peeking = true
			burst = rng.randi_range(1, 3)
			aim_t = 0.0
			peek_t = rng.randf_range(2.0, 3.5)

func _try_shoot(_dt: float, tp: Vector3, scale: float) -> bool:
	if target_seen_t > 1.5 or combat_t < lerpf(1.6, 0.7, skill):
		return false
	# accuracy: distance, target speed, skill, suppression; first shots of an engagement are less accurate
	var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	var warmup := lerpf(2.2, 1.0, clampf(combat_t / 8.0, 0.0, 1.0))
	var dist := body.global_position.distance_to(tp)
	var s := scale * lerpf(4.0, 1.6, skill) * warmup * (1.0 + tv.length() * 0.15) * (1.0 + suppress * 0.6) * (1.0 + dist / 60.0)
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

func _flee(dt: float) -> void:
	if flee_goal != Vector3.INF:
		# run inside through the nearest doorway and hide there
		body.intent.move_to = flee_goal
		body.intent.speed = Human.SPRINT if body.global_position.distance_to(flee_goal) > 4.0 else Human.JOG
		body.intent.aim_at = null
		body.intent.crouch = false
		body.gun.drawn = false
		if Vector2(flee_goal.x - body.global_position.x, flee_goal.z - body.global_position.z).length() < 0.9:
			flee_goal = Vector3.INF
			state = State.COWER
			if Game.population:
				Game.population.stat("fled_inside", 1)
		return
	if routine != null:
		calm_t -= dt
		if calm_t <= 0.0:
			state = State.ROUTINE
			return
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
