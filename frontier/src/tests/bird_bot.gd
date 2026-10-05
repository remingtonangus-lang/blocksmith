extends RefCounted
## Bird bot (--bot birds): a crow flock, a turkey flock and a sage grouse covey on the ground near Ruth, a
## red-tailed hawk soaring overhead and a jackrabbit in the open.
## Checks:
## - the ground birds stay on the ground while undisturbed
## - a gunshot lifts the crows, turkeys and grouse into the air, and they land again
## - the hawk soars within its altitude band and stoops (the dive), then climbs back to soaring
## - a turkey shot in the air tumbles to the ground and can be plucked
## - the flight update stays cheap (µs per bird per tick)

static func run(runner: Node, _seconds: float) -> Dictionary:
	var res := {"bot": "birds", "ok": true, "failures": [], "errors": []}
	var tree := runner.get_tree()
	var p = Game.player
	var w: WorldData = Game.world
	var err0: int = Game.error_logger.take().size()
	var c := Vector3(520.0, 0, 1480.0)
	c.y = w.height(c.x, c.z) + 1.0
	Game.terrain.ensure_collision_at(c)
	p.global_position = c
	if Game.wildlife:
		Game.wildlife.set_process(false)        # only the bot's birds
	var flocks := {}
	var all: Array = []
	var spots := {"crow": Vector3(28, 0, -10), "turkey": Vector3(-35, 0, -25), "sage_grouse": Vector3(10, 0, 32)}
	for sp in spots:
		var group := []
		var n := 8 if sp == "crow" else 5
		for i in n:
			var q: Vector3 = c + spots[sp] + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
			q.y = w.height(q.x, q.z)
			var b := Bird.spawn(Game.main, q, sp, 900 + i + sp.length() * 31)
			group.append(b)
			b.flock = group
			b.home = c + spots[sp]
			all.append(b)
		flocks[sp] = group
	var hawk := Bird.spawn(Game.main, c + Vector3(0, 0, 0), "red_tailed_hawk", 77)
	hawk.home = c
	hawk.t_mode = 999.0
	all.append(hawk)
	var rq := c + Vector3(55, 0, 20)
	rq.y = w.height(rq.x, rq.z) + 0.3
	Game.terrain.ensure_collision_at(rq)
	var rabbit := Animal.spawn(Game.main, rq, "rabbit", 31)
	rabbit.set_physics_process(false)
	# 1. undisturbed: on the ground
	await _wait(tree, 3.0)
	var on_ground := 0
	var ground_n := 0
	for sp in flocks:
		for b in flocks[sp]:
			ground_n += 1
			if b.global_position.y - w.height(b.global_position.x, b.global_position.z) < 0.3:
				on_ground += 1
	res["ground_before"] = "%d/%d" % [on_ground, ground_n]
	if on_ground < ground_n:
		_fail(res, "%d of %d ground birds not on the ground before the shot" % [ground_n - on_ground, ground_n])
	# hawk altitude band while soaring
	var alt_min := INF
	var alt_max := -INF
	for i in 120:
		await tree.physics_frame
		var a: float = hawk.global_position.y - w.height(hawk.global_position.x, hawk.global_position.z)
		alt_min = minf(alt_min, a)
		alt_max = maxf(alt_max, a)
	res["hawk_alt"] = "%.0f-%.0f m" % [alt_min, alt_max]
	if alt_min < 25.0 or alt_max > 95.0:
		_fail(res, "hawk soaring altitude %.0f-%.0f m outside 25-95 m" % [alt_min, alt_max])
	# 2. a gunshot
	Game.noise.emit(p.global_position, 260.0, p)
	await _wait(tree, 2.0)
	for sp in flocks:
		var up := 0
		for b in flocks[sp]:
			if b.global_position.y - w.height(b.global_position.x, b.global_position.z) > 1.2:
				up += 1
		res["airborne_" + sp] = "%d/%d" % [up, flocks[sp].size()]
		if up < int(ceil(flocks[sp].size() * 0.8)):
			_fail(res, "%s: only %d of %d took off at the gunshot" % [sp, up, flocks[sp].size()])
	# shoot one turkey out of the air
	var tk: Bird = flocks["turkey"][0]
	tk.damageable.apply_hit({"amount": 100.0, "zone": "chest", "attacker": p})
	var fell := false
	for i in 300:
		await tree.physics_frame
		if tk.mode == Bird.Mode.DEAD:
			fell = true
			break
	res["turkey_fell"] = fell
	if not fell:
		_fail(res, "shot turkey did not fall to the ground")
	else:
		var before: int = int(Game.state.inventory.get("meat_turkey", 0)) if Game.state else 0
		tk.interact(p)
		if Game.state and int(Game.state.inventory.get("meat_turkey", 0)) <= before:
			_fail(res, "plucking the turkey gave no meat")
	# 3. they land again
	var landed := {}
	var t := 0.0
	while t < 45.0:
		await tree.physics_frame
		t += runner.get_physics_process_delta_time()
		var done := true
		for sp in flocks:
			var n := 0
			for b in flocks[sp]:
				if b.alive and b.mode == Bird.Mode.GROUND:
					n += 1
			landed[sp] = n
			var alive_n: int = flocks[sp].filter(func(b): return b.alive).size()
			if n < int(ceil(alive_n * 0.7)):
				done = false
		if done:
			break
	res["land_s"] = snappedf(t, 0.1)
	for sp in flocks:
		var alive_n: int = flocks[sp].filter(func(b): return b.alive).size()
		res["landed_" + sp] = "%d/%d" % [landed.get(sp, 0), alive_n]
		if landed.get(sp, 0) < int(ceil(alive_n * 0.7)):
			_fail(res, "%s: only %d of %d landed again within 45 s" % [sp, landed.get(sp, 0), alive_n])
	# 4. the hawk's stoop on the rabbit
	hawk.t_mode = 0.0
	var dived := false
	var back := false
	t = 0.0
	while t < 40.0:
		await tree.physics_frame
		t += runner.get_physics_process_delta_time()
		if hawk.mode == Bird.Mode.DIVE:
			dived = true
		if dived and hawk.mode == Bird.Mode.SOAR:
			back = true
			break
	res["hawk_dives"] = hawk.dives
	res["hawk_kills"] = hawk.kills
	if not dived:
		_fail(res, "hawk never dived")
	if not back:
		_fail(res, "hawk did not climb back to soaring after the dive")
	# 5. cost of the flight model: 60 crows in the air, µs per bird per tick
	var test: Array = []
	for i in 60:
		var b := Bird.spawn(Game.main, c + Vector3(randf_range(-40, 40), 20.0, randf_range(-40, 40)), "crow", 5000 + i)
		b.mode = Bird.Mode.FLY
		b.speed = 10.0
		b.target = c + Vector3(randf_range(-100, 100), 20, randf_range(-100, 100))
		b.set_physics_process(false)
		test.append(b)
	var t0 := Time.get_ticks_usec()
	for k in 30:
		for b in test:
			b._physics_process(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / (30.0 * test.size())
	res["us_per_bird_tick"] = snappedf(us, 0.1)
	if us > 150.0:
		_fail(res, "flight update %.0f us per bird per tick" % us)
	for b in test + all:
		if is_instance_valid(b):
			b.queue_free()
	if is_instance_valid(rabbit):
		rabbit.queue_free()
	if Game.wildlife:
		Game.wildlife.set_process(true)
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	res["metrics"] = {}
	for k in res.keys():
		if not k in ["bot", "ok", "failures", "errors", "metrics"]:
			res.metrics[k] = str(res[k])
	return res

static func _wait(tree: SceneTree, s: float) -> void:
	var t := 0.0
	while t < s:
		await tree.physics_frame
		t += 1.0 / 60.0

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
