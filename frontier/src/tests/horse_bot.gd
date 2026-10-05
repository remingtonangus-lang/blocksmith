extends Node
## Horse bots (called from bot_runner.gd). Both mount the player's horse and drive it only through the rider's
## `intent` (stick + sprint taps + camera yaw), the same path a human uses.
##   ride   town to town along a road at canter/gallop (tapping sprint for pace, easing off when stamina is low);
##          oracles: NaN, below terrain, left map, stuck, falls/stumbles, thrown off, long airborne, script errors.
##          Also records hoof contacts during steady canter/gallop stretches for the gait oracle.
##   gaits  rides each gait (walk/trot/canter/gallop) along a road and runs the gait oracle per gait:
##          footfall beats + order vs the reference table and foot slide (cm of planted-hoof drift per stance).
## Options: --ride_to <town id> (default mesquite_wells), --ride_seconds N (default: --seconds).

var runner
var horse: Horse
var player

func run(kind: String, seconds: float, r) -> Dictionary:
	runner = r
	player = Game.player
	horse = Horse.player_horse
	var res := {"bot": kind, "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "frame_avg_ms": 0.0, "frame_p99_ms": 0.0, "gaits": {}}
	if horse == null:
		_fail(res, "no player horse spawned")
		return res
	var err0: int = Game.error_logger.take().size()
	if kind == "ride":
		await _ride(res, Game.arg_f("ride_seconds", seconds))
	else:
		await _gaits(res)
	runner._recording = false
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d engine/script/shader errors, first: %s" % [errs.size(), str(errs[0])])
	res.frame_spikes = runner._spikes
	var st: Dictionary = runner._stats(runner._frame_ms)
	res.frame_avg_ms = st.avg
	res.frame_p99_ms = st.p99
	for g in res.gaits:
		print(HorseGaitOracle.format_line(g, res.gaits[g]))
	if horse.rider != null:
		horse.dismount(-1.0)
	return res

func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)

func _road(to: String) -> Array:
	var pts := []
	for rd in Game.world.features.roads:
		if (rd.a == "bitter_spring" and rd.b == to) or (rd.b == "bitter_spring" and rd.a == to):
			for p in rd.points:
				pts.append(Vector3(p[0], p[2], p[1]))
			if rd.b == "bitter_spring":
				pts.reverse()
			break
	return pts

## First route index clear of any settlement (towns have buildings across the old road line now).
func _outside_town(route: Array) -> int:
	var st = Game.main.get("settlements")
	for i in route.size() - 3:
		var p: Vector3 = route[i]
		var inside := false
		if st and st.has_method("town_at"):
			inside = st.town_at(p, 25.0) != ""
		if not inside:
			return i
	return 0

func _start_at(p: Vector3, toward: Vector3) -> void:
	var w: WorldData = Game.world
	p.y = w.height(p.x, p.z)
	Game.terrain.ensure_collision_at(p)
	if horse.rider != null:
		horse.dismount(-1.0)
	horse.global_position = p
	horse.speed = 0.0
	var d := toward - p
	horse.yaw = atan2(-d.x, -d.z)
	horse.rotation.y = horse.yaw
	horse.stamina = horse.stamina_max
	var side := horse.global_transform * Vector3(-1.0, 0.0, 0.0)
	side.y = w.height(side.x, side.z) + 0.1
	player.global_position = side
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	if not horse.mount(player, -1.0):
		return
	for i in 70:
		await get_tree().physics_frame

## Advance along the route with a look-ahead point; returns the new waypoint index.
func _steer(route: Array, wp: int, look := 9.0) -> int:
	var pos: Vector3 = horse.global_position
	while wp < route.size() - 1 and Vector2(route[wp].x - pos.x, route[wp].z - pos.z).length() < look:
		wp += 1
	var tgt: Vector3 = route[wp]
	var to := Vector3(tgt.x - pos.x, 0, tgt.z - pos.z)
	player.cam_yaw = atan2(-to.x, -to.z)
	player.intent.move = Vector2(0, 1)
	return wp

func _tap_to(target_pace: int, t: float) -> void:
	# tap sprint (press/release every 0.25 s) until the horse reaches the pace; hold it for a gallop
	if horse.pace < target_pace:
		player.intent.sprint = fmod(t, 0.5) < 0.25
	else:
		player.intent.sprint = target_pace == 3 and fmod(t, 1.2) < 0.9

