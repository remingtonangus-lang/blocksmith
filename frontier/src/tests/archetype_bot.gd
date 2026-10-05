extends RefCounted
## Enemy archetype oracle (headless): on open ground (a wide plank above the map, Ruth standing still and unhurt),
## a rusher must close inside 8 m and a marksman must hold 30-95 m while still firing; a gunman engages and fires.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "archetypes", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var tree := runner.get_tree()
	var p = Game.player
	# open, flat, dry ground away from towns (the gunfight bot's arena finder); steering probes the real heightmap
	var w: WorldData = Game.world
	var o: Vector3 = load("res://src/tests/combat_bot.gd")._arena(w, Vector3(-1500.0, 0.0, 1800.0))
	o.y = w.height(o.x, o.z)
	Game.terrain.ensure_collision_at(o)
	Game.terrain.ensure_collision_at(o + Vector3(0, 0, -40.0))
	Game.args["no_actor_lod"] = true        # keep them physical whatever the collision ring does
	var was_bot: bool = p.bot_driven
	p.bot_driven = true
	p.global_position = o + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	var scale0: float = p.damageable.damage_scale
	p.damageable.damage_scale = 0.0
	await tree.physics_frame
	var specs := {"rusher": "calder_double", "marksman": "bowden_bolt", "gunman": "lockhart_sa"}
	var seed := 700
	for kind in specs:
		seed += 1
		var start := o + Vector3(0, 0.0, -40.0)
		start.y = w.height(start.x, start.z) + 0.3
		var h := Human.spawn(Game.main, start, {"seed": seed, "role": "gunman", "faction": "bandit", "name": kind.capitalize(),
			"weapon": specs[kind], "skill": 0.5, "bravery": 0.9})
		var shots := [0]
		h.gun.fired.connect(func(_i, _o, _d): shots[0] += 1)
		h.brain.target = p
		h.brain.target_seen_t = 0.0
		h.brain._enter_combat()
		var min_d := 999.0
		var t := 0.0
		while t < 14.0:
			await tree.physics_frame
			t += 1.0 / 60.0
			h.brain.target_seen_t = 0.0          # open ground: always in sight
			var d: float = h.global_position.distance_to(p.global_position)
			min_d = minf(min_d, d)
			if Game.args.has("arch_debug") and int(t * 60.0) % 60 == 0:
				print("    %s t %.0f d %.1f state %s move_to %s pos %s" % [kind, t, d, h.brain.debug_state, str(h.intent.move_to), str(h.global_position - o)])
		var end_d: float = h.global_position.distance_to(p.global_position)
		res.checks[kind] = {"archetype": h.brain.archetype, "min_m": snappedf(min_d, 0.1), "end_m": snappedf(end_d, 0.1), "shots": shots[0]}
		if h.brain.archetype != kind:
			_fail(res, "%s spawned as %s" % [kind, h.brain.archetype])
		match kind:
			"rusher":
				if min_d > 8.0:
					_fail(res, "rusher never closed in (nearest %.1f m)" % min_d)
			"marksman":
				if end_d < 30.0 or end_d > 95.0:
					_fail(res, "marksman ended at %.1f m (wants 30-95)" % end_d)
				if shots[0] < 1:
					_fail(res, "marksman never fired")
			"gunman":
				if shots[0] < 1:
					_fail(res, "gunman never fired")
		h.queue_free()
		await tree.physics_frame
	p.damageable.damage_scale = scale0
	p.damageable.health = p.damageable.max_health
	p.bot_driven = was_bot
	Game.args.erase("no_actor_lod")
	await tree.physics_frame
	print("  archetypes: %s" % str(res.checks))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  archetypes FAIL: " + why)
