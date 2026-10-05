extends RefCounted
## Lasso oracle (headless, open ground): the throw catches a man 9 m ahead; the rope keeps him inside its length
## while he tries to run; pulling away drags him down; Interact hogties him; he is still down 8 s later; cut loose,
## he gets up.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "lasso", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var tree := runner.get_tree()
	var p = Game.player
	var w: WorldData = Game.world
	var o: Vector3 = load("res://src/tests/combat_bot.gd")._arena(w, Vector3(900.0, 0.0, 1200.0))
	o.y = w.height(o.x, o.z)
	Game.terrain.ensure_collision_at(o)
	Game.args["no_actor_lod"] = true
	var was_bot: bool = p.bot_driven
	p.bot_driven = true
	p.global_position = o + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	p.facing = 0.0
	p.cam_yaw = 0.0
	var start := o + Vector3(0, 0, -9.0)
	start.y = w.height(start.x, start.z) + 0.3
	var h := Human.spawn(Game.main, start, {"seed": 811, "faction": "civilian", "name": "Runaway", "bravery": 0.2})
	await _physics(tree, 20)
	# 1. throw
	p.intent.lasso = true
	await _physics(tree, 3)
	res.checks["caught"] = p.lasso.caught == h
	if p.lasso.caught != h:
		_fail(res, "the throw missed a man 9 m ahead")
		return await _end(res, tree, p, h, was_bot)
	# 2. he tries to run: stays inside the rope
	h.brain.state = h.brain.State.FLEE
	h.intent.move_to = h.global_position + Vector3(0, 0, -40.0)
	h.intent.speed = Human.SPRINT
	var max_d := 0.0
	for i in 120:
		h.intent.move_to = h.global_position + Vector3(0, 0, -40.0)
		await tree.physics_frame
		max_d = maxf(max_d, Vector2(h.global_position.x - p.global_position.x, h.global_position.z - p.global_position.z).length())
	res.checks["rope_m"] = snappedf(p.lasso.length, 0.1)
	res.checks["max_dist_m"] = snappedf(max_d, 0.1)
	if max_d > p.lasso.length + 0.6:
		_fail(res, "he ran past the rope (%.1f m on a %.1f m rope)" % [max_d, p.lasso.length])
	# 3. pull away: down
	p.intent.move = Vector2(0, -1)                # away from him (he is ahead, -z)
	var down := false
	for i in 300:
		await tree.physics_frame
		if Melee.is_down(h):
			down = true
			break
	p.intent.move = Vector2.ZERO
	res.checks["pulled_down"] = down
	if not down:
		_fail(res, "pulling on a taut rope never dragged him down")
		return await _end(res, tree, p, h, was_bot)
	# 4. walk up and hogtie
	for i in 400:
		var to: Vector3 = h.global_position - p.global_position
		to.y = 0.0
		if to.length() < 1.6:
			break
		p.cam_yaw = atan2(-to.x, -to.z)
		p.intent.move = Vector2(0, 1)
		await tree.physics_frame
	p.intent.move = Vector2.ZERO
	await _physics(tree, 5)
	p.intent.interact = true
	await _physics(tree, 3)
	res.checks["hogtied"] = h.get_meta("hogtied", false)
	if not h.get_meta("hogtied", false):
		_fail(res, "Interact did not hogtie him (dist %.1f)" % h.global_position.distance_to(p.global_position))
	# 5. stays down
	await _physics(tree, 480)
	res.checks["down_after_8s"] = Melee.is_down(h)
	if not Melee.is_down(h):
		_fail(res, "a hogtied man got up on his own")
	# 6. cut loose
	Lasso.cut_loose(h)
	await _physics(tree, 150)
	res.checks["up_after_cut"] = not Melee.is_down(h)
	if Melee.is_down(h):
		_fail(res, "cut loose, he never got up")
	print("  lasso: %s" % str(res.checks))
	return await _end(res, tree, p, h, was_bot)

static func _end(res: Dictionary, tree: SceneTree, p, h, was_bot: bool) -> Dictionary:
	p.lasso.release()
	p.intent.move = Vector2.ZERO
	p.bot_driven = was_bot
	Game.args.erase("no_actor_lod")
	if is_instance_valid(h):
		h.queue_free()
	await tree.physics_frame
	return res

static func _physics(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
	print("  lasso FAIL: " + why)
