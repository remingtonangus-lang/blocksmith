extends RefCounted
## Open-world systems bot: crime in front of a witness -> wanted + bounty; pay the bounty; buy/use items;
## save, scramble state, load -> state equality. Each check is an oracle.

static func run(runner: Node) -> Dictionary:
	var res := {"bot": "systems", "ok": true, "failures": [], "distance": 0.0, "stuck_events": 0, "fall_events": 0,
		"frame_spikes": 0, "errors": [], "checks": {}}
	var st: WorldState = Game.state
	var tree := runner.get_tree()
	var err0: int = Game.error_logger.take().size()
	var p = Game.player
	var town := Mission.place("bitter_spring", 20.0, 20.0)
	Game.terrain.ensure_collision_at(town)
	p.global_position = town + Vector3(0, 1.0, 0)
	await tree.physics_frame
	# 1. witnessed murder -> wanted + bounty, Standing drops
	var victim := Human.spawn(Game.main, town + Vector3(4, 0.5, 0), {"seed": 71, "faction": "civilian", "name": "Victim"})
	var witness := Human.spawn(Game.main, town + Vector3(8, 0.5, 3), {"seed": 72, "faction": "civilian", "name": "Witness"})
	for i in 5:
		await tree.physics_frame
	var s0 := st.standing
	victim.damageable.apply_hit({"amount": 500.0, "zone": "chest", "attacker": p, "position": victim.global_position})
	await tree.physics_frame
	res.checks["wanted_after_murder"] = st.wanted
	res.checks["bounty"] = st.bounties.duplicate()
	if st.wanted < 2:
		_fail(res, "witnessed murder did not make Ruth wanted (level %d)" % st.wanted)
	if st.standing >= s0:
		_fail(res, "murder did not lower Standing")
	# 2. pay the bounty
	var county := st.county_at(town)
	st.add_money(500.0)
	if not st.pay_bounty(county):
		_fail(res, "could not pay bounty in %s" % county)
	if st.wanted != 0 or float(st.bounties.get(county, 0.0)) > 0.0:
		_fail(res, "bounty paid but still wanted")
	# 3. items
	p.damageable.health = 30.0
	st.add_item("tonic_health")   # self-contained: earlier bots (encounters) may have given the satchel's tonics away
	if not st.use_item("tonic_health") or p.damageable.health <= 30.0:
		_fail(res, "health tonic did nothing")
	# 4. economy round trip: buy cartridges at the gunsmith, sell a pelt at the butcher
	var shops := tree.get_nodes_in_group("interactable").filter(func(n): return n.has_method("sell_all"))
	if shops.is_empty():
		_fail(res, "no shops in the world")
	else:
		var gun_shop = shops.filter(func(n): return n.kind == "gunsmith")
		var butcher = shops.filter(func(n): return n.kind == "butcher")
		var ammo0: int = p.gun.ammo.get("revolver", 0)
		var m0: float = st.money
		if gun_shop.size() > 0 and not gun_shop[0].buy("ammo_revolver", 1.0):
			_fail(res, "could not buy cartridges")
		if p.gun.ammo.get("revolver", 0) != ammo0 + 24 or st.money >= m0:
			_fail(res, "buying cartridges did not add ammo / take money")
		st.add_item("pelt_mule_deer_q3")
		var m1: float = st.money
		if butcher.size() > 0:
			var got: float = butcher[0].sell_all()
			if got <= 0.0 or st.money <= m1:
				_fail(res, "selling a perfect deer pelt paid nothing")
		res.checks["shops"] = shops.size()
	# 5. every random encounter stages and resolves (autopilot) without errors
	var enc = Game.get("encounters")
	if enc != null:
		Game.missions.autopilot = true
		for kind in enc.TYPES:
			var at: Vector3 = p.global_position + Vector3(30, 0, 30)
			await enc.start(kind, at)
		Game.missions.autopilot = false
		res.checks["encounters"] = enc.history.duplicate()
		if enc.history.size() < enc.TYPES.size():
			_fail(res, "only %d/%d encounters ran" % [enc.history.size(), enc.TYPES.size()])
	# 5b. hold-up and store robbery: hands up, rob, crime logged, shop shuts its door
	var rb = Game.get("robbery")
	if rb == null:
		_fail(res, "no robbery system")
	else:
		var vic: Human = Human.spawn(Game.main, p.global_position + Vector3(4, 0.3, 0), {"seed": 777, "role": "townsfolk", "faction": "civilian", "name": "Mark"})
		await tree.physics_frame
		rb.react(vic)
		var m3: float = st.money
		var crimes_before: int = st.crimes_log.size()
		if vic.brain.state != vic.brain.State.SURRENDER:
			_fail(res, "held-up civilian did not raise their hands")
		elif vic.interact_prompt().begins_with("Rob"):
			vic.interact(p)
			if st.money <= m3 or st.crimes_log.size() <= crimes_before:
				_fail(res, "robbing a held-up civilian paid nothing or logged no crime")
		else:
			_fail(res, "no rob prompt on a surrendered civilian")
		if shops.size() > 0:
			var take: float = rb.rob_shop(shops[0])
			if take <= 0.0 or rb.shop_open(shops[0]):
				_fail(res, "store robbery paid nothing or the shop stayed open")
		res.checks["robbery"] = rb.history.duplicate()
		vic.queue_free()
		for cty in st.bounties.keys():
			st.pay_bounty(cty)           # settle up so the law doesn't interfere with the next checks
	# 5c. fishing: buy a rod, cast at the river, hook, fight and land a fish
	var fs = Game.get("fishing")
	if fs == null:
		_fail(res, "no fishing system")
	else:
		var gen := shops.filter(func(s): return s.kind == "general")
		if gen.size() > 0:
			gen[0].buy("fishing_rod", 6.0)
		if int(st.inventory.get("fishing_rod", 0)) <= 0:
			st.add_item("fishing_rod")
		var bank := _river_bank()
		if bank.is_empty():
			_fail(res, "no river bank found for fishing")
		else:
			Game.terrain.ensure_collision_at(bank.pos)
			p.global_position = bank.pos
			p.facing = bank.facing
			fs.auto = true
			var caught_before: int = fs.catches.size()
			if not fs.start(p):
				_fail(res, "could not start fishing at a river bank (%s)" % fs.water_ahead(p))
			else:
				var t := 0.0
				while fs.state != fs.S.IDLE and t < 60.0:
					await tree.physics_frame
					t += 1.0 / 60.0
				if fs.catches.size() <= caught_before:
					_fail(res, "no fish landed in 60 s (state %d)" % fs.state)
			fs.auto = false
			res.checks["fishing"] = fs.catches.duplicate()
	# 6. a bounty end to end (autopilot): accept, travel, gang, custody, paid 1.5x
	var boards := tree.get_nodes_in_group("interactable").filter(func(n): return n.has_method("accept"))
	if boards.is_empty():
		_fail(res, "no bounty boards")
	else:
		Game.missions.autopilot = true
		var m2: float = st.money
		var bd = boards[0]
		var reward: float = bd.posters[0].reward
		bd.accept(0)
		for i in 600:
			await tree.physics_frame
			if bd.active.is_empty():
				break
		Game.missions.autopilot = false
		if not bd.active.is_empty():
			_fail(res, "bounty never resolved")
		elif st.money < m2 + reward * 1.5 - 0.01:
			_fail(res, "bounty paid %.2f, expected %.2f" % [st.money - m2, reward * 1.5])
	# 7. save -> scramble -> load equality
	var money := st.money
	var standing := st.standing
	var pos: Vector3 = p.global_position
	if not st.save_game("bot_test"):
		_fail(res, "save failed")
	st.money = 1.0
	st.standing = 77.0
	p.global_position += Vector3(50, 0, 50)
	if not st.load_game("bot_test"):
		_fail(res, "load failed")
	await tree.physics_frame
	if absf(st.money - money) > 0.01 or absf(st.standing - standing) > 0.01:
		_fail(res, "save/load mismatch money %.2f/%.2f standing %.2f/%.2f" % [st.money, money, st.standing, standing])
	if p.global_position.distance_to(pos) > 1.5:
		_fail(res, "save/load moved the player by %.1f m" % p.global_position.distance_to(pos))
	for n in [victim, witness]:
		if is_instance_valid(n):
			n.queue_free()
	var errs: Array = Game.error_logger.take().slice(err0)
	res.errors = errs
	if errs.size() > 0:
		_fail(res, "%d errors, first: %s" % [errs.size(), str(errs[0])])
	return res

static func _fail(res: Dictionary, why: String) -> void:
	res.ok = false
	res.failures.append(why)

## A dry point a few metres from the Sable River with the facing (yaw) towards the water.
static func _river_bank() -> Dictionary:
	var w: WorldData = Game.world
	for r in w.features.get("rivers", []):
		var pts: Array = r.points
		for i in range(pts.size() / 3, pts.size(), 7):
			var c := Vector3(pts[i][0], 0, pts[i][1])
			if not w.is_water(c.x, c.z):
				continue
			for k in 8:
				var ang := k * PI / 4.0
				var dir := Vector3(cos(ang), 0, sin(ang))
				for d in [5.0, 7.0, 9.0, 12.0]:
					var q: Vector3 = c + dir * d
					if not w.is_water(q.x, q.z) and w.height(q.x, q.z) - w.water_level(c.x, c.z) < 3.0:
						q.y = w.height(q.x, q.z) + 0.3
						var to: Vector3 = c - q
						return {"pos": q, "facing": atan2(-to.x, -to.z)}
	return {}