func _ride(res: Dictionary, seconds: float) -> void:
	var w: WorldData = Game.world
	var to := str(Game.args.get("ride_to", "mesquite_wells"))
	var route := _road(to)
	if route.size() < 3:
		_fail(res, "no road bitter_spring -> " + to)
		return
	var s0 := _outside_town(route)
	await _start_at(route[s0], route[mini(s0 + 2, route.size() - 1)])
	if horse.rider != player:
		_fail(res, "could not mount")
		return
	res["waypoints"] = route.size()
	var t := 0.0
	var wp := s0 + 1
	var last: Vector3 = horse.global_position
	var anchor: Vector3 = last
	var stuck_t := 0.0
	var air_t := 0.0
	var warm := 0
	var seg := {"gait": "", "t": 0.0, "samples": []}
	var best_seg := {}
	var arrived := false
	var falls0 := horse.falls
	while t < seconds:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		warm += 1
		runner._recording = warm > 120
		wp = _steer(route, wp)
		var end: Vector3 = route[route.size() - 1]
		if Vector2(end.x - horse.global_position.x, end.z - horse.global_position.z).length() < 12.0:
			arrived = true
			break
		# pace: gallop while stamina allows, else canter
		var want := 3 if horse.stamina > 35.0 else 2
		if horse.stamina < 12.0:
			want = 2
		_tap_to(want, t)
		var pos: Vector3 = horse.global_position
		res.distance += Vector2(pos.x - last.x, pos.z - last.z).length()
		last = pos
		# --- gait recording on steady stretches
		var g: String = horse.gait + ("_r" if horse.lead_right and horse.gait in ["canter", "gallop"] else "")
		if g != seg.gait:
			_keep_best(best_seg, seg)
			seg = {"gait": g, "t": 0.0, "samples": []}
			horse.gait_samples = []
		seg.t += dt
		horse.record_gait = seg.t > 1.0 and g in ["canter", "gallop", "canter_r", "gallop_r"]
		if horse.record_gait:
			seg.samples = horse.gait_samples
		# --- oracles
		if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
			_fail(res, "NaN horse position at t=%.1f" % t)
			break
		var gy := w.height(pos.x, pos.z)
		if pos.y < gy - 0.8:
			_fail(res, "horse below terrain at (%.0f, %.1f, %.0f), ground %.1f" % [pos.x, pos.y, pos.z, gy])
			res.fall_events += 1
			break
		if not w.in_bounds(pos.x, pos.z):
			_fail(res, "left the map")
			break
		if horse.airborne:
			air_t += dt
			if air_t > 4.0:
				_fail(res, "airborne > 4 s at (%.0f, %.0f)" % [pos.x, pos.z])
				break
		else:
			air_t = 0.0
		if horse.rider != player:
			_fail(res, "rider came off at t=%.1f (%s)" % [t, "fall" if horse.falls > falls0 else "dismount"])
			res.fall_events += 1
			break
		stuck_t += dt
		if stuck_t > 8.0:
			if pos.distance_to(anchor) < 3.0:
				res.stuck_events += 1
				Game.log_event("horse_bot_stuck", {"pos": [pos.x, pos.y, pos.z]})
				wp = mini(wp + 2, route.size() - 1)
				if res.stuck_events > 2:
					_fail(res, "stuck near (%.0f, %.0f)" % [pos.x, pos.z])
					break
			stuck_t = 0.0
			anchor = pos
	horse.record_gait = false
	_keep_best(best_seg, seg)
	player.intent.move = Vector2.ZERO
	player.intent.sprint = false
	res["arrived"] = arrived
	res["waypoints_reached"] = wp
	res["stumbles"] = horse.stumbles
	res["avg_speed"] = res.distance / maxf(t, 0.01)
	print("RIDE to %s: %s  %.0f m in %.0f s (avg %.1f m/s)  waypoints %d/%d  stumbles %d  stamina %.0f" % [to,
		"ARRIVED" if arrived else "en route", res.distance, t, res.avg_speed, wp, route.size(), horse.stumbles, horse.stamina])
	if horse.falls > falls0:
		res.fall_events += horse.falls - falls0
		_fail(res, "horse fell %d times" % (horse.falls - falls0))
	if not arrived and wp - s0 < mini(route.size() - 1 - s0, 8):
		_fail(res, "reached only %d/%d waypoints" % [wp, route.size()])
	for g in best_seg:
		var s: Dictionary = best_seg[g]
		var cyc: float = horse.visual.gait_info(g.trim_suffix("_r")).get("cycle", 0.0)
		res.gaits[g + "(ride)"] = HorseGaitOracle.analyse_samples(s.samples, g, 0.0 if cyc == 0.0 else cyc)

func _keep_best(best: Dictionary, seg: Dictionary) -> void:
	if seg.samples.size() < 60:
		return
	var g: String = seg.gait
	if not best.has(g) or best[g].samples.size() < seg.samples.size():
		best[g] = {"samples": seg.samples.duplicate()}

