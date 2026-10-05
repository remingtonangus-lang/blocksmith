extends RefCounted
## Disarm oracle (headless): a shot to the gun arm knocks the gun out of a bandit's hand. The gun lies on the ground
## as an item; a brave man squares up with fists, a timid one surrenders; Ruth picks the gun up.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "disarm", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var tree := runner.get_tree()
	var p = Game.player
	var w: WorldData = Game.world
	var o: Vector3 = load("res://src/tests/combat_bot.gd")._arena(w, Vector3(-600.0, 0.0, 2100.0))
	o.y = w.height(o.x, o.z)
	Game.terrain.ensure_collision_at(o)
	Game.args["no_actor_lod"] = true
	var was_bot: bool = p.bot_driven
	p.bot_driven = true
	p.global_position = o + Vector3(0, 0.3, 0)
	var cases := {"brave": 0.95, "timid": 0.2}
	var i := 0
	for k in cases:
		i += 1
		var at := o + Vector3(-3.0 + i * 3.0, 0, -6.0)
		at.y = w.height(at.x, at.z) + 0.3
		var h := Human.spawn(Game.main, at, {"seed": 830 + i, "faction": "bandit", "name": "Bandit_" + k, "weapon": "lockhart_sa",
			"bravery": cases[k], "skill": 0.3})
		await tree.physics_frame
		h.gun.drawn = true
		h.damageable.apply_hit({"amount": 8.0, "zone": "arm", "attacker": p, "position": h.global_position + Vector3(0, 1.2, 0),
			"direction": Vector3(0, 0, -1), "weapon": "lockhart_sa", "disarm_chance": 1.0})
		await tree.physics_frame
		var dropped: Node = null
		for n in tree.get_nodes_in_group("interactable"):
			if n is DroppedGun and (n as Node3D).global_position.distance_to(h.global_position) < 2.0:
				dropped = n
		var st: String = h.brain.State.keys()[h.brain.state]
		res.checks[k] = {"unarmed": h.gun.weapons.is_empty(), "dropped": dropped != null, "state": st}
		if not h.gun.weapons.is_empty() or dropped == null:
			_fail(res, "%s bandit kept his gun (dropped %s)" % [k, dropped != null])
		if k == "brave" and st != "FIST":
			_fail(res, "the brave one did not square up (%s)" % st)
		if k == "timid" and st != "SURRENDER":
			_fail(res, "the timid one did not surrender (%s)" % st)
		if k == "timid" and dropped != null:
			var before: int = p.gun.weapons.size()
			var had: bool = p.gun.weapons.has("lockhart_sa")
			dropped.interact(p)
			await tree.physics_frame
			res.checks["picked_up"] = had or p.gun.weapons.size() > before
			if not res.checks.picked_up:
				_fail(res, "picking up the dropped gun added nothing")
		h.queue_free()
	p.bot_driven = was_bot
	Game.args.erase("no_actor_lod")
	await tree.physics_frame
	print("  disarm: %s" % str(res.checks))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  disarm FAIL: " + why)
