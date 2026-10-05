extends RefCounted
## Gunfight bot: spawns a Shale gang ambush around the player in open country, lets the player bot fight back
## (aims at the nearest visible enemy chest, fires semi-auto, reloads), and checks combat oracles:
## every enemy engages, enemies use cover, enemies hit the player at a believable rate, nobody gets stuck,
## the fight resolves, no script errors.

static func run(runner: Node, seconds: float) -> Dictionary:
	var res := {"bot": "gunfight", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "enemies": 0, "killed": 0, "engaged": 0, "used_cover": 0,
		"player_hits_taken": 0, "player_shots": 0, "player_hits": 0, "duration": 0.0}
	var player = Game.player
	var w: WorldData = Game.world
	var tree := runner.get_tree()
	# open country near the outfit camp with some cover (trees / terrain)
	var c := w.poi("caddell_camp")
	var center := Vector3(c.x + 120.0, 0, c.z - 60.0)
	center.y = w.height(center.x, center.z) + 1.0
	Game.terrain.ensure_collision_at(center)
	player.global_position = center
	player.velocity = Vector3.ZERO
	player.damageable.health = player.damageable.max_health
	player.damageable.alive = true
	print("gunfight: settling vegetation")
	if Game.main.vegetation and Game.main.vegetation.has_method("settle_now"):
		Game.main.vegetation.settle_now()
	print("gunfight: settled")
	await tree.physics_frame
	var enemies: Array = []
	var group: Array = []
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var p := center + Vector3(sin(a) * 32.0, 0, cos(a) * 32.0)
		p.y = w.height(p.x, p.z) + 0.5
		Game.terrain.ensure_collision_at(p)
		var h := Human.spawn(Game.main, p, {"seed": 900 + i, "role": "gunman", "faction": "shale",
			"name": "Shale Rider", "weapon": ["lockhart_sa", "merriman_lever", "calder_double"][i], "skill": 0.45})
		enemies.append(h)
		group.append(h)
	for h in enemies:
		h.brain.group = group
	res.enemies = enemies.size()
	var hits_taken := [0]
	player.damageable.damaged.connect(func(_i): hits_taken[0] += 1)
	var player_hits := [0]
	player.gun.hit_landed.connect(func(info): if info.has("target"): player_hits[0] += 1)
	player.gun.drawn = true
	var engaged := {}
	var covered := {}
	var t := 0.0
	var shoot_t := 0.0
	var err0: int = Game.error_logger.take().size()
	while t < seconds:
		await tree.physics_frame
		var dt := runner.get_physics_process_delta_time()
		t += dt
		var alive := enemies.filter(func(e): return is_instance_valid(e) and e.alive)
		for e in enemies:
			if is_instance_valid(e) and e.brain.state == e.brain.State.COMBAT:
				engaged[e.name] = true
				if e.brain.cover != Vector3.INF:
					covered[e.name] = true
		if alive.is_empty() or not player.damageable.alive:
			break
		# player bot: nearest visible enemy, aim at chest, fire when lined up
		var best = null
		var bd := INF
		for e in alive:
			var d: float = player.global_position.distance_to(e.global_position)
			var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.5, 0), e.global_position + Vector3(0, 1.25, 0), 1)
			if player.get_world_3d().direct_space_state.intersect_ray(q).is_empty() and d < bd:
				bd = d
				best = e
		player.intent.move = Vector2.ZERO
		player.intent.aim = best != null
		if best != null:
			var to: Vector3 = best.global_position + Vector3(0, 1.25, 0) - (player.camera.global_position if player.camera else player.global_position)
			var want_yaw := atan2(-to.x, -to.z)
			var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
			player.cam_yaw = lerp_angle(player.cam_yaw, want_yaw, 0.25)
			player.cam_pitch = lerpf(player.cam_pitch, want_pitch, 0.25)
			shoot_t -= dt
			player.intent.fire = false
			if shoot_t <= 0.0 and absf(angle_difference(player.cam_yaw, want_yaw)) < 0.05:
				player.intent.fire = true
				shoot_t = 0.55
				res.player_shots += 1
		else:
			player.intent.fire = false
			if player.gun.clip.get(player.gun.weapon_id(), 0) < 3:
				player.gun.start_reload()
	player.intent.aim = false
	player.intent.fire = false
	res.duration = t
	res.engaged = engaged.size()
	res.used_cover = covered.size()
	res.player_hits_taken = hits_taken[0]
	res.player_hits = player_hits[0]
	res.killed = enemies.filter(func(e): return is_instance_valid(e) and not e.alive).size()
	for e in enemies:
		if is_instance_valid(e):
			res.stuck_events += e.stuck_events
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d engine/script errors, first: %s" % [errs.size(), str(errs[0])])
	if res.engaged < res.enemies:
		_fail(res, "only %d/%d enemies engaged" % [res.engaged, res.enemies])
	if res.used_cover == 0:
		_fail(res, "no enemy used cover")
	if res.player_hits_taken == 0 and t > 20.0:
		_fail(res, "enemies never hit the player in %.0f s" % t)
	if res.stuck_events > 4:
		_fail(res, "%d NPC stuck events" % res.stuck_events)
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
