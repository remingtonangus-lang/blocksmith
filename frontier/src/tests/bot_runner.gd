extends Node
## Automated play: bots drive the real player through the same `intent` interface a human uses, while oracles
## watch every physics tick. Writes a JSON report (and prints a summary line per bot) and exits non-zero on any
## failed oracle.
##   --bot road      ride/walk the road network from town to town (default)
##   --bot explore   wander between random reachable points (curiosity)
##   --bot ride      mount the player's horse and ride town to town along a road at canter/gallop (horse_bot.gd)
##   --bot gaits     ride each gait on a road, gait oracle (footfall beats/order) + foot-slide metric
##   --bot all       every bot in sequence
##   --seconds N     time per bot (default 90)
##   --report PATH   JSON report path (default user://bot_report.json)
##   --benchmark     scripted camera + player route, frame-time percentiles + memory to benchmark.json
## Oracles: script/shader errors, NaN transform, below terrain / fell out of world, out of bounds, stuck while
## trying to move, long free fall, frame spikes (> 100 ms after warmup), health dropping without cause.

var main: Node
var player
var report := {"bots": [], "ok": true}
var _frame_ms: PackedFloat32Array = []
var _last_t := 0
var _spikes := 0
var _recording := false

func run(m: Node) -> void:
	main = m
	if Game.args.has("prof"):
		add_child(load("res://src/tests/_prof.gd").new())
	player = Game.player
	player.bot_driven = true
	await get_tree().process_frame
	await get_tree().physics_frame
	if Game.args.has("benchmark"):
		await _benchmark()
		get_tree().quit(0)
		return
	var which := str(Game.args.get("bot", "road"))
	var seconds := Game.arg_f("seconds", 90.0)
	var bots: Array = ["road", "explore", "ride", "gaits", "town", "gunfight", "hunt", "birds", "ecology", "horsework", "missions", "camp", "encounters", "social", "openworld", "presentation", "living", "systems", "ui", "footik", "cover", "melee", "armory", "archetypes", "lasso", "disarm"] if which == "all" or which == "true" else Array(which.split(","))
	for b in bots:
		var res: Dictionary
		if b == "ride" or b == "gaits" or b == "horsework":
			var hb = load("res://src/tests/horse_bot.gd").new()
			add_child(hb)
			res = await hb.run(b, seconds, self)
			hb.queue_free()
		elif b == "missions":
			res = await _run_missions()
		elif b == "camp":
			res = await _run_camp()
		elif b == "encounters":
			res = await _run_encounters()
		elif b == "social":
			res = await _run_social()
		elif b == "openworld":
			res = await _run_openworld()
		elif b == "presentation":
			res = await _run_presentation()
		elif b == "living":
			res = await _run_living()
		elif b == "town":
			res = await _run_town(seconds)
		elif b == "hunt":
			res = await load("res://src/tests/hunt_bot.gd").run(self, seconds)
		elif b == "ecology":
			res = await load("res://src/tests/ecology_bot.gd").run(self, seconds)
		elif b == "birds":
			res = await load("res://src/tests/bird_bot.gd").run(self, seconds)
		elif b == "systems":
			res = await load("res://src/tests/systems_bot.gd").run(self)
		elif b == "disarm":
			res = await load("res://src/tests/disarm_bot.gd").run(self)
		elif b == "lasso":
			res = await load("res://src/tests/lasso_bot.gd").run(self)
		elif b == "archetypes":
			res = await load("res://src/tests/archetype_bot.gd").run(self)
		elif b == "armory":
			res = await load("res://src/tests/armory_bot.gd").run(self)
		elif b == "melee":
			res = await load("res://src/tests/melee_bot.gd").run(self)
		elif b == "cover":
			res = await load("res://src/tests/cover_bot.gd").run(self)
		elif b == "footik":
			res = await load("res://src/tests/foot_ik_bot.gd").run(self)
		elif b == "ui":
			res = await load("res://src/tests/ui_bot.gd").run(self)
		elif b == "gunfight":
			res = await load("res://src/tests/combat_bot.gd").run(self, seconds)
			print("  gunfight: enemies %d engaged %d cover %d killed %d | player shots %d hits %d, hits taken %d, %.0f s" % [
				res.enemies, res.engaged, res.used_cover, res.killed, res.player_shots, res.player_hits, res.player_hits_taken, res.duration])
		else:
			res = await _run_bot(b, seconds)
		report.bots.append(res)
		if not res.ok:
			report.ok = false
		var line := "BOT %s: %s  errors=%d" % [b, "PASS" if res.ok else "FAIL", res.errors.size()]
		if float(res.get("distance", 0.0)) > 0.0:
			line += "  dist=%.0f m  stuck=%d  falls=%d  spikes=%d  avg_ms=%.1f  p99_ms=%.1f" % [res.distance, res.stuck_events,
				res.fall_events, res.frame_spikes, res.get("frame_avg_ms", 0.0), res.get("frame_p99_ms", 0.0)]
		line += _metrics(res)
		print(line)
		for f in res.failures:
			print("  oracle: ", f)
	var path := str(Game.args.get("report", "user://bot_report.json"))
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(report, "  "))
	print("BOTS %s -> %s" % ["PASS" if report.ok else "FAIL", ProjectSettings.globalize_path(path)])
	get_tree().quit(0 if report.ok else 1)

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _recording and _last_t > 0:
		var ms := (now - _last_t) / 1000.0
		_frame_ms.append(ms)
		if ms > 100.0:
			_spikes += 1
	_last_t = now

# ------------------------------------------------------------------ bots
func _route_for(kind: String) -> Array:
	var w: WorldData = Game.world
	var pts := []
	if kind == "road":
		# follow the first road out of Bitter Spring end to end
		for r in w.features.roads:
			if r.a == "bitter_spring" and r.b == "halvorsen_ranch":
				for p in r.points:
					pts.append(Vector3(p[0], p[2], p[1]))
				break
		if pts.is_empty() and w.features.roads.size() > 0:
			for p in w.features.roads[0].points:
				pts.append(Vector3(p[0], p[2], p[1]))
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Game.args.get("seed", 7))
		var start: Vector3 = player.global_position
		var cur := start
		for i in 12:
			for attempt in 20:
				var c := cur + Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-120, 120))
				c.y = w.height(c.x, c.z)
				if w.in_bounds(c.x, c.z, 200.0) and not w.is_water(c.x, c.z) and (1.0 - w.normal(c.x, c.z).y) < 0.3:
					pts.append(c)
					cur = c
					break
	return pts

