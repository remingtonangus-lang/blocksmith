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
	var bots: Array = ["road", "explore", "ride", "gaits", "town", "gunfight", "hunt", "missions", "camp", "systems"] if which == "all" or which == "true" else Array(which.split(","))
	for b in bots:
		var res: Dictionary
		if b == "ride" or b == "gaits":
			var hb = load("res://src/tests/horse_bot.gd").new()
			add_child(hb)
			res = await hb.run(b, seconds, self)
			hb.queue_free()
		elif b == "missions":
			res = await _run_missions()
		elif b == "camp":
			res = await _run_camp()
		elif b == "town":
			res = await _run_town(seconds)
		elif b == "hunt":
			res = await load("res://src/tests/hunt_bot.gd").run(self, seconds)
		elif b == "systems":
			res = await load("res://src/tests/systems_bot.gd").run(self)
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
	var t := Game.world.town("bitter_spring")
	var p := Vector3(t.x, 0, t.z)
	p.y = Game.world.height(p.x, p.z) + 1.0
	Game.terrain.ensure_collision_at(p)
	player.global_position = p
	player.intent.move = Vector2.ZERO
	var err0: int = Game.error_logger.take().size()
	var el := 0.0
	var dur := minf(seconds, 90.0)
	var stuck0 := {}
	while el < dur:
		await get_tree().physics_frame
		el += get_physics_process_delta_time()
	var npcs := get_tree().get_nodes_in_group("humans")
	res.npcs = npcs.size()
	for h in npcs:
		res.stuck_events += h.stuck_events
		var gy := Game.world.height(h.global_position.x, h.global_position.z)
		if h.global_position.y < gy - 1.5:
			res.fall_events += 1
	res.npc_minutes = res.npcs * dur / 60.0
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
	for i in 30:
		var avail: Array = md.available()
		if avail.is_empty():
			break
		var m: Mission = avail[0]
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
		for i in 30:
			await get_tree().process_frame
		_frame_ms = PackedFloat32Array()
		_spikes = 0
		_recording = true
		var t := 0.0
		var dur: float = sg.secs * secs_scale
		while t < dur:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			t += dt
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
		out.segments.append(st)
		all.append_array(_frame_ms)
		print("BENCH %-18s avg %.2f ms (%.0f fps)  p95 %.2f  p99 %.2f  1%%low %.0f fps  max %.1f" % [sg.name, st.avg, st.fps, st.p95, st.p99, st.low1, st.max])
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
	for k in ["enemies", "engaged", "used_cover", "flanked", "killed", "player_shots", "player_hits", "player_hits_taken",
			"npcs", "npc_minutes", "pelt_quality", "kills", "skinned", "lines_said", "stances", "slide_cm"]:
		if res.has(k):
			var v = res[k]
			out += ("  %s=%.1f" % [k, v]) if typeof(v) == TYPE_FLOAT else ("  %s=%s" % [k, str(v)])
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
