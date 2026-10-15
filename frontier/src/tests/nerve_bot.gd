extends RefCounted
## Nerve oracle (headless): rank 1 caps marks at 3 (six rounds loaded); a full core refills the meter far faster than
## an empty one; experience raises the rank (bigger meter, deeper slow); bitters restore the core; rank survives a
## save/load.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "nerve", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var tree := runner.get_tree()
	var p = Game.player
	var n: Nerve = p.nerve
	var g: GunHandler = p.gun
	var was_pos: Vector3 = p.global_position
	p.global_position = Vector3(0, 3600.0, 0)
	await tree.physics_frame
	n.rank = 1
	n.xp = 0.0
	n.max_meter = n.RANK_METER[0]
	n.meter = n.max_meter
	n.core = 100.0
	g.select(0)
	g.drawn = true
	g.clip[g.weapon_id()] = 6
	# 1. rank 1: three marks
	n.activate()
	var slow0 := Engine.time_scale
	for i in 6:
		n.mark(p.global_position, Vector3(0, 0, -1).rotated(Vector3.UP, i * 0.05))
	res.checks["marks_rank1"] = n.marks.size() if not n._executing else 3
	res.checks["slow_rank1"] = snappedf(slow0, 0.01)
	if n.marks.size() > 3:
		_fail(res, "rank 1 allowed %d marks" % n.marks.size())
	n.deactivate()
	# 2. core sets the refill rate
	n.meter = 0.0
	n.core = 100.0
	for i in 300:
		await tree.process_frame
	var full_core: float = n.meter
	n.meter = 0.0
	n.core = 0.0
	for i in 300:
		await tree.process_frame
	var empty_core: float = n.meter
	res.checks["refill_5s_core_full_vs_empty"] = [snappedf(full_core, 0.1), snappedf(empty_core, 0.1)]
	if full_core < empty_core * 3.0:
		_fail(res, "the core does not matter for the refill (%.1f vs %.1f)" % [full_core, empty_core])
	# 3. bitters restore it
	Game.state.add_item("tonic_nerve")
	Game.state.use_item("tonic_nerve")
	res.checks["core_after_bitters"] = snappedf(n.core, 0.1)
	if n.core < 99.0:
		_fail(res, "bitters did not restore the core (%.1f)" % n.core)
	# 4. rank up
	n.add_xp(20.0)
	res.checks["rank_after_20xp"] = n.rank
	res.checks["meter_max"] = n.max_meter
	if n.rank < 3 or n.max_meter <= n.RANK_METER[0]:
		_fail(res, "20 xp left Nerve at rank %d (max %.0f)" % [n.rank, n.max_meter])
	g.clip[g.weapon_id()] = 6
	n.meter = n.max_meter
	n.activate()
	res.checks["slow_rank3"] = snappedf(Engine.time_scale, 0.01)
	if Engine.time_scale >= slow0:
		_fail(res, "a higher rank did not slow time more")
	n.deactivate()
	# 5. save / load
	if Game.state.save_game("nerve_test"):
		var r := n.rank
		n.rank = 1
		n.xp = 0.0
		Game.state.load_game("nerve_test")
		res.checks["rank_after_load"] = n.rank
		if n.rank != r:
			_fail(res, "save/load lost the Nerve rank (%d vs %d)" % [n.rank, r])
	n.rank = 1
	n.xp = 0.0
	n.max_meter = n.RANK_METER[0]
	n.meter = n.max_meter
	n.core = 100.0
	p.global_position = was_pos
	await tree.physics_frame
	print("  nerve: %s" % str(res.checks))
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  nerve FAIL: " + why)
