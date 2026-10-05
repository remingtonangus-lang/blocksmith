extends RefCounted
## Hunting + ecology bot: wildlife spawns around Ruth in the hills; she shoots a deer with a rifle at ~35 m, skins
## it (pelt quality must be good or perfect for a clean chest/head hit with a suitable weapon), and the ecology
## keeps a non-zero, bounded population over time.

static func run(runner: Node, seconds: float) -> Dictionary:
	var res := {"bot": "hunt", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "population": [], "pelt_quality": 0}
	var tree := runner.get_tree()
	var p = Game.player
	var w: WorldData = Game.world
	var err0: int = Game.error_logger.take().size()
	var c := Vector3(500.0, 0, 1500.0)
	c.y = w.height(c.x, c.z) + 1.0
	Game.terrain.ensure_collision_at(c)
	p.global_position = c
	# a deer 35 m ahead, unaware
	var dpos := c + Vector3(0, 0, -35.0)
	for k in 16:
		var a := TAU * k / 16.0
		var q := c + Vector3(sin(a) * 35.0, 0, cos(a) * 35.0)
		if absf(w.height(q.x, q.z) - (c.y - 1.0)) < 2.0:
			dpos = q
			break
	dpos.y = w.height(dpos.x, dpos.z) + 0.3
	Game.terrain.ensure_collision_at(dpos)
	var deer := Animal.spawn(Game.main, dpos, "mule_deer", 4242)
	for i in 10:
		await tree.physics_frame
	p.gun.select(1)                # Merriman repeater
	p.gun.drawn = true
	p.gun.cooldown = 0.0
	var origin: Vector3 = p.global_position + Vector3(0, 1.5, 0)
	var target := deer.global_position + Vector3(0, deer.spec.size.y * 0.62, 0)
	# a clean, aimed heart shot (bypass the camera so the bot's aim is exact)
	p.gun.accuracy_bonus = 1.0
	var hits: Array = p.gun.fire(origin, (target - origin).normalized(), true, 0.01)
	print("  hunt: shot hits ", hits.map(func(h): return [h.get("collider"), h.get("zone", "-"), h.get("distance")]), " deer at ", deer.global_position, " origin ", origin)
	await tree.physics_frame
	if deer.alive:
		# second shot if needed (quality drops)
		p.gun.cooldown = 0.0
		p.gun.fire(origin, (deer.global_position + Vector3(0, 0.6, 0) - origin).normalized(), true, 0.01)
		await tree.physics_frame
	if deer.alive:
		_fail(res, "deer survived two rifle shots")
	else:
		var r: Dictionary = deer.skin()
		res.pelt_quality = r.get("quality", 0)
		if res.pelt_quality < 2:
			_fail(res, "clean rifle kill gave pelt quality %d" % res.pelt_quality)
		if Game.state and int(Game.state.inventory.get(r.get("item", "?"), 0)) < 1:
			_fail(res, "pelt not in satchel")
	# ecology: let the population build up and check it stays bounded
	var t := 0.0
	var samples := []
	while t < minf(seconds, 60.0):
		await tree.physics_frame
		t += runner.get_physics_process_delta_time()
		if int(t * 10) % 50 == 0:
			samples.append(tree.get_nodes_in_group("animals").size())
	res.population = samples
	var last: int = samples[-1] if samples.size() > 0 else 0
	if last <= 1:
		_fail(res, "no wildlife spawned around the player")
	if last > 40:
		_fail(res, "wildlife population exploded (%d)" % last)
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	print("  hunt: pelt quality %d, population samples %s" % [res.pelt_quality, str(samples.slice(0, 8))])
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
