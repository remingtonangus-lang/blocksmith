extends RefCounted
## Ecology oracle (--bot ecology): two in-game days of the wildlife system around a still observer, on a
## compressed clock. The sky runs 10x faster (a 4.8 min day) and the engine runs 3x, so two days take about 3
## real minutes. Animals move at their real speeds; only the day is shorter.
## Measures:
##   population   animal count sampled every 4 game-seconds after warm-up: min / mean / max, coefficient of
##                variation, and the first-day vs second-day means (no drift)
##   predation    predator chases and kills logged by the animals (plus the hawk's stoops)
##   herds        herd cohesion: the share of samples where every live member of a herd of 2+ is within 30 m of
##                the herd's centroid
##   activity     share of animals moving (> 0.3 m/s) by hour and activity type (day / night / crepuscular),
##                and the ratio of moving shares in and out of each type's active hours
## Pass: population >= 8 and <= 40 after warm-up, CV < 0.35, |day2 - day1| / mean < 0.3; at least one predator
## chase and one kill; cohesion >= 0.8; day and night species each move at least 1.5x more in their active hours.
## Options: --eco_days N (default 2).

const SKY_SCALE := 300.0
const ENGINE_SCALE := 3.0

static func run(runner: Node, _seconds: float) -> Dictionary:
	var res := {"bot": "ecology", "ok": true, "failures": [], "errors": []}
	var tree := runner.get_tree()
	var p = Game.player
	var w: WorldData = Game.world
	var err0: int = Game.error_logger.take().size()
	var days := Game.arg_f("eco_days", 2.0)
	# observer: a still point in the hills, lifted out of the animals' senses (they spawn and live around it)
	var c := Vector3(-300.0, 0, 600.0)
	for k in 24:
		var q := Vector3(-300.0 + 400.0 * cos(TAU * k / 24.0), 0, 600.0 + 400.0 * sin(TAU * k / 24.0))
		if w.in_bounds(q.x, q.z, 600.0) and not w.is_water(q.x, q.z):
			var b := w.ctrl(q.x, q.z).b
			if b > 0.45 and b < 0.8:
				c = q
				break
	c.y = w.height(c.x, c.z) + 160.0
	p.global_position = c
	# a fresh start: whatever earlier bots left behind goes, the ecology repopulates around the observer
	for a in tree.get_nodes_in_group("animals"):
		a.queue_free()
	if Game.wildlife:
		Game.wildlife.animals.clear()
		Game.wildlife.set("_queue", [])
		Game.wildlife.set_process(true)
	p.set_physics_process(false)
	var sky = Game.sky
	var old_scale: float = sky.time_scale
	sky.time_scale = SKY_SCALE
	sky.hours = 6.0
	Engine.time_scale = ENGINE_SCALE
	Engine.max_physics_steps_per_frame = 12
	var log0 := Game.log_lines.size()
	var game_t := 0.0
	var day_len := 86400.0 / SKY_SCALE
	var total := day_len * days
	var warm := day_len * 0.15
	var pops: Array = []
	var pop_day := [[], []]
	var cohesion_ok := 0
	var cohesion_n := 0
	var moving := {"day": [], "night": [], "crepuscular": []}      # [hour, moving_share] samples
	var next_sample := 0.0
	var last_pos := {}
	while game_t < total:
		await tree.physics_frame
		game_t += runner.get_physics_process_delta_time()
		if game_t < next_sample:
			continue
		next_sample = game_t + 4.0
		p.global_position = c
		var animals: Array = tree.get_nodes_in_group("animals").filter(func(a): return is_instance_valid(a) and a.alive)
		if game_t < warm:
			continue
		pops.append(animals.size())
		pop_day[mini(int(game_t / day_len), 1)].append(animals.size())
		# activity: moving share per activity type
		var counts := {"day": [0, 0], "night": [0, 0], "crepuscular": [0, 0]}
		for a in animals:
			var act: String = a.spec.get("active", "day")
			if not counts.has(act):
				continue
			counts[act][1] += 1
			if a.speed > 0.3:
				counts[act][0] += 1
		for act in counts:
			if counts[act][1] > 0:
				moving[act].append([float(sky.hours), float(counts[act][0]) / counts[act][1]])
		# herds
		var seen := {}
		for a in animals:
			var herd: Array = a.herd
			if herd.size() < 2 or seen.has(herd):
				continue
			seen[herd] = true
			var live: Array = herd.filter(func(m): return is_instance_valid(m) and m.alive)
			if live.size() < 2:
				continue
			var cen := Vector3.ZERO
			for m in live:
				cen += m.global_position
			cen /= live.size()
			var ok := true
			for m in live:
				if Vector2(m.global_position.x - cen.x, m.global_position.z - cen.z).length() > 30.0:
					ok = false
			cohesion_n += 1
			if ok:
				cohesion_ok += 1
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	sky.time_scale = old_scale
	p.set_physics_process(true)
	# events
	var chases := 0
	var kills := 0
	var dives := 0
	var by_pred := {}
	for i in range(log0, Game.log_lines.size()):
		var line: String = Game.log_lines[i]
		if line.contains(" predator_chase "):
			chases += 1
		elif line.contains(" predation "):
			kills += 1
			var j = JSON.parse_string(line.substr(line.find("{")))
			if j is Dictionary:
				by_pred[str(j.get("predator", "?"))] = int(by_pred.get(str(j.get("predator", "?")), 0)) + 1
		elif line.contains(" hawk_dive "):
			dives += 1
	# numbers
	var m := {}
	var pmin := 9999
	var pmax := 0
	var psum := 0.0
	for v in pops:
		pmin = mini(pmin, v)
		pmax = maxi(pmax, v)
		psum += v
	var mean := psum / maxf(pops.size(), 1)
	var var_ := 0.0
	for v in pops:
		var_ += (v - mean) * (v - mean)
	var cv := sqrt(var_ / maxf(pops.size(), 1)) / maxf(mean, 1.0)
	var d1 := _mean(pop_day[0])
	var d2 := _mean(pop_day[1])
	m["days"] = days
	m["population"] = "%d/%.1f/%d" % [pmin, mean, pmax]
	m["pop_cv"] = snappedf(cv, 0.01)
	m["pop_day1_day2"] = "%.1f/%.1f" % [d1, d2]
	m["chases"] = chases
	m["kills"] = kills
	m["kills_by"] = str(by_pred).replace(" ", "")
	m["hawk_dives"] = dives
	var coh := float(cohesion_ok) / maxf(cohesion_n, 1)
	m["herd_cohesion"] = snappedf(coh, 0.01)
	var ratios := {}
	for act in ["day", "night", "crepuscular"]:
		var on := []
		var off := []
		for e in moving[act]:
			if _active(act, e[0]):
				on.append(e[1])
			else:
				off.append(e[1])
		var r := _mean(on) / maxf(_mean(off), 0.01)
		ratios[act] = r
		m["moving_" + act] = "%.2f/%.2f" % [_mean(on), _mean(off)]
		m["activity_ratio_" + act] = snappedf(r, 0.01)
	res["metrics"] = m
	if pops.is_empty():
		_fail(res, "no population samples")
	else:
		if pmin < 8:
			_fail(res, "population fell to %d" % pmin)
		if pmax > 40:
			_fail(res, "population rose to %d" % pmax)
		if cv > 0.35:
			_fail(res, "population unstable (CV %.2f)" % cv)
		if pop_day[1].size() > 0 and absf(d2 - d1) / maxf(mean, 1.0) > 0.3:
			_fail(res, "population drifted %.1f -> %.1f between the days" % [d1, d2])
	if chases < 1:
		_fail(res, "no predator chases in %.0f days" % days)
	if kills < 1:
		_fail(res, "no predation kills in %.0f days" % days)
	if cohesion_n > 0 and coh < 0.8:
		_fail(res, "herds scattered (cohesion %.2f)" % coh)
	for act in ["day", "night"]:
		if moving[act].size() > 10 and ratios[act] < 1.5:
			_fail(res, "%s-active animals move only %.2fx more in their hours" % [act, ratios[act]])
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

static func _active(act: String, h: float) -> bool:
	match act:
		"day": return h > 6.0 and h < 19.0
		"night": return h < 6.5 or h > 18.5
		"crepuscular": return (h > 4.5 and h < 10.0) or (h > 16.0 and h < 21.5)
	return true

static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
