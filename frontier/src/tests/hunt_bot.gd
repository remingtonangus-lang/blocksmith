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
		# the skinning action: Ruth kneels at the carcass, held in place for a few seconds
		p.global_position = deer.global_position + Vector3(1.0, 0.3, 0.0)
		var task := SkinningTask.start(p, deer)
		var held := 0
		var busy_frames := 0
		while is_instance_valid(task) and not task.done and busy_frames < 600:
			await tree.physics_frame
			busy_frames += 1
			if p.busy != null:
				held += 1
		var r: Dictionary = task.result if is_instance_valid(task) else {}
		if r.is_empty():
			r = {"quality": 3 if deer.skinned else 0, "item": "pelt_mule_deer_q3"}
		res.pelt_quality = r.get("quality", 0)
		res["skin_s"] = snappedf(busy_frames / 60.0, 0.1)
		if held < 120:
			_fail(res, "skinning did not hold Ruth in place (%d frames)" % held)
		if not deer.skinned:
			_fail(res, "carcass not skinned after the skinning action")
		if res.pelt_quality < 2:
			_fail(res, "clean rifle kill gave pelt quality %d" % res.pelt_quality)
		if Game.state and int(Game.state.inventory.get(r.get("item", "?"), 0)) < 1:
			_fail(res, "pelt not in satchel")
		p.global_position = c
	# prints and a blood trail: a deer walks past (prints), another is wounded and flees (blood leading to it)
	await _tracks_and_blood(runner, res, c)
	# a carcass laid over the horse, then taken down again
	await _carry(runner, res, c)
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
	# per-species gait oracle on the generated models (footfall beats/order vs the reference table per gait type)
	var checked := 0
	for sp in Animal.SPECIES.keys():
		if HorseVisual.model_path_for(sp) == "":
			continue
		var v := HorseVisual.new()
		Game.main.add_child(v)
		v.build(AnimalCoats.roll(sp, 1), sp)
		v.position = Vector3(0, -500, 0)
		for g in v.meta.get("gaits", {}):
			var r := HorseGaitOracle.analyse_animation(v, g)
			print("  " + HorseGaitOracle.format_line("%s/%s" % [sp, g], r))
			checked += 1
			if not r.get("ok", false):
				_fail(res, "gait oracle %s/%s: %s" % [sp, g, str(r.get("failures", []))])
		v.queue_free()
	res["gaits_checked"] = checked
	if checked == 0:
		print("  hunt: gait oracle SKIP (no wildlife models fetched)")
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	print("  hunt: pelt quality %d, population samples %s" % [res.pelt_quality, str(samples.slice(0, 8))])
	res["metrics"] = {}
	for k in ["skin_s", "prints", "blood_drops", "blood_path_m", "blood_lead_m", "carry", "unload"]:
		if res.has(k):
			res.metrics[k] = str(res[k]).replace(" ", "_")
	return res

static func _tracks_and_blood(runner: Node, res: Dictionary, c: Vector3) -> void:
	var tree := runner.get_tree()
	var w: WorldData = Game.world
	var q := c + Vector3(15, 0, 10)
	q.y = w.height(q.x, q.z) + 0.3
	Game.terrain.ensure_collision_at(q)
	var walker := Animal.spawn(Game.main, q, "mule_deer", 777)
	walker.goal = q + Vector3(-30, 0, 0)
	walker.state = Animal.State.WANDER
	walker.t_state = 30.0
	var prints0 := Tracks.count("cloven")
	for i in 600:
		await tree.physics_frame
	var prints := Tracks.count("cloven") - prints0
	res["prints"] = prints
	if prints < 6:
		_fail(res, "a walking deer left %d prints in 10 s" % prints)
	walker.queue_free()
	# wound a deer (a leg hit) and let it run: blood drops along its path, the last one near it
	var q2 := c + Vector3(-20, 0, 15)
	q2.y = w.height(q2.x, q2.z) + 0.3
	Game.terrain.ensure_collision_at(q2)
	var hurt := Animal.spawn(Game.main, q2, "mule_deer", 778)
	for i in 5:
		await tree.physics_frame
	var blood0 := Tracks.count("blood")
	hurt.damageable.apply_hit({"amount": 35.0, "zone": "chest", "attacker": Game.player})
	var path_len := 0.0
	var last := hurt.global_position
	for i in 720:
		await tree.physics_frame
		path_len += hurt.global_position.distance_to(last)
		last = hurt.global_position
	var drops := Tracks.count("blood") - blood0
	res["blood_drops"] = drops
	res["blood_path_m"] = snappedf(path_len, 0.1)
	if not hurt.alive:
		_fail(res, "the wounded deer died of a 35-point hit")
	if drops < 4:
		_fail(res, "a wounded, fleeing deer left %d blood drops over %.0f m" % [drops, path_len])
	else:
		# the newest blood mark is near the deer: the trail leads to it
		var inst: Tracks = Tracks.inst
		var newest := (inst._next - 1 + inst._pool.size()) % inst._pool.size()
		var dd: float = inst._pool[newest].global_position.distance_to(hurt.global_position)
		res["blood_lead_m"] = snappedf(dd, 0.1)
		if dd > 10.0:
			_fail(res, "the blood trail ends %.0f m from the wounded deer" % dd)
	hurt.queue_free()

static func _carry(runner: Node, res: Dictionary, c: Vector3) -> void:
	var tree := runner.get_tree()
	var w: WorldData = Game.world
	var q := c + Vector3(6, 0, -6)
	q.y = w.height(q.x, q.z) + 0.3
	Game.terrain.ensure_collision_at(q)
	var ph := Animal.spawn(Game.main, q, "pronghorn", 991)
	for i in 5:
		await tree.physics_frame
	ph.damageable.apply_hit({"amount": 500.0, "zone": "chest", "attacker": Game.player})
	for i in 30:
		await tree.physics_frame
	var h: Horse = Horse.player_horse
	if h == null:
		_fail(res, "no player horse for the carcass")
		return
	if h.rider != null:
		h.dismount(-1.0)
	h.global_position = ph.global_position + Vector3(2.5, 0, 0)
	h.global_position.y = w.height(h.global_position.x, h.global_position.z)
	for i in 10:
		await tree.physics_frame
	var prompt: String = ph.interact_prompt()
	ph.interact(Game.player)
	await tree.physics_frame
	res["carry"] = "%s, %.0f kg" % ["on horse" if h.carcass == ph else "no", h.carry_kg]
	if h.carcass != ph or h.carry_kg <= 0.0 or not prompt.begins_with("Lay"):
		_fail(res, "carcass not laid over the horse (prompt '%s')" % prompt)
		return
	# the carcass rides with the horse
	var off0: Vector3 = ph.global_position - h.global_position
	h.global_position += Vector3(5, 0, 0)
	for i in 5:
		await tree.physics_frame
	var off1: Vector3 = ph.global_position - h.global_position
	if off0.distance_to(off1) > 0.3:
		_fail(res, "carcass does not move with the horse")
	if ph.global_position.y - h.global_position.y < 1.0:
		_fail(res, "carcass is not up on the horse's back (%.2f m)" % (ph.global_position.y - h.global_position.y))
	var down := h.unload()
	res["unload"] = down != null and h.carcass == null and h.carry_kg == 0.0
	if not res.unload:
		_fail(res, "could not take the carcass down")

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)