func _gaits(res: Dictionary) -> void:
	var route := _road(str(Game.args.get("gait_road", "port_linden")))
	if route.size() < 10:
		_fail(res, "no road for the gait test")
		return
	if not horse.visual.has_model:
		print("GAIT ORACLE: SKIP (no horse model)")
		return
	var s0 := _outside_town(route)
	await _start_at(route[s0], route[mini(s0 + 2, route.size() - 1)])
	var wp := s0 + 1
	var t := 0.0
	for gname in ["walk", "trot", "canter", "gallop"]:
		var p: int = Horse.PACE_NAMES.find(gname)
		horse.debug_pace = p
		horse.record_gait = false
		var settle := 0.0
		var rec := 0.0
		var want_rec := 5.0 if gname == "walk" else 3.5
		while rec < want_rec:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			runner._recording = true
			wp = _steer(route, wp, 12.0)
			player.intent.sprint = false
			var g: String = horse.gait + ("_r" if horse.lead_right and horse.gait in ["canter", "gallop"] else "")
			if g.trim_suffix("_r") == gname and absf(horse.yaw_rate) < 0.25:
				settle += dt
			else:
				settle = 0.0
				if horse.record_gait:
					horse.record_gait = false
					rec = 0.0
			if settle > 1.5 and not horse.record_gait:
				horse.gait_samples = []
				horse.record_gait = true
			if horse.record_gait:
				rec += dt
			res.distance += horse.speed * dt
			if t > 120.0:
				_fail(res, "gait %s never settled" % gname)
				break
		horse.record_gait = false
		var gk: String = horse.gait + ("_r" if horse.lead_right and horse.gait in ["canter", "gallop"] else "")
		var cyc: float = horse.visual.gait_info(gname).get("cycle", 0.0) / maxf(absf(horse.speed) / maxf(horse.visual.gait_info(gname).get("speed", 1.0) * float(horse.stats.scale), 0.1), 0.1)
		var r := HorseGaitOracle.analyse_samples(horse.gait_samples, gk, cyc)
		res.gaits[gk] = r
		if not r.ok:
			_fail(res, "gait %s: %s" % [gk, str(r.failures)])
		elif r.slide_cm_avg > 10.0:
			_fail(res, "gait %s: feet slide %.1f cm per stance" % [gk, r.slide_cm_avg])
	horse.debug_pace = -1
	player.intent.move = Vector2.ZERO
	if horse.visual.ik:
		print("  foot IK: %d solves, last offsets %s" % [horse.visual.ik.calls, str(horse.visual.ik.offsets)])
	await _api_checks(res)

## Mount/dismount on both sides, whistle, fear, care: exercised once, failures become oracle failures.
func _api_checks(res: Dictionary) -> void:
	var notes := []
	for i in 60:
		await get_tree().physics_frame
	if not horse.dismount(1.0):
		_fail(res, "dismount right failed")
	var side: float = (player.global_position - horse.global_position).dot(horse.global_transform.basis.x)
	notes.append("dismount right side=%s" % ("ok" if side > 0.3 else "WRONG"))
	if side <= 0.3:
		_fail(res, "dismounted on the wrong side")
	# walk away, whistle: the horse must come within 4 m
	player.global_position = horse.global_position + Vector3(25, 0, 0)
	player.global_position.y = Game.world.height(player.global_position.x, player.global_position.z) + 0.1
	horse.call_to(player)
	var t := 0.0
	while t < 20.0 and horse.global_position.distance_to(player.global_position) > 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	notes.append("whistle: arrived in %.1f s" % t if t < 20.0 else "whistle: NOT arrived")
	if t >= 20.0:
		_fail(res, "called horse did not arrive")
	horse.dirt = 0.8
	horse.brush()
	horse.feed("oats")
	notes.append("brush dirt=%.1f bond_xp=%.0f" % [horse.dirt, horse.bond_xp])
	if not horse.mount(player, 1.0):
		_fail(res, "mount right failed")
	for i in 70:
		await get_tree().physics_frame
	notes.append("mounted right: on_horse=%s" % str(player.on_horse == horse))
	var r0 := horse.fear
	Horse.alarm(horse.global_position + Vector3(5, 0, 0), 40.0, 1.0, "gunfire")
	notes.append("gunfire fear %.2f -> %.2f" % [r0, horse.fear])
	if horse.fear <= r0:
		_fail(res, "horse not frightened by gunfire")
	for i in 120:
		await get_tree().physics_frame
	if horse.rider == null:
		notes.append("rider thrown by the rear (low bond)")
		horse.mount(player, -1.0)
	print("HORSE API: " + "; ".join(notes))