func _run_bot(kind: String, seconds: float) -> Dictionary:
	var w: WorldData = Game.world
	var route := _route_for(kind)
	var res := {"bot": kind, "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "waypoints_reached": 0, "waypoints": route.size()}
	if route.is_empty():
		res.ok = false
		res.failures.append("no route")
		return res
	# start at the first waypoint
	var start: Vector3 = route[0]
	start.y = w.height(start.x, start.z) + 1.0
	Game.terrain.ensure_collision_at(start)
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.health = 100.0
	await get_tree().physics_frame
	_frame_ms = PackedFloat32Array()
	_spikes = 0
	var warm := 0
	var t := 0.0
	var wp := 1
	var last_pos: Vector3 = player.global_position
	var stuck_t := 0.0
	var stuck_anchor: Vector3 = player.global_position
	var air_t := 0.0
	var health0: float = player.health
	var err0: int = Game.error_logger.take().size()
	while t < seconds and wp < route.size():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		warm += 1
		_recording = warm > 120
		var pos: Vector3 = player.global_position
		var target: Vector3 = route[wp]
		var to := Vector3(target.x - pos.x, 0, target.z - pos.z)
		if to.length() < 4.0:
			wp += 1
			res.waypoints_reached += 1
			continue
		# steer: camera yaw toward target, push stick forward, jog (sprint on long straights when stamina allows)
		var yaw := atan2(-to.x, -to.z)
		player.cam_yaw = lerp_angle(player.cam_yaw, yaw, 0.2)
		player.intent.move = Vector2(0, 1)
		player.intent.sprint = player.stamina > 40.0 and to.length() > 30.0
		player.intent.jump = false
		res.distance += pos.distance_to(last_pos)
		last_pos = pos
		# --- oracles
		if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
			_fail(res, "NaN position at t=%.1f" % t)
			break
		var gy := w.height(pos.x, pos.z)
		if pos.y < gy - 1.5:
			_fail(res, "below terrain at (%.0f, %.1f, %.0f), ground %.1f" % [pos.x, pos.y, pos.z, gy])
			res.fall_events += 1
			break
		if not w.in_bounds(pos.x, pos.z):
			_fail(res, "left the map at (%.0f, %.0f)" % [pos.x, pos.z])
			break
		if not player.is_on_floor():
			air_t += dt
			if air_t > 5.0:
				_fail(res, "free fall > 5 s at (%.0f, %.1f, %.0f)" % [pos.x, pos.y, pos.z])
				res.fall_events += 1
				break
		else:
			air_t = 0.0
		stuck_t += dt
		if stuck_t > 6.0:
			if pos.distance_to(stuck_anchor) < 1.0:
				res.stuck_events += 1
				Game.log_event("bot_stuck", {"bot": kind, "pos": [pos.x, pos.y, pos.z]})
				# try to unstick: jump and sidestep, then skip the waypoint
				player.intent.jump = true
				wp += 1
				if res.stuck_events > 3:
					_fail(res, "stuck repeatedly near (%.0f, %.0f)" % [pos.x, pos.z])
					break
			stuck_t = 0.0
			stuck_anchor = pos
		if player.health < health0 - 0.01 and player.fall_damage_taken <= 0.0:
			_fail(res, "health dropped without cause (%.1f -> %.1f)" % [health0, player.health])
			break
	player.intent.move = Vector2.ZERO
	player.intent.sprint = false
	_recording = false
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d engine/script/shader errors, first: %s" % [errs.size(), str(errs[0])])
	res.frame_spikes = _spikes
	var st := _stats(_frame_ms)
	res.frame_avg_ms = st.avg
	res.frame_p99_ms = st.p99
	if kind == "road" and res.waypoints_reached < mini(route.size() - 1, 8) and t < seconds:
		_fail(res, "reached only %d/%d waypoints" % [res.waypoints_reached, route.size()])
	return res

## Behaviour sim: stand in Bitter Spring for a while and audit the townsfolk (stuck rate, falls, errors).
func _run_town(seconds: float) -> Dictionary:
	var res := {"bot": "town", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "npcs": 0, "npc_minutes": 0.0}
	var t := Game.world.town(str(Game.args.get("town", "bitter_spring")))      # --town port_linden etc.
	var p := Vector3(t.x, 0, t.z)
	p.y = Game.world.height(p.x, p.z) + 1.0
	Game.terrain.ensure_collision_at(p)
	player.global_position = p
	player.intent.move = Vector2.ZERO
	# start at 8:30, when the town gets going (residents leave their porches, shops are open) - unless --hour
	if Game.sky:
		Game.sky.set_time(Game.arg_f("hour", 8.5))
	var err0: int = Game.error_logger.take().size()
	var el := 0.0
	var dur := minf(seconds, 90.0)
	var pop = Game.population
	while el < dur:
		await get_tree().physics_frame
		el += get_physics_process_delta_time()
	var npcs := get_tree().get_nodes_in_group("humans")
	res.npcs = npcs.size()
	var stuck_list := []
	for h in npcs:
		res.stuck_events += h.stuck_events
		if h.stuck_events > 0:
			stuck_list.append(h)
		var gy := Game.world.height(h.global_position.x, h.global_position.z)
		if h.global_position.y < gy - 1.5:
			res.fall_events += 1
	res.npc_minutes = res.npcs * dur / 60.0
	if pop != null and pop.has_method("town_metrics"):
		var m: Dictionary = pop.town_metrics()
		res["town"] = m
		res.stuck_events = maxi(res.stuck_events, int(m.stuck))
		res.npc_minutes = maxf(res.npc_minutes, float(m.npc_minutes))
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("  town metric: %d residents on screen of a %d cast | on schedule %.0f%% | spots reached %d of %d walks (%.0f%%), %d skipped unseen | went home %d | doors used %d | stuck %d (%.3f per NPC-minute) | chats %d, greetings %d, nudges %d | draw calls %s" % [
			m.residents, m.cast, m.on_schedule, m.arrived, m.arrived + m.failed, m.reached, m.skipped, m.home, m.doors,
			res.stuck_events, res.stuck_events / maxf(res.npc_minutes, 0.01), m.chats, m.greetings, m.nudges,
			str(dc) if dc > 0 else "n/a (headless)"])
		if m.arrived + m.failed >= 10 and m.reached < 70.0:
			_fail(res, "only %.0f%% of walks reached their spot" % m.reached)
	if pop != null and pop.has_method("town_metrics"):
		await _town_reactions(res, pop)
	for h in stuck_list.slice(0, 8):
		var rt = h.brain.get("routine")
		print("    stuck x%d %s at %s state %s %s" % [h.stuck_events, h.name, str(h.global_position.snapped(Vector3.ONE * 0.1)),
			h.brain.debug_state, ("%s/%s goal %s" % [rt.block.get("kind", ""), rt.phase, str(rt.goal.snapped(Vector3.ONE * 0.1))]) if rt != null else ""])
	if res.npcs == 0:
		_fail(res, "town is empty")
	if res.npc_minutes > 0.0 and res.stuck_events / res.npc_minutes > 0.5:
		_fail(res, "NPC stuck rate %.2f per NPC-minute" % (res.stuck_events / res.npc_minutes))
	if res.fall_events > 0:
		_fail(res, "%d NPCs fell through the world" % res.fall_events)
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	print("  town: %d npcs, %d stuck events, %.1f npc-minutes" % [res.npcs, res.stuck_events, res.npc_minutes])
	return res

## Reactions: Ruth walks up to a resident (look + greeting), then a shot goes off in the street (people run inside,
## cower, call the alarm). Prints a reactions line; fails only if nobody reacts at all.
func _town_reactions(res: Dictionary, pop) -> void:
	var g0: int = pop.metrics.greetings
	var target: Human = null
	for k in pop.residents:
		var h: Human = pop.residents[k]
		if is_instance_valid(h) and h.alive and h.brain.routine != null and not h.brain.routine.busy_seated() \
				and not ActorLOD.far(h) and h.brain.state == h.brain.State.ROUTINE:
			target = h
			break
	var looked := false
	if target != null:
		var fwd := Vector3(-sin(target.facing), 0, -cos(target.facing))
		var p: Vector3 = target.global_position + fwd * 3.0
		p.y = target.global_position.y + 0.2
		player.global_position = p
		for i in 180:
			await get_tree().physics_frame
			if target.brain.looking:
				looked = true
	var greeted: int = pop.metrics.greetings - g0
	var f0: int = pop.metrics.fled_inside
	Game.noise.emit(player.global_position, 260.0, player)
	var scared := 0
	for i in 60:
		await get_tree().physics_frame
	for k in pop.residents:
		var h: Human = pop.residents[k]
		if is_instance_valid(h) and h.brain.state in [h.brain.State.FLEE, h.brain.State.COWER]:
			scared += 1
	for i in 360:
		await get_tree().physics_frame
	res["reactions"] = {"looked": looked, "greeted": greeted, "scared": scared, "fled_inside": pop.metrics.fled_inside - f0}
	print("  town reactions: resident looked at Ruth %s, greetings %d | gunshot: %d fled or cowered, %d ran inside within 6 s" % [
		str(looked), greeted, scared, pop.metrics.fled_inside - f0])
	if scared == 0:
		_fail(res, "nobody reacted to a gunshot in town")

## Mission bot: autopilot through every story mission in order; softlock/fail/error oracles.
## Camp bot: the camp's pick self-test, then the real thing at Willow Bend — every companion recruited and at their
## spot, sit at the fire (the fitting talk plays, then a fresh hold-up changes it), stew, a drink, a hand with Del.
func _run_camp() -> Dictionary:
	var res := {"bot": "camp", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var camp = Game.camp
	var md: MissionDirector = Game.missions
	if camp == null or md == null:
		_fail(res, "no camp or mission director")
		return res
	var err0: int = Game.error_logger.take().size()
	md.autopilot = true
	var st = Game.state
	var keep := {"flags": st.flags.duplicate(true), "money": st.money, "crimes": st.crimes_log.duplicate(true),
		"completed": md.completed.duplicate(), "standing": st.standing}
	var t: Dictionary = camp.selftest()
	for l in t.lines:
		print(l)
	if not t.ok:
		_fail(res, "camp picks: %d failed" % t.fails)
	# everyone recruited, Ruth at the fire in the evening
	for f in ["billy_joined", "del_joined", "doc_joined", "joseph_joined"]:
		st.flags[f] = true
	st.flags["doc_sober"] = false
	if not md.completed.has("c1_drover"):
		md.completed.append("c1_drover")
	if Game.sky:
		Game.sky.set_time(19.5)
	var p: Vector3 = camp.center + Vector3(3.0, 0, 4.0)
	p.y = Game.world.height(p.x, p.z) + 0.5
	Game.terrain.ensure_collision_at(p)
	player.global_position = p
	var waited := 0.0
	while camp.members.size() < 5 and waited < 10.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	print("  camp: %d companions in camp (%s)" % [camp.members.size(), ", ".join(camp.members.keys())])
	if camp.members.size() < 5:
		_fail(res, "only %d companions came to camp" % camp.members.size())
	var talk1: String = await camp.sit_at_fire()
	st.crimes_log.append({"kind": "robbery", "pos": [p.x, p.z], "t": Time.get_unix_time_from_system()})
	var talk2: String = await camp.sit_at_fire()
	var talk3: String = await camp.sit_at_fire()
	print("  camp: at the fire -> %s; after a hold-up -> %s; again -> %s" % [talk1, talk2, talk3])
	if talk1 == "" or talk2 != "robbery" or talk3 == "robbery":
		_fail(res, "fireside talk didn't follow the hold-up (%s, %s, %s)" % [talk1, talk2, talk3])
	player.damageable.health = 40.0
	var ate: bool = await camp.eat_stew()
	var ate2: bool = await camp.eat_stew()
	var drink: String = await camp.drink_with_doc()
	var m0: float = st.money
	var cards: Dictionary = await camp.play_with_del()
	var money_ok: bool = absf((st.money - m0) - float(cards.get("net", 0.0))) < 0.011
	print("  camp: stew %s (health %.0f), second bowl %s, Doc pours %s, cards with Del: %d hands, net $%.2f" % [
		ate, player.damageable.health, ate2, drink, int(cards.get("hands", 0)), float(cards.get("net", 0.0))])
	if not ate or ate2 or player.damageable.health < 99.0 or drink != "whiskey" or not cards.get("played", false) or not money_ok:
		_fail(res, "camp activities wrong")
	st.flags = keep.flags
	st.money = keep.money
	st.crimes_log = keep.crimes
	st.standing = keep.standing
	md.completed.assign(keep.completed)
	md.autopilot = false
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

func _run_missions() -> Dictionary:
	var res := {"bot": "missions", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "completed": []}
	var md: MissionDirector = Game.missions
	md.autopilot = true
	md.step_timeout = 60.0
	var failed := []
	var forced := []
	# one deliberate failure right after a checkpoint, to exercise failure -> retry from checkpoint -> replay
	md.test_fail = str(Game.args.get("force_fail", "c2_cards:cards_done"))
	md.mission_failed.connect(func(id, why):
		if str(why).begins_with("forced failure"):
			forced.append(id)
		else:
			failed.append("%s: %s" % [id, why]))
	var err0: int = Game.error_logger.take().size()
	for i in 60:
		var avail: Array = md.available()
		if avail.is_empty():
			break
		# a side story runs as soon as its chapter opens (it waits at its marker in normal play), so each one plays
		# in the world state of its chapter; --no_strangers runs the story alone
		var m: Mission = avail[0]
		for a in avail:
			if a.stranger and not Game.args.has("no_strangers"):
				m = a
				break
		if Game.args.has("no_strangers") and m.stranger:
			md.completed.append(m.id)
			continue
		var t0 := Time.get_ticks_msec()
		await md.start(m)
		print("  mission %-22s %s in %.1f s" % [m.id, "done" if md.completed.has(m.id) else "FAILED", (Time.get_ticks_msec() - t0) / 1000.0])
		if not md.completed.has(m.id):
			break
	res.completed = md.completed.duplicate()
	for f in failed:
		_fail(res, f)
	# story coverage: every line said exists in the dialogue tables; report the choices and minigames played
	var said := 0
	var choices := []
	var outcomes := []
	for ln in Game.log_lines:
		var parts := ln.split(" ", false, 2)
		if parts.size() < 3:
			continue
		var data = JSON.parse_string(parts[2])
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if parts[1] == "say":
			said += 1
			if not md.dialogue.has(str(data.get("id", ""))):
				_fail(res, "dialogue line '%s' missing from design/dialogue" % data.get("id", ""))
		elif parts[1] == "choice":
			choices.append("%s:%d" % [data.get("mission", ""), int(data.get("index", 0))])
		elif parts[1] in ["sneak", "stampede", "defend"]:
			outcomes.append("%s:%s" % [parts[1], str(not data.get("spotted", false)) if parts[1] == "sneak" else str(data.get("turned", data.get("held", "")))])
		elif parts[1] == "minigame_end":
			print("  minigame %s: %s" % [data.get("name", ""), JSON.stringify(data)])
	res.lines_said = said
	res.choices = choices
	print("  lines said %d, choices %s" % [said, " ".join(choices)])
	print("  outcomes %s" % " ".join(outcomes))
	# the endings: Standing locked a branch at the end of chapter 5 and the credits rolled after the epilogue
	if md.completed.has("c6_spring"):
		var credit_lines := 0
		for ln in Game.log_lines:
			if ln.contains(" credits_roll "):
				var dd = JSON.parse_string(ln.split(" ", false, 2)[2])
				if typeof(dd) == TYPE_DICTIONARY:
					credit_lines = int(dd.get("licences", 0))
		var fl: Dictionary = Game.state.flags
		print("  ending: %s (eben %s, pell %s, hap alive %s, joseph left %s, del left %s, asa spared %s), credits licences %d" % [
			fl.get("ending", "?"), fl.get("eben_fate", "?"), fl.get("pell_fate", "?"), fl.get("hap_alive", "?"), fl.get("joseph_left", "?"),
			fl.get("del_left", "?"), fl.get("spared_asa", "?"), credit_lines])
		if not fl.has("ending") or credit_lines < 10:
			_fail(res, "ending/credits not reached properly")
		if Game.args.has("expect_ending") and str(fl.get("ending", "")) != str(Game.args.expect_ending):
			_fail(res, "expected ending %s, got %s" % [Game.args.expect_ending, fl.get("ending", "")])
	# the forced failure must have been retried from its checkpoint and the mission finished
	if md.test_fail != "":
		var fm := md.test_fail.split(":")[0]
		var resumed := false
		var replayed := 0
		for ln in Game.log_lines:
			if ln.contains(" checkpoint_resumed ") and ln.contains('"%s"' % fm):
				resumed = true
			if ln.contains(" choice_replayed ") or ln.contains(" minigame_replayed "):
				replayed += 1
		print("  retry test: forced failure in %s %s, resumed from checkpoint: %s, decisions replayed: %d, completed: %s" % [
			fm, "seen" if forced.has(fm) else "NOT SEEN", resumed, replayed, md.completed.has(fm)])
		if not (forced.has(fm) and resumed and md.completed.has(fm)):
			_fail(res, "retry from checkpoint not exercised for %s" % fm)
	# the journal: a page for every mission played, in the words that match what she did, and the menu opens
	var jr = load("res://src/missions/journal.gd")
	var all_ids := []
	var markers := []
	for path in MissionDirector.MISSIONS:
		var mm: Mission = load(path).new()
		all_ids.append(mm.id)
		if mm.stranger:
			markers.append("%s@%s(%d,%d)" % [mm.id, mm.region.replace(" ", "_"), int(mm.start_pos.x), int(mm.start_pos.z)])
			if mm.start_pos == Vector3.ZERO or mm.region == "" or Game.world.is_water(mm.start_pos.x, mm.start_pos.z):
				_fail(res, "stranger %s has no usable marker (start_pos %s, region '%s')" % [mm.id, mm.start_pos, mm.region])
	print("  stranger markers: %s" % " ".join(markers))
	var jt: Dictionary = jr.selftest(all_ids)
	if not jt.ok:
		_fail(res, "journal entries missing: %s" % ", ".join(jt.missing))
	var words := 0
	for id in md.completed:
		var txt: String = jr.text_for(id, Game.state.flags)
		words += txt.split(" ", false).size()
		if txt == "":
			_fail(res, "journal: no page for %s" % id)
	if Game.get("menus") != null:
		Game.menus.open_journal()
		await get_tree().process_frame
		Game.menus.close_all()
	print("  journal: %d pages, %d words" % [md.completed.size(), words])
	# results cards: every main mission played left a rated result in WorldState
	var medals: Dictionary = Game.state.flags.get("medals", {})
	var tallies := {"gold": 0, "silver": 0, "bronze": 0}
	var unrated := []
	for id in md.completed:
		if str(id).begins_with("c"):
			var mr: Dictionary = medals.get(id, {})
			if mr.is_empty():
				unrated.append(id)
			else:
				tallies[str(mr.medal)] = int(tallies.get(str(mr.medal), 0)) + 1
	print("  results cards: gold %d, silver %d, bronze %d%s" % [tallies.gold, tallies.silver, tallies.bronze,
		(", unrated: " + ", ".join(unrated)) if not unrated.is_empty() else ""])
	if not unrated.is_empty():
		_fail(res, "missions without a results card: %s" % ", ".join(unrated))
	var pk: Dictionary = load("res://src/minigames/poker_engine.gd").selftest()
	if not pk.ok:
		_fail(res, "poker self-test: %d failed" % pk.fails)
	if md.completed.size() < MissionDirector.MISSIONS.size():
		_fail(res, "completed %d/%d missions" % [md.completed.size(), MissionDirector.MISSIONS.size()])
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	md.autopilot = false
	return res

## Encounters bot: stage every roadside encounter kind under autopilot on the Port Linden road, in three passes —
## (A) honourable Ruth answering every choice with the first option, (B) an outlaw Ruth answering with the second,
## (C) the Standing-dependent branches again from the middle (the hanging she has to fight for, the bounty she can't
## pay). Oracle: each finishes, the scene kinds report an outcome, every line said exists, both branches of every
## two-way choice are seen, no script errors.
func _run_encounters() -> Dictionary:
	var res := {"bot": "encounters", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var enc = Game.get("encounters")
	var md: MissionDirector = Game.missions
	if enc == null or md == null:
		_fail(res, "no encounter system")
		return res
	var err0: int = Game.error_logger.take().size()
	md.autopilot = true
	md.step_timeout = 60.0
	var st = Game.state
	var keep := {"flags": st.flags.duplicate(true), "money": st.money, "standing": st.standing, "bounties": st.bounties.duplicate()}
	var passes := [
		{"name": "A", "standing": 40.0, "branch": 0, "money": 100.0, "kinds": enc.TYPES},
		{"name": "B", "standing": -30.0, "branch": 1, "money": 100.0, "kinds": enc.TYPES},
		{"name": "C", "standing": 0.0, "branch": 0, "money": 0.0, "kinds": ["hanging", "bounty_hunters"]},
	]
	var log0 := Game.log_lines.size()
	var n := 0
	var seen := {}
	for ps in passes:
		var outs := []
		for kind in ps.kinds:
			st.standing = float(ps.standing)
			st.money = float(ps.money)
			st.bounties = {"bitter_spring": 40.0} if kind == "bounty_hunters" else {}
			st.wanted = 0
			# each one a little further down the road, Ruth 45 m short of the scene
			var f := 0.08 + 0.8 * float(n % 18) / 18.0
			n += 1
			var at := Mission.road_point("bitter_spring", "port_linden", f)
			var from := Mission.road_point("bitter_spring", "port_linden", maxf(f - 0.02, 0.0))
			Game.terrain.ensure_collision_at(from)
			md._teleport_player(from)
			md._choice_queue.clear()
			for i in 6:
				md._choice_queue.append(int(ps.branch))
			var s0: float = st.standing
			var t0 := Time.get_ticks_msec()
			await enc.start(kind, at)
			var out := str(enc.outcome)
			outs.append("%s:%s(%+.1f)" % [kind, out if out != "" else "-", st.standing - s0])
			seen["%s:%s" % [kind, out]] = true
			if TYPES_NEW.has(kind) and out == "":
				_fail(res, "encounter %s (pass %s) ended without an outcome" % [kind, ps.name])
			if Time.get_ticks_msec() - t0 > 90000:
				_fail(res, "encounter %s took %.0f s" % [kind, (Time.get_ticks_msec() - t0) / 1000.0])
			await get_tree().physics_frame
		print("  encounters pass %s (standing %+.0f, choices %d): %s" % [ps.name, ps.standing, ps.branch, " ".join(outs)])
	md._choice_queue.clear()
	# both sides of every two-way scene
	for pair in [["hanging:talked_down", "hanging:rode_on"], ["hanging:fought", "hanging:rode_on"], ["runaway:caught", "runaway:overturned"],
			["duel:shot", "duel:talked"], ["snake_oil:bought", "snake_oil:exposed"], ["bounty_hunters:paid", "bounty_hunters:fought"],
			["stranded:robbed", "stranded:fought"], ["drunk:drank", "drunk:disarmed"], ["fire:saved", "fire:lost"],
			["preacher:gave", "preacher:passed"], ["stage:stopped", "stage:rode_on"], ["lost_child:home", "lost_child:home"],
			["ambush:fought_off", "ambush:fought_off"]]:
		for k in pair:
			if not seen.has(k):
				_fail(res, "encounter branch %s never seen" % k)
	var said := 0
	for i in range(log0, Game.log_lines.size()):
		var ln: String = Game.log_lines[i]
		var parts := ln.split(" ", false, 2)
		if parts.size() < 3 or parts[1] != "say":
			continue
		said += 1
		var data = JSON.parse_string(parts[2])
		if typeof(data) == TYPE_DICTIONARY and not md.dialogue.has(str(data.get("id", ""))):
			_fail(res, "dialogue line '%s' missing from design/dialogue" % data.get("id", ""))
	res.lines_said = said
	res.encounters = n
	print("  encounters: %d staged, %d lines said, %d distinct outcomes" % [n, said, seen.size()])
	st.flags = keep.flags
	st.money = keep.money
	st.standing = keep.standing
	st.bounties = keep.bounties
	md.autopilot = false
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

const TYPES_NEW := ["ambush", "hanging", "runaway", "lost_child", "duel", "snake_oil", "bounty_hunters", "stranded", "drunk", "fire",
	"preacher", "stage"]

## Social bot (world reactivity): greet / antagonize / defuse on real townsfolk by the Bitter Spring road (antagonize
## escalates insult -> shove -> draw or flee by arms and bravery; defuse stands a drawn man down unless Ruth is
## wanted), the same person's lines by Standing band, gossip picks for given facts, and newspaper front pages for
## given flags and deeds (plus buying one and opening the printed page).
func _run_social() -> Dictionary:
	var res := {"bot": "social", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var err0: int = Game.error_logger.take().size()
	for i in 4:
		await get_tree().process_frame
	var so = Game.get_meta("social") if Game.has_meta("social") else null
	var nw = Game.get_meta("news") if Game.has_meta("news") else null
	if so == null or nw == null:
		_fail(res, "social/newspaper systems missing")
		return res
	var st = Game.state
	var keep := {"standing": st.standing, "money": st.money, "flags": st.flags.duplicate(true), "bounties": st.bounties.duplicate(), "wanted": st.wanted}
	var at := Mission.road_point("bitter_spring", "port_linden", 0.2)
	Game.terrain.ensure_collision_at(at)
	Game.missions._teleport_player(at)
	await get_tree().physics_frame
	var mk := func(dx: float, opts: Dictionary) -> Human:
		var p: Vector3 = at + Vector3(dx, 0, 2.0)
		p.y = Game.world.height(p.x, p.z) + 0.3
		Game.terrain.ensure_tile(p)
		var o := {"seed": 4400 + int(dx * 10), "faction": "civilian", "name": "Test %d" % int(dx)}
		o.merge(opts, true)
		return Human.spawn(Game.main, p, o)
	var lines := []
	# 1. armed and brave: insult, shove, draw; then talked down (Standing mid)
	st.standing = 0.0
	st.bounties = {}
	st.wanted = 0
	var a: Human = mk.call(2.0, {"role": "rancher", "weapon": "lockhart_sa", "bravery": 0.9})
	await get_tree().physics_frame
	var steps := []
	for i in 3:
		steps.append(so.antagonize(a))
	var s_before: float = st.standing
	var drew: bool = a.brain.aggressive and a.brain.state == a.brain.State.COMBAT
	var d1: String = so.defuse(a)
	var calm: bool = not a.brain.aggressive and a.brain.state == a.brain.State.ROUTINE
	lines.append("armed+brave: %s -> combat %s; defuse %s (calm %s, standing %+.1f)" % ["/".join(steps), drew, d1, calm, st.standing - s_before])
	if steps != ["insult", "shove", "draw"] or not drew or d1 != "stood_down" or not calm:
		_fail(res, "armed brave townsman: %s" % lines.back())
	# 2. the same, but Ruth is wanted: sorry doesn't cover it
	st.bounties = {"bitter_spring": 80.0}
	st.wanted = 1
	var b: Human = mk.call(-2.0, {"role": "rancher", "weapon": "lockhart_sa", "bravery": 0.8})
	await get_tree().physics_frame
	steps = []
	for i in 3:
		steps.append(so.antagonize(b))
	var d2: String = so.defuse(b)
	lines.append("armed+brave, Ruth wanted: %s; defuse %s (still fighting %s)" % ["/".join(steps), d2, b.brain.aggressive])
	if steps.back() != "draw" or d2 != "failed" or not b.brain.aggressive:
		_fail(res, "wanted Ruth defuse: %s" % lines.back())
	b.brain.aggressive = false
	b.brain.target = null
	b.brain.state = b.brain.State.ROUTINE
	st.bounties = {}
	st.wanted = 0
	# 3. unarmed: a hard case puts his fists up, a timid one runs
	var c: Human = mk.call(4.0, {"role": "worker", "weapon": "", "bravery": 0.9})
	await get_tree().physics_frame
	steps = []
	for i in 3:
		steps.append(so.antagonize(c))
	lines.append("unarmed brave: %s -> %s" % ["/".join(steps), c.brain.State.keys()[c.brain.state]])
	if steps.back() != "fists" or c.brain.state != c.brain.State.FIST:
		_fail(res, "unarmed hard case: %s" % lines.back())
	c.brain.state = c.brain.State.ROUTINE
	c.brain.target = null
	var c2: Human = mk.call(5.5, {"role": "worker", "weapon": "", "bravery": 0.5})
	await get_tree().physics_frame
	steps = []
	for i in 3:
		steps.append(so.antagonize(c2))
	lines.append("unarmed: %s -> %s" % ["/".join(steps), c2.brain.State.keys()[c2.brain.state]])
	if steps.back() != "flee" or c2.brain.state != c2.brain.State.FLEE:
		_fail(res, "unarmed townsman: %s" % lines.back())
	# 4. armed coward: runs too
	var e: Human = mk.call(-4.0, {"role": "gambler", "weapon": "lockhart_sa", "bravery": 0.2})
	await get_tree().physics_frame
	steps = []
	for i in 3:
		steps.append(so.antagonize(e))
	lines.append("armed coward: %s" % "/".join(steps))
	if steps.back() != "flee":
		_fail(res, "armed coward: %s" % lines.back())
	# 5. a lawman always draws
	var l: Human = mk.call(6.0, {"role": "lawman", "faction": "law", "weapon": "harlan_carbine", "bravery": 0.1})
	await get_tree().physics_frame
	steps = []
	for i in 3:
		steps.append(so.antagonize(l))
	var d5: String = so.defuse(l)
	lines.append("lawman: %s; defuse %s" % ["/".join(steps), d5])
	if steps.back() != "draw" or d5 != "failed":
		_fail(res, "lawman: %s" % lines.back())
	# 6. an insult, then calmed
	var f: Human = mk.call(-6.0, {"role": "lady", "weapon": ""})
	await get_tree().physics_frame
	var s6: String = so.antagonize(f)
	var d6: String = so.defuse(f)
	var d6b: String = so.defuse(f)
	lines.append("lady: %s, defuse %s, again %s" % [s6, d6, d6b if d6b != "" else "(nothing to calm)"])
	if s6 != "insult" or d6 != "calmed" or d6b != "":
		_fail(res, "insult then defuse: %s" % lines.back())
	# 7. the same man by band: greeting follow-ups differ for an honourable and a wanted Ruth
	var g_by := {}
	for bd in ["high", "mid", "low", "wanted"]:
		g_by[bd] = so.pick("greet", "town", bd)
	lines.append("greet follow-ups by band: %s" % JSON.stringify(g_by))
	if g_by.high == g_by.wanted or not str(g_by.high).contains("_high_") or not str(g_by.wanted).contains("_wanted_"):
		_fail(res, "greeting lines don't follow Standing band")
	st.standing = 40.0
	var gid: String = so.greet(f, true)
	lines.append("greet (Standing 40): %s" % gid)
	if gid == "":
		_fail(res, "greet said nothing")
	# 8. gossip picks for given facts
	var base := func(extra: Dictionary) -> Dictionary:
		var cx := {"flags": {}, "completed": [], "wanted": 0, "bounty": 0.0, "standing": 0.0, "kills": {"civilian": 0, "outlaw": 0},
			"robberies": 0, "shop_robberies": 0, "weather": "FAIR", "hour": 12.0, "night": false, "role": "townsfolk", "town": "bitter_spring"}
		cx.merge(extra, true)
		return cx
	var cases := [
		["Cutter jailed", base.call({"flags": {"cutter_fate": "jailed"}, "completed": ["c3_fork"]}), "gos_cutter_jail"],
		["Cutter dead", base.call({"flags": {"cutter_fate": "dead"}, "completed": ["c3_fork"]}), "gos_cutter_dead"],
		["the train robbed", base.call({"flags": {"payroll_taken": true}, "completed": ["c5_train"]}), "*train|payroll"],
		["Pell in print", base.call({"flags": {"ledger_to_fenn": true}, "completed": ["c5_owe"]}), "gos_ledger"],
		["Pell arrested", base.call({"flags": {"pell_fate": "arrested"}, "completed": ["c6_ink"]}), "gos_pell_arrest"],
		["a storm", base.call({"weather": "STORM"}), "gos_w_storm"],
		["night", base.call({"night": true, "hour": 23.0}), "gos_night"],
		["lawman, Ruth wanted", base.call({"role": "lawman", "wanted": 1}), "gos_law_eye1"],
		["lawman, dead or alive", base.call({"role": "lawman", "wanted": 3}), "gos_law_eye2"],
		["shop, robbed twice", base.call({"role": "shop", "shop_robberies": 2, "robberies": 2}), "gos_shop_robbed2"],
		["shop, honourable Ruth", base.call({"role": "shop", "standing": 40.0}), "gos_shop_high"],
		["shop, low Ruth", base.call({"role": "shop", "standing": -30.0}), "gos_shop_low"],
		["three robberies", base.call({"robberies": 3}), "gos_robbed3"],
		["a murder", base.call({"kills": {"civilian": 1, "outlaw": 0}}), "gos_murder"],
		["the comet", base.call({"flags": {"stayed_for_comet": true}}), "gos_comet"],
	]
	var gfail := 0
	for cs in cases:
		var got: String = so.pick_gossip(cs[1], false)
		var want: String = cs[2]
		var ok: bool = got == want
		if want.begins_with("*"):
			ok = false
			for w in want.substr(1).split("|"):
				if got.contains(w):
					ok = true
		if not ok:
			gfail += 1
		lines.append("  gossip %s %-22s -> %s" % ["ok  " if ok else "FAIL", cs[0], got])
	if gfail > 0:
		_fail(res, "gossip: %d picks wrong" % gfail)
	# 9. newspapers for given flags and deeds
	var nbase := func(extra: Dictionary) -> Dictionary:
		var cx: Dictionary = base.call({"records": [], "day": 3, "county": "bitter_spring"})
		cx.merge(extra, true)
		return cx
	var ncases := [
		["chapter 1 start", nbase.call({"completed": ["c1_rider"]}), "land_offer"],
		["Willow Bend", nbase.call({"completed": ["c1_rider", "c1_drover"]}), "willow_bend"],
		["the press attacked", nbase.call({"completed": ["c1_fire", "c2_lantern"]}), "press"],
		["the poster", nbase.call({"completed": ["c2_exchange", "c2_terms"], "flags": {"ruth_poster": 200.0}, "bounty": 200.0}), "poster"],
		["Cutter jailed", nbase.call({"completed": ["c3_fork"], "flags": {"cutter_fate": "jailed"}}), "cutter_jailed"],
		["the strike", nbase.call({"completed": ["c4_strike"], "flags": {"strike_terms": "inspector"}}), "strike"],
		["the express", nbase.call({"completed": ["c5_train"], "flags": {"payroll_taken": false, "messenger_killed": false}}), "express"],
		["Pell's ledger", nbase.call({"completed": ["c5_owe"], "flags": {"ledger_to_fenn": true}}), "ledger"],
		["Pell arrested", nbase.call({"completed": ["c6_ink"], "flags": {"pell_fate": "arrested"}}), "pell_arrested"],
		["spring", nbase.call({"completed": ["c6_ink", "c6_spring"], "flags": {"pell_fate": "untouched"}}), "spring"],
		["a store robbed", nbase.call({"completed": ["c1_rider"], "records": [{"kind": "store_robbery", "town": "coldwater", "shop": "gunsmith", "take": 72.5, "day": 2}]}), "store_robbery"],
		["robbery wave", nbase.call({"completed": ["c1_rider"], "records": [{"kind": "store_robbery", "town": "coldwater", "day": 1}, {"kind": "store_robbery", "town": "port_linden", "day": 2}, {"kind": "store_robbery", "town": "bitter_spring", "day": 3}]}), "robberies"],
		["a gunfight", nbase.call({"completed": ["c1_rider"], "records": [{"kind": "gunfight", "town": "bitter_spring", "shots": 14, "day": 3}]}), "gunfight"],
		["a bounty", nbase.call({"completed": ["c1_rider"], "records": [{"kind": "bounty", "name": "Jubal Pardee", "amount": 45, "alive": true, "day": 3}]}), "bounty"],
		["old news", nbase.call({"completed": ["c1_rider", "c1_drover"], "day": 20, "records": [{"kind": "gunfight", "town": "bitter_spring", "day": 2}]}), "willow_bend"],
		["the comet", nbase.call({"completed": ["c1_rider"], "flags": {"stayed_for_comet": true}}), "comet"],
	]
	var nfail := 0
	var heads := []
	for cs in ncases:
		var ed: Dictionary = nw.edition(cs[1])
		var lead: Dictionary = ed.get("lead", {})
		var txt := ""
		for it in [lead] + ed.get("items", []):
			txt += str(it.get("head", "")) + str(it.get("deck", "")) + str(it.get("body", ""))
		var date_s := str(ed.get("date", ""))
		var ok: bool = lead.get("id", "") == cs[2] and not txt.contains("{") and ed.get("ads", []).size() == 3 \
			and str(ed.get("weather", "")) != "" and (date_s.contains("1899") or date_s.contains("1900"))
		if not ok:
			nfail += 1
		heads.append(str(lead.get("head", "")))
		lines.append("  paper %s %-18s -> %s | %s | %s%s" % ["ok  " if ok else "FAIL", cs[0], lead.get("id", "?"), lead.get("head", ""), ed.get("date", ""), "" if ok else " [ads %d, weather %d, brace %s]" % [ed.get("ads", []).size(), str(ed.get("weather", "")).length(), txt.contains("{")]])
	if nfail > 0:
		_fail(res, "newspaper: %d front pages wrong" % nfail)
	var nstories: int = nw.data.get("stories", []).size()
	if nstories < 12:
		_fail(res, "only %d headline templates" % nstories)
	# buy one and open the printed page
	st.money = 5.0
	var bought: Dictionary = nw.buy("port_linden")
	await get_tree().process_frame
	var opened: bool = Game.get("menus") != null and not Game.menus.stack.is_empty()
	if Game.get("menus"):
		Game.menus.close_all()
	lines.append("bought %s for 5 cents: %s, page opened %s" % [bought.get("masthead", "?"), bought.get("lead", {}).get("head", "?"), opened])
	if bought.is_empty() or absf(st.money - 4.95) > 0.001:
		_fail(res, "buying a paper failed")
	for ln in lines:
		print("  " + ln if not ln.begins_with("  ") else ln)
	res.social_cases = 7
	res.gossip_cases = cases.size()
	res.paper_cases = ncases.size()
	for h in [a, b, c, e, l, f]:
		if is_instance_valid(h):
			h.queue_free()
	st.standing = keep.standing
	st.money = keep.money
	st.flags = keep.flags
	st.bounties = keep.bounties
	st.wanted = keep.wanted
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

## Open-world bot: the bounty board (named outlaws, hideout and roaming lairs, alive across the saddle vs dead with
## proof, turn-in, journal/gossip/newspaper hooks, the first treasure map in Hatcher's saddlebag), the four
## legendary animals (clue trail, the beast, the pelt, the outfit), the treasure-map chain to the gold, a lawman's
## misdemeanour fine paid at a board, and reading the last newspaper from the satchel.
func _run_openworld() -> Dictionary:
	var res := {"bot": "openworld", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var err0: int = Game.error_logger.take().size()
	var md: MissionDirector = Game.missions
	md.autopilot = true
	md.step_timeout = 60.0
	for i in 150:
		await get_tree().process_frame
	var st = Game.state
	st.money = 200.0
	var so = Game.get_meta("social") if Game.has_meta("social") else null
	var nw = Game.get_meta("news") if Game.has_meta("news") else null
	var lg = Game.get_meta("legendary") if Game.has_meta("legendary") else null
	var tr = Game.get_meta("treasure") if Game.has_meta("treasure") else null
	if so == null or nw == null or lg == null or tr == null:
		_fail(res, "open-world systems missing")
		return res
	var lines := []
	var skip := str(Game.args.get("ow_skip", "")).split(",", false)
	# ---------------------------------------------------------------- 1. bounties
	var boards := get_tree().get_nodes_in_group("interactable").filter(func(n): return n.has_method("accept") and n.has_method("refresh"))
	var bd = null
	for b in boards:
		if str(b.town_id) == "bitter_spring":
			bd = b
	if bd == null:
		_fail(res, "no bounty board at Bitter Spring")
	elif not skip.has("1"):
		bd.refresh()
		lines.append("board at %s: %s" % [bd.town_id, ", ".join(bd.posters.map(func(p): return "%s ($%d, %s)" % [p.name, int(p.reward), p.lair]))])
		var B = bd.get_script()
		var rmo: Dictionary = B.outlaw("marlow")
		var roam_ok: bool = B.lair_pos(rmo, 0).distance_to(B.lair_pos(rmo, 1)) > 100.0
		lines.append("roaming camp moves: Marlow day 0 %s, day 1 %s" % [B.lair_pos(rmo, 0).snapped(Vector3.ONE), B.lair_pos(rmo, 1).snapped(Vector3.ONE)])
		if not roam_ok:
			_fail(res, "roaming camp doesn't move")
		for o in B.OUTLAWS:
			var lp: Vector3 = B.lair_pos(o)
			if Game.world.is_water(lp.x, lp.z):
				_fail(res, "lair of %s is in water" % o.name)
		# Hatcher alive (the default answer): tied, carried, turned in for 1.5x, map in his saddlebag
		var log0 := Game.log_lines.size()
		var cases := [["hatcher", 0, "alive"], ["penn", 1, "dead"]]
		for cs in cases:
			bd.refresh()
			var idx := -1
			for i in bd.posters.size():
				if bd.posters[i].id == cs[0]:
					idx = i
			if idx < 0:
				_fail(res, "%s not on the board" % cs[0])
				continue
			var reward: float = bd.posters[idx].reward
			var m0: float = st.money
			md._choice_queue = [cs[1]]
			bd.accept(idx)
			var tied := false
			for f in 900:
				await get_tree().physics_frame
				if bd.stage == "carry":
					tied = true
				if bd.active.is_empty():
					break
			var got: String = str(st.flags.get("outlaw_" + str(cs[0]), ""))
			var paid: float = st.money - m0
			var want: float = reward * (1.5 if cs[2] == "alive" else 1.0)
			lines.append("bounty %s: %s, carried across the saddle %s, paid $%.2f (expected $%.2f)" % [cs[0], got, tied, paid, want])
			if got != cs[2] or absf(paid - want) > 0.01 or (cs[2] == "alive" and not tied):
				_fail(res, "bounty %s: %s" % [cs[0], lines.back()])
		md._choice_queue.clear()
		var has_map: bool = int(st.inventory.get("treasure_map_1", 0)) > 0
		lines.append("Hatcher's saddlebag: treasure_map_1 %s" % has_map)
		if not has_map:
			_fail(res, "no treasure map from Hatcher")
		var ex: Array = load("res://src/missions/journal.gd").extra_entries(st.flags, st.inventory)
		var titles := ex.map(func(e): return str(e.title))
		lines.append("journal extra pages: %s" % ", ".join(titles))
		if not titles.has("Cole Hatcher") or not titles.has("Ezra Penn") or not titles.has("The Hatcher Map"):
			_fail(res, "journal pages for bounties/map missing")
		var gc: Dictionary = so.context(null, "townsfolk")
		var g1: String = so.pick_gossip(gc, false)
		var ed: Dictionary = nw.edition(nw.context("bitter_spring"))
		lines.append("gossip after: %s; paper lead: %s" % [g1, ed.get("lead", {}).get("head", "")])
		if not (g1.begins_with("gos_out_")) or ed.get("lead", {}).get("id", "") != "bounty":
			_fail(res, "bounty gossip/newspaper hooks: %s / %s" % [g1, ed.get("lead", {}).get("id", "")])
	# ---------------------------------------------------------------- 2. legendary animals
	var L = lg.get_script()
	for l in ([] if skip.has("2") else L.LEGENDS.slice(0, int(Game.args.get("ow_legends", 4)))):
		var log1 := Game.log_lines.size()
		var ok: bool = await lg.hunt(l.id)
		var clues := 0
		var hp := 0.0
		for i in range(log1, Game.log_lines.size()):
			var ln: String = Game.log_lines[i]
			if ln.contains(" legend_clue "):
				clues += 1
			if ln.contains(" legend_spawned "):
				var dd = JSON.parse_string(ln.split(" ", false, 2)[2])
				hp = float(dd.get("hp", 0.0))
		var base_hp: float = float(Animal.SPECIES[l.species].hp)
		var made: bool = lg.make_outfit(l.id)
		var outfit: bool = int(st.inventory.get("outfit_" + str(l.id), 0)) > 0
		lines.append("legend %s (%s): clues %d, beast hp %.0f (species %.0f), pelt %s, outfit %s" % [l.name, l.species, clues, hp, base_hp, ok, outfit])
		if not ok or clues != 3 or hp < base_hp * 3.0 or not made or not outfit or L.status(l.id) != "outfit":
			_fail(res, "legend %s: %s" % [l.id, lines.back()])
	var stall_ok := get_tree().get_nodes_in_group("interactable").any(func(n): return str(n.name) == "TrapperStall")
	var g2: String = so.pick_gossip(so.context(null, "townsfolk"), false)
	var ed2: Dictionary = nw.edition(nw.context("bitter_spring"))
	lines.append("trapper stall at Greer's: %s; paper lead after the hunts: %s; options left: %d" % [stall_ok, ed2.get("lead", {}).get("head", ""), lg.options().size()])
	if not skip.has("2") and (not stall_ok or ed2.get("lead", {}).get("id", "") != "legend"):
		_fail(res, "legendary hooks: stall %s, paper %s" % [stall_ok, ed2.get("lead", {}).get("id", "")])
	# ---------------------------------------------------------------- 3. treasure maps
	var T = tr.get_script()
	var targets := []
	if skip.has("1") and not skip.has("3"):
		st.add_item("treasure_map_1")
	for n in ([] if skip.has("3") else [1, 2, 3]):
		var tp: Vector3 = T.target(n)
		targets.append(tp)
		var spot_prompt := ""
		for s in tr.spots:
			if s.n == n:
				spot_prompt = s.interact_prompt()
		var sk = T.MapSketch.new()
		sk.setup(tp, n)
		var lo := INF
		var hi := -INF
		var wet := 0
		for v in sk._grid:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		for wv in sk._water:
			wet += int(wv)
		sk.free()
		var found: String = tr.dig(n)
		lines.append("map %d: X at (%d, %d) %s, relief %.0f m, water cells %d, dig prompt '%s' -> %s" % [n, int(tp.x), int(tp.z),
			"dry" if not Game.world.is_water(tp.x, tp.z) else "WET", hi - lo, wet, spot_prompt, found])
		var want_found := ("treasure_map_%d" % (n + 1)) if n < 3 else "gold"
		if found != want_found or Game.world.is_water(tp.x, tp.z) or hi - lo < 4.0:
			_fail(res, "treasure map %d: %s" % [n, lines.back()])
	if not skip.has("3") and int(st.inventory.get("gold_bar", 0)) != 3:
		_fail(res, "no gold at the end of the maps")
	if targets.size() == 3 and (targets[0].distance_to(targets[1]) < 300.0 or targets[1].distance_to(targets[2]) < 300.0):
		_fail(res, "treasure sites too close together")
	# ---------------------------------------------------------------- 4. a lawman's misdemeanour
	st.bounties = {}
	st.wanted = 0
	var at := Mission.road_point("bitter_spring", "port_linden", 0.15)
	Game.terrain.ensure_tile(at)
	var law := Human.spawn(Game.main, at + Vector3(2, 0.3, 2), {"seed": 6611, "role": "lawman", "faction": "law", "name": "Deputy Test", "weapon": "harlan_carbine"})
	await get_tree().physics_frame
	var s1: String = so.antagonize(law)
	var owed1: float = bd._fines() if bd else 0.0
	var w1: int = st.wanted
	var s2: String = so.antagonize(law)
	var owed2: float = bd._fines() if bd else 0.0
	var m3: float = st.money
	var paid_ok: bool = bd.pay_fines() if bd else false
	lines.append("lawman: %s -> fine $%d, wanted %d; %s -> fine $%d; paid at the board %s ($%.2f), wanted now %d" % [s1, int(owed1), w1, s2, int(owed2), paid_ok, m3 - st.money, st.wanted])
	if owed1 != 5.0 or w1 != 1 or owed2 != 15.0 or not paid_ok or st.wanted != 0 or absf(m3 - st.money - 15.0) > 0.01:
		_fail(res, "misdemeanour: %s" % lines.back())
	law.queue_free()
	# ---------------------------------------------------------------- 5. the satchel reads the last newspaper
	if skip.has("5"):
		for ln in lines:
			print("  " + ln)
		md.autopilot = false
		res.errors = Game.error_logger.take().slice(err0)
		return res
	nw.buy("port_linden")
	if Game.get("menus"):
		Game.menus.close_all()
	var readable: bool = Satchel.readable("newspaper") and Satchel.readable("treasure_map_2")
	Satchel.read("newspaper")
	await get_tree().process_frame
	var opened: bool = Game.get("menus") == null or not Game.menus.stack.is_empty()
	if Game.get("menus"):
		Game.menus.close_all()
	lines.append("satchel: newspaper readable %s, last edition '%s', opened %s" % [readable, st.flags.get("news_last", {}).get("lead", {}).get("head", ""), opened])
	if not readable or not nw.has_paper() or int(st.inventory.get("newspaper", 0)) <= 0:
		_fail(res, "satchel newspaper: %s" % lines.back())
	for ln in lines:
		print("  " + ln)
	md.autopilot = false
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

## Presentation bot: the conversation camera (two-shot open, a cut per speaker change, over-the-shoulder framing on
## the speaker, one side of the line of action, letterbox, depth of field, the pair facing each other, gestures),
## mission bookends (title card, results with objectives and medals stored in WorldState and shown in the journal),
## and the loose ends (gold sold at the bank and the fence, outfits on Ruth, a bounty turned in at another sheriff).
func _run_presentation() -> Dictionary:
	var res := {"bot": "presentation", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var err0: int = Game.error_logger.take().size()
	var md: MissionDirector = Game.missions
	var st = Game.state
	for i in 150:
		await get_tree().process_frame
	var lines := []
	# ---------------------------------------------------------------- 1. the conversation camera
	var at := Mission.road_point("bitter_spring", "port_linden", 0.12)
	Game.terrain.ensure_collision_at(at)
	md._teleport_player(at)
	await get_tree().physics_frame
	var npc := Human.spawn(Game.main, at + Vector3(2.0, 0.3, -1.6), {"seed": 9501, "role": "prospector", "faction": "civilian", "name": "Silas Wren"})
	npc.facing = 2.0
	md.npc_hold(npc, npc.global_position + Vector3(0, 0, -3.0))     # held like a mission speaker (looking away to start)
	for i in 10:
		await get_tree().physics_frame
	md.cine_test = true
	md.cine_begin()
	var bars_up: bool = md._bars.size() > 0 and md.get_node_or_null("Letterbox") != null
	var att = md._cine_cam.attributes if md._cine_cam else null
	var dof_set: bool = att is CameraAttributesPractical and att.dof_blur_far_enabled and att.dof_blur_near_enabled
	md.say_async("s_comet_01", npc)
	await get_tree().create_timer(0.4).timeout
	md.say_async("s_comet_02", Game.player)
	await get_tree().create_timer(0.4).timeout
	md.say_async("s_comet_03", npc)
	await get_tree().create_timer(0.4).timeout
	md.say_async("s_comet_05", npc)
	for i in 60:
		await get_tree().physics_frame
	var shots := md.cine_log.filter(func(e): return e.kind in ["two", "ots", "hold"])
	var kinds := shots.map(func(e): return e.kind)
	var gestures := md.cine_log.filter(func(e): return e.kind == "gesture").size()
	var aim_ok := true
	var sides := []
	for e in shots:
		if e.kind == "ots":
			var cam: Transform3D = e.cam
			var to: Vector3 = (e.focus - cam.origin).normalized()
			if (-cam.basis.z).dot(to) < 0.95:          # the speaker on the far third, well inside the frame
				aim_ok = false
			var mid: Vector3 = (npc.global_position + Game.player.global_position) * 0.5
			var line := npc.global_position - Game.player.global_position
			line.y = 0.0
			var side := line.normalized().cross(Vector3.UP)
			sides.append(signf((cam.origin - mid).dot(side)))
	var one_side: bool = sides.size() >= 2 and sides.all(func(x): return x == sides[0])
	var to_p := Game.player.global_position - npc.global_position
	var want_yaw := atan2(-to_p.x, -to_p.z)
	var face_err := rad_to_deg(absf(angle_difference(npc.facing, want_yaw)))
	var to_n := npc.global_position - Game.player.global_position
	var ruth_err := rad_to_deg(absf(angle_difference(Game.player.facing, atan2(-to_n.x, -to_n.z))))
	md.cine_end()
	md.cine_test = false
	var restored: bool = not md.cine and md._bars.is_empty()
	lines.append("camera: shots %s, letterbox %s, depth of field set %s (drawn on this renderer: %s), aimed at the speaker %s, one side of the line %s, gestures %d" % [
		"/".join(kinds), bars_up, dof_set, md.dof_drawn(), aim_ok, one_side, gestures])
	lines.append("facing: Wren to Ruth %.0f deg off, Ruth to Wren %.0f deg off; scene ended cleanly %s" % [face_err, ruth_err, restored])
	if kinds != ["two", "ots", "ots", "hold"] or not bars_up or not dof_set or not aim_ok or not one_side or gestures < 1 \
			or face_err > 40.0 or ruth_err > 10.0 or not restored:
		_fail(res, "conversation camera: %s / %s" % [lines[-2], lines[-1]])
	npc.queue_free()
	# ---------------------------------------------------------------- 2. mission bookends
	var P = load("res://src/missions/presentation.gd")
	var missing := []
	for path in MissionDirector.MISSIONS:
		var mm: Mission = load(path).new()
		if mm.stranger:
			continue
		var n: int = P.OBJECTIVES.get(mm.id, []).size()
		if n < 2 or n > 3 or not P.REGIONS.has(mm.id):
			missing.append(mm.id)
	if not missing.is_empty():
		_fail(res, "objectives/regions missing for %s" % ", ".join(missing))
	var g: Dictionary = P.rate("c3_fork", {"time": 300.0, "shots": 10, "hits": 7, "headshots": 1, "damage": 0.0, "civilians": 0}, {"fork_quiet": true, "cutter_fate": "jailed"})
	var s2: Dictionary = P.rate("c3_fork", {"time": 300.0, "shots": 10, "hits": 2, "headshots": 1, "damage": 0.0, "civilians": 0}, {"fork_quiet": true, "cutter_fate": "dead"})
	var b3: Dictionary = P.rate("c3_fork", {"time": 300.0, "shots": 10, "hits": 2, "headshots": 1, "damage": 0.0, "civilians": 0}, {"fork_quiet": false, "cutter_fate": "dead"})
	lines.append("medals for the Dry Fork: all three met %s, one met %s, none met %s" % [g.medal, s2.medal, b3.medal])
	if g.medal != "gold" or s2.medal != "bronze" or b3.medal != "bronze":
		_fail(res, "medal rating: %s" % lines.back())
	var two: Dictionary = P.rate("c3_fork", {"time": 300.0, "shots": 10, "hits": 7, "headshots": 1, "damage": 0.0, "civilians": 0}, {"fork_quiet": true, "cutter_fate": "dead"})
	if two.medal != "silver":
		_fail(res, "two of three should be silver, got %s" % two.medal)
	var log0 := Game.log_lines.size()
	md.autopilot = true
	md.step_timeout = 60.0
	var m1: Mission = load("res://src/missions/ch1/rider_from_the_west.gd").new()
	await md.start(m1)
	var title := {}
	var results := {}
	for i in range(log0, Game.log_lines.size()):
		var ln: String = Game.log_lines[i]
		var parts := ln.split(" ", false, 2)
		if parts.size() < 3:
			continue
		if parts[1] == "title_card":
			title = JSON.parse_string(parts[2])
		elif parts[1] == "mission_results":
			results = JSON.parse_string(parts[2])
	var stored: Dictionary = st.flags.get("medals", {}).get("c1_rider", {})
	var jline: String = P.medal_text("c1_rider", st.flags)
	lines.append("title card: %s | %s" % [title.get("chapter", "?"), title.get("line", "?")])
	lines.append("results: medal %s, objectives met %s/%s; stored in WorldState %s; journal line '%s'" % [results.get("medal", "?"),
		results.get("met", "?"), results.get("of", "?"), not stored.is_empty(), jline])
	if not str(title.get("chapter", "")).begins_with("Chapter One") or not str(title.get("line", "")).contains("1899") \
			or results.is_empty() or stored.is_empty() or jline == "":
		_fail(res, "bookends: %s / %s" % [lines[-2], lines[-1]])
	# ---------------------------------------------------------------- 3. loose ends
	var tr = Game.get_meta("treasure") if Game.has_meta("treasure") else null
	var buyers := get_tree().get_nodes_in_group("interactable").filter(func(n): return str(n.name).begins_with("GoldBuyer_"))
	if tr != null:
		st.inventory["gold_bar"] = 3
		st.wanted = 1
		var refused: float = tr.sell_gold("bank")
		st.wanted = 0
		var m0: float = st.money
		var bank: float = tr.sell_gold("bank")
		st.inventory["gold_bar"] = 2
		var fence: float = tr.sell_gold("fence")
		lines.append("gold: buyers placed %d; bank while wanted $%d; bank $%d for 3; fence $%d for 2; money +$%d" % [buyers.size(), int(refused), int(bank), int(fence), int(st.money - m0)])
		if buyers.size() != 2 or refused != 0.0 or bank != 540.0 or fence != 250.0:
			_fail(res, "gold sale: %s" % lines.back())
	var of = Game.get_meta("outfits") if Game.has_meta("outfits") else null
	if of != null:
		st.inventory["outfit_ironhide"] = 1
		var n_on: int = of.wear("ironhide")
		var worn: String = of.worn()
		var n_off: int = of.take_off()
		lines.append("outfit: Ironhide coat changed %d surface(s) on Ruth's figure, worn '%s'; taken off -> %d dressed" % [n_on, worn, n_off])
		if n_on < 1 or worn != "ironhide" or n_off != 0:
			_fail(res, "outfit: %s" % lines.back())
	var boards := get_tree().get_nodes_in_group("interactable").filter(func(n): return n.has_method("accept") and n.has_method("refresh"))
	var b_from = null
	var b_to = null
	for b in boards:
		if str(b.town_id) == "bitter_spring":
			b_from = b
		elif str(b.town_id) == "port_linden":
			b_to = b
	if b_from != null and b_to != null:
		b_from.refresh()
		var reward: float = b_from.posters[0].reward
		var name: String = b_from.posters[0].name
		b_from.auto_turn_in = false
		md._choice_queue = [0]
		var m2: float = st.money
		b_from.accept(0)
		for i in 600:
			await get_tree().physics_frame
			if b_from.stage == "carry":
				break
		var prompt: String = b_to.interact_prompt()
		b_to.interact(Game.player)
		await get_tree().physics_frame
		var at_town := ""
		for i in range(Game.log_lines.size() - 1, -1, -1):
			var ln: String = Game.log_lines[i]
			if ln.contains(" bounty_paid "):
				at_town = str(JSON.parse_string(ln.split(" ", false, 2)[2]).get("at", ""))
				break
		lines.append("bounty taken at Bitter Spring, %s turned in at %s ('%s'): paid $%.2f" % [name, at_town, prompt, st.money - m2])
		if at_town != "port_linden" or absf(st.money - m2 - reward * 1.5) > 0.01 or not b_from.active.is_empty():
			_fail(res, "turn-in at any sheriff: %s" % lines.back())
		b_from.auto_turn_in = true
	md.autopilot = false
	for ln in lines:
		print("  " + ln)
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

## Living-world bot: horse bond and care (brush, feed, calm, pat; bond levels raise stamina, courage and whistle
## range; mud on the coat cleaned), travel (train and stage counters, fare, hours, arrival with the horse, refusal
## when wanted, discovery and the camp map table), camp life (ledger, food, stocks with props, supplies, chores at
## camp spots, morale-coloured barks) and temperature (cold at altitude at night, heat in the Ocotillo, breath fog,
## drain, outfit warmth).
func _run_living() -> Dictionary:
	var res := {"bot": "living", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": []}
	var err0: int = Game.error_logger.take().size()
	var md: MissionDirector = Game.missions
	var st = Game.state
	for i in 150:
		await get_tree().process_frame
	var lines := []
	st.money = 500.0
	# ---------------------------------------------------------------- 1. horse bond
	var hc = Game.get_meta("horse_care") if Game.has_meta("horse_care") else null
	var h: Horse = Horse.player_horse if is_instance_valid(Horse.player_horse) else null
	if hc == null or h == null:
		_fail(res, "no horse or horse care (%s, %s)" % [hc, h])
	else:
		if h.rider != null:
			md.dismount_player()
		h.bond_xp = 0.0
		st.flags["horse_bond_xp"] = 0.0
		h._cores(0.0)
		var st1: float = h.stamina_max
		h.dirt = 0.8
		h.mud = 0.6
		var cleaned: float = hc.brush()
		var spot_ok: bool = h.get_node_or_null("CareSpot") != null
		for it in ["horse_oats", "apple", "carrot"]:
			st.add_item(it, 2)
		var fed := 0
		for it in ["horse_oats", "apple", "carrot"]:
			if hc.feed(it):
				fed += 1
		hc.calm()
		var patted: bool = hc.pat()
		var xp1: float = h.bond_xp
		# reach level 4 and compare
		h.fear = 1.0
		h._fear_update(1.0)
		var fear_l1: float = h.fear
		var far := Game.player.global_position + Vector3(380.0, 0, 0)
		var lvl1 := h.bond_level
		h.global_position = far
		var heard1: bool = h.whistle(Game.player)
		h.bond_xp = 1100.0
		h._cores(0.0)
		h.global_position = far
		h.state = Horse.State.FREE
		var heard4: bool = h.whistle(Game.player)
		h.fear = 1.0
		h._fear_update(1.0)
		var fear_l4: float = h.fear
		var st4: float = h.stamina_max
		var saved_xp := float(st.flags.get("horse_bond_xp", 0.0))
		for i in 3:
			await get_tree().create_timer(1.1).timeout
		saved_xp = float(st.flags.get("horse_bond_xp", 0.0))
		lines.append("horse: care spot %s; brushed %.2f of dirt+mud off (now %.2f); fed %d kinds, calmed, patted %s -> bond xp %.0f (level %d)" % [
			spot_ok, cleaned, h.dirt + h.mud, fed, patted, xp1, lvl1])
		lines.append("bond 1 vs 4: whistle at 380 m heard %s / %s (range %d / %d m); stamina %d / %d; fear after 1 s %.2f / %.2f; throw chance %.2f / %.2f; saved xp %.0f" % [
			heard1, heard4, int(h.WHISTLE_RANGE[0]), int(h.WHISTLE_RANGE[3]), int(st1), int(st4), fear_l1, fear_l4, h.THROW_CHANCE[0], h.THROW_CHANCE[3], saved_xp])
		if not spot_ok or cleaned < 1.3 or h.dirt + h.mud > 0.01 or fed != 3 or not patted or xp1 < 60.0 or heard1 or not heard4 \
				or st4 < st1 * 1.29 or fear_l4 >= fear_l1 or saved_xp < 1100.0:
			_fail(res, "horse bond: %s / %s" % [lines[-2], lines[-1]])
		h.global_position = Game.player.global_position + Vector3(3, 0, 2)
		h.state = Horse.State.FREE
	# ---------------------------------------------------------------- 2. travel
	var tv = Game.get_meta("travel") if Game.has_meta("travel") else null
	if tv == null:
		_fail(res, "no travel system")
	else:
		var trains: int = tv.counters.filter(func(c): return c.mode == "train").size()
		var stages: int = tv.counters.filter(func(c): return c.mode == "stage").size()
		md._teleport_player(tv.counter_pos("train", "bitter_spring"))
		st.wanted = 2
		var refused: bool = not await tv.travel("train", "bitter_spring", "port_linden")
		st.wanted = 0
		var f: Dictionary = tv.fare("train", "bitter_spring", "port_linden")
		var m0: float = st.money
		var h0: float = Game.sky.hours + Game.sky.day * 24.0
		var went: bool = await tv.travel("train", "bitter_spring", "port_linden")
		var dh: float = Game.sky.hours + Game.sky.day * 24.0 - h0
		var arrive_d: float = Game.player.global_position.distance_to(tv.counter_pos("train", "port_linden"))
		var horse_d: float = Horse.player_horse.global_position.distance_to(Game.player.global_position) if is_instance_valid(Horse.player_horse) else -1.0
		for i in 3:
			await get_tree().create_timer(1.1).timeout
		var disc: bool = tv.discovered().has("port_linden")
		for i in 6:
			if not load("res://src/missions/places.gd").spot(load("res://src/missions/places.gd").building("port_linden", "depot"), "ticket_agent").is_empty():
				break
			await get_tree().create_timer(1.0).timeout
		await get_tree().create_timer(2.2).timeout
		var from_spot: bool = load("res://src/missions/places.gd").spot(load("res://src/missions/places.gd").building("port_linden", "depot"), "ticket_agent").size() > 0
		# each railroad clerk stands at his town's depot (towns whose layout found room for one)
		var depots := []
		var depot_bad := 0
		for town in tv.TRAIN_STOPS:
			var dep: Dictionary = tv.any_building(town, "depot")
			var where := "depot"
			if dep.is_empty():
				dep = tv.any_building(town, "post")
				where = "telegraph office"
			if dep.is_empty():
				dep = tv.any_building(town, "water_tower")
				where = "water tower"
			var ck: Array = tv.counters.filter(func(c): return c.mode == "train" and c.town == town)
			if dep.is_empty() or ck.is_empty():
				depots.append("%s none" % town)
				depot_bad += 1
				continue
			var dd: float = Vector2(ck[0].global_position.x - dep.transform.origin.x, ck[0].global_position.z - dep.transform.origin.z).length()
			depots.append("%s %s %.1f m" % [town, where, dd])
			if dd > 16.0:
				depot_bad += 1
		var pl_clerk: Array = tv.counters.filter(func(c): return c.mode == "train" and c.town == "port_linden")
		var clerk_d: float = pl_clerk[0].global_position.distance_to(tv.counter_pos("train", "port_linden")) if pl_clerk.size() > 0 else -1.0
		lines.append("travel: counters train %d, stage %d (Port Linden depot ticket_agent spot %s, clerk %.1f m from where it should stand; clerk to depot: %s); refused while wanted %s; train to Port Linden %s for $%.2f (fare $%.2f), %.1f hours passed (%.1f), arrived %.1f m from the agent, horse %.1f m away, Port Linden discovered %s" % [
			trains, stages, from_spot, clerk_d, ", ".join(depots), refused, went, m0 - st.money, f.price, dh, f.hours, arrive_d, horse_d, disc])
		if trains != 3 or stages != 5 or not refused or not went or absf(m0 - st.money - float(f.price)) > 0.01 or absf(dh - float(f.hours)) > 0.05 \
				or arrive_d > 6.0 or horse_d < 0.0 or horse_d > 8.0 or not disc or clerk_d < 0.0 or clerk_d > 0.6 or depot_bad > 0:
			_fail(res, "travel: %s" % lines.back())
		var sf: Dictionary = tv.fare("stage", "port_linden", "coldwater")
		var sw: bool = await tv.travel("stage", "port_linden", "coldwater")
		tv.discovered()["greer_post"] = true
		var dests: Array = tv.destinations()
		md._teleport_player(Mission.place("caddell_camp", 3.0, -2.0))
		var rode: bool = await tv.travel("ride", "caddell_camp", "greer_post")
		var at_greer: float = Game.player.global_position.distance_to(Mission.place("greer_post"))
		var table_ok := get_tree().get_nodes_in_group("interactable").any(func(n): return str(n.name) == "MapTable")
		lines.append("stage to Coldwater %s ($%.2f, %.1f h); map table %s, destinations %s; rode to Greer's %s (%.0f m from the post)" % [sw, sf.price, sf.hours, table_ok, ", ".join(dests), rode, at_greer])
		if not sw or not table_ok or not dests.has("greer_post") or not rode or at_greer > 40.0:
			_fail(res, "fast travel: %s" % lines.back())
	# ---------------------------------------------------------------- 3. camp life
	var camp = Game.get("camp")
	if camp == null:
		_fail(res, "no camp")
	else:
		md._teleport_player(Mission.place("caddell_camp", 4.0, 4.0))
		for i in 30:
			await get_tree().physics_frame
		st.flags["camp_ledger"] = 0.0
		st.flags["camp_stock"] = {}
		st.flags["camp_morale_bonus"] = 0.0
		var mor0: float = camp.morale()
		camp.contribute(50.0)
		st.add_item("meat_mule_deer", 4)
		var food: float = camp.donate_food()
		var l1: int = camp.upgrade("provisions")
		var l2: int = camp.upgrade("ammo")
		var too_much: int = camp.upgrade("medicine")
		var props_p: int = camp.stock_prop_count("provisions")
		var props_a: int = camp.stock_prop_count("ammo")
		var ammo0: int = int(Game.player.gun.ammo.get("revolver", 0))
		var sup: Dictionary = camp.take_supplies()
		var again: Dictionary = camp.take_supplies()
		var mor1: float = camp.morale()
		var ch: Dictionary = camp.chore_for("hap", 6.0)
		var ch2: Dictionary = camp.chore_for("billy", 10.0)
		var ctx: Dictionary = camp.context()
		ctx["morale"] = 85.0
		var hi := false
		var lo := false
		for i in 60:
			if str(camp.pick_bark("hap", ctx).get("line", "")) == "camp_hap_morale_high":
				hi = true
		ctx["morale"] = 20.0
		for i in 60:
			if str(camp.pick_bark("hap", ctx).get("line", "")) == "camp_hap_morale_low":
				lo = true
		lines.append("camp: gave $50 + food worth $%.2f; provisions -> %d, ammo -> %d, medicine refused (%d); props %d/%d; supplies %s (again %s), revolver +%d; morale %.0f -> %.0f (%s)" % [
			food, l1, l2, too_much, props_p, props_a, JSON.stringify(sup), JSON.stringify(again), int(Game.player.gun.ammo.get("revolver", 0)) - ammo0, mor0, mor1, camp.morale_band(mor1)])
		lines.append("chores: Hap at 6:00 -> %s at a camp spot %s; Billy at 10:00 -> %s (%s); morale barks high %s low %s" % [
			ch.get("activity", "?"), ch.get("from_spot", false), ch2.get("activity", "?"), ch2.get("from_spot", false), hi, lo])
		if food != 6.0 or l1 != 1 or l2 != 1 or too_much != -1 or (not Game.headless and (props_p != 2 or props_a != 2)) or props_p != 2 \
				or int(sup.get("rounds", 0)) != 24 or not again.is_empty() or mor1 <= mor0 or ch.is_empty() or not hi or not lo:
			_fail(res, "camp life: %s / %s" % [lines[-2], lines[-1]])
	# ---------------------------------------------------------------- 4. temperature and clothing
	var cl = Game.get_meta("climate") if Game.has_meta("climate") else null
	if cl == null:
		_fail(res, "no climate system")
	else:
		var C = cl.get_script()
		var peak := Mission.place("trapper_cabin_n")
		for r in [200.0, 500.0, 900.0]:
			for k in 12:
				var q := Mission.place("trapper_cabin_n") + Vector3(cos(TAU * k / 12.0) * r, 0, sin(TAU * k / 12.0) * r)
				q.y = Game.world.height(q.x, q.z)
				if q.y > peak.y and not Game.world.is_water(q.x, q.z):
					peak = q
		var hot := Mission.place("san_lazaro")
		var t_peak_night: float = C.temperature(peak, 2.0, "CLEAR", 4)
		var t_desert_noon: float = C.temperature(hot, 15.0, "CLEAR", 2)
		var t_valley_noon: float = C.temperature(Mission.place("bitter_spring"), 13.0, "FAIR", 1)
		lines.append("temperature: Kestrel %.0f m at 2 a.m. in winter %.1f °C; San Lazaro at 3 p.m. %.1f °C; Bitter Spring at 1 p.m. in October %.1f °C" % [peak.y, t_peak_night, t_desert_noon, t_valley_noon])
		if t_peak_night > -2.0 or t_desert_noon < 32.0 or t_valley_noon < 12.0 or t_valley_noon > 26.0:
			_fail(res, "temperature model: %s" % lines.back())
		# live: cold on the mountain at night in her own clothes, then in the bearskin coat
		st.flags.erase("outfit_worn")
		md.completed.append("c4_coldwater")
		Game.sky.set_time(2.0)
		md._teleport_player(peak)
		Game.player.stamina = Game.player.STAMINA_MAX
		var hp0: float = Game.player.damageable.health
		for i in 4:
			await get_tree().create_timer(1.05).timeout
		var cold_own: float = cl.cold
		var breath: bool = cl.breath_on
		var stam_after: float = Game.player.stamina
		var hp_after: float = Game.player.damageable.health
		st.add_item("outfit_ironhide", 1)
		st.flags["outfit_worn"] = "ironhide"
		for i in 2:
			await get_tree().create_timer(1.05).timeout
		var cold_coat: float = cl.cold
		# heat in the Ocotillo at 3 p.m.: the bearskin is too much, the Pale Ghost vest is not
		md.completed.erase("c4_coldwater")
		Game.sky.set_time(15.0)
		md._teleport_player(hot)
		for i in 2:
			await get_tree().create_timer(1.05).timeout
		var heat_coat: float = cl.heat
		st.add_item("outfit_pale_ghost", 1)
		st.flags["outfit_worn"] = "pale_ghost"
		for i in 2:
			await get_tree().create_timer(1.05).timeout
		var heat_vest: float = cl.heat
		st.flags.erase("outfit_worn")
		lines.append("climate live: mountain night cold %.2f in her own clothes (breath fog %s, stamina %.0f -> %.0f, health %.0f -> %.0f), %.2f in the Ironhide coat; desert afternoon heat %.2f in the coat, %.2f in the Pale Ghost vest" % [
			cold_own, breath, Game.player.STAMINA_MAX, stam_after, hp0, hp_after, cold_coat, heat_coat, heat_vest])
		if cold_own <= 0.0 or not breath or stam_after >= Game.player.STAMINA_MAX or hp_after >= hp0 or cold_coat >= cold_own \
				or heat_coat <= 0.0 or heat_vest >= heat_coat:
			_fail(res, "climate: %s" % lines.back())
	for ln in lines:
		print("  " + ln)
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)

func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "fps": 0.0, "low1": 0.0}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var avg := sum / s.size()
	var p := func(q: float) -> float: return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]
	# 1% low fps = average fps over the slowest 1% of frames
	var n1 := maxi(1, s.size() / 100)
	var worst := 0.0
	for i in n1:
		worst += s[s.size() - 1 - i]
	return {"avg": avg, "p50": p.call(0.5), "p95": p.call(0.95), "p99": p.call(0.99), "max": s[s.size() - 1],
		"fps": 1000.0 / avg, "low1": 1000.0 / (worst / n1)}

# ------------------------------------------------------------------ benchmark
## Scripted route through representative scenes; frame-time percentiles + memory to benchmark.json.
func _benchmark() -> void:
	var w: WorldData = Game.world
	var town := w.town("bitter_spring")
	var segs := [
		{"name": "town_street", "kind": "walk", "from": Vector3(town.x - 60, 0, town.z), "to": Vector3(town.x + 60, 0, town.z + 10), "secs": 20.0},
		{"name": "river_valley_ride", "kind": "fly", "from": Vector3(-380, 0, -400), "to": Vector3(300, 0, 200), "secs": 20.0, "up": 2.2},
		{"name": "forest", "kind": "fly", "from": Vector3(1500, 0, -1900), "to": Vector3(1900, 0, -1500), "secs": 15.0, "up": 1.8},
		{"name": "vista", "kind": "fly", "from": Vector3(-1400, 0, -900), "to": Vector3(-1000, 0, -1300), "secs": 15.0, "up": 40.0},
		{"name": "desert", "kind": "fly", "from": Vector3(-2400, 0, 1700), "to": Vector3(-2000, 0, 2100), "secs": 15.0, "up": 2.0},
	]
	var secs_scale := Game.arg_f("bench_scale", 1.0)
	var out := {"version": ProjectSettings.get_setting("application/config/version"), "quality": Game.quality_name,
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "resolution": [get_viewport().size.x, get_viewport().size.y],
		"render_scale": get_viewport().scaling_3d_scale, "commit": str(Game.args.get("commit", "")), "segments": []}
	var all := PackedFloat32Array()
	var load_t0 := Time.get_ticks_msec()
	# --bench_segments forest,desert: run only these; --bench_settle N: streaming frames before recording (default 30;
	# prims per frame need only a few, which keeps software-renderer geometry measurements short)
	if Game.args.has("bench_segments"):
		var only: PackedStringArray = str(Game.args["bench_segments"]).split(",")
		segs = segs.filter(func(sg): return only.has(sg.name))
	var settle := int(Game.args.get("bench_settle", 30))
	for sg in segs:
		var a: Vector3 = sg.from
		var b: Vector3 = sg.to
		a.y = w.height(a.x, a.z)
		var cam: Camera3D = Game.camera
		if sg.kind == "walk":
			player.global_position = a + Vector3(0, 1.0, 0)
			Game.terrain.ensure_collision_at(player.global_position)
		else:
			player.on_horse = self     # park the player controller; camera is scripted
			cam.global_position = a + Vector3(0, sg.get("up", 2.0), 0)
		if main.vegetation and main.vegetation.has_method("settle_now"):
			main.vegetation.settle_now()
		if main.scatter != null and main.scatter.has_method("settle_now"):
			main.scatter.settle_now()
		for i in settle:
			await get_tree().process_frame
		_frame_ms = PackedFloat32Array()
		_spikes = 0
		_recording = true
		var t := 0.0
		var dur: float = sg.secs * secs_scale
		var draws := 0.0
		var prims := 0.0
		var objs := 0.0
		var nsamp := 0
		while t < dur:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			t += dt
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			nsamp += 1
			var f := t / dur
			if sg.kind == "walk":
				var to: Vector3 = b - player.global_position
				player.cam_yaw = atan2(-to.x, -to.z)
				player.intent.move = Vector2(0, 1)
			else:
				var p := a.lerp(b, f)
				p.y = maxf(w.height(p.x, p.z), w.water_level(p.x, p.z)) + sg.get("up", 2.0)
				var ahead := a.lerp(b, minf(f + 0.05, 1.0))
				ahead.y = p.y - 1.0
				cam.global_position = p
				cam.look_at(ahead + Vector3(0, 0.6, 0) if ahead.distance_to(p) > 0.5 else p + Vector3(1, 0, 0), Vector3.UP)
		_recording = false
		player.intent.move = Vector2.ZERO
		player.on_horse = null
		var st := _stats(_frame_ms)
		st["name"] = sg.name
		st["spikes_over_100ms"] = _spikes
		st["frames"] = _frame_ms.size()
		st["draw_calls"] = draws / maxf(nsamp, 1.0)
		st["primitives_k"] = prims / maxf(nsamp, 1.0) / 1000.0
		st["objects"] = objs / maxf(nsamp, 1.0)
		out.segments.append(st)
		all.append_array(_frame_ms)
		print("BENCH %-18s avg %.2f ms (%.0f fps)  p95 %.2f  p99 %.2f  1%%low %.0f fps  max %.1f  draws %.0f  prims %.0fk  objects %.0f" % [sg.name, st.avg, st.fps, st.p95, st.p99, st.low1, st.max, st.draw_calls, st.primitives_k, st.objects])
	var tot := _stats(all)
	out["overall"] = tot
	out["bench_seconds"] = (Time.get_ticks_msec() - load_t0) / 1000.0
	out["memory"] = _memory()
	out["errors"] = Game.error_logger.take().size()
	print("BENCH overall avg %.2f ms (%.0f fps)  1%%low %.0f fps  p99 %.2f ms  rss %.0f MB  vram %.0f MB" % [tot.avg, tot.fps, tot.low1, tot.p99, out.memory.rss_mb, out.memory.video_mb])
	var path := str(Game.args.get("bench_out", ""))
	if path == "":
		if OS.get_name() == "macOS":
			var dir := OS.get_environment("HOME").path_join("Library/Logs/Frontier")
			DirAccess.make_dir_recursive_absolute(dir)
			path = dir.path_join("benchmark.json")
		else:
			path = ProjectSettings.globalize_path("user://benchmark.json")
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(out, "  "))
		print("BENCH wrote ", path)

func _memory() -> Dictionary:
	var m := {"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"rss_mb": 0.0}
	var outp := []
	if OS.get_name() in ["macOS", "Linux"]:
		OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], outp)
		if outp.size() > 0:
			m.rss_mb = float(str(outp[0]).strip_edges()) / 1024.0
	return m

## What each bot actually exercised, for the summary line (critics read these; zeros must mean something).
static func _metrics(res: Dictionary) -> String:
	var out := ""
	for k in ["enemies", "enemy_shots", "enemy_hits", "engaged", "used_cover", "flanked", "killed", "player_shots", "player_hits", "player_hits_taken",
			"npcs", "npc_minutes", "pelt_quality", "kills", "skinned", "lines_said", "stances", "slide_cm"]:
		if res.has(k):
			var v = res[k]
			out += ("  %s=%.1f" % [k, v]) if typeof(v) == TYPE_FLOAT else ("  %s=%s" % [k, str(v)])
	for k in res.get("metrics", {}):
		out += "  %s=%s" % [k, str(res.metrics[k])]
	if res.has("completed"):
		out += "  missions=%d" % res.completed.size()
	if res.has("choices"):
		out += "  choices=%d" % res.choices.size()
	if res.has("checks"):
		var parts: PackedStringArray = []
		for k in res.checks.keys():
			var v = res.checks[k]
			parts.append("%s:%s" % [k, str(v.size()) if typeof(v) in [TYPE_ARRAY, TYPE_DICTIONARY] else str(v)])
		out += "  checks=[%s]" % ", ".join(parts)
	return out
